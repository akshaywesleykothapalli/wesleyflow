// Values and ports only. No framework objects or native execution authority.
public enum TaskServiceError: Error, Equatable, Sendable {
    case invalidPlan, queueFull, notStarted, duplicateTask, unknownTask
    case blocked, staleOperation, approvalDenied, approvalExpired, approvalRequired
    case unsupportedOperation, repositoryConflict, storageUnavailable, quotaExceeded
    case incompatibleSchema, corruptStore, storeAlreadyOpen, closed, executionLimit
}

public enum OperationKind: String, Codable, Sendable { case inspection, verification, fileWrite, process, automation }

public struct ScopedOperation: Codable, Equatable, Sendable {
    public let id: String
    public let kind: OperationKind
    public let digest: String
    public let workspaceID: String
    public let revision: String
    public init(id: String, kind: OperationKind = .inspection, digest: String, workspaceID: String, revision: String) {
        self.id = id; self.kind = kind; self.digest = digest
        self.workspaceID = workspaceID; self.revision = revision
    }
}

public struct TaskPlan: Codable, Equatable, Sendable {
    public let id: TaskIdentifier
    public let workflowID: String
    public let workflowVersion: Int
    public let workspaceID: String
    public let revision: String
    public let steps: [ScopedOperation]
    public let verification: ScopedOperation?
    public let retryOf: TaskIdentifier?
    public let retryCount: Int
    public init(id: TaskIdentifier, workflowID: String = "inline", workflowVersion: Int = 1, workspaceID: String, revision: String,
                steps: [ScopedOperation], verification: ScopedOperation? = nil,
                retryOf: TaskIdentifier? = nil, retryCount: Int = 0) throws {
        self.id = id; self.workflowID = workflowID; self.workflowVersion = workflowVersion; self.workspaceID = workspaceID
        self.revision = revision; self.steps = steps; self.verification = verification
        self.retryOf = retryOf; self.retryCount = retryCount
        try validate()
    }
    public func validate() throws {
        func identifier(_ s: String) -> Bool {
            !s.isEmpty && s.utf8.count <= 128 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_:.".contains($0)) }
        }
        let operations = steps + (verification.map { [$0] } ?? [])
        guard identifier(workflowID), identifier(id.rawValue), identifier(workspaceID), identifier(revision), workflowVersion > 0,
              !steps.isEmpty, operations.count <= 50, retryCount >= 0, retryCount <= 2,
              retryOf != id, (retryCount == 0) == (retryOf == nil), Set(operations.map(\.id)).count == operations.count,
              verification == nil || verification?.kind == .verification,
              steps.allSatisfy({ $0.kind != .verification }), operations.allSatisfy({ op in
                  identifier(op.id) && op.workspaceID == workspaceID && op.revision == revision &&
                  op.digest.utf8.count == 64 && op.digest.allSatisfy({ "0123456789abcdef".contains($0) })
              }) else { throw TaskServiceError.invalidPlan }
    }
    public var verificationRequirement: VerificationRequirement { verification == nil ? .none : .required }
}

public struct ApprovalRequest: Codable, Equatable, Sendable {
    public let id: String
    public let taskID: TaskIdentifier
    public let operation: ScopedOperation
    public let generation: Int
    public let session: String
    public let expiresAt: Int64
    public init(id: String, taskID: TaskIdentifier, operation: ScopedOperation, generation: Int, session: String, expiresAt: Int64) {
        self.id = id; self.taskID = taskID; self.operation = operation
        self.generation = generation; self.session = session; self.expiresAt = expiresAt
    }
}

public struct OperationToken: Equatable, Sendable {
    public let taskID: TaskIdentifier
    public let operationID: String
    public let generation: Int
    public init(taskID: TaskIdentifier, operationID: String, generation: Int) {
        self.taskID = taskID; self.operationID = operationID; self.generation = generation
    }
}

