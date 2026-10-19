import Domain
import Foundation

/// The grant issuer is available only to trusted composition/UI, never through the policy port.
@MainActor
public final class UserApprovalAuthority {
    private let decide: @Sendable (String, Bool) async throws -> Void
    fileprivate init(decide: @escaping @Sendable (String, Bool) async throws -> Void) { self.decide = decide }
    public func approve(_ requestID: String) async throws { try await decide(requestID, true) }
    public func deny(_ requestID: String) async throws { try await decide(requestID, false) }
}

public actor PermissionBroker: TaskPermissionPolicy {
    private struct Entry { let request: ApprovalRequest; var approved = false; var denied = false }
    private let clock: any TaskClock
    private var session = UUID().uuidString
    private var entries: [String: Entry] = [:]
    private var revocations: [TaskIdentifier: Int] = [:]
    private init(clock: any TaskClock) { self.clock = clock }

    @MainActor
    public static func compose(clock: any TaskClock) -> (policy: PermissionBroker, authority: UserApprovalAuthority) {
        let broker = PermissionBroker(clock: clock)
        return (broker, UserApprovalAuthority { id, approve in try await broker.decide(id, approve: approve) })
    }
    public func beginSession() { entries.removeAll(); revocations.removeAll(); session = UUID().uuidString }
    public func request(taskID: TaskIdentifier, operation: ScopedOperation, generation: Int) async throws -> ApprovalRequest {
        guard operation.kind == .inspection || operation.kind == .verification else { throw TaskServiceError.unsupportedOperation }
        let currentSession = session
        let revision = revocations[taskID, default: 0]
        let now = await clock.now()
        guard session == currentSession, revocations[taskID, default: 0] == revision else { throw TaskServiceError.staleOperation }
        let request = ApprovalRequest(id: UUID().uuidString, taskID: taskID, operation: operation,
                                      generation: generation, session: session, expiresAt: now + 300_000)
        entries[request.id] = Entry(request: request)
        return request
    }
    private func decide(_ id: String, approve: Bool) async throws {
        let now = await clock.now()
        guard var entry = entries[id], entry.request.session == session else { throw TaskServiceError.staleOperation }
        guard now < entry.request.expiresAt else { entries[id] = nil; throw TaskServiceError.approvalExpired }
        guard !entry.approved && !entry.denied else { throw TaskServiceError.staleOperation }
        entry.approved = approve; entry.denied = !approve; entries[id] = entry
    }
    public func validate(_ request: ApprovalRequest, operation: ScopedOperation, generation: Int) async throws {
        let now = await clock.now()
        guard let entry = entries[request.id], entry.request == request, request.session == session,
              request.operation == operation, request.generation == generation else { throw TaskServiceError.staleOperation }
        guard now < request.expiresAt else { throw TaskServiceError.approvalExpired }
        guard !entry.denied else { throw TaskServiceError.approvalDenied }
        guard entry.approved else { throw TaskServiceError.approvalRequired }
    }
    public func consume(_ request: ApprovalRequest, operation: ScopedOperation, generation: Int, notAfter: Int64 = .max) async throws {
        let now = await clock.now()
        guard let entry = entries[request.id], entry.request == request, request.session == session,
              request.operation == operation, request.generation == generation else { throw TaskServiceError.staleOperation }
        guard now < request.expiresAt else { entries[request.id] = nil; throw TaskServiceError.approvalExpired }
        guard !entry.denied else { entries[request.id] = nil; throw TaskServiceError.approvalDenied }
        guard entry.approved else { throw TaskServiceError.approvalRequired }
        guard now < notAfter else { throw TaskServiceError.executionLimit }
        entries[request.id] = nil // atomic one-use consumption, after the final await
    }
    public func revoke(taskID: TaskIdentifier) {
        revocations[taskID, default: 0] += 1
        entries = entries.filter { $0.value.request.taskID != taskID }
    }
}

/// Monotonic elapsed time anchored to an epoch timestamp, so wall-clock rollback cannot extend grants.
public struct SystemTaskClock: TaskClock {
    private let start = ContinuousClock.now
    private let epoch = Int64(Date().timeIntervalSince1970 * 1000)
    public init() {}
    public func now() async -> Int64 {
        let elapsed = start.duration(to: .now).components
        return epoch + elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
    }
    public func sleep(until deadline: Int64) async throws {
        let remaining = max(0, deadline - (await now()))
        try await Task.sleep(for: .milliseconds(remaining))
    }
}
