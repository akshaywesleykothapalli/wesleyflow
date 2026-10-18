/// Pure lifecycle rules only. No execution, permission issuance, or persistence.
public enum TaskTransitions {
    public static func nextState(
        from state: TaskState,
        event: TaskEvent,
        verification: VerificationRequirement,
        facts: TransitionFacts
    ) throws -> TaskState {
        guard !state.isTerminal else {
            throw TaskTransitionError.invalidTransition(state: state.kind, event: event.kind)
        }

        switch (state, event) {
        case (.queued, .start):
            try require(facts.isQueueHead, .queueHead)
            try require(facts.hasExecutionLease, .executionLease)
            return .planning

        case (.planning, .requestApproval), (.running, .requestApproval),
             (.verifying, .requestApproval):
            try require(facts.hasPendingExactOperation, .pendingExactOperation)
            if state.kind != .planning { try require(!facts.hasActiveEffect, .noActiveEffect) }
            return .awaitingApproval(resumePhase: state.kind == .verifying ? .verifying : .running)

        case (.awaitingApproval(let phase), .approveExecution):
            try require(facts.approvalIsValid, .approvalValid)
            try require(phase == .running, .approvalResumePhase)
            return .running

        case (.awaitingApproval(let phase), .approveVerification):
            try require(facts.approvalIsValid, .approvalValid)
            try require(phase == .verifying, .approvalResumePhase)
            return .verifying

        case (.planning, .planReady):
            try require(facts.planningIsComplete, .planningComplete)
            try require(!facts.hasPendingExactOperation, .noPendingApproval)
            return .running

        case (.running, .executionDone):
            try require(verification == .required, .verificationRequired)
            try require(facts.executionIsComplete, .executionComplete)
            return .verifying

        case (.running, .noVerificationDone):
            try require(verification == .none, .verificationNotRequired)
            try require(facts.executionIsComplete, .executionComplete)
            return .succeeded

        case (.verifying, .verificationPassed):
            try require(facts.evidenceIsCommitted, .evidenceCommitted)
            try require(facts.workspaceRevisionMatches, .workspaceRevision)
            return .succeeded

        case (.queued, .cancel(let intent)), (.planning, .cancel(let intent)),
             (.awaitingApproval, .cancel(let intent)), (.running, .cancel(let intent)),
             (.verifying, .cancel(let intent)):
            return .cancelling(intent: intent)

        case (.cancelling(let intent), .cleanupCancelled):
            try require(intent == .cancelled, .cancellationIntent)
            try require(facts.cleanupIsComplete, .cleanupComplete)
            return .cancelled

        case (.cancelling(let intent), .cleanupFailed(let reason)):
            if reason == .interrupted {
                try requireRecovery(facts)
                return .failed(.interrupted)
            }
            try require(facts.cleanupIsComplete || facts.cleanupDidFail, .cleanupComplete)
            if case .failed(let originalReason) = intent { return .failed(originalReason) }
            try require(facts.cleanupDidFail, .cleanupFailure)
            return .failed(reason)

        case (.queued, .failure(let reason)), (.planning, .failure(let reason)),
             (.awaitingApproval, .failure(let reason)), (.running, .failure(let reason)),
             (.verifying, .failure(let reason)):
            try require(facts.resourcesAreReleased, .resourcesReleased)
            return .failed(reason)

        case (.queued, .interrupted), (.planning, .interrupted),
             (.awaitingApproval, .interrupted), (.running, .interrupted),
             (.verifying, .interrupted):
            try requireRecovery(facts)
            return .failed(.interrupted)

        default:
            throw TaskTransitionError.invalidTransition(state: state.kind, event: event.kind)
        }
    }

    private static func require(_ condition: Bool, _ reason: TransitionCondition) throws {
        guard condition else { throw TaskTransitionError.unmetCondition(reason) }
    }

    private static func requireRecovery(_ facts: TransitionFacts) throws {
        try require(facts.isStartupRecovery, .startupRecovery)
        try require(facts.previousSessionIsRevoked, .previousSessionRevoked)
        try require(facts.effectsAreUncertain, .uncertainEffects)
    }
}

public struct TaskLifecycle: Equatable, Sendable {
    public let id: TaskIdentifier
    public let retryOf: TaskIdentifier?
    public let verification: VerificationRequirement
    public private(set) var state: TaskState = .queued

    public init(id: TaskIdentifier, verification: VerificationRequirement) {
        self.id = id
        self.verification = verification
        self.retryOf = nil
    }

    private init(id: TaskIdentifier, verification: VerificationRequirement, retryOf: TaskIdentifier) {
        self.id = id
        self.verification = verification
        self.retryOf = retryOf
    }

    /// Mutation occurs only after all rules pass; a thrown error preserves self.
    public mutating func apply(_ event: TaskEvent, facts: TransitionFacts = .init()) throws {
        state = try TaskTransitions.nextState(from: state, event: event, verification: verification, facts: facts)
    }

    public func retry(with newID: TaskIdentifier) throws -> TaskLifecycle {
        guard state.isTerminal else { throw TaskTransitionError.retryRequiresTerminalState }
        guard newID != id else { throw TaskTransitionError.retryRequiresNewIdentifier }
        return TaskLifecycle(id: newID, verification: verification, retryOf: id)
    }
}
