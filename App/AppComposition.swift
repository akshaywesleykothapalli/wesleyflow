import SwiftUI
import Foundation
import Domain
import TaskExecution
import Persistence
import SystemOperations

struct FoundationStatus: Equatable, Sendable {
    let title: String
    let phase: String
    let message: String
}

@MainActor
protocol FoundationStatusProviding {
    func status() -> FoundationStatus
}

@MainActor
struct NativeFoundationStatus: FoundationStatusProviding {
    func status() -> FoundationStatus {
        FoundationStatus(
            title: "Wesley Flow",
            phase: "Phase 1A · Task foundation",
            message: "Durable task services are available to approved integrations. Feature workflows belong to separately approved phases."
        )
    }
}

@MainActor
struct AppComposition {
    private let statusProvider: any FoundationStatusProviding

    init(statusProvider: any FoundationStatusProviding = NativeFoundationStatus()) {
        self.statusProvider = statusProvider
    }

    func makeShellState() -> FoundationStatus { statusProvider.status() }
    func makeRootView() -> FoundationView { FoundationView(state: makeShellState()) }
}

@MainActor
struct TaskServices {
    let coordinator: TaskCoordinator
    let repository: SwiftDataTaskRepository
    let approvals: UserApprovalAuthority

    func close() async {
        await coordinator.shutdown()
        // A stalled SwiftData actor cannot safely be closed or killed in-process.
        // Keep it owned for a later explicit close/restart rather than blocking this bounded close.
        guard !(await coordinator.hasPendingPersistence) else { return }
        await repository.close()
    }
}

extension AppComposition {
    /// Explicit storage location and executor injection; no production system executor is supplied.
    func makeTaskServices(storeURL: URL, executor: any TaskOperationExecutor,
                          verifier: any TaskVerificationRunner,
                          clock: any TaskClock = SystemTaskClock()) async throws -> TaskServices {
        let repository = try await SwiftDataTaskRepository.open(url: storeURL)
        let permission = PermissionBroker.compose(clock: clock)
        let coordinator = TaskCoordinator(history: repository, policy: permission.policy,
                                          executor: executor, verifier: verifier, clock: clock)
        do { try await coordinator.start() }
        catch { await repository.close(); throw error }
        return TaskServices(coordinator: coordinator, repository: repository, approvals: permission.authority)
    }
}
