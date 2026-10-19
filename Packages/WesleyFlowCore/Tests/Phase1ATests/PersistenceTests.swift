import Domain
import Persistence
import TaskExecution
import SystemOperations
import Foundation
import Synchronization
import Dispatch
import Testing

final class SaveFault: Sendable {
    let state = Mutex<PersistenceCheckpoint?>(nil)
    func arm(_ point: PersistenceCheckpoint?) { state.withLock { $0 = point } }
    func check(_ point: PersistenceCheckpoint) throws {
        let fail = state.withLock { selected in selected == point }
        if fail { throw FixtureFailure.injected }
    }
}
func fixtureURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WesleyFlow-Phase1A-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent("history.store")
}
func storedRecord(_ id: String = "task", now: Int64 = 1_000, state: TaskState.Kind = .queued, intent: Bool = false) throws -> TaskRecord {
    var record = TaskRecord(plan: try plan(id, verification: state == .verifying ? operation("verify", kind: .verification) : nil), now: now)
    var facts = TransitionFacts(); facts.isQueueHead = true; facts.hasExecutionLease = true
    facts.resourcesAreReleased = true; facts.hasPendingExactOperation = true; facts.approvalIsValid = true
    if state == .failed { try record.lifecycle.apply(.failure(.setup), facts: facts) }
    if [.planning, .awaitingApproval, .running, .verifying, .cancelling].contains(state) {
        try record.lifecycle.apply(.start, facts: facts)
    }
    if [.awaitingApproval, .running, .verifying, .cancelling].contains(state) {
        try record.lifecycle.apply(.requestApproval, facts: facts)
    }
    if [.running, .verifying, .cancelling].contains(state) { try record.lifecycle.apply(.approveExecution, facts: facts) }
    if state == .verifying { facts.executionIsComplete = true; try record.lifecycle.apply(.executionDone, facts: facts) }
    if state == .cancelling { try record.lifecycle.apply(.cancel(.cancelled)) }
    if intent { record.intents = ["inspect"] }
    return record
}

