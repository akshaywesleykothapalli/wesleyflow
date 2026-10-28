import Domain
import TaskExecution
import SystemOperations
import Testing

@Suite("Durable orchestration", .timeLimit(.minutes(1)))
@MainActor
struct CoordinatorTests {
    @Test func approvalPrecedesIntentAndOrderedCompletion() async throws {
        let h = try await Harness(); let p = try plan()
        try await h.coordinator.submit(p)
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        #expect(await h.executor.started.isEmpty)
        await #expect(throws: TaskServiceError.approvalRequired) { try await h.coordinator.resumeApproval(p.id) }
        #expect(await h.history.events(for: p.id).allSatisfy { $0.kind != .intent })
        try await h.approve(p.id)
        let done = try await h.coordinator.waitForState(p.id, .succeeded)
        #expect(done.lifecycle.state == .succeeded)
        let events = await h.history.events(for: p.id)
        #expect(events.map(\.sequence) == Array(0..<events.count))
        let approvalIndex = try #require(events.firstIndex { $0.kind == .approvalGranted })
        let intentIndex = try #require(events.firstIndex { $0.kind == .intent })
        let outcomeIndex = try #require(events.firstIndex { $0.kind == .outcome })
        #expect(approvalIndex < intentIndex); #expect(intentIndex < outcomeIndex)
        #expect(done.sequence == events.count - 1)
        await h.coordinator.shutdown()
    }
    @Test func deniedOperationNeverRuns() async throws {
        let h = try await Harness(); let p = try plan()
        try await h.coordinator.submit(p)
        let waiting = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        try await h.authority.deny(try #require(waiting.pendingApproval).id)
        try await h.coordinator.resumeApproval(p.id)
        #expect(try await h.coordinator.waitForState(p.id, .cancelled).lifecycle.state == .cancelled)
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
    }
    @Test func fifoOverflowAndQueuedCancellation() async throws {
        let h = try await Harness(); let first = try plan("first")
        try await h.coordinator.submit(first)
        _ = try await h.coordinator.waitForState(first.id, .awaitingApproval)
        for i in 0..<16 { try await h.coordinator.submit(plan("waiting-\(i)")) }
        await #expect(throws: TaskServiceError.queueFull) { try await h.coordinator.submit(plan("overflow")) }
        let removed = TaskIdentifier(rawValue: "waiting-0")
        await h.coordinator.cancel(removed)
        #expect(try await h.coordinator.waitForState(removed, .cancelled).lifecycle.state == .cancelled)
        await h.coordinator.cancel(first.id)
        _ = try await h.coordinator.waitForState(first.id, .cancelled)
        let next = try await h.coordinator.waitForState(.init(rawValue: "waiting-1"), .awaitingApproval)
        #expect(next.plan.id.rawValue == "waiting-1")
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
    }
    @Test func eachStepAndVerificationNeedFreshApproval() async throws {
        let h = try await Harness(); let verify = operation("verify", kind: .verification)
        let p = try plan(steps: [operation("a"), operation("b")], verification: verify)
        try await h.coordinator.submit(p); try await h.approve(p.id)
        let second = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        #expect(second.pendingApproval?.operation.id == "b")
        #expect(await h.executor.started.count == 1)
        try await h.approve(p.id)
        let approval = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        #expect(approval.lifecycle.state == .awaitingApproval(resumePhase: .verifying))
        #expect(approval.pendingApproval?.operation == verify)
        try await h.approve(p.id)
        #expect(try await h.coordinator.waitForState(p.id, .succeeded).lifecycle.state == .succeeded)
        #expect(await h.executor.started.map(\.operationID) == ["a", "b", "verify"])
        await h.coordinator.shutdown()
    }
    @Test(arguments: [DeterministicExecutor.Mode.failure, .staleRevision, .staleDigest])
    func verificationNeverHidesFailure(_ mode: DeterministicExecutor.Mode) async throws {
        let h = try await Harness(executor: .init(verification: mode))
        let p = try plan(verification: operation("verify", kind: .verification))
        try await h.coordinator.submit(p); try await h.approve(p.id); try await h.approve(p.id)
        let done = try await h.coordinator.waitForState(p.id, .failed)
        #expect(done.lifecycle.state == .failed(mode == .failure ? .verification : .conflict))
        #expect(done.hasUnresolvedIntent == false)
        await h.coordinator.shutdown()
    }
    @Test func cancellingHeldExecutorReleasesOnlyAfterAcknowledgement() async throws {
        let executor = DeterministicExecutor(operation: .held)
        let h = try await Harness(executor: executor); let p = try plan()
        try await h.coordinator.submit(p); try await h.approve(p.id); await executor.waitForStarts(1)
        try await h.coordinator.submit(plan("next"))
        await h.coordinator.cancel(p.id)
        #expect(try await h.coordinator.waitForState(p.id, .cancelled).lifecycle.state == .cancelled)
        #expect(await executor.cancelled.count == 1)
        #expect(try await h.coordinator.waitForState(.init(rawValue: "next"), .awaitingApproval).pendingApproval != nil)
        #expect(await executor.started.count == 1)
        await h.coordinator.shutdown()
    }
    @Test func nonCooperativeCleanupQuarantinesAndLateSuccessIsIgnored() async throws {
        let executor = DeterministicExecutor(operation: .held, cleanup: .held)
        let h = try await Harness(executor: executor); let p = try plan()
        try await h.coordinator.submit(p); try await h.approve(p.id); await executor.waitForStarts(1)
        try await h.coordinator.submit(plan("next"))
        await h.coordinator.cancel(p.id)
        let deadline = await h.clock.now() + 5_000
        await h.clock.waitUntilScheduled(deadline); await h.clock.advance(to: deadline)
        let failed = try await h.coordinator.waitForState(p.id, .failed)
        #expect(failed.lifecycle.state == .failed(.cleanupIncomplete)); #expect(failed.requiresInspection)
        #expect(await h.coordinator.isQuarantined)
        await executor.complete(p.steps[0]); await executor.releaseAll()
        #expect(await h.coordinator.snapshot(p.id)?.lifecycle.state == .failed(.cleanupIncomplete))
        #expect(await h.coordinator.snapshot(.init(rawValue: "next"))?.lifecycle.state == .queued)
        #expect(await executor.started.count == 1)
        await h.coordinator.shutdown()
    }
    @Test func approvalExpiryAndOperationTimeoutUseInjectedClock() async throws {
        let h = try await Harness(); let p = try plan()
        try await h.coordinator.submit(p)
        let record = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        let deadline = try #require(record.pendingApproval).expiresAt
        await h.clock.waitUntilScheduled(deadline); await h.clock.advance(to: deadline)
        #expect(try await h.coordinator.waitForState(p.id, .failed).lifecycle.state == .failed(.approvalExpired))
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
        let second = try await Harness(executor: .init(operation: .held)); let task = try plan("timeout")
        try await second.coordinator.submit(task); try await second.approve(task.id); await second.executor.waitForStarts(1)
        let timeout = await second.clock.now() + 300_000
        await second.clock.waitUntilScheduled(timeout); await second.clock.advance(to: timeout)
        #expect(try await second.coordinator.waitForState(task.id, .failed).lifecycle.state == .failed(.timeout))
        await second.coordinator.shutdown()
    }
    @Test func storageFailurePreventsDispatchAndUncommittedCleanupRemainsVisible() async throws {
        let executor = DeterministicExecutor(operation: .held)
        let h = try await Harness(executor: executor); let p = try plan()
        try await h.coordinator.submit(p); try await h.approve(p.id); await executor.waitForStarts(1)
        await h.history.configure(failAll: true)
        await h.coordinator.cancel(p.id, failure: .storage)
        let failed = try await h.coordinator.waitForState(p.id, .failed)
        #expect(failed.lifecycle.state == .failed(.storage)); #expect(failed.durability == .uncommitted)
        #expect(await executor.cancelled.count == 1); #expect(await h.coordinator.isBlocked)
        await h.history.configure()
        let restart = try await Harness(history: h.history)
        let recovered = try #require(await restart.coordinator.snapshot(p.id))
        #expect(recovered.lifecycle.state == .failed(.interrupted)); #expect(recovered.previousState == .running)
        #expect(recovered.requiresInspection); #expect(recovered.pendingApproval == nil)
        #expect(await restart.executor.started.isEmpty)
        await h.coordinator.shutdown(); await restart.coordinator.shutdown()
    }
    @Test(arguments: [false, true])
    func failedIntentCommitNeverDispatchesEvenWhenCommitWasUnacknowledged(_ afterSave: Bool) async throws {
        let h = try await Harness(); let p = try plan()
        try await h.coordinator.submit(p)
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        await h.history.configure(failKind: .intent, afterSave: afterSave)
        try await h.approve(p.id)
        let failed = try await h.coordinator.waitForState(p.id, .failed)
        #expect(failed.lifecycle.state.isTerminal); #expect(await h.executor.started.isEmpty)
        #expect(await h.coordinator.isBlocked)
        await h.coordinator.shutdown()
    }
    @Test func cleanupDoesNotWaitForCancellationSave() async throws {
        let executor = DeterministicExecutor(operation: .held)
        let h = try await Harness(executor: executor); let p = try plan()
        try await h.coordinator.submit(p); try await h.approve(p.id); await executor.waitForStarts(1)
        await h.history.configure(holdKind: .cancellation)
        let cancellation = Task { await h.coordinator.cancel(p.id) }
        await h.history.waitForHeldCommit()
        await executor.waitForCancellation() // Must happen while the history commit is still held.
        #expect(await executor.cancelled.count == 1)
        await h.history.releaseCommit(); await cancellation.value
        #expect(try await h.coordinator.waitForState(p.id, .cancelled).lifecycle.state == .cancelled)
        await h.coordinator.shutdown()
    }
    @Test func unsupportedEffectsAndInvalidPlansAreRejected() async throws {
        let h = try await Harness(); let p = try plan(steps: [operation(kind: .process)])
        try await h.coordinator.submit(p)
        #expect(try await h.coordinator.waitForState(p.id, .failed).lifecycle.state == .failed(.policyDenied))
        #expect(await h.executor.started.isEmpty)
        #expect(throws: TaskServiceError.invalidPlan) { try plan(steps: Array(repeating: operation(), count: 51)) }
        #expect(throws: TaskServiceError.invalidPlan) {
            try TaskPlan(id: .init(rawValue: "task"), workspaceID: "workspace", revision: "revision-1", steps: [operation()], retryCount: 3)
        }
        await h.coordinator.shutdown()
    }
    @Test func failedQueuedAdmissionRevokesActiveWorkToo() async throws {
        let executor = DeterministicExecutor(operation: .held)
        let h = try await Harness(executor: executor); let p = try plan()
        try await h.coordinator.submit(p); try await h.approve(p.id); await executor.waitForStarts(1)
        await h.history.configure(failKind: .submitted)
        await #expect(throws: FixtureFailure.self) { try await h.coordinator.submit(plan("queued")) }
        let done = try await h.coordinator.waitForState(p.id, .failed)
        #expect(done.lifecycle.state == .failed(.storage))
        #expect(await executor.cancelled.count == 1); #expect(await h.coordinator.isBlocked)
        // Rejected/uncertain admissions are now inspectable rather than disappearing from status.
        let rejected = try #require(await h.coordinator.snapshot(.init(rawValue: "queued")))
        #expect(rejected.lifecycle.state == .failed(.storage)); #expect(rejected.durability == .uncommitted)
        #expect(await h.history.events(for: rejected.plan.id).isEmpty)
        await h.coordinator.shutdown()
    }
    @Test func cumulativeExecutionBudgetExcludesApprovalWaits() async throws {
        let executor = DeterministicExecutor(operation: .held)
        let h = try await Harness(executor: executor)
        let operations = (0..<4).map { operation("step-\($0)") }
        let p = try plan(steps: operations)
        try await h.coordinator.submit(p)
        for i in 0..<3 {
            _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
            // Deliberate approval delay below the 5-minute expiry; it must not consume execution time.
            await h.clock.advance(to: await h.clock.now() + 100_000)
            try await h.approve(p.id); await executor.waitForStarts(i + 1)
            let expiry = await h.clock.now() + 300_000
            await h.clock.waitUntilScheduled(expiry)
            await h.clock.advance(to: expiry - 1)
            await executor.complete(operations[i])
        }
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        try await h.approve(p.id); await executor.waitForStarts(4)
        let finalDeadline = await h.clock.now() + 3 // 900,000 - 3 * 299,999
        await h.clock.waitUntilScheduled(finalDeadline); await h.clock.advance(to: finalDeadline)
        #expect(try await h.coordinator.waitForState(p.id, .failed).lifecycle.state == .failed(.timeout))
        await h.coordinator.shutdown()
    }

