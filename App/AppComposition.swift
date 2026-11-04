import SwiftUI
import AppKit
import AVFoundation
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
        let speakers = SpeakerSettings()
        let english = AppleDictationInput(exclusiveCapture:NativeDictationInstanceGuard.requireOwnership)
        let telugu = TeluguDictationInput(exclusiveCapture:NativeDictationInstanceGuard.requireOwnership)
        english.speakerCapture = speakers.capture
        telugu.speakerCapture = speakers.capture
        let speech = LanguageDictationInput(english:english,telugu:telugu)
        return SystemWideDictationCoordinator(input:speech,targets:NativeInsertionTargetCapture(),
            insertion:TextInsertionService(clipboard:NativeDictationPasteboard(),clock:clock),shortcut:NativeDictationShortcut(),clock:clock,
            historyFactory:{ try await SwiftDataDictationHistoryStore.open(url:storeURL) },personalPlanner:ApplePersonalPlanner(memory:SystemInferenceMemory(),clock:clock),personalMessageResolution:{plan in try await NativeAgentResolution.resolve(plan)},offlineRewriter:AppleTranscriptRewriter(memory:SystemInferenceMemory(),clock:clock),previewRegistrar:NativePreviewShortcuts(),focusedTextResolver:NativeFocusedTextResolver(),minimumHoldMilliseconds:250,speakers:speakers)
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

@MainActor final class SpeakerSettings: ObservableObject {
    static let passages = [
        "This morning I opened the window and heard the birds outside. A little later, I made tea and sat down to plan the day.",
        "Please put the blue notebook beside the lamp. I will pick it up before I head out to the shop.",
        "On the way home, we stopped at a quiet park. The trees were moving in the wind, and the path was still wet from the rain."
    ]
    @Published private(set) var enabled = false
    @Published private(set) var profiles: [(id: UUID, name: String)] = []
    @Published private(set) var enrolling = false
    @Published private(set) var recording = false
    @Published private(set) var working = false
    @Published private(set) var sample = 0
    @Published private(set) var status = "Add a speaker to label saved dictations on this Mac."
    let capture = SpeakerCapture()
    private let engine: BundledSpeakerEngine
    private let repository: KeychainSpeakerProfileRepository
    private let enrollment: SpeakerEnrollment
    private var microphone: AVAudioEngine?
    private var configurationObserver: (any NSObjectProtocol)?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private let defaultsKey = "voiceProfileDictationEnabled"

    init() {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let model = resources.appendingPathComponent("wespeaker.onnx")
        let engine = BundledSpeakerEngine(artifact: model)
        let repository = KeychainSpeakerProfileRepository()
        self.engine = engine
        self.repository = repository
        enrollment = SpeakerEnrollment(engine: engine, repository: repository)
        enabled = UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func refresh() async {
        do {
            let model = engine.model
            profiles = try await repository.getProfiles()
                .filter { $0.model == model && $0.minimumSimilarity != nil }
                .map { ($0.id, $0.displayName) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            status = "Voice profiles could not be read from the local Keychain."
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }

    func begin(name: String) async {
        guard !working, !enrolling else { return }
        working = true
        defer { working = false }
        do {
            try await engine.loadModel()
            try await enrollment.startEnrollment(displayName: name)
            sample = 0
            enrolling = true
            status = "Read each passage in your normal voice."
        } catch BundledSpeakerEngine.Failure.runtimeUnavailable {
            status = "The offline speaker runtime is missing. Install the speaker-enabled build."
        } catch BundledSpeakerEngine.Failure.missingModel {
            status = "The offline speaker model is missing."
        } catch BundledSpeakerEngine.Failure.invalidModel {
            status = "The offline speaker model failed its checksum check."
        } catch {
            status = "Could not start enrollment. Enter a valid speaker name."
        }
    }

    func startSample() async {
        guard enrolling, !working, !recording, sample < Self.passages.count else { return }
        working = true
        defer { working = false }
        let token = generation
        do {
            try NativeDictationInstanceGuard.requireOwnership()
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
            default: allowed = false
            }
            guard generation == token else { return }
            guard allowed else { status = "Allow microphone access in System Settings to record samples."; return }
            let engine = try capture.startEnrollmentCapture()
            microphone = engine
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.recording else { return }
                    self.stopMicrophone()
                    self.capture.reset()
                    self.status = "The microphone changed. Record this sample again."
                }
            }
            recording = true
            status = "Recording. Click Finish sample when you’re done."
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(13)) } catch { return }
                await self?.finishSample()
            }
        } catch {
            status = "Could not start this microphone. Check the selected sound input."
        }
    }

    private func stopMicrophone() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let microphone { microphone.stop(); microphone.inputNode.removeTap(onBus: 0) }
        microphone = nil
        timeout?.cancel()
        timeout = nil
        recording = false
    }

    func finishSample() async {
        guard recording, !working else { return }
        // If the timer fired, avoid cancelling the task performing this finalization.
        await finishSampleFromIndependentTask()
    }

    private func finishSampleFromIndependentTask() async {
        let task = Task { @MainActor [self] in await acceptSample() }
        await task.value
    }

    private func acceptSample() async {
        guard recording, !working else { return }
        working = true
        defer { working = false }
        let token = generation
        stopMicrophone()
        guard let task = capture.take(), let audio = await task.value, generation == token else {
            if generation == token { status = "That sample was too short, quiet, or interrupted. Try again." }
            return
        }
        do {
            try await enrollment.addEnrollmentSample(audio)
            guard generation == token else { return }
            sample += 1
            status = sample == Self.passages.count ? "Samples ready. Save this voice profile." : "Sample accepted. Read the next passage."
        } catch {
            if generation == token { status = "That sample could not be used. Speak clearly and try again." }
        }
    }

    func save() async {
        guard enrolling, !working, sample == Self.passages.count else { return }
        working = true
        defer { working = false }
        do {
            _ = try await enrollment.finishEnrollment()
            enrolling = false
            setEnabled(true)
            await refresh()
            status = "Voice profile saved. New saved dictations can be labeled by speaker."
        } catch SpeakerRecognitionError.invalidCalibration {
            status = "The samples did not agree. Cancel and enroll again in a quieter space."
        } catch {
            status = "The voice profile could not be saved to the local Keychain."
        }
    }

    func cancel() async {
        generation = UUID()
        stopMicrophone()
        capture.reset()
        enrolling = false
        await enrollment.cancelEnrollment()
        status = "Enrollment cancelled."
    }

    func delete(id: UUID) async {
        guard !working, !enrolling else { return }
        working = true
        defer { working = false }
        do {
            try await repository.deleteProfile(id: id)
            await refresh()
            status = "Voice profile deleted. Existing history keeps its original label."
        } catch { status = "The voice profile could not be deleted." }
    }

    func identify(_ captured: Task<SpeakerAudioSegment?, Never>) async -> DictationSpeakerLabel {
        guard enabled, !Task.isCancelled, let audio = await captured.value else { return .unknown }
        do {
            try await engine.loadModel()
            let embedding = try await engine.extractEmbedding(from: audio)
            let profiles = try await repository.getProfiles()
            try Task.checkCancellation()
            return try SpeakerMatching.enrolledLabel(embedding, model: engine.model, profiles: profiles)
        } catch { return .unknown }
    }
}