@Suite("SwiftData durability", .timeLimit(.minutes(1)))
@MainActor
struct PersistenceTests {
    @Test func atomicStateEventReopenAndSingleWriter() async throws {
        let url = try fixtureURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await SwiftDataTaskRepository.open(url: url)
        let record = try storedRecord()
        try await repository.commit(record, event: .init(record: record, kind: .submitted, generation: 0), expectedSequence: nil)
        await #expect(throws: TaskServiceError.storeAlreadyOpen) { try await SwiftDataTaskRepository.open(url: url) }
        await repository.close()
        let reopened = try await SwiftDataTaskRepository.open(url: url)
        #expect(try await reopened.load() == [record])
        #expect(try await reopened.events(for: record.plan.id).count == 1)
        await reopened.close()
    }
    @Test(arguments: [PersistenceCheckpoint.beforeSave, .afterSave])
    func saveFaultsNeverProduceHalfTransaction(_ checkpoint: PersistenceCheckpoint) async throws {
        let url = try fixtureURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fault = SaveFault()
        let repository = try await SwiftDataTaskRepository.open(url: url, failureInjector: { try fault.check($0) })
        let record = try storedRecord()
        try await repository.commit(record, event: .init(record: record, kind: .submitted, generation: 0), expectedSequence: nil)
        var next = record; next.sequence = 1; next.updatedAt = 2_000
        var facts = TransitionFacts(); facts.isQueueHead = true; facts.hasExecutionLease = true
        try next.lifecycle.apply(.start, facts: facts)
        fault.arm(checkpoint)
        await #expect(throws: FixtureFailure.self) {
            try await repository.commit(next, event: .init(record: next, kind: .transition, generation: 0), expectedSequence: 0)
        }
        fault.arm(nil); await repository.close()
        let reopened = try await SwiftDataTaskRepository.open(url: url)
        let rows = try await reopened.load(); let events = try await reopened.events(for: record.plan.id)
        #expect(rows.count == 1)
        #expect(rows[0].sequence == (checkpoint == .beforeSave ? 0 : 1))
        #expect(events.count == rows[0].sequence + 1)
        await reopened.close()
    }
    @Test func duplicateAndStaleWritesAreRejectedWithoutChangingAudit() async throws {
        let url = try fixtureURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await SwiftDataTaskRepository.open(url: url); let record = try storedRecord()
        let event = TaskEventRecord(record: record, kind: .submitted, generation: 0)
        try await repository.commit(record, event: event, expectedSequence: nil)
        await #expect(throws: TaskServiceError.repositoryConflict) { try await repository.commit(record, event: event, expectedSequence: nil) }
        #expect(try await repository.events(for: record.plan.id).count == 1)
        await repository.close()
    }
    @Test func corruptAndUnsupportedStoresArePreserved() async throws {
        let url = try fixtureURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = Data("corrupt fixture, preserve me".utf8)
        try original.write(to: url)
        await #expect(throws: TaskServiceError.corruptStore) { try await SwiftDataTaskRepository.open(url: url) }
        #expect(try Data(contentsOf: url) == original)
        try Data("999\n".utf8).write(to: url.appendingPathExtension("schema"))
        await #expect(throws: TaskServiceError.incompatibleSchema) { try await SwiftDataTaskRepository.open(url: url) }
        #expect(try Data(contentsOf: url) == original)
    }
    @Test func quotaBlocksAdmissionAndRetentionPreservesActiveUncertainEvidence() async throws {
        let url = try fixtureURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let tiny = try await SwiftDataTaskRepository.open(url: url, byteLimit: 1, recoveryReserve: 0)
        let queued = try storedRecord()
        await #expect(throws: TaskServiceError.quotaExceeded) {
            try await tiny.commit(queued, event: .init(record: queued, kind: .submitted, generation: 0), expectedSequence: nil)
        }
        #expect(try await tiny.load().isEmpty); await tiny.close()
        let repository = try await SwiftDataTaskRepository.open(url: url)
        let completed = try storedRecord("completed", state: .failed)
        let active = try storedRecord("active")
        let uncertain = try storedRecord("uncertain", state: .failed, intent: true)
        for record in [completed, active, uncertain] {
            try await repository.commit(record, event: .init(record: record, kind: .submitted, generation: 0), expectedSequence: nil)
        }
        #expect(try await repository.prune(now: 31 * 86_400_000) == 1)
        #expect(try await repository.load().count == 2)
        #expect(try await repository.events(for: completed.plan.id).isEmpty)
        await #expect(throws: TaskServiceError.blocked) { try await repository.remove(uncertain.plan.id) }
        await repository.close()
    }
    @Test(arguments: [TaskState.Kind.queued, .planning, .awaitingApproval, .running, .verifying, .cancelling])
    func recoveryMarksInterruptedWithoutRestoringAuthorityOrReplaying(_ kind: TaskState.Kind) async throws {
        let url = try fixtureURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = try await SwiftDataTaskRepository.open(url: url)
        let record = try storedRecord(state: kind, intent: kind == .running || kind == .cancelling)
        try await first.commit(record, event: .init(record: record, kind: .intent, generation: 0), expectedSequence: nil)
        await first.close()
        let repository = try await SwiftDataTaskRepository.open(url: url)
        let clock = ManualTaskClock(); let pair = PermissionBroker.compose(clock: clock); let executor = DeterministicExecutor()
        let coordinator = TaskCoordinator(history: repository, policy: pair.policy, executor: executor, verifier: executor, clock: clock)
        try await coordinator.start()
        let recovered = try #require(await coordinator.snapshot(record.plan.id))
        #expect(recovered.lifecycle.state == .failed(.interrupted)); #expect(recovered.previousState == record.lifecycle.state)
        #expect(recovered.pendingApproval == nil); #expect(recovered.requiresInspection == record.hasUnresolvedIntent)
        #expect(await executor.started.isEmpty)
        #expect(try await repository.events(for: record.plan.id).count == 2)
        await coordinator.shutdown(); await repository.close()
        let again = try await SwiftDataTaskRepository.open(url: url)
        let second = TaskCoordinator(history: again, policy: pair.policy, executor: executor, verifier: executor, clock: clock)
        try await second.start()
        #expect(await second.snapshot(record.plan.id)?.previousState == record.lifecycle.state)
        #expect(try await again.events(for: record.plan.id).count == 2)
        await second.shutdown(); await again.close()
    }
}

