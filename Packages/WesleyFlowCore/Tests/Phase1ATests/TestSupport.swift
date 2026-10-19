import Domain
import TaskExecution
import SystemOperations
import Foundation
import Testing

actor ManualTaskClock: TaskClock {
    private var value: Int64 = 1_000
    private var nextID = 0
    private var sleepers: [Int: (Int64, CheckedContinuation<Void, any Error>)] = [:]
    private var scheduled: [(Int64, CheckedContinuation<Void, Never>)] = []
    func now() -> Int64 { value }
    func sleep(until deadline: Int64) async throws {
        if deadline <= value { return }
        let id = nextID; nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                sleepers[id] = (deadline, continuation)
                var remaining: [(Int64, CheckedContinuation<Void, Never>)] = []
                for (time, waiter) in scheduled {
                    if time == deadline { waiter.resume() } else { remaining.append((time, waiter)) }
                }
                scheduled = remaining
            }
        } onCancel: { Task { await self.cancelSleep(id) } }
    }
    private func cancelSleep(_ id: Int) { sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
    func waitUntilScheduled(_ deadline: Int64) async {
        if deadline <= value || sleepers.values.contains(where: { $0.0 == deadline }) { return }
        await withCheckedContinuation { scheduled.append((deadline, $0)) }
    }
    func jumpWithoutWaking(to time: Int64) { precondition(time >= value); value = time }
    func advance(to time: Int64) {
        precondition(time >= value); value = time
        let ids = sleepers.filter { $0.value.0 <= time }.map(\.key)
        for id in ids { sleepers.removeValue(forKey: id)?.1.resume() }
    }
}

enum FixtureFailure: Error { case injected }
actor MemoryHistory: TaskHistoryRepository {
    var records: [TaskIdentifier: TaskRecord] = [:]
    var log: [TaskIdentifier: [TaskEventRecord]] = [:]
    var failAll = false
    var failKind: TaskEventKind?
    var failAfterSave = false
    var holdKind: TaskEventKind?
    private var held: CheckedContinuation<Void, Never>?
    private var holdWaiters: [CheckedContinuation<Void, Never>] = []
    private var eventWaiters: [(TaskEventKind, TaskIdentifier, CheckedContinuation<Void, Never>)] = []
    func configure(failAll: Bool = false, failKind: TaskEventKind? = nil, afterSave: Bool = false, holdKind: TaskEventKind? = nil) {
        self.failAll = failAll; self.failKind = failKind; failAfterSave = afterSave; self.holdKind = holdKind
    }
    func load() -> [TaskRecord] { Array(records.values) }
    func events(for id: TaskIdentifier) -> [TaskEventRecord] { log[id, default: []] }
    func commit(_ record: TaskRecord, event: TaskEventRecord, expectedSequence: Int?) async throws {
        if holdKind == event.kind {
            holdKind = nil
            await withCheckedContinuation { held = $0; holdWaiters.forEach { $0.resume() }; holdWaiters = [] }
        }
        guard records[record.plan.id]?.sequence == expectedSequence else { throw TaskServiceError.repositoryConflict }
        let fail = failAll || failKind == event.kind
        if fail && !failAfterSave { throw FixtureFailure.injected }
        records[record.plan.id] = record; log[record.plan.id, default: []].append(event)
        let ready = eventWaiters.filter { $0.0 == event.kind && $0.1 == record.plan.id }
        eventWaiters.removeAll { $0.0 == event.kind && $0.1 == record.plan.id }
        ready.forEach { $0.2.resume() }
        if fail { throw FixtureFailure.injected }
    }
    func waitForEvent(_ kind: TaskEventKind, for id: TaskIdentifier) async {
        if log[id, default: []].contains(where: { $0.kind == kind }) { return }
        await withCheckedContinuation { eventWaiters.append((kind, id, $0)) }
    }
    func waitForHeldCommit() async { if held != nil { return }; await withCheckedContinuation { holdWaiters.append($0) } }
    func releaseCommit() { held?.resume(); held = nil }
}

