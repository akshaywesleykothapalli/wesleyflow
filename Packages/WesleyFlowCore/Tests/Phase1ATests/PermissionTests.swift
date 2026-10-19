import Domain
import SystemOperations
import Testing

@Suite("Scoped human authority", .timeLimit(.minutes(1)))
@MainActor
struct PermissionTests {
    @Test func grantsBindScopeDigestGenerationSessionAndAreOneUse() async throws {
        let clock = ManualTaskClock(); let pair = PermissionBroker.compose(clock: clock)
        let id = TaskIdentifier(rawValue: "task"); let op = operation()
        let request = try await pair.policy.request(taskID: id, operation: op, generation: 7)
        await #expect(throws: TaskServiceError.approvalRequired) { try await pair.policy.consume(request, operation: op, generation: 7) }
        try await pair.authority.approve(request.id)
        let changed = ScopedOperation(id: op.id, digest: String(repeating: "b", count: 64), workspaceID: op.workspaceID, revision: op.revision)
        await #expect(throws: TaskServiceError.staleOperation) { try await pair.policy.consume(request, operation: changed, generation: 7) }
        await #expect(throws: TaskServiceError.staleOperation) { try await pair.policy.consume(request, operation: op, generation: 8) }
        let outside = ScopedOperation(id: op.id, digest: op.digest, workspaceID: "another-workspace", revision: op.revision)
        await #expect(throws: TaskServiceError.staleOperation) { try await pair.policy.consume(request, operation: outside, generation: 7) }
        try await pair.policy.consume(request, operation: op, generation: 7)
        await #expect(throws: TaskServiceError.staleOperation) { try await pair.policy.consume(request, operation: op, generation: 7) }
        let old = try await pair.policy.request(taskID: id, operation: op, generation: 9)
        try await pair.authority.approve(old.id); await pair.policy.beginSession()
        await #expect(throws: TaskServiceError.staleOperation) { try await pair.policy.consume(old, operation: op, generation: 9) }
    }
    @Test func expiryRevocationAndUnsupportedOperationsFailClosed() async throws {
        let clock = ManualTaskClock(); let pair = PermissionBroker.compose(clock: clock)
        let id = TaskIdentifier(rawValue: "task"); let op = operation()
        let request = try await pair.policy.request(taskID: id, operation: op, generation: 0)
        try await pair.authority.approve(request.id); await clock.advance(to: request.expiresAt)
        await #expect(throws: TaskServiceError.approvalExpired) { try await pair.policy.consume(request, operation: op, generation: 0) }
        let revoked = try await pair.policy.request(taskID: id, operation: op, generation: 0)
        try await pair.authority.approve(revoked.id); await pair.policy.revoke(taskID: id)
        await #expect(throws: TaskServiceError.staleOperation) { try await pair.policy.validate(revoked, operation: op, generation: 0) }
        for kind in [OperationKind.process, .automation, .fileWrite] {
            await #expect(throws: TaskServiceError.unsupportedOperation) {
                try await pair.policy.request(taskID: id, operation: operation(kind: kind), generation: 0)
            }
        }
    }
    @Test func validGrantCannotStartAfterExecutionDeadline() async throws {
        let clock = ManualTaskClock(); let pair = PermissionBroker.compose(clock: clock)
        let op = operation(); let request = try await pair.policy.request(taskID: .init(rawValue: "task"), operation: op, generation: 0)
        try await pair.authority.approve(request.id)
        await #expect(throws: TaskServiceError.executionLimit) {
            try await pair.policy.consume(request, operation: op, generation: 0, notAfter: await clock.now())
        }
    }

}
