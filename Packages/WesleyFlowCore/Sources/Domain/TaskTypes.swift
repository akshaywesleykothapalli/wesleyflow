/// An application-assigned identifier; this value grants no authority.
public struct TaskIdentifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum VerificationRequirement: Equatable, Sendable {
    case none
    case required
}

public enum TaskPhase: Equatable, Sendable {
    case running
    case verifying
}

public enum TaskFailure: Equatable, Sendable {
    case setup
    case approvalExpired
    case approvalRevoked
    case timeout
    case execution
    case verification
    case storage
    case interrupted
    case cleanupIncomplete
}

public enum CancellationIntent: Equatable, Sendable {
    case cancelled
    case failed(TaskFailure)
}

public enum TaskState: Equatable, Sendable {
    case queued
    case planning
    case awaitingApproval(resumePhase: TaskPhase)
    case running
    case verifying
    case cancelling(intent: CancellationIntent)
    case succeeded
    case failed(TaskFailure)
    case cancelled

    public enum Kind: String, CaseIterable, Sendable {
        case queued, planning, awaitingApproval, running, verifying
        case cancelling, succeeded, failed, cancelled
    }

    public var kind: Kind {
        switch self {
        case .queued: .queued
        case .planning: .planning
        case .awaitingApproval: .awaitingApproval
        case .running: .running
        case .verifying: .verifying
        case .cancelling: .cancelling
        case .succeeded: .succeeded
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: true
        default: false
        }
    }
}

public enum TaskEvent: Equatable, Sendable {
    case start
    case requestApproval
    case approveExecution
    case approveVerification
    case planReady
    case executionDone
    case noVerificationDone
    case verificationPassed
    case cancel(CancellationIntent)
    case cleanupCancelled
    case cleanupFailed(TaskFailure)
    case failure(TaskFailure)
    case interrupted

    public enum Kind: String, CaseIterable, Sendable {
        case start, requestApproval, approveExecution, approveVerification, planReady
        case executionDone, noVerificationDone, verificationPassed, cancel
        case cleanupCancelled, cleanupFailed, failure, interrupted
    }

    public var kind: Kind {
        switch self {
        case .start: .start
        case .requestApproval: .requestApproval
        case .approveExecution: .approveExecution
        case .approveVerification: .approveVerification
        case .planReady: .planReady
        case .executionDone: .executionDone
        case .noVerificationDone: .noVerificationDone
        case .verificationPassed: .verificationPassed
        case .cancel: .cancel
        case .cleanupCancelled: .cleanupCancelled
        case .cleanupFailed: .cleanupFailed
        case .failure: .failure
        case .interrupted: .interrupted
        }
    }
}

/// Facts to be established by a future coordinator/broker. This pure value is
/// not an approval token, verifier, resource lease, or execution capability.
public struct TransitionFacts: Equatable, Sendable {
    public var isQueueHead = false
    public var hasExecutionLease = false
    public var hasPendingExactOperation = false
    public var hasActiveEffect = false
    public var approvalIsValid = false
    public var planningIsComplete = false
    public var executionIsComplete = false
    public var evidenceIsCommitted = false
    public var workspaceRevisionMatches = false
    public var resourcesAreReleased = false
    public var cleanupIsComplete = false
    public var cleanupDidFail = false
    public var isStartupRecovery = false
    public var previousSessionIsRevoked = false
    public var effectsAreUncertain = false

    public init() {}
}

public enum TransitionCondition: Equatable, Sendable {
    case queueHead, executionLease, pendingExactOperation, noActiveEffect
    case approvalValid, approvalResumePhase, planningComplete, noPendingApproval
    case executionComplete, verificationRequired, verificationNotRequired
    case evidenceCommitted, workspaceRevision, resourcesReleased
    case cancellationIntent, cleanupComplete, cleanupFailure
    case startupRecovery, previousSessionRevoked, uncertainEffects
}

public enum TaskTransitionError: Error, Equatable, Sendable {
    case invalidTransition(state: TaskState.Kind, event: TaskEvent.Kind)
    case unmetCondition(TransitionCondition)
    case retryRequiresTerminalState
    case retryRequiresNewIdentifier
}