actor DeterministicExecutor: TaskOperationExecutor, TaskVerificationRunner {
    enum Mode: Sendable { case success, failure, staleRevision, staleDigest, held }
    enum Cleanup: Sendable { case stopped, uncertain, held }
    let operationMode: Mode
    let verificationMode: Mode
    let cleanupMode: Cleanup
    private(set) var started: [OperationToken] = []
    private(set) var cancelled: [OperationToken] = []
    private var operationWaiters: [String: CheckedContinuation<OperationResult, any Error>] = [:]
    private var verificationWaiters: [String: CheckedContinuation<VerificationEvidence, any Error>] = [:]
    private var cleanupWaiters: [CheckedContinuation<CancellationAcknowledgement, Never>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    init(operation: Mode = .success, verification: Mode = .success, cleanup: Cleanup = .stopped) {
        operationMode = operation; verificationMode = verification; cleanupMode = cleanup
    }
    private func note(_ token: OperationToken) {
        started.append(token)
        let ready = startWaiters.filter { $0.0 <= started.count }; startWaiters.removeAll { $0.0 <= started.count }
        ready.forEach { $0.1.resume() }
    }
    func waitForStarts(_ count: Int) async { if started.count >= count { return }; await withCheckedContinuation { startWaiters.append((count, $0)) } }
    func waitForCancellation() async { if !cancelled.isEmpty { return }; await withCheckedContinuation { cancelWaiters.append($0) } }
    func execute(_ operation: ScopedOperation, token: OperationToken) async throws -> OperationResult {
        note(token)
        if operationMode == .held { return try await withCheckedThrowingContinuation { operationWaiters[operation.id] = $0 } }
        return OperationResult(succeeded: operationMode != .failure, observedRevision: operationMode == .staleRevision ? "changed" : operation.revision)
    }
    func verify(_ operation: ScopedOperation, token: OperationToken) async throws -> VerificationEvidence {
        note(token)
        if verificationMode == .held { return try await withCheckedThrowingContinuation { verificationWaiters[operation.id] = $0 } }
        return VerificationEvidence(passed: verificationMode != .failure,
                                    operationDigest: verificationMode == .staleDigest ? String(repeating: "b", count: 64) : operation.digest,
                                    observedRevision: verificationMode == .staleRevision ? "changed" : operation.revision)
    }
    func cancel(_ token: OperationToken) async -> CancellationAcknowledgement {
        cancelled.append(token); cancelWaiters.forEach { $0.resume() }; cancelWaiters = []
        switch cleanupMode {
        case .stopped:
            operationWaiters.removeValue(forKey: token.operationID)?.resume(throwing: CancellationError())
            verificationWaiters.removeValue(forKey: token.operationID)?.resume(throwing: CancellationError())
            return .stopped
        case .uncertain: return .uncertain
        case .held: return await withCheckedContinuation { cleanupWaiters.append($0) }
        }
    }
    func complete(_ operation: ScopedOperation) {
        operationWaiters.removeValue(forKey: operation.id)?.resume(returning: .init(succeeded: true, observedRevision: operation.revision))
        verificationWaiters.removeValue(forKey: operation.id)?.resume(returning: .init(passed: true, operationDigest: operation.digest, observedRevision: operation.revision))
    }
    func releaseAll() {
        for waiter in operationWaiters.values { waiter.resume(throwing: CancellationError()) }; operationWaiters = [:]
        for waiter in verificationWaiters.values { waiter.resume(throwing: CancellationError()) }; verificationWaiters = [:]
        cleanupWaiters.forEach { $0.resume(returning: .stopped) }; cleanupWaiters = []
    }
}

func operation(_ id: String = "inspect", kind: OperationKind = .inspection) -> ScopedOperation {
    .init(id: id, kind: kind, digest: String(repeating: "a", count: 64), workspaceID: "workspace", revision: "revision-1")
}
func plan(_ id: String = "task", steps: [ScopedOperation] = [operation()], verification: ScopedOperation? = nil) throws -> TaskPlan {
    try .init(id: .init(rawValue: id), workspaceID: "workspace", revision: "revision-1", steps: steps, verification: verification)
}
actor ObservedPermissionPolicy: TaskPermissionPolicy {
    private let base: PermissionBroker
    private var revoked: Set<TaskIdentifier> = []
    private var waiting: [TaskIdentifier: [CheckedContinuation<Void, Never>]] = [:]
    init(_ base: PermissionBroker) { self.base = base }
    func beginSession() async { await base.beginSession() }
    func request(taskID: TaskIdentifier, operation: ScopedOperation, generation: Int) async throws -> ApprovalRequest {
        try await base.request(taskID: taskID, operation: operation, generation: generation)
    }
    func validate(_ request: ApprovalRequest, operation: ScopedOperation, generation: Int) async throws {
        try await base.validate(request, operation: operation, generation: generation)
    }
    func consume(_ request: ApprovalRequest, operation: ScopedOperation, generation: Int, notAfter: Int64) async throws {
        try await base.consume(request, operation: operation, generation: generation, notAfter: notAfter)
    }
    func revoke(taskID: TaskIdentifier) async {
        await base.revoke(taskID: taskID)
        revoked.insert(taskID)
        waiting.removeValue(forKey: taskID)?.forEach { $0.resume() }
    }
    func waitForRevocation(_ id: TaskIdentifier) async {
        if revoked.contains(id) { return }
        await withCheckedContinuation { waiting[id, default: []].append($0) }
    }
}

@MainActor
struct Harness {
    let history: MemoryHistory
    let clock: ManualTaskClock
    let executor: DeterministicExecutor
    let broker: PermissionBroker
    let policy: ObservedPermissionPolicy
    let authority: UserApprovalAuthority
    let coordinator: TaskCoordinator
    init(executor: DeterministicExecutor = .init(), history: MemoryHistory = .init()) async throws {
        self.history = history; clock = ManualTaskClock(); self.executor = executor
        let permissions = PermissionBroker.compose(clock: clock); broker = permissions.policy; authority = permissions.authority
        policy = ObservedPermissionPolicy(broker)
        coordinator = TaskCoordinator(history: history, policy: policy, executor: executor, verifier: executor, clock: clock)
        try await coordinator.start()
    }
    func approve(_ id: TaskIdentifier) async throws {
        let record = try await coordinator.waitForState(id, .awaitingApproval)
        let request = try #require(record.pendingApproval)
        try await authority.approve(request.id); try await coordinator.resumeApproval(id)
    }
}

actor TestFlag {
    private(set) var isSet = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func set() { isSet = true; let ready = waiters; waiters = []; ready.forEach { $0.resume() } }
    func wait() async { if isSet { return }; await withCheckedContinuation { waiters.append($0) } }
}
actor TestCohort {
    let count: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ count: Int) { self.count = count }
    func arrive() async {
        arrivals += 1
        if arrivals == count { let ready = waiters; waiters = []; ready.forEach { $0.resume() }; return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
final class ObserverLifetime: Sendable {}

extension TaskCoordinator {
    // The notifier inherits this actor and cannot run until waitForState suspends after registration.
    func waitForStateSignallingRegistration(_ id: TaskIdentifier, _ kind: TaskState.Kind, registered: TestFlag) async throws -> TaskRecord {
        let notifier = Task { await registered.set() }
        defer { notifier.cancel() }
        return try await waitForState(id, kind)
    }
}
