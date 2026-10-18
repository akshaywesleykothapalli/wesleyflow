import Testing
@testable import Domain

@Suite("Approved lifecycle specification")
struct TaskLifecycleTests {
    // Independent oracle transcribed from the approved Phase 0A transition table.
    // Production rules are never queried to build expected destinations.
    private static let oracle: [TaskState.Kind: [TaskEvent.Kind: TaskState.Kind]] = [
        .queued: [.start: .planning, .cancel: .cancelling, .failure: .failed, .interrupted: .failed],
        .planning: [.requestApproval: .awaitingApproval, .planReady: .running,
                    .cancel: .cancelling, .failure: .failed, .interrupted: .failed],
        .awaitingApproval: [.approveExecution: .running, .approveVerification: .verifying,
                           .cancel: .cancelling, .failure: .failed, .interrupted: .failed],
        .running: [.requestApproval: .awaitingApproval, .executionDone: .verifying,
                   .noVerificationDone: .succeeded, .cancel: .cancelling,
                   .failure: .failed, .interrupted: .failed],
        .verifying: [.requestApproval: .awaitingApproval, .verificationPassed: .succeeded,
                     .cancel: .cancelling, .failure: .failed, .interrupted: .failed],
        .cancelling: [.cleanupCancelled: .cancelled, .cleanupFailed: .failed],
        .succeeded: [:], .failed: [:], .cancelled: [:]
    ]

    @Test(arguments: TaskState.Kind.allCases, TaskEvent.Kind.allCases)
    func everyStateEventPair(state: TaskState.Kind, event: TaskEvent.Kind) {
        let source = Self.state(state, for: event)
        let input = Self.event(event)
        let expected = Self.oracle[state]?[event]
        let verification: VerificationRequirement = event == .noVerificationDone ? .none : .required
        var facts = Self.satisfiedFacts
        facts.hasPendingExactOperation = event == .requestApproval
        do {
            let next = try TaskTransitions.nextState(from: source, event: input, verification: verification, facts: facts)
            #expect(expected != nil)
            #expect(next.kind == expected)
        } catch let error as TaskTransitionError {
            #expect(expected == nil)
            #expect(error == .invalidTransition(state: state, event: event))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func specificationHas117PairsAnd27AllowedTransitions() {
        #expect(TaskState.Kind.allCases.count * TaskEvent.Kind.allCases.count == 117)
        #expect(Self.oracle.values.reduce(0) { $0 + $1.count } == 27)
    }

    @Test(arguments: guardCases())
    func unsafeFactsCannotCrossGuard(_ example: GuardCase) {
        #expect(throws: TaskTransitionError.unmetCondition(example.condition)) {
            try TaskTransitions.nextState(
                from: example.state, event: example.event,
                verification: example.verification, facts: example.facts
            )
        }
    }

    @Test func verificationApprovalReturnsToVerification() throws {
        let paused = try TaskTransitions.nextState(
            from: .verifying, event: .requestApproval, verification: .required, facts: Self.satisfiedFacts
        )
        #expect(paused == .awaitingApproval(resumePhase: .verifying))
        let resumed = try TaskTransitions.nextState(
            from: paused, event: .approveVerification, verification: .required, facts: Self.satisfiedFacts
        )
        #expect(resumed == .verifying)
    }

    @Test func failedCleanupPreservesOriginalFailureAfterSuccessfulCleanup() throws {
        let state = try TaskTransitions.nextState(
            from: .cancelling(intent: .failed(.timeout)), event: .cleanupFailed(.cleanupIncomplete),
            verification: .required, facts: Self.satisfiedFacts
        )
        #expect(state == .failed(.timeout))
    }

    @Test func cancellingRecoveryUsesInterruptionRatherThanResuming() throws {
        let state = try TaskTransitions.nextState(
            from: .cancelling(intent: .failed(.timeout)), event: .cleanupFailed(.interrupted),
            verification: .required, facts: Self.satisfiedFacts
        )
        #expect(state == .failed(.interrupted))
    }

    @Test func applyingRejectedEventDoesNotMutateTask() throws {
        var task = TaskLifecycle(id: .init(rawValue: "task-a"), verification: .required)
        let original = task
        #expect(throws: TaskTransitionError.unmetCondition(.queueHead)) { try task.apply(.start) }
        #expect(task == original)
        try task.apply(.start, facts: Self.satisfiedFacts)
        #expect(task.state == .planning)
    }