extension PersistenceTests {
    @Test func v1PayloadWithoutRemediationFieldsStillDecodesAndReopens() async throws {
        let url = try fixtureURL()
        // SwiftData can retain SQLite handles until executor teardown; do not unlink a live store.
        defer { print("retained remediation store:", url.deletingLastPathComponent().path) }
        let original = try storedRecord("v1-compatible")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "executionDeadline"); json.removeValue(forKey: "lateResults")
        let decoded = try JSONDecoder().decode(TaskRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == original); #expect(decoded.executionDeadline == nil); #expect(decoded.lateResults == nil)
        let repository = try await SwiftDataTaskRepository.open(url: url)
        try await repository.commit(decoded, event: .init(record: decoded, kind: .submitted, generation: 0), expectedSequence: nil)
        await repository.close()
        let reopened = try await SwiftDataTaskRepository.open(url: url)
        #expect(try await reopened.load() == [original]); await reopened.close()
    }
    @Test func expiredPersistedDeadlinesAndApprovalsAreNeverResumed() async throws {
        let url = try fixtureURL()
        // SwiftData can retain SQLite handles until executor teardown; do not unlink a live store.
        defer { print("retained remediation store:", url.deletingLastPathComponent().path) }
        let clock = ManualTaskClock(); let permission = PermissionBroker.compose(clock: clock)
        var record = try storedRecord("expired-deadline", state: .awaitingApproval)
        let request = try await permission.policy.request(taskID: record.plan.id, operation: record.plan.steps[0], generation: 4)
        try await permission.authority.approve(request.id)
        record.pendingApproval = request; record.executionDeadline = 999
        let first = try await SwiftDataTaskRepository.open(url: url)
        try await first.commit(record, event: .init(record: record, kind: .approvalRequested, generation: 4), expectedSequence: nil)
        await first.close(); await clock.advance(to: request.expiresAt + 1)
        let reopened = try await SwiftDataTaskRepository.open(url: url)
        let executor = DeterministicExecutor()
        let coordinator = TaskCoordinator(history: reopened, policy: permission.policy, executor: executor, verifier: executor, clock: clock)
        try await coordinator.start()
        let recovered = try #require(await coordinator.snapshot(record.plan.id))
        #expect(recovered.lifecycle.state == .failed(.interrupted)); #expect(recovered.previousState == record.lifecycle.state)
        #expect(recovered.executionDeadline == 999); #expect(recovered.pendingApproval == nil)
        await #expect(throws: TaskServiceError.staleOperation) { try await permission.policy.validate(request, operation: request.operation, generation: 4) }
        await #expect(throws: TaskServiceError.staleOperation) { try await coordinator.resumeApproval(record.plan.id) }
        #expect(await executor.started.isEmpty)
        await coordinator.shutdown(); await reopened.close()
    }
    @Test func cancelledUnknownDispositionSurvivesReopenAndCannotBePruned() async throws {
        let url = try fixtureURL()
        // SwiftData can retain SQLite handles until executor teardown; do not unlink a live store.
        defer { print("retained remediation store:", url.deletingLastPathComponent().path) }
        let repository = try await SwiftDataTaskRepository.open(url: url)
        let clock = ManualTaskClock(); let pair = PermissionBroker.compose(clock: clock)
        let executor = DeterministicExecutor(operation: .held)
        let coordinator = TaskCoordinator(history: repository, policy: pair.policy, executor: executor, verifier: executor, clock: clock)
        try await coordinator.start(); let p = try plan("cancelled-unknown")
        try await coordinator.submit(p)
        let waiting = try await coordinator.waitForState(p.id, .awaitingApproval)
        let request = try #require(waiting.pendingApproval)
        try await pair.authority.approve(request.id); try await coordinator.resumeApproval(p.id)
        await executor.waitForStarts(1); await coordinator.cancel(p.id)
        let cancelled = try await coordinator.waitForState(p.id, .cancelled)
        #expect(cancelled.hasUnresolvedIntent); #expect(cancelled.requiresInspection); #expect(cancelled.outcomes.isEmpty)
        await coordinator.shutdown(); await repository.close()
        let reopened = try await SwiftDataTaskRepository.open(url: url)
        let restart = TaskCoordinator(history: reopened, policy: pair.policy, executor: executor, verifier: executor, clock: clock)
        try await restart.start()
        let recovered = try #require(await restart.snapshot(p.id))
        #expect(recovered.lifecycle.state == .cancelled); #expect(recovered.hasUnresolvedIntent)
        #expect(recovered.requiresInspection); #expect(recovered.pendingApproval == nil)
        #expect(try await reopened.prune(now: 31 * 86_400_000) == 0)
        await #expect(throws: TaskServiceError.blocked) { try await reopened.remove(p.id) }
        await #expect(throws: TaskServiceError.staleOperation) { try await pair.policy.validate(request, operation: request.operation, generation: request.generation) }
        #expect(await executor.started.count == 1)
        await restart.shutdown(); await reopened.close()
    }
}

