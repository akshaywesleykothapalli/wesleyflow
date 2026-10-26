import Foundation
import SwiftUI
import Domain
import SystemOperations
import VoiceInput

/// Owns a single speech/insertion/history session. Transcript data never submits a task.
@MainActor final class SystemWideDictationCoordinator: ObservableObject {
    enum Phase: String, CaseIterable { case idle, preparing, recording, finalizing, inserting, success, error }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Hold the selected dictation key to speak into the current text field; release to insert."
    @Published private(set) var raw = ""
    @Published private(set) var cleaned = ""
    @Published private(set) var engine: DictationInfo?
    @Published private(set) var entries: [DictationHistoryEntry] = []
    @Published private(set) var latest: DictationHistoryEntry?
    @Published private(set) var historyError: String?
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var microphoneStatus = "Not inspected"
    @Published private(set) var speechStatus = "Not inspected"
    @Published private(set) var speechConfiguration: AppleSpeechConfiguration?
    @Published private(set) var clipboardPending = false
    @Published private(set) var shortcutEnabled = false
    @Published var preferences: DictationPreferences { didSet {
        preferenceStore.save(preferences); networkPolicy.setBlocked(preferences.blockNetworkRequests); networkSnapshot = networkPolicy.snapshot()
        if (previewKind == .polish && !preferences.offlineAIRewriting) || (previewKind == .promptEngineering && !preferences.promptEngineeringEnabled) { cancelRewritePreview() }
        if oldValue.previewShortcutsEnabled != preferences.previewShortcutsEnabled || oldValue.offlineAIRewriting != preferences.offlineAIRewriting || oldValue.promptEngineeringEnabled != preferences.promptEngineeringEnabled || oldValue.activationKey != preferences.activationKey || oldValue.holdFnEnabled != preferences.holdFnEnabled { configurePreviewShortcuts() }
    } }
    @Published var search = ""
    @Published private(set) var modelInventory: [ModelDescriptor] = []
    @Published private(set) var modelStatus = "Coding inference is disabled. Ollama model metadata has not been inspected."
    @Published private(set) var commandArmed = false
    @Published private(set) var commandStatus = "Arm the next hold-to-talk gesture for a supported app-opening command."
    private var commandSession = false
    private let appOpener: @MainActor (AppOpeningCommand) async throws -> Void
    func armCommand() { guard !busy, !closed else { return }; commandArmed = true; commandStatus = "Next hold-to-talk gesture opens an app. Say, for example, open WhatsApp. Dictation will resume afterwards." }
    func disarmCommand() { commandArmed = false }
    func openApp(_ command: AppOpeningCommand) async {
        guard !busy, !closed else { return }
        phase = .inserting
        await performCommand(command)
    }
    func waitForCommandDispatch() async { await work?.value }
    private func performCommand(_ command: AppOpeningCommand) async {
        guard !closed, !Task.isCancelled else { return }
        do { try await appOpener(command); guard !closed else { return }; commandStatus = "Opened \(command.rawValue)."; phase = .success }
        catch { guard !closed else { return }; commandStatus = "Could not open \(command.rawValue). Check that it is installed and try again."; phase = .error }
        message = commandStatus
    }
    @Published private(set) var rewritePreview: OfflineRewriteOutcome?
    @Published private(set) var promptPreview: OfflineRewriteOutcome?
    @Published private(set) var previewKind: OfflinePreviewKind = .polish
    @Published private(set) var previewOriginalText = ""
    @Published private(set) var previewNotice = "Supply text or select a completed saved dictation. No external app text is read."
    @Published private(set) var previewPresented = false
    @Published private(set) var previewOriginProcessIdentifier: Int32?
    @Published private(set) var previewShortcutStatus = "Preview shortcuts are disabled."
    @Published var previewInputText = "" { didSet { if oldValue != previewInputText { cancelRewritePreview() } } }
    @Published var previewUseSaved = false { didSet { if oldValue != previewUseSaved { cancelRewritePreview() } } }
    @Published var selectedPreviewEntryID: String? { didSet { if oldValue != selectedPreviewEntryID { cancelRewritePreview() } } }
    @Published private(set) var isPreviewingRewrite = false
    private let offlineRewriter: (any OfflineTranscriptRewriting)?
    private let previewRegistrar: (any PreviewShortcutRegistering)?
    private var registeredPreviewKinds: Set<OfflinePreviewKind> = []
    private var previewTask: Task<Void,Never>?
    private var previewToken: String?
    private var reliableFinalID: String?
    var previewHistoryCandidates: [DictationHistoryEntry] {
        entries.filter { !$0.cleaned.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.cleaned.utf8.count <= 2048 && ![InsertionReason.speechFailed,.cancelled,.deadline].contains($0.insertion.reason) }
    }
    private var permittedPreviewText: String? {
        let text = previewUseSaved ? previewHistoryCandidates.first(where:{$0.id == selectedPreviewEntryID})?.cleaned : previewInputText
        guard let text, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.utf8.count <= 2048 else { return nil }; return text
    }
    func canPreviewSupplied(_ kind:OfflinePreviewKind) -> Bool {
        !busy && !closed && !isPreviewingRewrite && offlineRewriter != nil && permittedPreviewText != nil && (kind == .polish ? preferences.offlineAIRewriting : preferences.promptEngineeringEnabled)
    }
    var canPreviewRewrite: Bool { !busy && !closed && !isPreviewingRewrite && preferences.offlineAIRewriting && offlineRewriter != nil && latest?.id == reliableFinalID && latest != nil }
    @discardableResult func startRewritePreview() -> Task<Void,Never>? {
        guard canPreviewRewrite, let entry = latest else { return nil }
        return beginPreview(.polish,text:entry.cleaned,sourceID:entry.id,latestOnly:true)
    }
    @discardableResult func startSuppliedPreview(_ kind:OfflinePreviewKind) -> Task<Void,Never>? {
        guard canPreviewSupplied(kind), let text = permittedPreviewText else {
            previewNotice = "No permitted preview input, feature disabled, or another session is active. Supply up to 2,048 bytes or select a completed dictation."; return nil
        }
        return beginPreview(kind,text:text,sourceID:previewUseSaved ? selectedPreviewEntryID : nil,latestOnly:false)
    }
    private func beginPreview(_ kind:OfflinePreviewKind,text:String,sourceID:String?,latestOnly:Bool) -> Task<Void,Never>? {
        guard let offlineRewriter else { return nil }
        let token = UUID().uuidString; previewToken = token; previewKind = kind; isPreviewingRewrite = true
        rewritePreview = nil; promptPreview = nil; previewOriginalText = text; previewNotice = "Preview requested. Focus and clipboard stay unchanged."
        let request = OfflineRewriteRequest(id:token,text:text,localeIdentifier:localeIdentifier,
            vocabulary:preferences.formatting.vocabulary + preferences.formatting.replacements.map(\.replacement).filter { !$0.isEmpty },tone:preferences.polishTone,kind:kind)
        let task = Task { [weak self] in
            let result = await offlineRewriter.rewrite(request)
            guard let self, self.previewToken == token, !self.closed, !Task.isCancelled, !self.busy,
                  kind == .polish ? self.preferences.offlineAIRewriting : self.preferences.promptEngineeringEnabled else { return }
            if let sourceID {
                let valid = latestOnly ? self.latest?.id == sourceID : self.previewHistoryCandidates.contains(where:{$0.id == sourceID && $0.cleaned == text})
                guard valid else { self.cancelRewritePreview(); return }
            }
            if kind == .polish { self.rewritePreview = result } else { self.promptPreview = result }
            self.isPreviewingRewrite = false; self.previewToken = nil; self.previewTask = nil
            self.previewNotice = "\(kind == .polish ? "Smart Polish" : "Prompt Engineering"): \(result.status.rawValue). Open Smart Formatting to review; nothing was inserted."
        }
        previewTask = task; return task
    }
    func cancelRewritePreview() {
        let token = previewToken; previewToken = nil; previewTask?.cancel(); previewTask = nil
        isPreviewingRewrite = false; rewritePreview = nil; promptPreview = nil
        if let token, let offlineRewriter { Task { await offlineRewriter.cancel(requestID:token) } }
    }
    func rejectRewritePreview() {
        cancelRewritePreview()
        previewNotice = "Preview rejected. Original input retained; nothing was copied or inserted."
    }
    func dismissShortcutPreview() {
        cancelRewritePreview(); previewPresented = false; previewOriginProcessIdentifier = nil
    }
    func invokeShortcutPreview(_ kind: OfflinePreviewKind, originProcessIdentifier: Int32? = nil) {
        guard !closed else { return }
        previewPresented = true
        // A rapid second chord cannot replace the pending session's source/kind.
        guard !isPreviewingRewrite else { return }
        previewOriginProcessIdentifier = originProcessIdentifier
        previewKind = kind; rewritePreview = nil; promptPreview = nil
        previewOriginalText = permittedPreviewText ?? ""
        _ = startSuppliedPreview(kind)
    }
    func configurePreviewShortcuts() {
        guard !closed, preferences.previewShortcutsEnabled, let previewRegistrar else {
            self.previewRegistrar?.disable(); registeredPreviewKinds = []; if previewPresented { dismissShortcutPreview() }; previewShortcutStatus = "Preview shortcuts are disabled."; return
        }
        guard !(preferences.activationKey == .rightOption && preferences.holdFnEnabled) else {
            previewRegistrar.disable(); registeredPreviewKinds = []; previewShortcutStatus = "Conflict with right-Option hold-to-talk. Choose Fn or right Command first."; return
        }
        var kinds = Set<OfflinePreviewKind>()
        if preferences.offlineAIRewriting { kinds.insert(.polish) }; if preferences.promptEngineeringEnabled { kinds.insert(.promptEngineering) }
        guard !kinds.isEmpty else { previewRegistrar.disable(); registeredPreviewKinds = []; previewShortcutStatus = "Enable a preview feature before registering its shortcut."; return }
        if kinds == registeredPreviewKinds { return }
        do {
            try previewRegistrar.enable(kinds:kinds) { [weak self] signal in
                guard let self, !self.closed, self.preferences.previewShortcutsEnabled else { return }
                switch signal {
                case .invoke(let kind): self.invokeShortcutPreview(kind)
                case .invokeFrom(let kind, let process): self.invokeShortcutPreview(kind,originProcessIdentifier:process)
                case .suspended: self.cancelRewritePreview(); self.previewShortcutStatus = "Mac sleeping: pending preview cancelled; shortcuts suspended."
                case .resumed: self.previewShortcutStatus = "Shortcuts re-registered after wake. Physical delivery remains unverified."
                case .secureInput: self.cancelRewritePreview(); self.previewShortcutStatus = "Secure Input active: preview gesture ignored."
                case .unavailable: self.cancelRewritePreview(); self.registeredPreviewKinds = []; self.previewShortcutStatus = "Shortcut delivery or keyboard layout became unavailable. Disable and re-enable to retry."
                }
            }
            registeredPreviewKinds = kinds
            previewShortcutStatus = "Registered: " + kinds.sorted(by:{$0.rawValue < $1.rawValue}).map { $0 == .polish ? "Option+1" : "Option+2" }.joined(separator:", ") + ". Physical cross-app delivery remains unverified."
        } catch {
            registeredPreviewKinds = []
            switch error {
            case PreviewShortcutFailure.systemConflict: previewShortcutStatus = "Conflict with an enabled macOS system shortcut. Use the preview buttons."
            case PreviewShortcutFailure.layoutUnsupported: previewShortcutStatus = "Current keyboard layout does not map these physical keys to 1 and 2. Use the preview buttons."
            case PreviewShortcutFailure.secureInput: previewShortcutStatus = "Secure Input is active; registration was not attempted."
            case PreviewShortcutFailure.registration(let code): previewShortcutStatus = "Native shortcut registration failed (\(code)); another exclusive owner or OS restriction may apply. Use the preview buttons."
            default: previewShortcutStatus = "Preview shortcut registration unavailable. Use the preview buttons."
            }
        }
    }
    var rewritePreviewMessage: String {
        guard let result = previewKind == .polish ? rewritePreview : promptPreview else { return isPreviewingRewrite ? "Rewriting on this Mac…" : "Preview the latest completed dictation. Nothing is inserted automatically." }
        switch result.status {
        case .rewritten: return "Preview ready. Review before copying."
        case .unchanged: return "The model returned the deterministic text unchanged. Review before copying."
        case .modelUnavailable: return "The model or language is unavailable. Deterministic text retained."
        case .resourceBlocked: return "Safe resources are unavailable or the provider is settling. Deterministic text retained."
        case .cancelled: return "Preview cancelled. Deterministic text retained."
        case .timedOut: return "Rewrite timed out. Deterministic text retained."
        case .invalidOutput: return "The rewrite did not pass preservation checks. Deterministic text retained."
        }
    }
    private let historyCopy: @MainActor (String) -> Bool
    private let modelInspector: (@Sendable () async throws -> [ModelDescriptor])?
    var settingsError: String? { preferenceStore.error }
    let localeIdentifier: String
    let networkPolicy: ApplicationNetworkPolicy
    @Published private(set) var networkSnapshot: ApplicationNetworkPolicy.Snapshot
    private let input: any DictationInput
    private let targets: any InsertionTargetCapturing
    private let insertion: any DictationTextInserting
    private let shortcut: any DictationShortcutMonitoring
    private let minimumHoldMilliseconds: Int64
    private let clock: any TaskClock
    private let wallTime: @Sendable () -> Date
    private let preferenceStore: DictationPreferenceStore
    private let historyFactory: (@Sendable () async throws -> any DictationHistoryStore)?
    private var history: (any DictationHistoryStore)?
    private var opening: Task<any DictationHistoryStore,any Error>?
    private var startup: Task<Void,Never>?
    private var timer: Task<Void,Never>?
    private var work: Task<Void,Never>?
    private var session: String?
    private var destination: (any InsertionTarget)?
    private var fallback = TextInsertionReceipt(.unsupportedTarget,.manualOnly)
    private var recordingBegan: Int64?
    private var timestamp = Date()
    private var historyConsentAtStart = false
    private var shortcutHeld = false
    private var startedFromShortcut = false
    private var captureExplanation: String?
    private var shortcutGeneration = 0
    private var reloadGeneration = 0
    private var closed = false
    var shortcutLabel: String { preferences.activationKey.label }
    var pillVisible: Bool { preferences.showPill && ((preferences.idlePillEnabled && !closed) || (startedFromShortcut && busy)) }
    var busy: Bool { [.preparing,.recording,.finalizing,.inserting].contains(phase) }
    var filteredHistory: [DictationHistoryEntry] { DictationHistoryQuery.filter(entries,search:search) }
    var groupedHistory: [(date:Date,entries:[DictationHistoryEntry])] { DictationHistoryQuery.groups(filteredHistory,calendar:.current) }
    init(input: any DictationInput, targets: any InsertionTargetCapturing, insertion: any DictationTextInserting,
         shortcut: any DictationShortcutMonitoring, clock: any TaskClock = SystemTaskClock(),
         preferenceStore: DictationPreferenceStore = DictationPreferenceStore(),
         networkPolicy: ApplicationNetworkPolicy = .shared,
         history: (any DictationHistoryStore)? = nil,
         historyFactory: (@Sendable () async throws -> any DictationHistoryStore)? = nil,
         appOpener: @escaping @MainActor (AppOpeningCommand) async throws -> Void = NativeAppOpening.open,
         modelInspector: (@Sendable () async throws -> [ModelDescriptor])? = nil,
         offlineRewriter: (any OfflineTranscriptRewriting)? = nil,
         previewRegistrar: (any PreviewShortcutRegistering)? = nil,
         historyCopy: @escaping @MainActor (String) -> Bool = HistoryClipboard.write,
         localeIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier,
         minimumHoldMilliseconds: Int64 = 0,
         wallTime: @escaping @Sendable () -> Date = { Date() }) {
        self.networkPolicy = networkPolicy; self.networkSnapshot = networkPolicy.snapshot()
        self.offlineRewriter = offlineRewriter; self.previewRegistrar = previewRegistrar
        self.historyCopy = historyCopy
        self.minimumHoldMilliseconds = min(1000,max(0,minimumHoldMilliseconds))
        self.appOpener = appOpener
        self.input = input; self.targets = targets; self.insertion = insertion; self.shortcut = shortcut
        self.clock = clock; self.preferenceStore = preferenceStore; self.history = history; self.historyFactory = historyFactory
        self.localeIdentifier = localeIdentifier; self.wallTime = wallTime; self.modelInspector = modelInspector; preferences = preferenceStore.load()
        networkPolicy.setBlocked(preferences.blockNetworkRequests); networkSnapshot = networkPolicy.snapshot()
    }
    var clipboardRecoveryID: String? { insertion.pendingClipboardRecovery?.id }
    private func reconcileClipboard() {
        guard !busy else { return }
        if insertion.reconcileClipboardState() == .preservedNewer {
            clipboardPending = false
            message = "The earlier paste remains unverified. Your newer clipboard was preserved; a fresh dictation can start."
        }
    }
    func refreshPermissions() {
        networkSnapshot = networkPolicy.snapshot()
        reconcileClipboard()
        accessibilityAllowed = DictationAccess.accessibilityGranted
        let value = AppleSpeechConfiguration.permissionSummary(); microphoneStatus = value.microphone; speechStatus = value.speech
        if shortcutEnabled && !shortcut.authorizationReady { stopShortcutMonitoring(); cancel() }
    }
    func requestAccessibility() { _ = DictationAccess.requestAccessibility(); resumeShortcutIfAuthorized() }
    func resumeShortcutIfAuthorized() {
        refreshPermissions(); configurePreviewShortcuts()
        guard !closed, preferenceStore.error == nil, preferences.holdFnEnabled, shortcut.authorizationReady else { return }
        startShortcutMonitoring()
    }
    func inspectModels() async {
        guard let modelInspector else { modelStatus = "Model metadata inspection is unavailable. Inference remains disabled."; return }
        do { modelInventory = try await modelInspector(); modelStatus = "Ollama metadata observed; its coding and prompt inference remain disabled and memory-gated. Apple dictation previews are separately opt-in." }
        catch { modelStatus = "Local model metadata is unavailable. No service or model was started." }
    }
    func inspectSpeech() async { speechConfiguration = await AppleSpeechConfiguration.inspect(localeIdentifier:localeIdentifier); refreshPermissions() }
    func pillClicked(clickCount: Int = 1) {
        guard clickCount == 1, !closed else { return }
        if phase == .recording { stop(); return }
        guard !busy else { return }
        begin(manual:false)
    }
    func startManual() { guard !busy, !closed else { return }; begin(manual:true) }
    private func begin(manual: Bool, fromShortcut: Bool = false) {
        cancelRewritePreview(); reliableFinalID = nil
        reconcileClipboard()
        if !manual && !(fromShortcut && commandArmed) && insertion.hasPendingClipboard {
            clipboardPending = true; phase = .error; startedFromShortcut = false
            message = (insertion.failureExplanation.map { $0 + " " } ?? "") + "Recording was not started. Review clipboard restoration before another dictation."
            return
        }
        commandSession = fromShortcut && commandArmed; commandArmed = false
        startedFromShortcut = fromShortcut || preferences.idlePillEnabled; captureExplanation = nil
        let id = UUID().uuidString
        destination = nil; fallback = .init(.unsupportedTarget,.manualOnly)
        if !manual && !commandSession {
            do { destination = try targets.capture(session:id) }
            catch TextTargetError.secure { phase = .error; message = "Password and secure fields are excluded. Nothing was recorded."; return }
            catch TextTargetError.denied { fallback = .init(.denied,.permission) }
            catch TextTargetError.changed { fallback = .init(.targetChanged,.changed) }
            catch { fallback = .init(.unsupportedTarget,.unsupported) }
        }
        if destination == nil && !manual { captureExplanation = targets.failureExplanation }
        session = id; timestamp = wallTime(); recordingBegan = nil; historyConsentAtStart = preferences.keepHistory
        raw = ""; cleaned = ""; engine = nil; phase = .preparing
        message = "Preparing on-device speech. Allow microphone and speech access if asked."
        startup = Task { [weak self] in
            guard let self, self.session == id, !Task.isCancelled else { return }
            do {
                if fromShortcut && self.minimumHoldMilliseconds > 0 {
                    let now = await self.clock.now()
                    let deadline = now.addingReportingOverflow(self.minimumHoldMilliseconds)
                    guard !deadline.overflow else { throw CancellationError() }
                    try await self.clock.sleep(until:deadline.partialValue)
                    guard self.session == id, !Task.isCancelled else { return }
                }
                let info = try await self.input.start(localeIdentifier:self.localeIdentifier) { [weak self] event in self?.receive(event,id:id) }
                guard self.session == id, self.phase == .preparing, !Task.isCancelled else { return }
                self.engine = info; self.phase = .recording; self.recordingBegan = await self.clock.now()
                guard self.session == id, self.phase == .recording else { return }
                self.message = self.commandSession ? "Listening for an app-opening command. Release the key to open it." : (self.destination == nil ? "Listening. Release the key to finish; this field is unavailable, so text will remain for copy." : "Listening into the captured field. Release the key to insert.")
                self.armTimer(60_000,id:id,finishing:false)
            } catch {
                guard self.session == id else { return }
                self.input.cancel(); self.session = nil; self.destination = nil; self.phase = .error
                self.message = DictationModel.description(error as? DictationFailure ?? .recognitionFailed)
            }
            if self.session == id { self.startup = nil }
            self.refreshPermissions()
        }
    }
    private func receive(_ event: DictationEvent,id: String) {
        guard session == id, [.preparing,.recording,.finalizing].contains(phase) else { return }
        switch event {
        case .transcript(let text):
            guard text.utf8.count <= DictationText.maximumBytes else { input.cancel(); finish(id:id,forced:.init(.denied,.speechFailed)); return }
            raw = text
        case .finished: finish(id:id)
        case .failed(let error): input.cancel(); message = DictationModel.description(error); finish(id:id,forced:.init(.denied,.speechFailed))
        }
    }
    func stop() {
        guard let id = session, phase == .recording else { return }
        phase = .finalizing; message = "Finalizing speech…"; timer?.cancel(); input.stop()
        if phase == .finalizing { armTimer(8000,id:id,finishing:true) }
    }
    func cancel() {
        cancelRewritePreview()
        guard let id = session else { return }
        input.cancel(); startup?.cancel(); timer?.cancel(); shortcutHeld = false
        if phase == .inserting { work?.cancel(); message = "Cancelling; preserving the actual insertion outcome."; return }
        finish(id:id,forced:.init(.cancelled,.cancelled))
    }
    private func armTimer(_ delay: Int64,id: String,finishing: Bool) {
        timer?.cancel()
        timer = Task { [weak self,clock] in
            let now = await clock.now()
            guard now >= 0, now <= Int64.max-delay else {
                guard let self, self.session == id else { return }
                self.input.cancel(); self.finish(id:id,forced:.init(.timedOut,.deadline)); return
            }
            do { try await clock.sleep(until:now+delay) } catch { return }
            guard let self, self.session == id, !Task.isCancelled else { return }
            if finishing { self.input.cancel(); self.finish(id:id,forced:.init(.timedOut,.deadline)) } else { self.stop() }
        }
    }
    private func finish(id: String,forced: TextInsertionReceipt? = nil) {
        guard session == id, phase != .inserting else { return }
        timer?.cancel(); timer = nil; startup = nil
        cleaned = NativeDictationFormatting.format(raw,options:preferences.formatting,whitespace:preferences.spacingCleanup,locale:localeIdentifier)
        guard !cleaned.isEmpty else {
            input.cancel(); session = nil; destination = nil; phase = forced?.outcome == .cancelled ? .idle : .error
            message = forced?.outcome == .cancelled ? "Cancelled. Nothing inserted." : "No speech was recognized. Try again or check microphone permission."
            return
        }
        if commandSession {
            commandSession = false; session = nil; destination = nil; input.cancel()
            guard forced == nil, let command = AppOpeningCommand.parse(cleaned) else {
                phase = .error; commandStatus = forced == nil ? "Command not recognized. Use one of the exact open-app phrases in Commands. Nothing was opened." : "Command cancelled or incomplete. Nothing was opened."
                message = commandStatus; return
            }
            phase = .inserting
            work = Task { [weak self] in guard let self, !Task.isCancelled else { return }; await self.performCommand(command); self.work = nil }
            return
        }
        phase = .inserting; message = "Checking the original target and insertion result…"
        let target = destination, source = target?.info.applicationName, raw = raw, text = cleaned
        let fallback = fallback, captureExplanation = captureExplanation, date = timestamp, began = recordingBegan, saveAtStart = historyConsentAtStart
        work = Task { [weak self] in
            guard let self else { return }
            let now = await self.clock.now()
            let receipt: TextInsertionReceipt
            if let forced { receipt = forced }
            else if let target { receipt = await self.insertion.insert(text,target:target,session:id) }
            else { receipt = fallback }
            self.clipboardPending = self.insertion.hasPendingClipboard
            let duration = began.map { start -> Int64 in
                let delta = now.subtractingReportingOverflow(start)
                return delta.overflow ? 0 : max(0,min(120_000,delta.partialValue))
            } ?? 0
            let entry = DictationHistoryEntry(id:id,timestamp:date,raw:raw,cleaned:text,sourceApplication:source,durationMilliseconds:duration,insertion:receipt)
            self.latest = entry
            self.reliableFinalID = forced == nil ? entry.id : nil
            if saveAtStart && self.preferences.keepHistory {
                do { let store = try await self.getHistory(); try await store.append(entry); await self.loadHistory() }
                catch { self.historyError = "Dictation is available for copy, but local history could not be saved. Check storage or clear old history." }
            }
            guard self.session == id else { return }
            self.input.cancel(); self.session = nil; self.destination = nil; self.work = nil
            if receipt.outcome == .inserted { self.phase = .success; self.message = "Text insertion verified in the original field." }
            else if receipt.reason == .manualOnly { self.phase = .success; self.message = "Dictation ready for review and manual copy." }
            else if receipt.outcome == .cancelled { self.phase = .idle; self.message = "Cancelled. Dictation retained locally; nothing was submitted." }
            else { self.phase = .error; self.message = receipt == fallback ? (captureExplanation ?? Self.insertionExplanation(receipt)) : (((receipt.reason == .clipboardUnsupported || receipt.outcome == .uncertain) ? self.insertion.failureExplanation : nil) ?? Self.insertionExplanation(receipt)) }
        }
    }
    private func getHistory() async throws -> any DictationHistoryStore {
        if let history { return history }
        if opening == nil {
            guard let historyFactory else { throw DictationHistoryFailure.unavailable }
            opening = Task { try await historyFactory() }
        }
        let store = try await opening!.value
        if closed { await store.close(); throw DictationHistoryFailure.closed }
        history = store; opening = nil; return store
    }
    // Explicit UI copy cannot overlap dictation or discard an unresolved insertion lease.
    var historyCopyAllowed: Bool { !closed && !busy && !insertion.hasPendingClipboard }
    func copyReviewedText(_ text:String) -> Bool {
        guard historyCopyAllowed, text.utf8.count <= DictationText.maximumBytes else { return false }
        return historyCopy(text)
    }
    func copyHistory(id:String) -> Bool {
        guard let entry = entries.first(where:{ $0.id == id }) else { return false }
        return copyReviewedText(entry.cleaned)
    }
    func loadHistory() async {
        reloadGeneration += 1; let token = reloadGeneration
        do {
            let store = try await getHistory(), rows = try await store.load()
            guard token == reloadGeneration, !closed else { return }; entries = rows; historyError = nil
        } catch { if token == reloadGeneration { opening = nil; historyError = "Local history is unavailable. Existing files were preserved. Dictation and manual copy remain available." } }
    }
    func deleteHistory(id: String) async {
        guard !busy else { return }
        if latest?.id == id || selectedPreviewEntryID == id { cancelRewritePreview(); if latest?.id == id { reliableFinalID = nil }; if selectedPreviewEntryID == id { selectedPreviewEntryID = nil } }
        do { let store = try await getHistory(); try await store.delete(id:id); await loadHistory() }
        catch { historyError = "The entry could not be deleted." }
    }
    func clearHistory() async {
        guard !busy else { return }
        cancelRewritePreview(); reliableFinalID = nil
        do { let store = try await getHistory(); try await store.clear(); latest = nil; await loadHistory() }
        catch { historyError = "History could not be cleared." }
    }
    func restoreClipboardAfterConfirmation(expectedRecoveryID: String?) {
        guard let expectedRecoveryID else { message = "That recovery request is no longer available. No clipboard was changed."; return }
        let result = insertion.restoreAfterUserConfirmation(expectedRecoveryID:expectedRecoveryID); clipboardPending = insertion.hasPendingClipboard
        message = result == .restored ? "Previous clipboard restored." : result == .preservedNewer ? "Your newer clipboard was preserved." : "Clipboard restoration is still unavailable."
    }
    static func insertionExplanation(_ receipt: TextInsertionReceipt) -> String {
        switch receipt.reason {
        case .permission: "Text insertion needs Accessibility access for this build. Your transcript is in History for copying."
        case .unsupported: "This field does not expose a supported text and caret interface. Nothing was inserted; copy the transcript from History."
        case .secureField: "Secure fields are excluded. Nothing was inserted."
        case .changed: "The original app, field, selection or text changed. Nothing was redirected; copy from History."
        case .clipboardUnsupported: "The clipboard contains a format that cannot be safely backed up. Paste was skipped; copy from History."
        case .clipboardChanged: "The clipboard changed before paste. Your newer clipboard was preserved; copy the transcript from History."
        case .clipboardPending: "A previous paste needs clipboard review before another paste can be attempted."
        case .deadline, .verificationUnavailable: "Insertion could not be verified. Check the original field before copying to avoid duplicates."
        case .speechFailed: "Speech did not finish reliably. The available transcript is retained for manual copy."
        case .cancelled: "Dictation was cancelled; check any attempted insertion before copying."
        case .manualOnly: "Dictation is ready for manual copy."
        case .verified: "Insertion verified in the original field."
        }
    }
    func enableShortcut() {
        preferences.holdFnEnabled = true
        startShortcutMonitoring()
    }
    private func startShortcutMonitoring() {
        guard !closed, !shortcutEnabled else { return }
        shortcutGeneration += 1; let token = shortcutGeneration
        do {
            shortcut.configure(key:preferences.activationKey)
            try shortcut.enable { [weak self] event in
                guard let self, self.shortcutEnabled, self.shortcutGeneration == token else { return }
                switch event {
                case .pressed:
                    guard !self.shortcutHeld, !self.busy else { return }; self.shortcutHeld = true; self.begin(manual:false,fromShortcut:true)
                case .released:
                    guard self.shortcutHeld else { return }; self.shortcutHeld = false
                    if self.phase == .recording { self.stop() } else if self.phase == .preparing { self.cancel() }
                case .cancelled: self.cancel(); self.shortcutHeld = false
                case .unavailable: self.stopShortcutMonitoring(); self.cancel()
                }
            }
            shortcutEnabled = true
        } catch { message = "Allow Accessibility for hold-to-talk dictation, then enable it again. Hold the selected key to speak." }
        refreshPermissions()
    }
    func changeActivationKey(_ key: DictationActivationKey) {
        let enabled = shortcutEnabled; stopShortcutMonitoring(); cancel()
        preferences.activationKey = key
        if enabled { startShortcutMonitoring() }
    }
    func disableShortcut() { commandArmed = false; preferences.holdFnEnabled = false; stopShortcutMonitoring(); cancel() }
    private func stopShortcutMonitoring() { shortcutGeneration += 1; shortcutEnabled = false; shortcutHeld = false; shortcut.disable() }
    /// Normal Quit must not silently discard an in-flight insertion or its RAM clipboard backup.
    func canTerminateSafely() -> Bool {
        reconcileClipboard()
        if busy { message = "Finish or cancel dictation before quitting."; return false }
        if insertion.hasPendingClipboard { clipboardPending = true; message = "Review clipboard restoration before quitting; the saved clipboard is held in memory."; return false }
        return true
    }
    func close() {
        previewPresented = false; previewOriginProcessIdentifier = nil
        cancelRewritePreview(); previewRegistrar?.disable(); registeredPreviewKinds = []; closed = true; commandArmed = false; stopShortcutMonitoring(); cancel(); work?.cancel(); timer?.cancel()
        let store = history
        Task { await store?.close() }
    }
}
