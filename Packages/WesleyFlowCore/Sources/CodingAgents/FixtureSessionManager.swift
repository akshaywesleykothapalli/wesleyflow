import Domain
import Foundation
import CryptoKit

public enum FixtureSessionState: Equatable, Sendable { case ready, creating, active, reconnecting, terminal(RuntimeTerminalState) }
public struct FixtureSessionSnapshot: Equatable, Sendable {
    public let state: FixtureSessionState
    public let correlation: SessionCorrelation?
    public let error: RuntimeProtocolError?
    public let cleanup: CleanupAssessment
    public let queuedEvents: Int
    public let queuedBytes: Int
    public let identityCount: Int
    public let isObserving: Bool
}
/// No connection, launch, provider or broker capability. Only caller-supplied fixture bytes enter.
public actor FixtureSessionTransport {
    let sessionID: RuntimeSessionIdentifier
    let assessment: CleanupAssessment
    public private(set) var createCount = 0
    public private(set) var disposeCount = 0
    public init(sessionID: RuntimeSessionIdentifier, cleanup: CleanupAssessment = .fixtureDisposed) { self.sessionID = sessionID; assessment = cleanup }
    func create() -> RuntimeSessionIdentifier { createCount += 1; return sessionID }
    func dispose() -> CleanupAssessment { disposeCount += 1; return assessment }
}
/// One session per manager, one observer, bounded replay ledger and critical queue.
public actor FixtureSessionManager: CodingAgentRuntime {
    private let transport: FixtureSessionTransport
    private let clock: any TaskClock
    private let queueLimit: Int
    private let byteLimit: Int
    private let identityLimit: Int
    private var parser: SSEParser
    private var state: FixtureSessionState = .ready
    private var correlation: SessionCorrelation?
    private var deadline: Int64 = 0
    private var queue: [(RuntimeEvent, Int)] = []
    private var queueBytes = 0
    private var seen: [String: [UInt8]] = [:]
    private var error: RuntimeProtocolError?
    private var observer: (Int, CheckedContinuation<RuntimeEvent?, any Error>)?
    private var nextObserver = 0
    private var timer: Task<Void, Never>?
    private var cleanupTask: Task<CleanupAssessment, Never>?
    private var cleanup: CleanupAssessment = .uncertain
    private var shutdownRequested = false
    private var receiving = false
    public init(transport: FixtureSessionTransport, clock: any TaskClock, queueLimit: Int = 64, byteLimit: Int = 262_144, identityLimit: Int = 256) throws {
        guard queueLimit > 0, queueLimit <= 64, byteLimit > 0, byteLimit <= 262_144, identityLimit > 0, identityLimit <= 256 else { throw RuntimeProtocolError.invalidManifest }
        self.transport = transport; self.clock = clock; self.queueLimit = queueLimit; self.byteLimit = byteLimit; self.identityLimit = identityLimit
        parser = try SSEParser()
    }
    public func create(_ manifest: SessionManifest) async throws -> SessionCorrelation {
        guard !Task.isCancelled else { throw RuntimeProtocolError.cancelled }
        guard !shutdownRequested, state == .ready else { throw RuntimeProtocolError.closed }
        state = .creating
        let now = await clock.now()
        guard !shutdownRequested, state == .creating else { throw RuntimeProtocolError.closed }
        guard now < manifest.deadline else { terminate(.timedOut, error: .timeout); throw RuntimeProtocolError.timeout }
        let id = await transport.create()
        guard !shutdownRequested, state == .creating, !Task.isCancelled else {
            terminate(.cancelled, error: .cancelled); throw RuntimeProtocolError.cancelled
        }
        let acceptedAt = await clock.now()
        guard !shutdownRequested, state == .creating, !Task.isCancelled else { terminate(.cancelled, error: .cancelled); throw RuntimeProtocolError.cancelled }
        guard acceptedAt < manifest.deadline else { terminate(.timedOut, error: .timeout); throw RuntimeProtocolError.timeout }
        let identity = try SessionCorrelation(taskID: manifest.taskID, operationID: manifest.operationID, sessionID: id, generation: manifest.generation)
        correlation = identity; deadline = manifest.deadline; state = .active
        timer = Task {
            do { try await self.clock.sleep(until: manifest.deadline) } catch { return }
            self.terminate(.timedOut, error: .timeout)
        }
        return identity
    }
    private func validate(_ value: SessionCorrelation) throws {
        guard let own = correlation else { throw RuntimeProtocolError.unknownSession }
        guard value.taskID == own.taskID, value.operationID == own.operationID, value.sessionID == own.sessionID, value.generation == own.generation else { throw RuntimeProtocolError.foreignSession }
        guard value.connectionEpoch == own.connectionEpoch else { throw RuntimeProtocolError.staleConnection }
    }
    private var isTerminal: Bool { if case .terminal = state { true } else { false } }
    private func checkTime() async throws {
        let now = await clock.now()
        if !isTerminal, now >= deadline { terminate(.timedOut, error: .timeout) }
        if let error { throw error }
    }
    public func receive(_ bytes: [UInt8], for value: SessionCorrelation) async throws {
        guard !receiving else { throw RuntimeProtocolError.busy }
        receiving = true; defer { receiving = false }
        try validate(value)
        try await checkTime()
        try validate(value)
        guard state == .active, !shutdownRequested else { throw RuntimeProtocolError.closed }
        // Copy parser state to avoid overlapping mutation of actor state in the synchronous callback.
        var input = parser
        do {
            try input.feed(bytes) { frame in
                guard !self.isTerminal else { throw RuntimeProtocolError.closed }
                let event = try OpenCodeV1EventDecoder.decode(frame, correlation: value)
                let digest = Array(SHA256.hash(data: Data(frame.data.utf8)))
                try self.accept(event, digest: digest, bytes: frame.data.utf8.count + 256)
            }
            parser = input
        } catch {
            let failure = error as? RuntimeProtocolError ?? .invalidPayload
            // Rejecting a foreign event is inspectable but cannot terminate another session.
            if failure != .foreignSession, !isTerminal { terminate(.uncertain, error: failure) }
            throw failure
        }
    }
    private func accept(_ event: RuntimeEvent, digest: [UInt8], bytes: Int) throws {
        if let prior = seen[event.id] {
            guard prior == digest else { throw RuntimeProtocolError.duplicateConflict }
            return
        }
        guard seen.count < identityLimit else { throw RuntimeProtocolError.identityLimit }
        seen[event.id] = digest
        if !event.kind.isCritical, let last = queue.last, !last.0.kind.isCritical {
            queueBytes -= last.1; queue.removeLast()
        }
        while queue.count >= queueLimit || bytes > byteLimit - queueBytes {
            if let index = queue.firstIndex(where: { !$0.0.kind.isCritical }) { queueBytes -= queue[index].1; queue.remove(at: index) }
            else if !event.kind.isCritical { return } // Explicit lossy progress policy only.
            else { throw RuntimeProtocolError.criticalOverflow }
        }
        if let waiting = observer {
            observer = nil; waiting.1.resume(returning: event)
        } else { queue.append((event, bytes)); queueBytes += bytes }
        switch event.kind {
        case .terminal(let terminal): terminate(terminal, error: nil)
        case .error(let failure): terminate(.uncertain, error: failure)
        default: break
        }
    }
    public func nextEvent(for value: SessionCorrelation) async throws -> RuntimeEvent? {
        guard !Task.isCancelled else { throw RuntimeProtocolError.cancelled }; try validate(value)
        // Already accepted critical events are drained even if a later overflow failed the session.
        if !queue.isEmpty { let item = queue.removeFirst(); queueBytes -= item.1; return item.0 }
        if let error { throw error }
        if isTerminal { return nil }
        guard state == .active else { throw RuntimeProtocolError.staleConnection }
        try await checkTime()
        try validate(value)
        if !queue.isEmpty { let item = queue.removeFirst(); queueBytes -= item.1; return item.0 }
        if let error { throw error }
        if isTerminal { return nil }
        guard state == .active else { throw RuntimeProtocolError.staleConnection }
        guard observer == nil else { throw RuntimeProtocolError.busy }
        let token = nextObserver; nextObserver += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: RuntimeProtocolError.cancelled); return }
                observer = (token, continuation)
            }
        } onCancel: { Task { await self.cancelObserver(token) } }
    }
    private func cancelObserver(_ token: Int) {
        guard observer?.0 == token else { return }
        let waiting = observer; observer = nil
        waiting?.1.resume(throwing: RuntimeProtocolError.cancelled)
        terminate(.cancelled, error: .cancelled)
    }
    private func terminate(_ terminal: RuntimeTerminalState, error failure: RuntimeProtocolError?) {
        guard !isTerminal else { return }
        state = .terminal(terminal); error = failure; timer?.cancel(); timer = nil
        let waiting = observer; observer = nil
        if let failure { waiting?.1.resume(throwing: failure) } else { waiting?.1.resume(returning: nil) }
        if cleanupTask == nil {
            cleanupTask = Task {
                let result = await self.transport.dispose()
                self.cleanup = result
                return result
            }
        }
    }
    public func disconnect(for value: SessionCorrelation) throws {
        try validate(value); guard state == .active else { throw RuntimeProtocolError.closed }
        // Reconnect is a fixture operation; no prompt or effect is ever resent.
        state = .reconnecting
        let waiting = observer; observer = nil; waiting?.1.resume(throwing: RuntimeProtocolError.staleConnection)
    }
    public func reconnect(for value: SessionCorrelation) async throws -> SessionCorrelation {
        try validate(value); try await checkTime(); try validate(value)
        guard state == .reconnecting, !shutdownRequested, value.connectionEpoch < Int.max else { throw RuntimeProtocolError.closed }
        correlation = try SessionCorrelation(taskID: value.taskID, operationID: value.operationID, sessionID: value.sessionID, generation: value.generation, connectionEpoch: value.connectionEpoch + 1)
        parser = try SSEParser(); state = .active
        return correlation!
    }
    public func endOfStream(for value: SessionCorrelation) throws {
        try validate(value)
        do { try parser.finish() } catch { terminate(.uncertain, error: .malformedUTF8); throw RuntimeProtocolError.malformedUTF8 }
        if !isTerminal { terminate(.uncertain, error: .unexpectedEnd) }
    }
    public func cancel(_ request: CancellationRequest) async -> CleanupAssessment {
        guard (try? validate(request.correlation)) != nil else { return .uncertain }
        terminate(.cancelled, error: .cancelled)
        return await cleanupTask?.value ?? cleanup
    }
    public func shutdown() async -> CleanupAssessment {
        shutdownRequested = true
        terminate(.cancelled, error: .cancelled)
        return await cleanupTask?.value ?? cleanup
    }
    public func snapshot() -> FixtureSessionSnapshot {
        .init(state: state, correlation: correlation, error: error, cleanup: cleanup, queuedEvents: queue.count, queuedBytes: queueBytes, identityCount: seen.count, isObserving: observer != nil)
    }
}
