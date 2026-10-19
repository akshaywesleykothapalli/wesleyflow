import Domain

/// Restricted adapter for the EXISTING coordinator. It prepares data; no productive operation dispatch.
public actor ProposalTaskExecutor: TaskOperationExecutor {
    private let taskID: TaskIdentifier
    private let operation: ScopedOperation
    private let generation: Int
    private let request: InferenceRequest
    private let service: any ProposalPreparationService
    private var used = false
    private var cancelled = false
    private var result: PreparedProposal?
    public init(taskID: TaskIdentifier, operation: ScopedOperation, request: InferenceRequest, generation: Int = 0, service: any ProposalPreparationService) throws {
        guard operation.kind == .inspection, generation >= 0 else { throw TaskServiceError.unsupportedOperation }
        self.generation = generation; self.taskID = taskID; self.operation = operation; self.request = request; self.service = service
    }
    public func execute(_ operation: ScopedOperation, token: OperationToken) async throws -> OperationResult {
        guard !Task.isCancelled, !cancelled, !used, self.operation == operation, token.taskID == taskID,
              token.operationID == operation.id, token.generation == generation else { throw TaskServiceError.staleOperation }
        used = true
        let prepared = try await service.prepare(request)
        guard !Task.isCancelled, !cancelled else { throw TaskServiceError.staleOperation }
        result = prepared
        // Original revision is unchanged. Task success means proposal prepared, never code verified/applied.
        return .init(succeeded:true, observedRevision:operation.revision)
    }
    public func cancel(_ token: OperationToken) async -> CancellationAcknowledgement {
        guard token.taskID == taskID, token.operationID == operation.id, token.generation == generation else { return .uncertain }
        cancelled = true; result = nil
        switch await service.cancel(requestID:request.id) {
        case .notSent, .completed: return .stopped
        case .httpCancelledProviderUncertain, .residencyAbsent: return .uncertain
        }
    }
    public func takePreparedProposal() -> PreparedProposal? { let value = result; result = nil; return value }
}