    @Test func retryCreatesNewLinkedQueuedValueWithoutChangingOriginal() throws {
        var task = TaskLifecycle(id: .init(rawValue: "task-a"), verification: .required)
        try task.apply(.failure(.setup), facts: Self.satisfiedFacts)
        let original = task
        let retried = try task.retry(with: .init(rawValue: "task-b"))
        #expect(retried.state == .queued)
        #expect(retried.id.rawValue == "task-b")
        #expect(retried.retryOf == task.id)
        #expect(retried.verification == .required)
        #expect(task == original)
        #expect(throws: TaskTransitionError.retryRequiresNewIdentifier) { try task.retry(with: task.id) }
    }

    @Test func activeTaskCannotBeRetried() {
        let task = TaskLifecycle(id: .init(rawValue: "task-a"), verification: .none)
        #expect(throws: TaskTransitionError.retryRequiresTerminalState) {
            try task.retry(with: .init(rawValue: "task-b"))
        }
    }

    @Test func cancellationIntentSurvivesUntilCleanup() throws {
        var task = TaskLifecycle(id: .init(rawValue: "task-a"), verification: .none)
        try task.apply(.cancel(.failed(.storage)))
        #expect(task.state == .cancelling(intent: .failed(.storage)))
        #expect(throws: TaskTransitionError.unmetCondition(.cancellationIntent)) {
            try task.apply(.cleanupCancelled, facts: Self.satisfiedFacts)
        }
        try task.apply(.cleanupFailed(.cleanupIncomplete), facts: Self.satisfiedFacts)
        #expect(task.state == .failed(.storage))
    }

    @Test(arguments: [TaskFailure.approvalExpired, .approvalRevoked, .timeout, .setup, .storage])
    func approvalWaitCanFailLocallyWithTypedCause(_ reason: TaskFailure) throws {
        let next = try TaskTransitions.nextState(
            from: .awaitingApproval(resumePhase: .running), event: .failure(reason),
            verification: .required, facts: Self.satisfiedFacts
        )
        #expect(next == .failed(reason))
    }

    private static var satisfiedFacts: TransitionFacts {
        var f = TransitionFacts()
        f.isQueueHead = true
        f.hasExecutionLease = true
        f.hasPendingExactOperation = true
        f.approvalIsValid = true
        f.planningIsComplete = true
        f.executionIsComplete = true
        f.evidenceIsCommitted = true
        f.workspaceRevisionMatches = true
        f.resourcesAreReleased = true
        f.cleanupIsComplete = true
        f.cleanupDidFail = true
        f.isStartupRecovery = true
        f.previousSessionIsRevoked = true
        f.effectsAreUncertain = true
        return f
    }

    private static func state(_ kind: TaskState.Kind, for event: TaskEvent.Kind) -> TaskState {
        switch kind {
        case .queued: .queued
        case .planning: .planning
        case .awaitingApproval: .awaitingApproval(resumePhase: event == .approveVerification ? .verifying : .running)
        case .running: .running
        case .verifying: .verifying
        case .cancelling: .cancelling(intent: .cancelled)
        case .succeeded: .succeeded
        case .failed: .failed(.execution)
        case .cancelled: .cancelled
        }
    }

    private static func event(_ kind: TaskEvent.Kind) -> TaskEvent {
        switch kind {
        case .start: .start
        case .requestApproval: .requestApproval
        case .approveExecution: .approveExecution
        case .approveVerification: .approveVerification
        case .planReady: .planReady
        case .executionDone: .executionDone
        case .noVerificationDone: .noVerificationDone
        case .verificationPassed: .verificationPassed
        case .cancel: .cancel(.cancelled)
        case .cleanupCancelled: .cleanupCancelled
        case .cleanupFailed: .cleanupFailed(.cleanupIncomplete)
        case .failure: .failure(.execution)
        case .interrupted: .interrupted
        }
    }

    struct GuardCase: Sendable {
        let state: TaskState
        let event: TaskEvent
        let verification: VerificationRequirement
        let facts: TransitionFacts
        let condition: TransitionCondition
    }

    static func guardCases() -> [GuardCase] {
        var cases: [GuardCase] = []
        func add(_ state: TaskState, _ event: TaskEvent, _ key: WritableKeyPath<TransitionFacts, Bool>,
                 _ condition: TransitionCondition, value: Bool = false,
                 verification: VerificationRequirement = .required) {
            var f = satisfiedFacts
            f[keyPath: key] = value
            if event == .planReady, key != \TransitionFacts.hasPendingExactOperation {
                f.hasPendingExactOperation = false
            }
            cases.append(GuardCase(state: state, event: event, verification: verification, facts: f, condition: condition))
        }
        add(.queued, .start, \.isQueueHead, .queueHead)
        add(.queued, .start, \.hasExecutionLease, .executionLease)
        add(.planning, .requestApproval, \.hasPendingExactOperation, .pendingExactOperation)
        add(.running, .requestApproval, \.hasActiveEffect, .noActiveEffect, value: true)
        add(.verifying, .requestApproval, \.hasActiveEffect, .noActiveEffect, value: true)
        add(.awaitingApproval(resumePhase: .running), .approveExecution, \.approvalIsValid, .approvalValid)
        add(.awaitingApproval(resumePhase: .verifying), .approveVerification, \.approvalIsValid, .approvalValid)
        add(.planning, .planReady, \.planningIsComplete, .planningComplete)
        add(.planning, .planReady, \.hasPendingExactOperation, .noPendingApproval, value: true)
        add(.running, .executionDone, \.executionIsComplete, .executionComplete)
        add(.running, .noVerificationDone, \.executionIsComplete, .executionComplete, verification: .none)
        add(.verifying, .verificationPassed, \.evidenceIsCommitted, .evidenceCommitted)
        add(.verifying, .verificationPassed, \.workspaceRevisionMatches, .workspaceRevision)
        let activeStates: [TaskState] = [.queued, .planning, .awaitingApproval(resumePhase: .running), .running, .verifying]
        for state in activeStates {
            add(state, .failure(.timeout), \.resourcesAreReleased, .resourcesReleased)
            add(state, .interrupted, \.isStartupRecovery, .startupRecovery)
            add(state, .interrupted, \.previousSessionIsRevoked, .previousSessionRevoked)
            add(state, .interrupted, \.effectsAreUncertain, .uncertainEffects)
        }
        add(.cancelling(intent: .cancelled), .cleanupCancelled, \.cleanupIsComplete, .cleanupComplete)
        add(.cancelling(intent: .failed(.timeout)), .cleanupFailed(.interrupted), \.isStartupRecovery, .startupRecovery)
        add(.cancelling(intent: .failed(.timeout)), .cleanupFailed(.interrupted), \.previousSessionIsRevoked, .previousSessionRevoked)
        add(.cancelling(intent: .failed(.timeout)), .cleanupFailed(.interrupted), \.effectsAreUncertain, .uncertainEffects)
        add(.cancelling(intent: .cancelled), .cleanupFailed(.cleanupIncomplete), \.cleanupDidFail, .cleanupFailure)
        cases += [
            GuardCase(state: .awaitingApproval(resumePhase: .verifying), event: .approveExecution,
                      verification: .required, facts: satisfiedFacts, condition: .approvalResumePhase),
            GuardCase(state: .awaitingApproval(resumePhase: .running), event: .approveVerification,
                      verification: .required, facts: satisfiedFacts, condition: .approvalResumePhase),
            GuardCase(state: .running, event: .noVerificationDone,
                      verification: .required, facts: satisfiedFacts, condition: .verificationNotRequired),
            GuardCase(state: .running, event: .executionDone,
                      verification: .none, facts: satisfiedFacts, condition: .verificationRequired),
            GuardCase(state: .cancelling(intent: .failed(.timeout)), event: .cleanupCancelled,
                      verification: .required, facts: satisfiedFacts, condition: .cancellationIntent)
        ]
        var notClean = satisfiedFacts
        notClean.cleanupIsComplete = false
        notClean.cleanupDidFail = false
        cases.append(GuardCase(state: .cancelling(intent: .failed(.timeout)), event: .cleanupFailed(.cleanupIncomplete),
                               verification: .required, facts: notClean, condition: .cleanupComplete))
        return cases
    }
}