    @Test func retriesAreLinkedNewTasksRequiringNewApproval() async throws {
        let h = try await Harness()
        let p = try TaskPlan(id: .init(rawValue: "original"), workflowID: "review", workflowVersion: 7, workspaceID: "workspace", revision: "revision-1", steps: [operation()])
        try await h.coordinator.submit(p)
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        await h.coordinator.cancel(p.id)
        _ = try await h.coordinator.waitForState(p.id, .cancelled)
        let id = TaskIdentifier(rawValue: "retry-1")
        try await h.coordinator.retry(p.id, as: id)
        let retried = try await h.coordinator.waitForState(id, .awaitingApproval)
        #expect(retried.plan.retryOf == p.id); #expect(retried.lifecycle.retryOf == p.id)
        #expect(retried.plan.workflowID == "review"); #expect(retried.plan.workflowVersion == 7)
        #expect(retried.plan.retryCount == 1); #expect(await h.executor.started.isEmpty)
        #expect(await h.coordinator.snapshot(p.id)?.lifecycle.state == .cancelled)
        await h.coordinator.shutdown()
    }

    @Test(arguments: [TaskEventKind.transition, .approvalRequested, .approvalGranted, .intent])
    func cancellationDuringPreDispatchSaveNeverExecutes(_ point: TaskEventKind) async throws {
        let h = try await Harness(); let p = try plan()
        if point == .transition || point == .approvalRequested { await h.history.configure(holdKind: point) }
        try await h.coordinator.submit(p)
        var resume: Task<Void, any Error>?
        if point == .approvalGranted || point == .intent {
            _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
            await h.history.configure(holdKind: point)
            resume = Task { try await h.approve(p.id) }
        }
        await h.history.waitForHeldCommit()
        let cancellation = Task { await h.coordinator.cancel(p.id) }
        await h.policy.waitForRevocation(p.id)
        await h.history.releaseCommit(); await cancellation.value
        if let resume { try await resume.value }
        #expect(try await h.coordinator.waitForState(p.id, .cancelled).lifecycle.state == .cancelled)
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
    }
    @Test(arguments: [TaskEventKind.outcome, .verification])
    func cancellationDuringResultSaveCannotPromoteLateSuccess(_ point: TaskEventKind) async throws {
        let h = try await Harness(); let verify = point == .verification ? operation("verify", kind: .verification) : nil
        let p = try plan(verification: verify)
        await h.history.configure(holdKind: point)
        try await h.coordinator.submit(p); try await h.approve(p.id)
        if verify != nil { try await h.approve(p.id) }
        await h.history.waitForHeldCommit()
        let cancellation = Task { await h.coordinator.cancel(p.id) }
        await h.policy.waitForRevocation(p.id)
        await h.history.releaseCommit(); await cancellation.value
        let done = try await h.coordinator.waitForState(p.id, .cancelled)
        #expect(done.lifecycle.state == .cancelled)
        await h.coordinator.shutdown()
    }
    @Test func cancellationDuringVerificationUsesVerifierCancellationPort() async throws {
        let executor = DeterministicExecutor(verification: .held)
        let h = try await Harness(executor: executor)
        let p = try plan(verification: operation("verify", kind: .verification))
        try await h.coordinator.submit(p); try await h.approve(p.id); try await h.approve(p.id)
        await executor.waitForStarts(2); await h.coordinator.cancel(p.id)
        #expect(try await h.coordinator.waitForState(p.id, .cancelled).lifecycle.state == .cancelled)
        #expect(await executor.cancelled.last?.operationID == "verify")
        await h.coordinator.shutdown()
    }

}

