import SwiftUI
import AppKit
import Foundation
import Domain
import TaskExecution
import Persistence
import SystemOperations
import VoiceInput
import ModelProviders

enum AppRelease {
    static let name = "Wesley Flow"
    static var version:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown" }
    static var build:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown" }
    static var diagnosticHeader:String { "\(name) version=\(version) build=\(build)" }
}

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
            phase: "Ready",
            message: "On-device dictation, text formatting and voice commands."
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
    func makeRootView(dictation: DictationModel? = nil) -> FoundationView { FoundationView(state: makeShellState(), dictation: dictation ?? makeDictationModel()) }
    func makeDictationModel(input: any DictationInput = AppleDictationInput(exclusiveCapture:NativeDictationInstanceGuard.requireOwnership)) -> DictationModel {
        DictationModel(input:input)
    }
    func makeSystemWideCoordinator() -> SystemWideDictationCoordinator {
        let clock = SystemTaskClock()
        let storeURL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("WesleyFlow/Dictation",isDirectory:true).appendingPathComponent("dictations.store")
        let speech = LanguageDictationInput(english:AppleDictationInput(exclusiveCapture:NativeDictationInstanceGuard.requireOwnership),
            telugu:TeluguDictationInput(exclusiveCapture:NativeDictationInstanceGuard.requireOwnership))
        return SystemWideDictationCoordinator(input:speech,targets:NativeInsertionTargetCapture(),
            insertion:TextInsertionService(clipboard:NativeDictationPasteboard(),clock:clock),shortcut:NativeDictationShortcut(),clock:clock,
            historyFactory:{ try await SwiftDataDictationHistoryStore.open(url:storeURL) },personalPlanner:ApplePersonalPlanner(memory:SystemInferenceMemory(),clock:clock),personalMessageResolution:{plan in try await NativeAgentResolution.resolve(plan)},offlineRewriter:AppleTranscriptRewriter(memory:SystemInferenceMemory(),clock:clock),previewRegistrar:NativePreviewShortcuts(),focusedTextResolver:NativeFocusedTextResolver(),minimumHoldMilliseconds:250)
    }

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

/// No process is terminated and no clipboard state is changed. The oldest running
/// copy owns native capture; secondary copies fail before permissions or microphone start.
@MainActor enum NativeDictationInstanceGuard {
    static func requireOwnership() throws {
        let current = NSRunningApplication.current
        guard let bundle = current.bundleIdentifier else { throw DictationFailure.anotherInstance }
        let copies = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundle && !$0.isTerminated }
        guard !copies.isEmpty, copies.count <= 32, copies.allSatisfy({ $0.launchDate != nil }) else { throw DictationFailure.anotherInstance }
        let instances = copies.map { DictationInstance(processID:$0.processIdentifier,launchedAt:$0.launchDate!.timeIntervalSinceReferenceDate) }
        guard DictationInstanceAdmission.permits(processID:current.processIdentifier,instances:instances) else { throw DictationFailure.anotherInstance }
    }
}
