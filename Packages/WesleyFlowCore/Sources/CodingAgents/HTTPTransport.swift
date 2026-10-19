import Domain
import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable { case get = "GET", post = "POST" }
    public let id: String
    public let method: Method
    public let path: String
    public let body: [UInt8]
    public let timeoutMilliseconds: Int64
    public let responseLimit: Int
    public init(id: String, method: Method, path: String, body: [UInt8] = [], timeoutMilliseconds: Int64 = 5_000, responseLimit: Int = 262_144) throws {
        guard RuntimeSessionIdentifier.isValid(id), path.hasPrefix("/"), !path.hasPrefix("//"),
              !path.contains("\0"), !path.contains("\r"), !path.contains("\n"), path.utf8.count <= 1024,
              body.count <= 262_144, timeoutMilliseconds > 0, timeoutMilliseconds <= 300_000,
              responseLimit > 0, responseLimit <= 262_144 else { throw RuntimeProtocolError.invalidRequest }
        self.id = id; self.method = method; self.path = path; self.body = body
        self.timeoutMilliseconds = timeoutMilliseconds; self.responseLimit = responseLimit
    }
}
public struct HTTPResponseHead: Sendable {
    public let status: Int
    public let contentType: String
    public init(status: Int, contentType: String = "application/json") { self.status = status; self.contentType = contentType }
}
/// Injectable byte transport; no network implementation or credential store is supplied.
public protocol HTTPTransport: Sendable {
    func open(_ request: HTTPRequest) async throws -> HTTPResponseHead
    func nextChunk() async throws -> [UInt8]?
    func dispose() async -> CleanupAssessment
}
/// One exchange per client. Owned I/O is retained until settlement; timeout never joins a stuck child.
public actor FixtureHTTPClient {
    private let transport: any HTTPTransport
    private let clock: any TaskClock
    private var used = false
    private var completed = false
    private var waiter: CheckedContinuation<[UInt8], any Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var disposal: Task<Void, Never>?
    private var deadline: Int64?
    public private(set) var cleanup: CleanupAssessment = .uncertain
    public private(set) var hasPendingWork = false
    public init(transport: any HTTPTransport, clock: any TaskClock) { self.transport = transport; self.clock = clock }
    public func perform(_ request: HTTPRequest) async throws -> [UInt8] {
        guard !Task.isCancelled else { throw RuntimeProtocolError.cancelled }
        guard !used else { throw RuntimeProtocolError.closed }
        used = true; hasPendingWork = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { hasPendingWork = false; continuation.resume(throwing: RuntimeProtocolError.cancelled); complete(.failure(.cancelled)); return }
                waiter = continuation
                work = Task { await self.exchange(request) }
            }
        } onCancel: { Task { await self.cancel() } }
    }
    private func exchange(_ request: HTTPRequest) async {
        defer { work = nil; hasPendingWork = false }
        do {
            let now = await clock.now()
            guard !completed else { return }
            let (limit, overflow) = now.addingReportingOverflow(request.timeoutMilliseconds)
            guard !overflow else { throw RuntimeProtocolError.invalidRequest }
            deadline = limit
            timer = Task {
                do { try await self.clock.sleep(until: limit) } catch { return }
                self.complete(.failure(.timeout))
            }
            let head = try await transport.open(request)
            try await checkDeadline()
            guard (200...299).contains(head.status) else { throw RuntimeProtocolError.invalidStatus }
            guard head.contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else { throw RuntimeProtocolError.invalidPayload }
            var bytes: [UInt8] = []
            while let chunk = try await transport.nextChunk() {
                try await checkDeadline()
                guard chunk.count <= request.responseLimit - bytes.count else { throw RuntimeProtocolError.oversizedResponse }
                bytes.append(contentsOf: chunk)
            }
            try await checkDeadline()
            guard !bytes.isEmpty, (try? JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])) != nil else { throw RuntimeProtocolError.invalidPayload }
            complete(.success(bytes))
        } catch { complete(.failure(error as? RuntimeProtocolError ?? (error is CancellationError ? .cancelled : .transportFailure))) }
    }
    private func checkDeadline() async throws {
        let now = await clock.now()
        guard !completed else { throw RuntimeProtocolError.cancelled }
        guard let deadline, now < deadline else { throw RuntimeProtocolError.timeout }
        try Task.checkCancellation()
    }
    private func complete(_ result: Result<[UInt8], RuntimeProtocolError>) {
        guard !completed else { return }
        completed = true; timer?.cancel(); timer = nil; work?.cancel()
        let continuation = waiter; waiter = nil
        switch result { case .success(let value): continuation?.resume(returning: value); case .failure(let error): continuation?.resume(throwing: error) }
        disposal = Task {
            let assessment = await self.transport.dispose()
            self.cleanup = assessment; self.disposal = nil
        }
    }
    public func cancel() { used = true; complete(.failure(.cancelled)) }
}
/// Sealed deterministic fixture backend. It never opens a URL or starts a runtime.
public actor FixtureHTTPTransport: HTTPTransport {
    private let head: HTTPResponseHead
    private var chunks: [[UInt8]]
    private var held: Bool
    private var opener: CheckedContinuation<Void, any Error>?
    private var observed = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var disposeObservers: [CheckedContinuation<Void, Never>] = []
    public private(set) var disposed = false
    public private(set) var openCount = 0
    public init(status: Int = 200, contentType: String = "application/json", chunks: [[UInt8]], holdOpen: Bool = false) throws {
        guard contentType.utf8.count <= 128, chunks.count <= 64, chunks.allSatisfy({ $0.count <= 262_144 }), chunks.reduce(0, { $0 + $1.count }) <= 524_288 else { throw RuntimeProtocolError.invalidManifest }
        head = .init(status: status, contentType: contentType); self.chunks = chunks; held = holdOpen
    }
    public func open(_ request: HTTPRequest) async throws -> HTTPResponseHead {
        guard !disposed else { throw RuntimeProtocolError.closed }
        openCount += 1; observed = true
        let pending = observers; observers = []; pending.forEach { $0.resume() }
        if held { try await withCheckedThrowingContinuation { opener = $0 } }
        guard !disposed else { throw RuntimeProtocolError.cancelled }
        return head
    }
    public func nextChunk() throws -> [UInt8]? {
        guard !disposed else { throw RuntimeProtocolError.closed }
        return chunks.isEmpty ? nil : chunks.removeFirst()
    }
    public func release() { held = false; let continuation = opener; opener = nil; continuation?.resume() }
    public func waitUntilOpened() async { if observed { return }; await withCheckedContinuation { observers.append($0) } }
    public func waitUntilDisposed() async { if disposed { return }; await withCheckedContinuation { disposeObservers.append($0) } }
    public func dispose() -> CleanupAssessment {
        disposed = true; chunks = []; let continuation = opener; opener = nil
        continuation?.resume(throwing: RuntimeProtocolError.cancelled)
        let pending = disposeObservers; disposeObservers = []; pending.forEach { $0.resume() }
        return .fixtureDisposed
    }
}