@Suite("Phase 1A remediation", .timeLimit(.minutes(1)))
@MainActor
struct RemediationTests {
    @Test func cancellationDoesNotInventOperationDisposition() async throws {
        let h = try await Harness(executor: .init(operation: .held))
        let p = try plan("uncertain-cancel")
        try await h.coordinator.submit(p); try await h.approve(p.id); await h.executor.waitForStarts(1)
        await h.coordinator.cancel(p.id)
        let done = try await h.coordinator.waitForState(p.id, .cancelled)
        #expect(done.lifecycle.state == .cancelled)
        #expect(done.outcomes.isEmpty); #expect(done.hasUnresolvedIntent); #expect(done.requiresInspection)
        let restart = try await Harness(history: h.history)
        #expect(await restart.coordinator.snapshot(p.id)?.requiresInspection == true)
        #expect(await restart.executor.started.isEmpty)
        await h.coordinator.shutdown(); await restart.coordinator.shutdown()
    }
    @Test(arguments: [-1, 0, 1])
    func completionDeadlineIsCheckedWithoutTimerDelivery(_ offset: Int64) async throws {
        let h = try await Harness(executor: .init(operation: .held)); let p = try plan("deadline")
        try await h.coordinator.submit(p); try await h.approve(p.id); await h.executor.waitForStarts(1)
        let deadline = await h.clock.now() + 300_000
        await h.clock.waitUntilScheduled(deadline); await h.clock.jumpWithoutWaking(to: deadline + offset)
        await h.executor.complete(p.steps[0])
        let done = try await h.coordinator.waitForState(p.id, offset < 0 ? .succeeded : .failed)
        #expect(done.lifecycle.state == (offset < 0 ? .succeeded : .failed(.timeout)))
        await h.coordinator.shutdown()
    }
}

