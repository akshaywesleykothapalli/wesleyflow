import Foundation
import SwiftUI
import Domain
import SystemOperations

@MainActor final class DictationModel: ObservableObject {
    enum Phase: Equatable { case idle, preparing, recording, finalizing, complete, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var raw = ""
    @Published private(set) var edited = ""
    @Published private(set) var prompt = ""
    @Published private(set) var message = "Hold Fn / Globe to dictate after enabling it below. Text is not saved automatically."
    @Published private(set) var info: DictationInfo?
    @Published private(set) var shortcutEnabled = false
    @Published private(set) var shortcutMessage = "Enable Fn dictation, then hold Fn / Globe in a text field and release to insert."
    @Published private(set) var shortcutPresses = 0
    private var shortcutRequested = false
    private let shortcut: any DictationShortcutMonitoring
    private let destinations: any DictationDestinationCapturing
    private var shortcutGeneration = 0
    private var held = false
    private var destination: (any DictationTextDestination)?
    @Published private(set) var isRewriting = false
    @Published private(set) var isCancellingRewrite = false
    @Published private(set) var localProviderUncertain = false
    private var activeRewriteID: String?
    @Published var rewriteModelName = "qwen2.5-coder:7b"
    private let rewriter: (any PromptRewriting)?
    private var rewriteTask: Task<Void, Never>?
    private var rewriteGeneration = 0
    let localeIdentifier: String
    private let input: any DictationInput
    private let clock: any TaskClock
    private var generation = 0
    private var startup: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var previous = (raw: "", edited: "")
    var busy: Bool { [.preparing, .recording, .finalizing].contains(phase) }
    var cleaned: String { DictationText.cleaned(raw) }
    var canUseText: Bool { !busy && !isRewriting && !localProviderUncertain && !edited.isEmpty }
    init(input: any DictationInput, clock: any TaskClock = SystemTaskClock(),
         localeIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier,
         shortcut: any DictationShortcutMonitoring = NativeDictationShortcut(),
         destinations: any DictationDestinationCapturing = NativeDictationDestinationCapture(),
         rewriter: (any PromptRewriting)? = nil) {
        self.input = input; self.clock = clock; self.localeIdentifier = localeIdentifier
        self.shortcut = shortcut; self.destinations = destinations; self.rewriter = rewriter
    }
    func start() {
        guard !busy, !isRewriting, !localProviderUncertain else { return }
        previous = (raw, edited); raw = ""; edited = ""; info = nil
        generation += 1; let token = generation
        phase = .preparing; message = "Preparing on-device dictation. Allow microphone and speech access if asked."
        startup = Task { [weak self] in
            guard let self, !Task.isCancelled, self.generation == token, self.phase == .preparing else { return }
            do {
                let info = try await self.input.start(localeIdentifier: self.localeIdentifier) { [weak self] event in self?.receive(event, generation: token) }
                guard self.generation == token, !Task.isCancelled, self.phase == .preparing else { return }
                self.info = info; self.phase = .recording
                self.message = "Release the held key when finished."
            } catch {
                guard self.generation == token else { return }
                self.discardDestination(); self.input.cancel(); self.phase = .failed
                self.message = Self.description(error as? DictationFailure ?? .recognitionFailed)
            }
            if self.generation == token { self.startup = nil }
        }
    }
    func waitForCaptureStartup() async { await startup?.value }
    func stop() {
        guard phase == .recording else { return }
        phase = .finalizing; message = "Finishing transcription…"; timer?.cancel()
        input.stop()
        if phase == .finalizing { armTimer(milliseconds: 8_000, generation: generation, finalizing: true) }
    }
    func cancel() {
        guard busy else { return }
        discardDestination()
        generation += 1; startup?.cancel(); startup = nil; timer?.cancel(); timer = nil
        input.cancel(); raw = previous.raw; edited = previous.edited
        phase = .idle; message = "Dictation cancelled. New speech was discarded."
    }
    func close() {
        cancelRewrite()
        if busy { cancel() }
        generation += 1; startup?.cancel(); timer?.cancel(); input.cancel()
    }
    func edit(_ text: String) {
        guard !busy else { return }
        guard text.utf8.count <= DictationText.maximumBytes else { message = "Text is limited to 64 KiB."; return }
        if isRewriting { cancelRewrite() }
        edited = text
    }
    func editPrompt(_ text: String) {
        guard text.utf8.count <= DictationText.maximumBytes else { message = "Prompt is limited to 64 KiB."; return }
        if isRewriting { cancelRewrite() }
        prompt = text
    }
    @discardableResult func useAsPrompt() -> Task<Void, Never>? {
        guard canUseText else { return nil }
        guard let rewriter else { message = "Local AI rewriting is unavailable. Your text is unchanged."; return nil }
        rewriteGeneration += 1; let token = rewriteGeneration, id = UUID().uuidString
        let text = edited, modelName = rewriteModelName
        activeRewriteID = id; isRewriting = true; message = "Rewriting your request with local AI…"
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeRewriteID == id {
                    self.isRewriting = false; self.isCancellingRewrite = false
                    self.rewriteTask = nil; self.activeRewriteID = nil
                }
            }
            guard !Task.isCancelled else { return }
            var output: String?; var failure: InferenceFailure?
            do {
                let result = try await rewriter.rewrite(text,modelName:modelName,requestID:id)
                guard !result.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, result.utf8.count <= DictationText.maximumBytes else { throw InferenceFailure.invalidResponse }
                output = result
            } catch { failure = error as? InferenceFailure ?? .unavailable }
            let settlement = await rewriter.settle()
            guard self.activeRewriteID == id else { return }
            self.localProviderUncertain = settlement == .httpCancelledProviderUncertain
            guard !Task.isCancelled, self.rewriteGeneration == token else { return }
            if let output { self.prompt = output; self.message = "AI prompt ready. Review it before using it. No task was started." }
            else { self.message = Self.rewriteDescription(failure ?? .invalidResponse) }
            if self.localProviderUncertain { self.message += " Check provider cleanup before dictating again." }
        }
        rewriteTask = task; return task
    }
    func cancelRewrite() {
        guard isRewriting, !isCancellingRewrite, let id = activeRewriteID else { return }
        rewriteGeneration += 1; isCancellingRewrite = true; rewriteTask?.cancel()
        if let rewriter { Task { _ = await rewriter.cancel(requestID:id) } }
        message = "AI rewrite cancelled. Waiting for the local provider to settle; your text is unchanged."
    }
    @discardableResult func checkRewriteProvider() -> Task<Void,Never>? {
        guard !isRewriting, let rewriter else { return nil }
        let id = UUID().uuidString; activeRewriteID = id; isRewriting = true
        let task = Task { [weak self] in
            let state = await rewriter.settle()
            guard let self, self.activeRewriteID == id else { return }
            self.localProviderUncertain = state == .httpCancelledProviderUncertain
            self.activeRewriteID = nil; self.isRewriting = false; self.rewriteTask = nil
            self.message = self.localProviderUncertain ? "Local provider cleanup is still uncertain. Dictation remains paused." : "Local provider is settled. Dictation is available."
        }
        rewriteTask = task; return task
    }
    static func rewriteDescription(_ failure: InferenceFailure) -> String {
        switch failure {
        case .memoryAdmissionDenied, .memoryPressure: "AI rewrite could not run within the safe memory budget. Your text is unchanged. No template was substituted."
        case .modelMissing: "The selected local model is not installed. No model was downloaded."
        case .quarantined, .busy: "The local provider is busy or still settling. Your text is unchanged."
        case .invalidRequest: "This request does not fit the local model's bounded context. Shorten it to at most 1,800 UTF-8 bytes."
        case .timeout: "The local AI rewrite timed out. Your previous prompt is unchanged."
        case .cancelled: "AI rewrite cancelled. Your previous prompt is unchanged."
        default: "The text rewrite was unavailable or returned an invalid response. Your original text was kept."
        }
    }
    private func receive(_ event: DictationEvent, generation token: Int) {
        guard generation == token, busy else { return }
        switch event {
        case .transcript(let text):
            guard text.utf8.count <= DictationText.maximumBytes else { fail(.overflow); return }
            raw = text // Full snapshot replaces earlier partial text; never append callback snapshots.
        case .finished:
            guard phase == .finalizing else { fail(.providerEnded); return }
            timer?.cancel(); timer = nil; startup = nil; edited = cleaned
            phase = edited.isEmpty ? .failed : .complete
            message = edited.isEmpty ? "No speech was recognized. You can try again or type below." : "Ready to review. Cleanup changes whitespace only."
            if edited.isEmpty { discardDestination() } else if !held { insertShortcutText() }
        case .failed(let reason): fail(reason)
        }
    }
    private func fail(_ reason: DictationFailure) {
        discardDestination()
        generation += 1; timer?.cancel(); timer = nil; startup?.cancel(); startup = nil
        input.cancel(); edited = cleaned; phase = .failed; message = Self.description(reason)
    }
    private func armTimer(milliseconds: Int64, generation token: Int, finalizing: Bool) {
        timer?.cancel()
        timer = Task { [weak self, clock] in
            let now = await clock.now()
            do { try await clock.sleep(until: now + milliseconds) } catch { return }
            guard let self, !Task.isCancelled, self.generation == token else { return }
            if finalizing { self.fail(.timedOut) } else { self.stop() }
        }
    }
    func enableShortcut() {
        shortcutRequested = true
        guard !shortcutEnabled else { return }
        shortcutGeneration += 1; let token = shortcutGeneration
        do {
            try shortcut.enable { [weak self] signal in
                guard let self, self.shortcutEnabled, self.shortcutGeneration == token else { return }
                self.handleShortcut(signal)
            }
            shortcutEnabled = true
            shortcutMessage = "Ready: hold Fn / Globe to speak; release to insert. Escape cancels."
        } catch {
            shortcut.disable()
            shortcutMessage = "Allow Wesley Flow in System Settings → Privacy & Security → Accessibility (and Input Monitoring if requested), then click Enable again."
        }
    }
    func disableShortcut() {
        shortcutRequested = false
        shortcutGeneration += 1; shortcutEnabled = false; shortcut.disable()
        if destination != nil { cancel() }
        discardDestination(); shortcutMessage = "Fn dictation is disabled."
    }
    func refreshShortcutPermission() {
        if shortcutEnabled && !shortcut.authorizationReady { disableShortcut(); shortcutMessage = "Accessibility access was revoked. Enable Fn dictation after restoring it." }
        else if shortcutRequested && !shortcutEnabled && shortcut.authorizationReady { enableShortcut() }
    }
    private func handleShortcut(_ signal: DictationShortcutEvent) {
        switch signal {
        case .pressed:
            shortcutPresses += 1
            guard !isRewriting, !localProviderUncertain else { shortcutMessage = "Local AI is working or its cleanup is uncertain. Check the provider before dictating."; return }
            guard !held, !busy, destination == nil else { return }
            do {
                destination = try destinations.capture(); held = true; start()
                shortcutMessage = "Keep holding Fn while speaking. Release to insert; Escape cancels."
            } catch { shortcutMessage = "Click an editable text field first. Password and unsupported fields are excluded." }
        case .released:
            guard held else { return }; held = false
            if phase == .recording { stop() }
            else if phase == .complete { insertShortcutText() }
            else if phase == .preparing { cancel(); shortcutMessage = "Speech was still preparing. Allow access if asked, then hold Fn again." }
        case .cancelled:
            guard destination != nil else { return }
            cancel(); discardDestination(); shortcutMessage = "Dictation cancelled; nothing inserted. Use Fn alone to dictate."
        case .unavailable:
            disableShortcut(); shortcutMessage = "The keyboard monitor stopped. Enable Fn dictation again."
        }
    }
    private func discardDestination() { held = false; destination = nil }
    private func insertShortcutText() {
        guard let target = destination else { return }
        discardDestination() // Consume the gesture before effects: never retry or insert twice.
        do {
            try target.insert(edited)
            shortcutMessage = "Text insertion requested. If the app did not accept it, copy the text from Wesley Flow."
        } catch { shortcutMessage = "Text was kept here. The field changed or insertion was unavailable; copy it manually." }
    }
    static func description(_ failure: DictationFailure) -> String {
        switch failure {
        case .microphoneDenied: "Microphone access is unavailable. Check System Settings → Privacy & Security → Microphone. You can still type."
        case .speechDenied: "Speech recognition access is unavailable. Check System Settings → Privacy & Security → Speech Recognition. You can still type."
        case .assetsMissing, .unavailable: "On-device speech is unavailable for this Mac language. Check your macOS speech/language resources, then retry. No cloud fallback is used."
        case .audioUnavailable: "The microphone is unavailable or its configuration changed. Check the default input device and try again."
        case .busy: "The previous speech session is still stopping. Try again shortly."
        case .recognitionFailed: "Dictation stopped unexpectedly. Review any partial text or try again."
        case .noAudioCaptured: "The microphone delivered no audio. Check the selected input in System Settings → Sound, then hold Fn until the waveform appears before speaking."
        case .speechBelowThreshold: "Audio reached the microphone, but no sustained speech passed detection. Check the selected sound input and input volume, then speak closer to the microphone."
        case .noSpeechRecognized: "Audio was captured, but the local model returned no words. Check General → Language, then try a short sentence after the waveform appears."
        case .unsupportedRecognitionScript: "Recognition returned another writing system instead of Telugu or English. Nothing was inserted."
        case .repetitiveRecognition: "Recognition returned an unreliable repeated sequence. Nothing was inserted. Try a short sentence again."
        case .overflow: "Dictation stopped because its audio or text limit was reached. Review the partial text."
        case .timedOut: "Speech did not finish in time. Capture was stopped; review any partial text."
        case .anotherInstance: "Another Wesley Flow copy owns dictation. Finish or cancel capture and resolve clipboard recovery, then quit the other copy normally. Nothing was recorded."
        case .providerEnded: "The on-device speech provider ended before release, possibly at its duration limit. Recording stopped. Available text is retained for manual copy; nothing was inserted."
        }
    }
}