public struct OperationResult: Equatable, Sendable {
    public let succeeded: Bool
    public let observedRevision: String
    public init(succeeded: Bool, observedRevision: String) { self.succeeded = succeeded; self.observedRevision = observedRevision }
}
public struct VerificationEvidence: Equatable, Sendable {
    public let passed: Bool
    public let operationDigest: String
    public let observedRevision: String
    public init(passed: Bool, operationDigest: String, observedRevision: String) {
        self.passed = passed; self.operationDigest = operationDigest; self.observedRevision = observedRevision
    }
}
/// Resource termination only; stopped never establishes whether an operation was applied.
public enum CancellationAcknowledgement: Equatable, Sendable { case stopped, uncertain }
/// Acknowledgement of storage, not an operation's execution disposition.
public struct PersistenceAcknowledgement: Equatable, Sendable {
    public let taskID: TaskIdentifier
    public let sequence: Int
    public let succeeded: Bool
    public let failure: TaskServiceError?
    public init(taskID: TaskIdentifier, sequence: Int, succeeded: Bool, failure: TaskServiceError? = nil) {
        self.taskID = taskID; self.sequence = sequence; self.succeeded = succeeded; self.failure = failure
    }
}
public struct LateOperationResult: Codable, Equatable, Sendable {
    public let operationID: String
    public let generation: Int
    public let observedAt: Int64
    public let succeeded: Bool
    public let revisionMatches: Bool
    public let digestMatches: Bool
    public init(operationID: String, generation: Int, observedAt: Int64, succeeded: Bool, revisionMatches: Bool, digestMatches: Bool) {
        self.operationID = operationID; self.generation = generation; self.observedAt = observedAt
        self.succeeded = succeeded; self.revisionMatches = revisionMatches; self.digestMatches = digestMatches
    }
}
public enum Durability: String, Codable, Sendable { case committed, uncommitted }

public struct TaskRecord: Codable, Equatable, Sendable {
    public let plan: TaskPlan
    public var lifecycle: TaskLifecycle
    public var sequence: Int
    public let createdAt: Int64
    public var updatedAt: Int64
    public var completedOperations: [String] = []
    public var intents: [String] = []
    public var outcomes: [String] = []
    // Optional additions decode existing v1 payloads without a schema reset/migration.
    // This session's clock anchor is diagnostic only after restart; recovery never resumes a deadline.
    public var executionDeadline: Int64?
    public var lateResults: [LateOperationResult]?
    public var pendingApproval: ApprovalRequest?
    public var previousState: TaskState?
    public var requiresInspection = false
    public var durability: Durability = .committed
    public init(plan: TaskPlan, now: Int64) {
        self.plan = plan
        self.lifecycle = TaskLifecycle(id: plan.id, verification: plan.verificationRequirement, retryOf: plan.retryOf)
        self.sequence = 0; self.createdAt = now; self.updatedAt = now
    }
    public var hasUnresolvedIntent: Bool { intents.contains { !outcomes.contains($0) } }
}

public enum TaskEventKind: String, Codable, Sendable {
    case submitted, transition, approvalRequested, approvalGranted, approvalDenied
    case intent, outcome, verification, cancellation, cleanup, interrupted, lateResult
}
public struct TaskEventRecord: Codable, Equatable, Sendable {
    public let taskID: TaskIdentifier
    public let sequence: Int
    public let timestamp: Int64
    public let kind: TaskEventKind
    public let state: TaskState
    public let operationID: String?
    public let operationDigest: String?
    public let generation: Int
    public init(record: TaskRecord, kind: TaskEventKind, operation: ScopedOperation? = nil, generation: Int) {
        taskID = record.plan.id; sequence = record.sequence; timestamp = record.updatedAt
        self.kind = kind; state = record.lifecycle.state
        operationID = operation?.id; operationDigest = operation?.digest; self.generation = generation
    }
}

public protocol TaskClock: Sendable {
    func now() async -> Int64
    func sleep(until deadline: Int64) async throws
}
public protocol TaskHistoryRepository: Sendable {
    func load() async throws -> [TaskRecord]
    func commit(_ record: TaskRecord, event: TaskEventRecord, expectedSequence: Int?) async throws
    func events(for taskID: TaskIdentifier) async throws -> [TaskEventRecord]
}
public protocol TaskPermissionPolicy: Sendable {
    func beginSession() async
    func request(taskID: TaskIdentifier, operation: ScopedOperation, generation: Int) async throws -> ApprovalRequest
    func validate(_ request: ApprovalRequest, operation: ScopedOperation, generation: Int) async throws
    func consume(_ request: ApprovalRequest, operation: ScopedOperation, generation: Int, notAfter: Int64) async throws
    func revoke(taskID: TaskIdentifier) async
}
public protocol TaskOperationExecutor: Sendable {
    func execute(_ operation: ScopedOperation, token: OperationToken) async throws -> OperationResult
    func cancel(_ token: OperationToken) async -> CancellationAcknowledgement
}
public protocol TaskVerificationRunner: Sendable {
    func verify(_ operation: ScopedOperation, token: OperationToken) async throws -> VerificationEvidence
    func cancel(_ token: OperationToken) async -> CancellationAcknowledgement
}