extension RemediationTests {
    @Test func shutdownAccountsForPendingAdmissionBeforeReturning() async throws {
        let h = try await Harness(); let p = try plan("pending")
        await h.history.configure(holdKind: .submitted)
        let submission = Task { () -> Bool in
            do { try await h.coordinator.submit(p); return true }
            catch TaskServiceError.closed { return false }
            catch { Issue.record("Unexpected admission error: \(error)"); return false }
        }
        await h.history.waitForHeldCommit()
        let closing = Task { await h.coordinator.shutdown() }
        await h.clock.waitUntilScheduled(await h.clock.now() + 5_000)
        #expect(await h.coordinator.shutdownCompleted == false)
        #expect(await h.coordinator.pendingAdmissionIDs.contains(p.id))
        await #expect(throws: TaskServiceError.closed) { try await h.coordinator.submit(plan("too-late")) }
        await h.history.releaseCommit()
        #expect(await submission.value == false)
        await closing.value
        #expect(await h.coordinator.shutdownCompleted)
        #expect(await h.coordinator.pendingAdmissionIDs.isEmpty)
        #expect(await h.coordinator.snapshot(p.id)?.lifecycle.state == .cancelled)
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
    }
    @Test(arguments: [false, true])
    func shutdownReturnsAtBudgetWithStalledHistoryAndRepeatedCallers(_ backendFails: Bool) async throws {
        let h = try await Harness(executor: .init(operation: .held, cleanup: .held)); let p = try plan("stalled")
        try await h.coordinator.submit(p); try await h.approve(p.id); await h.executor.waitForStarts(1)
        await h.history.configure(holdKind: .cancellation)
        let first = Task { await h.coordinator.shutdown() }
        let second = Task { await h.coordinator.shutdown() }
        await h.history.waitForHeldCommit(); await h.executor.waitForCancellation()
        let deadline = await h.clock.now() + 5_000
        await h.clock.waitUntilScheduled(deadline); await h.clock.advance(to: deadline)
        await first.value; await second.value
        let emergency = try #require(await h.coordinator.snapshot(p.id))
        #expect(emergency.lifecycle.state.isTerminal); #expect(emergency.durability == .uncommitted)
        #expect(emergency.requiresInspection); #expect(await h.coordinator.isQuarantined)
        #expect(await h.coordinator.hasPendingPersistence)
        await h.coordinator.shutdown() // Already complete; cannot start a new five-second wait.
        if backendFails { await h.history.configure(failKind: .cancellation) }
        await h.history.releaseCommit(); await h.executor.releaseAll()
        await h.coordinator.waitForPersistenceSettlement()
        #expect(await h.coordinator.latePersistenceAcknowledgements.last?.succeeded == !backendFails)
        #expect(await h.coordinator.latePersistenceAcknowledgements.last?.failure == (backendFails ? .storageUnavailable : nil))
        #expect(await h.coordinator.snapshot(p.id)?.lifecycle.state == emergency.lifecycle.state)
        let restart = try await Harness(history: h.history)
        #expect(await restart.coordinator.snapshot(p.id)?.lifecycle.state == .failed(.interrupted))
        #expect(await restart.coordinator.snapshot(p.id)?.pendingApproval == nil)
        #expect(await restart.executor.started.isEmpty)
        await restart.coordinator.shutdown()
    }
    @Test func stalledAdmissionIsRejectedAndRemainsVisibleAfterBoundedShutdown() async throws {
        let h = try await Harness(); let p = try plan("stalled-admission")
        await h.history.configure(holdKind: .submitted)
        let submission = Task { () -> Bool in
            do { try await h.coordinator.submit(p); return true }
            catch TaskServiceError.closed { return false }
            catch { Issue.record("Unexpected error: \(error)"); return false }
        }
        await h.history.waitForHeldCommit()
        let closing = Task { await h.coordinator.shutdown() }
        let deadline = await h.clock.now() + 5_000
        await h.clock.waitUntilScheduled(deadline); await h.clock.advance(to: deadline)
        await closing.value
        #expect(await submission.value == false)
        let visible = try #require(await h.coordinator.snapshot(p.id))
        #expect(visible.lifecycle.state.isTerminal); #expect(visible.durability == .uncommitted)
        #expect(await h.coordinator.hasPendingPersistence)
        await h.history.releaseCommit(); await h.coordinator.waitForPersistenceSettlement()
        #expect(await h.coordinator.latePersistenceAcknowledgements.count == 1)
        #expect(await h.coordinator.snapshot(p.id)?.lifecycle.state == visible.lifecycle.state)
        let restart = try await Harness(history: h.history)
        #expect(await restart.coordinator.snapshot(p.id)?.lifecycle.state == .failed(.interrupted))
        #expect(await restart.executor.started.isEmpty)
        await restart.coordinator.shutdown()
    }
    @Test func cancellationDuringAdmissionNeverDispatchesOrReportsAcceptance() async throws {
        let h = try await Harness(); let p = try plan("cancel-admission")
        await h.history.configure(holdKind: .submitted)
        let submission = Task { () -> Bool in
            do { try await h.coordinator.submit(p); return true }
            catch TaskServiceError.closed { return false }
            catch { Issue.record("Unexpected error: \(error)"); return false }
        }
        await h.history.waitForHeldCommit()
        await h.coordinator.cancel(p.id)
        await h.history.releaseCommit()
        #expect(await submission.value == false)
        #expect(try await h.coordinator.waitForState(p.id, .cancelled).lifecycle.state == .cancelled)
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
    }
    @Test(arguments: [false, true])
    func admissionFailurePreservesUncertaintyAndNeverAcknowledges(_ afterSave: Bool) async throws {
        let h = try await Harness(); let p = try plan("failed-admission")
        await h.history.configure(failKind: .submitted, afterSave: afterSave)
        await #expect(throws: FixtureFailure.self) { try await h.coordinator.submit(p) }
        #expect(await h.coordinator.snapshot(p.id)?.durability == .uncommitted)
        #expect(await h.coordinator.isBlocked); #expect(await h.executor.started.isEmpty)
        await h.history.configure()
        let restart = try await Harness(history: h.history)
        #expect(await restart.coordinator.snapshot(p.id)?.lifecycle.state == (afterSave ? .failed(.interrupted) : nil))
        await h.coordinator.shutdown(); await restart.coordinator.shutdown()
    }
    @Test func lateSuccessIsDiagnosticAndCannotReplaceTimeout() async throws {
        let h = try await Harness(executor: .init(operation: .held, cleanup: .held)); let p = try plan("late")
        try await h.coordinator.submit(p); try await h.approve(p.id); await h.executor.waitForStarts(1)
        let deadline = await h.clock.now() + 300_000
        await h.clock.waitUntilScheduled(deadline); await h.clock.advance(to: deadline)
        await h.executor.waitForCancellation()
        // Adapter cancellation starts before the cancellation record commits. Do not
        // advance its cleanup deadline until this test's timeout intent is durable;
        // storage-stall/emergency-overlay behavior has separate coverage.
        _ = try await h.coordinator.waitForState(p.id, .cancelling)
        let cleanupDeadline = deadline + 5_000
        await h.clock.waitUntilScheduled(cleanupDeadline); await h.clock.advance(to: cleanupDeadline)
        let failed = try await h.coordinator.waitForState(p.id, .failed)
        #expect(failed.lifecycle.state == .failed(.timeout))
        await h.history.waitForEvent(.cleanup, for: p.id)
        await h.executor.complete(p.steps[0]); await h.executor.releaseAll()
        await h.history.waitForEvent(.lateResult, for: p.id)
        let saved = try #require(await h.history.load().first { $0.plan.id == p.id })
        #expect(saved.lifecycle.state == .failed(.timeout))
        #expect(saved.lateResults?.last?.succeeded == true); #expect(saved.outcomes.isEmpty)
        #expect(saved.requiresInspection)
        await h.coordinator.shutdown()
    }
    @Test(arguments: [-1, 0, 1])
    func verificationDeadlineCannotBeBypassedByLateSuccess(_ offset: Int64) async throws {
        let h = try await Harness(executor: .init(verification: .held))
        let p = try plan("verification-deadline", verification: operation("verify", kind: .verification))
        try await h.coordinator.submit(p); try await h.approve(p.id); try await h.approve(p.id)
        await h.executor.waitForStarts(2)
        let deadline = await h.clock.now() + 300_000
        await h.clock.waitUntilScheduled(deadline); await h.clock.jumpWithoutWaking(to: deadline + offset)
        await h.executor.complete(p.verification!)
        let done = try await h.coordinator.waitForState(p.id, offset < 0 ? .succeeded : .failed)
        #expect(done.lifecycle.state == (offset < 0 ? .succeeded : .failed(.timeout)))
        await h.coordinator.shutdown()
    }
    @Test func cancelledObserversTerminateAndReleaseCapturedResources() async throws {
        let h = try await Harness(); let p = try plan("observer")
        try await h.coordinator.submit(p)
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        for _ in 0..<32 {
            weak var reference: ObserverLifetime?
            var observer: Task<Void, Never>?
            do {
                let lifetime = ObserverLifetime(); reference = lifetime
                observer = Task { [lifetime] in
                    do { _ = try await h.coordinator.waitForState(p.id, .succeeded); Issue.record("Cancelled observer returned state") }
                    catch is CancellationError {} catch { Issue.record("Unexpected observer error: \(error)") }
                    withExtendedLifetime(lifetime) {}
                }
            }
            observer!.cancel(); await observer!.value; observer = nil
            #expect(reference == nil)
        }
        await h.coordinator.cancel(p.id)
        await h.coordinator.shutdown()
    }
    @Test(arguments: Array(0..<12))
    func concurrentAdmissionShutdownStress(_ iteration: Int) async throws {
        let h = try await Harness(); let coordinator = h.coordinator
        let cohort = TestCohort(33)
        let outcomes = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for index in 0..<32 {
                group.addTask {
                    await cohort.arrive()
                    do { try await coordinator.submit(plan("stress-\(iteration)-\(index)")); return 1 }
                    catch TaskServiceError.closed { return 2 }
                    catch TaskServiceError.queueFull { return 3 }
                    catch { Issue.record("Unexpected stress error: \(error)"); return -1 }
                }
            }
            group.addTask { await cohort.arrive(); await coordinator.shutdown(); return 0 }
            var result: [Int] = []
            for await value in group { result.append(value) }
            return result
        }
        print("admission-shutdown stress", iteration, "attempts 32 accepted", outcomes.filter { $0 == 1 }.count,
              "closed", outcomes.filter { $0 == 2 }.count, "full", outcomes.filter { $0 == 3 }.count)
        #expect(outcomes.count == 33); #expect(!outcomes.contains(-1))
        #expect(await coordinator.shutdownCompleted); #expect(await coordinator.pendingAdmissionIDs.isEmpty)
        #expect(await coordinator.allRecords().allSatisfy { $0.lifecycle.state.isTerminal })
        #expect(await h.executor.started.isEmpty)
        await #expect(throws: TaskServiceError.closed) { try await coordinator.submit(plan("after-stress")) }
        await coordinator.shutdown()
    }
}