private final class BlockingSave: Sendable {
    private let armed = Mutex(false)
    private let opened = Mutex(false)
    private let gate = DispatchSemaphore(value: 0)
    let entered: AsyncStream<Void>
    private let notification: AsyncStream<Void>.Continuation
    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        entered = pair.stream; notification = pair.continuation
    }
    func arm() { armed.withLock { $0 = true } }
    func check(_ checkpoint: PersistenceCheckpoint) {
        guard checkpoint == .beforeSave else { return }
        let hold = armed.withLock { value in let selected = value; value = false; return selected }
        if hold {
            notification.yield(()) // Synchronous notification cannot inherit the deliberately blocked executor.
            gate.wait() // Deliberately block only the test store's executor, representing stalled synchronous I/O.
        }
    }
    func release() {
        let signal = opened.withLock { value in if value { return false }; value = true; return true }
        if signal { gate.signal() }
    }
}
extension PersistenceTests {
    @Test func realStoreStallCannotBlockBoundedShutdownAndLateReceiptIsHonest() async throws {
        let url = try fixtureURL()
        // SwiftData can retain SQLite handles until executor teardown; do not unlink a live store.
        defer { print("retained remediation store:", url.deletingLastPathComponent().path) }
        let blocker = BlockingSave(); defer { blocker.release() }
        let repository = try await SwiftDataTaskRepository.open(url: url, failureInjector: { blocker.check($0) })
        let clock = ManualTaskClock(); let permission = PermissionBroker.compose(clock: clock)
        let executor = DeterministicExecutor(operation: .held)
        let coordinator = TaskCoordinator(history: repository, policy: permission.policy, executor: executor, verifier: executor, clock: clock)
        try await coordinator.start(); let p = try plan("real-store-stall")
        try await coordinator.submit(p)
        let waiting = try await coordinator.waitForState(p.id, .awaitingApproval)
        try await permission.authority.approve(try #require(waiting.pendingApproval).id)
        try await coordinator.resumeApproval(p.id); await executor.waitForStarts(1)
        blocker.arm()
        let closing = Task { await coordinator.shutdown() }
        var notification = blocker.entered.makeAsyncIterator()
        _ = await notification.next()
        print("real-store-stall: entered blocked save")
        let deadline = await clock.now() + 5_000
        print("real-store-stall: clock deadline", deadline)
        await clock.waitUntilScheduled(deadline)
        print("real-store-stall: timer registered")
        await clock.advance(to: deadline)
        print("real-store-stall: timer advanced")
        await closing.value
        print("real-store-stall: closing completed")
        let emergency = try #require(await coordinator.snapshot(p.id))
        #expect(emergency.lifecycle.state.isTerminal); #expect(emergency.durability == .uncommitted)
        #expect(emergency.requiresInspection); #expect(await coordinator.hasPendingPersistence)
        #expect(await coordinator.isQuarantined)
        print("real-store-stall: bounded shutdown returned")
        blocker.release(); await coordinator.waitForPersistenceSettlement()
        print("real-store-stall: late save acknowledged")
        #expect(await coordinator.latePersistenceAcknowledgements.last?.succeeded == true)
        #expect(await coordinator.snapshot(p.id)?.durability == .uncommitted)
        await repository.close()
        let reopened = try await SwiftDataTaskRepository.open(url: url)
        let restart = TaskCoordinator(history: reopened, policy: permission.policy, executor: executor, verifier: executor, clock: clock)
        try await restart.start()
        let recovered = try #require(await restart.snapshot(p.id))
        #expect(recovered.lifecycle.state == .failed(.interrupted)); #expect(recovered.requiresInspection)
        #expect(recovered.pendingApproval == nil); #expect(await executor.started.count == 1)
        await restart.shutdown(); await reopened.close()
    }
}
