import AppKit
import Domain
import Foundation
import TaskExecution
import Persistence
import SystemOperations
import Testing
@testable import WesleyFlow

@Suite("Native shell composition")
@MainActor
struct CompositionTests {
    @Test func productionCompositionConstructsHonestShell() {
        let composition = AppComposition()
        let state = composition.makeShellState()
        #expect(state.title == "Wesley Flow")
        #expect(state.phase == "Phase 1A · Task foundation")
        #expect(state.message.contains("separately approved phases"))
        #expect(composition.makeRootView().state == state)
    }

    @Test func compositionUsesInjectedProvider() {
        let expected = FoundationStatus(title: "Fixture", phase: "Composition test", message: "Injected value")
        let composition = AppComposition(statusProvider: FixedStatus(value: expected))
        #expect(composition.makeShellState() == expected)
        #expect(composition.makeRootView().state == expected)
    }

    @Test func localDomainProductLinksIntoApplicationTests() {
        let task = TaskLifecycle(id: .init(rawValue: "composition-test"), verification: .required)
        #expect(task.state == .queued)
        #expect(task.retryOf == nil)
        #expect(TaskState.Kind.allCases.count == 9)
    }

    @Test func appKitLifecycleClosesApplicationAfterLastWindow() {
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}

@MainActor
private struct FixedStatus: FoundationStatusProviding {
    let value: FoundationStatus
    func status() -> FoundationStatus { value }
}

@Suite("Phase 1A application composition", .timeLimit(.minutes(1)))
@MainActor
struct TaskServiceCompositionTests {
    @Test func compositionOpensRealStoreAndRunsOnlyInjectedExecutor() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WesleyFlow-Composition-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let executor = CompositionExecutor()
        let services = try await AppComposition().makeTaskServices(storeURL: folder.appendingPathComponent("history.store"), executor: executor, verifier: executor)
        let operation = ScopedOperation(id: "inspect", digest: String(repeating: "a", count: 64), workspaceID: "fixture", revision: "r1")
        let plan = try TaskPlan(id: .init(rawValue: "composition"), workspaceID: "fixture", revision: "r1", steps: [operation])
        try await services.coordinator.submit(plan)
        let waiting = try await services.coordinator.waitForState(plan.id, .awaitingApproval)
        try await services.approvals.approve(try #require(waiting.pendingApproval).id)
        try await services.coordinator.resumeApproval(plan.id)
        #expect(try await services.coordinator.waitForState(plan.id, .succeeded).lifecycle.state == .succeeded)
        #expect(try await services.repository.load().count == 1)
        await services.close()
    }
}
private actor CompositionExecutor: TaskOperationExecutor, TaskVerificationRunner {
    func execute(_ operation: ScopedOperation, token: OperationToken) -> OperationResult { .init(succeeded: true, observedRevision: operation.revision) }
    func verify(_ operation: ScopedOperation, token: OperationToken) -> VerificationEvidence { .init(passed: true, operationDigest: operation.digest, observedRevision: operation.revision) }
    func cancel(_ token: OperationToken) -> CancellationAcknowledgement { .stopped }
}