extension RemediationTests {
    @Test func cancellationBeforeExecutionDoesNotInventUncertainty() async throws {
        let h = try await Harness(); let p = try plan("before-execution")
        try await h.coordinator.submit(p)
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        await h.coordinator.cancel(p.id)
        let done = try await h.coordinator.waitForState(p.id, .cancelled)
        #expect(done.intents.isEmpty); #expect(done.outcomes.isEmpty)
        #expect(done.requiresInspection == false); #expect(done.durability == .committed)
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
    }
    @Test func registeredObserverCancellationRemovesItsContinuation() async throws {
        let h = try await Harness(); let p = try plan("registered-observer")
        try await h.coordinator.submit(p)
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        let registered = TestFlag()
        let observer = Task {
            do {
                _ = try await h.coordinator.waitForStateSignallingRegistration(p.id, .succeeded, registered: registered)
                Issue.record("Cancelled registered waiter returned state")
            } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        }
        await registered.wait(); observer.cancel(); await observer.value
        #expect(await h.coordinator.snapshot(p.id)?.lifecycle.state.kind == .awaitingApproval)
        await h.coordinator.shutdown()
    }
    @Test func simultaneousDuplicateAdmissionsHaveOneAcknowledgement() async throws {
        let h = try await Harness(); let p = try plan("duplicate-admission")
        let coordinator = h.coordinator; let gate = TestCohort(2)
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    await gate.arrive()
                    do { try await coordinator.submit(p); return true }
                    catch TaskServiceError.duplicateTask { return false }
                    catch { Issue.record("Unexpected duplicate error: \(error)"); return false }
                }
            }
            var result: [Bool] = []; for await accepted in group { result.append(accepted) }; return result
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(await coordinator.allRecords().count == 1)
        #expect(await h.history.events(for: p.id).filter { $0.kind == .submitted }.count == 1)
        #expect(await h.executor.started.isEmpty)
        await coordinator.shutdown()
    }
    @Test func cancelledCallerCannotAcknowledgeAdmissionAfterCommit() async throws {
        let h = try await Harness(); let p = try plan("caller-cancelled")
        await h.history.configure(holdKind: .submitted)
        let submission = Task { () -> Bool in
            do { try await h.coordinator.submit(p); return true }
            catch TaskServiceError.closed { return false }
            catch is CancellationError { return false }
            catch { Issue.record("Unexpected error: \(error)"); return false }
        }
        await h.history.waitForHeldCommit(); submission.cancel()
        await h.history.releaseCommit()
        #expect(await submission.value == false)
        #expect(await h.coordinator.snapshot(p.id)?.lifecycle.state == .cancelled)
        #expect(await h.executor.started.isEmpty)
        await h.coordinator.shutdown()
    }
    @Test(arguments: [-1, 0, 1])
    func finalCumulativeBudgetChecksResultsWithoutTimerDelivery(_ offset: Int64) async throws {
        let h = try await Harness(executor: .init(operation: .held))
        let operations = (0..<4).map { operation("budget-\($0)") }
        let p = try plan("final-budget", steps: operations)
        try await h.coordinator.submit(p)
        for index in 0..<3 {
            _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
            await h.clock.advance(to: await h.clock.now() + 100_000)
            try await h.approve(p.id); await h.executor.waitForStarts(index + 1)
            let deadline = await h.clock.now() + 300_000
            await h.clock.waitUntilScheduled(deadline); await h.clock.advance(to: deadline - 1)
            await h.executor.complete(operations[index])
        }
        _ = try await h.coordinator.waitForState(p.id, .awaitingApproval)
        try await h.approve(p.id); await h.executor.waitForStarts(4)
        let deadline = await h.clock.now() + 3
        #expect(await h.coordinator.snapshot(p.id)?.executionDeadline == deadline)
        await h.clock.waitUntilScheduled(deadline); await h.clock.jumpWithoutWaking(to: deadline + offset)
        await h.executor.complete(operations[3])
        let done = try await h.coordinator.waitForState(p.id, offset < 0 ? .succeeded : .failed)
        #expect(done.lifecycle.state == (offset < 0 ? .succeeded : .failed(.timeout)))
        await h.coordinator.shutdown()
    }
}
