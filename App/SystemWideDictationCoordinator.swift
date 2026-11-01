import UserNotifications
import Foundation
import SwiftUI
import Domain
import SystemOperations
import VoiceInput

/// Owns a single speech/insertion/history session. Transcript data never submits a task.
@MainActor final class SystemWideDictationCoordinator: ObservableObject {
    enum Phase: String, CaseIterable { case idle, preparing, recording, finalizing, inserting, success, error }
    @Published private(set) var phase: Phase = .idle
    enum InPlaceHUD: Equatable { case idle, polishing, structuring, success, error }
    @Published private(set) var lastAIShortcutFailure:String?
    @Published private(set) var inPlaceHUD: InPlaceHUD = .idle { didSet {
        if inPlaceHUD == .error { lastAIShortcutFailure = message }
        else if inPlaceHUD == .success { lastAIShortcutFailure = nil }
    } }
    @Published private(set) var hudFeedbackVisible = false
    @Published private(set) var audioBars = [Double](repeating:0,count:7)
    private var meterTask: Task<Void,Never>?
    private var feedbackTask: Task<Void,Never>?
    private var hudTicket = UUID()
    private var rewriteAnchor: (any DictationRewriteAnchor)?
    private var receiptCreatedAt: Int64?
    private var receiptExpiryTask: Task<Void,Never>?
    func waitForReceiptExpiration() async { await receiptExpiryTask?.value }
    private func armReceiptExpiration(sessionID:String,createdAt:Int64) {
        receiptExpiryTask?.cancel()
        let deadline = createdAt.addingReportingOverflow(120_000)
        guard !deadline.overflow else { rejectProvenance(DictationRewriteValidationFailure.expired); return }
        receiptExpiryTask = Task { [weak self,clock] in
            do { try await clock.sleep(until:deadline.partialValue) } catch { return }
            guard let self, !Task.isCancelled, self.rewriteAnchor?.sessionID == sessionID,
                  self.receiptCreatedAt == createdAt else { return }
            self.rejectProvenance(DictationRewriteValidationFailure.expired)
        }
    }
    private var rewriteEligibility = "No insertion receipt exists in this process. Dictate again with in-place mode enabled."
    enum ProvenanceReason: String {
        case none = "NONE", noReceipt = "NO_INSERTION_RECEIPT", uncertain = "INSERTION_UNCERTAIN"
        case failed = "INSERTION_FAILED", expired = "RECEIPT_EXPIRED", targetChanged = "TARGET_CHANGED"
        case targetInvalid = "TARGET_INVALID", invalidated = "SESSION_INVALIDATED"
        case replacementUnsupported = "EDITOR_REPLACEMENT_UNSUPPORTED"
        case rangeUnavailable = "SOURCE_RANGE_UNAVAILABLE", disabled = "CAPTURE_DISABLED"
        case clipboard = "CLIPBOARD_PENDING", consumed = "RECEIPT_CONSUMED"
    }
    enum PipelineResult:String {
        case notStarted = "NOT_STARTED", pending = "PENDING", recording = "RECORDING", success = "SUCCESS"
        case failed = "FAILED", cancelled = "CANCELLED", unsupported = "UNSUPPORTED", unverified = "UNCERTAIN"
        case dispatched = "DISPATCHED_UNVERIFIED", restored = "RESTORED", preservedNewer = "NEWER_DATA_PRESERVED"
        case notNeeded = "NOT_NEEDED", recoveryPending = "RECOVERY_PENDING"
    }
    @Published private(set) var audioCaptureResult:PipelineResult = .notStarted
    @Published private(set) var transcriptionResult:PipelineResult = .notStarted
    @Published private(set) var targetCaptureResult:PipelineResult = .notStarted
    @Published private(set) var targetValidationResult:PipelineResult = .notStarted
    @Published private(set) var pasteboardLeaseResult:PipelineResult = .notStarted
    @Published private(set) var insertionDispatchResult:PipelineResult = .notStarted
    private var destinationBundleIdentifier:String?
    private var speechFailureCode = "NONE"
    private var terminalSpeechFailure:DictationFailure?
    @Published private(set) var unmergedSpeechRecoveryEntry: DictationHistoryEntry?
    @Published private(set) var speechFailureDiagnostics: DictationSpeechDiagnostics?
    @Published private(set) var speechRunDiagnostics: [String] = []
    var speechDiagnosticSummary: String {
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"
        let executable = Bundle.main.executableURL?.path ?? "unknown"
        let current = speechFailureDiagnostics ?? (input as? any DictationCaptureReporting)?.speechDiagnostics
        return "45A-R3 / speech38L3R3 build=\(build) pid=\(ProcessInfo.processInfo.processIdentifier) executable=\(executable) hotkeyHeldObservedNow=\(shortcutHeld) · "
            + "agentStartupMs=" + (agentStartupMilliseconds.map(String.init) ?? "unmeasured") + " · "
            + (current?.summary ?? "speechTelemetry=unavailable")
            + "\nCapture: " + ((input as? any DictationCaptureReporting)?.captureDiagnosticSummary ?? "unavailable")
            + "\nDestination binding: " + destinationBindingSummary
            + "\nCurrent inspected resources: " + (speechConfiguration.map { value in
                "requestedLocale=\(value.locale) speechAvailable=\(value.speech.deviceAvailable) speechState=\(value.speech.state.rawValue) speechInventory=\(value.speech.inventoryStatus) dictationState=\(value.dictation.state.rawValue) dictationInventory=\(value.dictation.inventoryStatus)"
            } ?? "notInspected")
            + " preparationNow=" + (speechPreparation.map { "verified:" + $0.engine.rawValue + ":" + $0.resolvedLocale } ?? "notVerified")
            + " resourceOperationActive=\(speechResourceWorking)"
            + "\nRecent terminal metadata (no text/audio):\n" + speechRunDiagnostics.joined(separator:"\n")
    }
    private func recordSpeechRun(_ kind: String, failure: DictationFailure? = nil, stage: DictationSpeechStage? = nil) {
        if let failure { terminalSpeechFailure = failure }
        let captured = (input as? any DictationCaptureReporting)?.speechDiagnostics
        var value = captured ?? DictationSpeechDiagnostics()
        if captured == nil { value.preservedBytes = raw.utf8.count }
        if let failure { value.failure = String(describing:failure); value.phase = "failed" }
        if let stage { value.stage = stage }
        if failure != nil {
            speechFailureDiagnostics = value
            if let candidate = (input as? any DictationRecoveryProviding)?.unmergedRecognitionText, !candidate.isEmpty, candidate.utf8.count <= DictationText.maximumBytes {
                unmergedSpeechRecoveryEntry = .init(id:UUID().uuidString,timestamp:wallTime(),raw:candidate,cleaned:candidate,sourceApplication:nil,durationMilliseconds:0,insertion:.init(.denied,.speechFailed))
            }
        }
        if speechRunDiagnostics.count == 8 { speechRunDiagnostics.removeFirst() }
        speechRunDiagnostics.append("operation=\(diagnosticOperation) terminal=\(kind) shortcutSession=\(startedFromShortcut) hotkeyHeldObserved=\(shortcutHeld) " + value.summary)
    }
    private var pipelineSummary:String {
        let bundle:String
        if let value = destinationBundleIdentifier, value.utf8.count <= 255,
           value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) { bundle = value }
        else { bundle = "unknown" }
        return [destinationBindingSummary,"destinationBundle="+bundle,"CAPTURE_RESULT="+audioCaptureResult.rawValue,
                "TRANSCRIPTION_RESULT="+transcriptionResult.rawValue,"speechCode="+speechFailureCode,
                "TARGET_CAPTURE_RESULT="+targetCaptureResult.rawValue,"TARGET_VALIDATION_RESULT="+targetValidationResult.rawValue,
                "PASTEBOARD_LEASE_RESULT="+pasteboardLeaseResult.rawValue,"INSERTION_DISPATCH_RESULT="+insertionDispatchResult.rawValue,
                "DESTINATION_READBACK_RESULT="+readbackStatus.rawValue,"INSERTION_OUTCOME="+deliveryStatus.rawValue].joined(separator:" · ")
    }
    enum CrossAppStatus:String {
        case notRequested = "NOT_REQUESTED", unknown = "UNKNOWN", noReceipt = "NO_INSERTION_RECEIPT"
        case notDelivered = "DICTATION_NOT_DELIVERED", insertedUnverified = "DICTATION_INSERTED_UNVERIFIED"
        case readbackUnavailable = "ACCESSIBILITY_READBACK_UNAVAILABLE", rangeUnavailable = "INSERTION_RANGE_UNAVAILABLE"
        case targetChanged = "INSERTION_TARGET_CHANGED", replacementUnsupported = "EDITOR_REPLACEMENT_UNSUPPORTED"
        case verifiedInsertion = "VERIFIED_INSERTION_AVAILABLE", sourceChanged = "SOURCE_TEXT_CHANGED"
        case memoryBlocked = "MODEL_MEMORY_BLOCKED", generationFailed = "GENERATION_FAILED"
        case replacementVerified = "REPLACEMENT_VERIFIED", replacementUncertain = "REPLACEMENT_UNCERTAIN"
        case featureDisabled = "AI_FEATURE_DISABLED", settingsConflict = "SETTINGS_CONFLICT"
        case clipboardPending = "CLIPBOARD_RECOVERY_PENDING", inputRejected = "AI_INPUT_REJECTED"
        case generationCancelled = "GENERATION_CANCELLED"
        case apiAdvertised = "REPLACEMENT_API_ADVERTISED", generationRequested = "GENERATION_REQUESTED", generationCompleted = "GENERATION_COMPLETED"
    }
    @Published private(set) var deliveryStatus:CrossAppStatus = .notRequested
    @Published private(set) var readbackStatus:CrossAppStatus = .notRequested
    @Published private(set) var replacementCapabilityStatus:CrossAppStatus = .unknown
    @Published private(set) var generationStatus:CrossAppStatus = .notRequested
    @Published private(set) var replacementResultStatus:CrossAppStatus = .notRequested
    @Published private(set) var crossAppFailure:CrossAppStatus = .notRequested
    private var latestReplacementCapability:EditorReplacementCapability = .unknown
    private var latestTargetProcessIdentifier:Int32?
    private var diagnosticOperation = UUID().uuidString
    private var activeCaptureDiagnostics:[InsertionVerificationDiagnostic] = []
    private var activeInsertionDiagnostics:[InsertionVerificationDiagnostic] {
        guard let session, insertion.verificationSession == session else { return [] }
        return insertion.verificationDiagnostics
    }
    private var captureElapsedMilliseconds:Int64?
    private var insertionElapsedMilliseconds:Int64?
    private var crossAppSummary:String {
        ["operationID="+diagnosticOperation,"DICTATION_DELIVERY="+deliveryStatus.rawValue,
         "INSERTION_VERIFICATION="+readbackStatus.rawValue,"REPLACEMENT_CAPABILITY="+replacementCapabilityStatus.rawValue,
         "AI_GENERATION="+generationStatus.rawValue,"REPLACEMENT_RESULT="+replacementResultStatus.rawValue,
         "failureCode="+crossAppFailure.rawValue,"captureMs="+(captureElapsedMilliseconds.map(String.init) ?? "unknown"),
         "insertionMs="+(insertionElapsedMilliseconds.map(String.init) ?? "unknown")].joined(separator:" · ")
    }
    private func classifyInsertion(_ receipt:TextInsertionReceipt,target:(any InsertionTarget)?) {
        latestReplacementCapability = target?.replacementCapability ?? .unknown
        latestTargetProcessIdentifier = target?.info.processID
        replacementCapabilityStatus = latestReplacementCapability == .unavailable ? .replacementUnsupported : (latestReplacementCapability == .available ? .apiAdvertised : .unknown)
        deliveryStatus = receipt.attempted ? (receipt.status == .insertedVerified ? .verifiedInsertion : .insertedUnverified) : .notDelivered
        let codes = (activeCaptureDiagnostics + activeInsertionDiagnostics).map(\.code)
        targetValidationResult = receipt.attempted ? .success : (receipt.reason == .changed || receipt.reason == .permission || receipt.reason == .secureField ? .failed : .notStarted)
        insertionDispatchResult = receipt.attempted ? .dispatched : .notStarted
        if codes.contains(.clipboardRetained) || receipt.clipboardPending { pasteboardLeaseResult = .recoveryPending }
        else if codes.contains(.clipboardSuperseded) { pasteboardLeaseResult = .preservedNewer }
        else if codes.contains(.clipboardRestored) { pasteboardLeaseResult = .restored }
        else if codes.contains(.clipboardAcquired) { pasteboardLeaseResult = .pending }
        else if receipt.reason == .clipboardUnsupported { pasteboardLeaseResult = .unsupported }
        else if receipt.reason == .clipboardChanged { pasteboardLeaseResult = .failed }
        else { pasteboardLeaseResult = .notNeeded }
        targetIdentityMatched = receipt.status == .insertedVerified ? "true" : (receipt.reason == .changed || codes.contains(.targetChanged) ? "false" : "notChecked")
        if receipt.status == .insertedVerified { readbackStatus = .verifiedInsertion; crossAppFailure = .notRequested }
        else if codes.contains(.targetChanged) || receipt.reason == .changed { readbackStatus = .targetChanged; crossAppFailure = .targetChanged }
        else if codes.contains(.rangeInvalid) || codes.contains(.rangeUnavailable) { readbackStatus = .rangeUnavailable; crossAppFailure = .rangeUnavailable }
        else if receipt.reason == .permission || codes.contains(.readbackDenied) || codes.contains(.readbackUnsupported) || codes.contains(.readbackTemporary) { readbackStatus = .readbackUnavailable; crossAppFailure = .readbackUnavailable }
        else { readbackStatus = receipt.attempted ? .insertedUnverified : .notRequested; crossAppFailure = deliveryStatus }
    }
    private var captureActivation:DictationActivationContext?
    private var captureObservedIdentity:DictationApplicationIdentity?
    private var destinationBindingSummary:String {
        "destinationActivation=["+(captureActivation?.summary ?? "immediateCapture")+"] observedAtCapture=["+(captureObservedIdentity?.summary ?? "unavailable")+"]"
    }
    private func captureDestination(session:String) throws -> any InsertionTarget {
        let began = ContinuousClock.now
        defer {
            let elapsed = began.duration(to:.now).components
            let seconds = elapsed.seconds.multipliedReportingOverflow(by:1000)
            let total = seconds.partialValue.addingReportingOverflow(elapsed.attoseconds / 1_000_000_000_000_000)
            captureObservedIdentity = targets.observedApplicationIdentity
            activeCaptureDiagnostics = targets.captureDiagnostics
            if let bundle = targets.captureBundleIdentifier { destinationBundleIdentifier = bundle }
            captureElapsedMilliseconds = !seconds.overflow && !total.overflow && total.partialValue >= 0 ? total.partialValue : nil
        }
        do {
            let target: any InsertionTarget
            if let activation=captureActivation { target=try targets.capture(session:session,activation:activation) }
            else { target=try targets.capture(session:session) }
            targetCaptureResult = .success
            destinationBundleIdentifier = target.info.bundleIdentifier ?? targets.captureBundleIdentifier
            return target
        } catch { targetCaptureResult = .failed; throw error }
    }
    @Published private(set) var provenanceReason: ProvenanceReason = .noReceipt
    private var latestInsertionOutcome = "none"
    private var verifiedReceiptCreated = false
    private var targetIdentityMatched = "notChecked"
    private var targetVerificationAvailable = false
    private var shortcutOperation = "none"
    @Published private var insertionLookupSummary = "No shortcut receipt lookup"
    @Published private var insertionTraceSummary = "No insertion readback recorded"
    private func recordInsertionTrace(_ target:(any InsertionTarget)?,receipt:TextInsertionReceipt) {
        #if DEBUG
        let native = target?.insertionDiagnostics ?? []
        let service = activeInsertionDiagnostics
        let values = Array(activeCaptureDiagnostics.suffix(12)) + Array(native.prefix(3)) + Array(native.suffix(8)) + Array(service.prefix(6)) + Array(service.suffix(10))
        insertionTraceSummary = values.map { d in
            var parts = [d.stage.rawValue,d.code.rawValue,d.status.rawValue,d.timing.rawValue]
            if let value = d.axError { parts.append("AX=\(value)") }
            if let value = d.expectedUTF16 { parts.append("expected=\(value)") }
            if let value = d.observedUTF16 { parts.append("observed=\(value)") }
            if let value = d.rangeLocation { parts.append("location=\(value)") }
            if let value = d.rangeLength { parts.append("length=\(value)") }
            if let value = d.elapsedMilliseconds { parts.append("elapsedMs=\(value)") }
            return parts.joined(separator:":")
        }.joined(separator:" · ") + " · receipt=" + receipt.status.rawValue
        #endif
    }
    var eligibleReceiptPresent: Bool { rewriteAnchor != nil }
    private func invalidateProvenance(_ reason:ProvenanceReason,_ explanation:String) {
        receiptExpiryTask?.cancel(); receiptExpiryTask = nil
        rewriteAnchor = nil; receiptCreatedAt = nil; targetVerificationAvailable = false; provenanceReason = reason; rewriteEligibility = explanation
    }
    private func rejectProvenance(_ error:any Error) {
        let reason:ProvenanceReason
        switch error {
        case DictationRewriteValidationFailure.expired: reason = .expired
        case DictationRewriteValidationFailure.targetChanged, TextTargetError.changed: reason = .targetChanged
        case DictationRewriteValidationFailure.editorUnavailable: reason = .targetInvalid
        case DictationRewriteValidationFailure.consumed: reason = .consumed
        case DictationRewriteValidationFailure.unsupportedEditor, TextTargetError.unsupported: reason = .replacementUnsupported
        default: reason = .rangeUnavailable
        }
        switch error {
        case DictationRewriteValidationFailure.unsupportedEditor, TextTargetError.unsupported:
            replacementCapabilityStatus = .replacementUnsupported; crossAppFailure = .replacementUnsupported
        case DictationRewriteValidationFailure.textMismatch, DictationRewriteValidationFailure.contextChanged: crossAppFailure = .sourceChanged
        case DictationRewriteValidationFailure.textUnavailable, DictationRewriteValidationFailure.permission, TextTargetError.denied: crossAppFailure = .readbackUnavailable
        case DictationRewriteValidationFailure.targetChanged, DictationRewriteValidationFailure.editorUnavailable, TextTargetError.changed: crossAppFailure = .targetChanged
        default: crossAppFailure = .rangeUnavailable
        }
        if reason == .targetChanged || reason == .targetInvalid { targetIdentityMatched = "false" }
        invalidateProvenance(reason,Self.rewriteSourceExplanation(error))
    }
    private var inPlaceTask: Task<Void,Never>?
    private var inPlaceID: String?
    var inPlaceRunning: Bool { inPlaceTask != nil }
    func waitForCaptureStartup() async { await startup?.value }
    func waitForInsertionCompletion() async { await work?.value }
    func waitForInPlaceRewrite() async { await inPlaceTask?.value }
    @discardableResult func cancelInPlaceRewrite() -> Task<Void,Never>? {
        let completion = inPlaceTask
        let id = inPlaceID
        if id != nil {
            traceRoute(inPlaceHUD == .structuring ? .promptEngineering : .polish,.cancelled)
            generationStatus = .generationCancelled; crossAppFailure = .generationCancelled
            verificationModelState = "cancelled"
        }
        inPlaceID = nil; inPlaceTask?.cancel(); inPlaceTask = nil
        inPlaceHUD = .idle
        if let id, let offlineRewriter { Task { await offlineRewriter.cancel(requestID:id) } }
        return completion
    }
    private func startAudioVisualization(id:String) {
        stopAudioVisualization()
        guard commandSession || input is any DictationAudioMetering else { return }
        meterTask = Task { [weak self] in
            var envelope = DictationAudioEnvelope()
            while !Task.isCancelled {
                guard let self, self.session == id, self.phase == .recording else { return }
                if self.commandSession {
                    do { try self.agentCaptureValidation() } catch { self.cancel(); return }
                }
                envelope.update((self.input as? any DictationAudioMetering)?.audioLevel() ?? .init())
                self.audioBars = envelope.bars
                do { try await Task.sleep(for:.milliseconds(50)) } catch { return }
            }
        }
    }
    private func stopAudioVisualization() { meterTask?.cancel(); meterTask = nil; audioBars = [Double](repeating:0,count:7) }
    func waitForHUDFeedback() async { await feedbackTask?.value }
    private func showHUDFeedback() {
        // Keep the exact compact outcome inspectable in the existing General
        // shortcut-status row after the transient HUD dismisses.
        if inPlaceHUD != .idle { previewShortcutStatus = message }
        feedbackTask?.cancel(); let ticket = UUID(); hudTicket = ticket; hudFeedbackVisible = true
        feedbackTask = Task { [weak self] in
            guard let self else { return }
            let deadline = await self.hudClock.now() + 1200
            do { try await self.hudClock.sleep(until:deadline) } catch { return }
            guard self.hudTicket == ticket else { return }
            self.hudFeedbackVisible = false
            if self.inPlaceHUD == .success || self.inPlaceHUD == .error { self.inPlaceHUD = .idle }
        }
    }
    enum ShortcutRouteStage: String {
        case received, inPlaceSelected, settingsDisagree, ignoredBusy
        case noEligibleDictation, featureDisabled, clipboardPending, foreignSource, oversizedInput, providerMissing
        case sourceRejected, generationRequested, generationReturned, outputRejected, sourceChanged
        case unchanged, replacementRequested, replacementVerified, replacementUncertain, cancelled
    }
    struct ShortcutRouteSample: Equatable {
        let kind: OfflinePreviewKind
        let stage: ShortcutRouteStage
    }
    /// Bounded metadata only: no text, clipboard data, hashes or AX document contents.
    private(set) var shortcutRouteTrace: [ShortcutRouteSample] = []
    private func traceRoute(_ kind:OfflinePreviewKind,_ stage:ShortcutRouteStage) {
        #if DEBUG
        if shortcutRouteTrace.count == 32 { shortcutRouteTrace.removeFirst() }
        shortcutRouteTrace.append(.init(kind:kind,stage:stage))
        #endif
    }
    var shortcutModeDescription: String {
        preferences.inPlaceAIRewrite
            ? "38L3R3 · Option+1/2 request in-place AI only. A new verified dictation and supported unchanged editor are required. No preview opens on failure. Nothing is submitted."
            : "38L3R3 · Option+1/2 show only the pill while this switch is OFF. Enable before a new verified dictation. Manual preview is available only through Settings."
    }
    @Published private var verificationDetail = "No verification requested"
    var verificationDiagnosticSummary: String {
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"
        return "45A-R3 / speech38L3R3 build=" + build + " lifecycle=" + (closed ? "closed" : phase.rawValue)
            + " outcome=" + latestInsertionOutcome + " verifiedReceipt=" + String(verifiedReceiptCreated)
            + " eligibleReceipt=" + String(eligibleReceiptPresent) + " reason=" + provenanceReason.rawValue
            + " expiration=" + (provenanceReason == .expired ? "expired" : (eligibleReceiptPresent ? "native120sRecheckedOnUse" : "noActiveAnchor"))
            + " targetMatched=" + targetIdentityMatched + " verificationAvailable=" + String(targetVerificationAvailable)
            + " operation=" + shortcutOperation + " model=" + verificationModelState + " · " + verificationDetail + " · insertion: " + insertionTraceSummary + " · " + insertionLookupSummary + " · " + crossAppSummary + " · " + pipelineSummary + " · " + ((input as? any DictationCaptureReporting)?.captureDiagnosticSummary ?? "captureTelemetry=unavailable") + " · formatRawBytes=\(raw.utf8.count) formatOutputBytes=\(cleaned.utf8.count) formattingChanged=\(raw != cleaned)"
    }
    private var verificationModelState = "notRequested"
    private func recordVerification(_ phase:String,_ values:[DictationVerificationDiagnostic],failure:(any Error)? = nil) {
        #if DEBUG
        let fields = values.suffix(12).map { value in
            value.stage.rawValue + ":" + value.result.rawValue + (value.expectedUTF16.map { " expectedUTF16=\($0)" } ?? "") + (value.currentUTF16.map { " currentUTF16=\($0)" } ?? "")
        }.joined(separator:" · ")
        let code = (failure as? DictationRewriteValidationFailure)?.rawValue ?? (failure == nil ? "none" : "unclassified")
        verificationDetail = phase + " model=" + verificationModelState + " failure=" + code + " · " + fields
        #endif
    }
    var hideCompletedDictationPill:Bool {
        guard inPlaceHUD == .idle,phase == .error,transcriptionResult == .success,
              let latest,latest.id == reliableFinalID,latest.insertion.attempted else { return false }
        return [.uncertain,.dispatchedUnverified].contains(latest.insertion.status)
    }
    var compactDictationStatus: String {
        if clipboardPending { return "Review clipboard" }
        if let detail = speechFailureDiagnostics, detail.failure != "none" { return detail.compactFailure }
        if speechFailureCode == "anotherInstance" { return "Another Flow copy" }
        if speechFailureCode == "providerEnded" { return "Speech provider ended" }
        if speechFailureCode == "overflow" { return "Dictation limit" }
        if speechFailureCode == "timedOut" { return "Speech timed out" }
        if speechFailureCode == "microphoneDenied" { return "Microphone access" }
        if speechFailureCode == "speechDenied" { return "Speech access" }
        if speechFailureCode == "audioUnavailable" { return "Microphone interrupted" }
        if speechFailureCode == "unsupportedRecognitionScript" { return "Wrong recognition script" }
        if speechFailureCode == "repetitiveRecognition" { return "Recognition repeated" }
        if speechFailureCode != "NONE" { return "Speech failed" }
        if clipboardPending { return "Clipboard pending" }
        if let latest, latest.id == reliableFinalID {
            if latest.insertion.status == .targetChanged { return "Target changed" }
            if latest.insertion.status == .unsupportedTarget { return "Field unavailable" }
        }
        if latest?.insertion.status == .dispatchedUnverified || latest?.insertion.status == .uncertain { return "Dictation finished" }
        return "Check dictation"
    }
    var compactAIStatus: String {
        if message.hasPrefix("Cannot verify inserted text") { return "Cannot verify text" }
        if message.hasPrefix("Original text location unavailable") { return "Text location missing" }
        if message.hasPrefix("Original editor no longer accessible") { return "Editor inaccessible" }
        if message.hasPrefix("Cannot verify editor composition") { return "Editor state unknown" }
        if message.hasPrefix("Original insertion expired") { return "Dictation expired" }
        if message.hasPrefix("Caret or selection moved") { return "Caret moved" }
        if message.hasPrefix("Inserted text differs") { return "Text changed" }
        if message.hasPrefix("Surrounding text changed") { return "Context changed" }
        if message.hasPrefix("Enable in-place") { return "Enable in-place AI" }
        if message.hasPrefix("Enable Smart Polish") { return "Enable Smart Polish" }
        if message.hasPrefix("Enable Prompt Engineering") { return "Enable Prompt Engineering" }
        if message.contains("AI input limit") { return "AI input too long" }
        if message.contains("Accessibility permission") { return "Accessibility needed" }
        if message.hasPrefix("No insertion receipt") { return "No insertion receipt" }
        if provenanceReason == .uncertain && message == rewriteEligibility { return "Insertion uncertain" }
        if provenanceReason == .failed && message == rewriteEligibility { return "Insertion failed" }
        if provenanceReason == .disabled && message == rewriteEligibility { return "New dictation needed" }
        if message.contains("No eligible recent dictation") { return "No recent dictation" }
        if message.contains("Destination editor") { return "Editor unsupported" }
        if message.contains("memory/resource") { return "Memory blocked" }
        if message.contains("unavailable") { return "AI unavailable" }
        if message.contains("cancelled") { return "Cancelled" }
        if message.contains("timed out") { return "AI timed out" }
        if message.contains("invalid") || message.contains("preservation checks") { return "Invalid AI output" }
        if message.contains("Secure input") { return "Secure input" }
        if message.contains("clipboard recovery") { return "Clipboard pending" }
        if message.contains("settings changed") { return "Settings changed" }
        if message.contains("changed or expired") { return "Target changed" }
        if message.contains("could not be verified") { return "Check replacement" }
        return "Can't replace text"
    }
    private static func rewriteSourceExplanation(_ error:any Error) -> String {
        if let failure = error as? DictationRewriteValidationFailure {
            switch failure {
            case .permission: return "Accessibility permission is required. Original retained."
            case .secureInput: return "Secure input or active composition prevents replacement. Original retained."
            case .editorUnavailable: return "Original editor no longer accessible. Nothing replaced."
            case .targetChanged: return "Original target changed or expired. Nothing replaced."
            case .expired: return "Original insertion expired. Dictate again; nothing replaced."
            case .consumed: return "No eligible recent dictation; that insertion was already used."
            case .unsupportedEditor: return "Destination editor is unsupported for safe exact-range replacement. Original retained."
            case .compositionUnavailable: return "Cannot verify editor composition state. Original retained."
            case .invalidRange: return "Original text location unavailable. Nothing replaced."
            case .textUnavailable: return "Cannot verify inserted text: readable AX data is unavailable. Nothing replaced."
            case .textMismatch: return "Inserted text differs at the verified original range. Nothing replaced."
            case .contextChanged: return "Surrounding text changed. Nothing replaced."
            case .caretChanged: return "Caret or selection moved outside the verified insertion. Nothing replaced."
            }
        }
        switch error {
        case TextTargetError.denied: return "Accessibility permission is required. Original retained."
        case TextTargetError.secure: return "Secure input or active composition prevents replacement. Original retained."
        case TextTargetError.unsupported: return "Destination editor does not expose safe exact-range replacement and IME state. Original retained."
        case TextTargetError.changed: return "Original target changed or expired. Nothing replaced."
        default: return "Cannot verify inserted text. Nothing replaced."
        }
    }
    private func rejectInPlace(_ kind:OfflinePreviewKind,_ stage:ShortcutRouteStage,_ explanation:String) {
        switch stage {
        case .featureDisabled: crossAppFailure = .featureDisabled
        case .settingsDisagree: crossAppFailure = .settingsConflict
        case .clipboardPending: crossAppFailure = .clipboardPending
        case .oversizedInput: crossAppFailure = .inputRejected
        case .foreignSource: crossAppFailure = .targetChanged
        case .providerMissing: crossAppFailure = .generationFailed
        default: break
        }
        traceRoute(kind,stage); previewPresented = false
        message = explanation; inPlaceHUD = .error; showHUDFeedback()
    }
    func invokeInPlaceRewrite(_ kind:OfflinePreviewKind, originProcessIdentifier:Int32?) {
        guard !closed, !busy, inPlaceTask == nil else { traceRoute(kind,.ignoredBusy); return }
        verificationModelState = "notRequested"
        generationStatus = .notRequested; replacementResultStatus = .notRequested
        shortcutOperation = kind.rawValue
        insertionLookupSummary = "SHORTCUT_RECEIPT_LOOKUP operation=" + kind.rawValue + " present=" + String(eligibleReceiptPresent) + " sessionMatched=" + String(rewriteAnchor != nil && rewriteAnchor?.sessionID == latest?.id)
        targetIdentityMatched = "notChecked"
        // A pending preview from an earlier mode may never become this route's fallback.
        cancelTextCapture(); cancelRewritePreview(); previewPresented = false
        guard preferences.inPlaceAIRewrite else {
            rejectInPlace(kind,.featureDisabled,"Enable in-place AI rewrite first, then dictate again. Original retained."); return
        }
        guard kind == .polish ? preferences.offlineAIRewriting : preferences.promptEngineeringEnabled else {
            rejectInPlace(kind,.featureDisabled,kind == .polish ? "Enable Smart Polish first. Original retained." : "Enable Prompt Engineering first. Original retained."); return
        }
        if rewriteAnchor == nil, latestReplacementCapability == .unavailable, latestTargetProcessIdentifier == originProcessIdentifier {
            crossAppFailure = .replacementUnsupported
            invalidateProvenance(.replacementUnsupported,"Destination editor is unsupported for precise replacement. Dictated text is retained. Use Smart Formatting’s manual preview and Copy instead.")
            rejectInPlace(kind,.sourceRejected,rewriteEligibility); return
        }
        guard !insertion.hasPendingClipboard else { rejectInPlace(kind,.clipboardPending,"Resolve pending clipboard recovery before rewriting. Original retained."); return }
        guard let anchor = rewriteAnchor else {
            if provenanceReason == .noReceipt { crossAppFailure = .noReceipt }
            rejectInPlace(kind,.noEligibleDictation,rewriteEligibility); return
        }
        guard anchor.processID == originProcessIdentifier else { targetIdentityMatched = "false"; crossAppFailure = .targetChanged; invalidateProvenance(.targetChanged,"The original destination app is not the shortcut source. Nothing replaced."); rejectInPlace(kind,.foreignSource,"The original destination app is not the shortcut source. Nothing replaced."); return }
        targetIdentityMatched = "true"
        guard anchor.originalText.utf8.count <= 2048 else { rejectInPlace(kind,.oversizedInput,"The last dictation exceeds the AI input limit. Original retained."); return }
        guard let offlineRewriter else { generationStatus = .generationFailed; crossAppFailure = .generationFailed; rejectInPlace(kind,.providerMissing,"Local AI is unavailable. Original retained."); return }
        do { try anchor.validate(); recordVerification("beforeGeneration",anchor.verificationDiagnostics) } catch {
            recordVerification("beforeGeneration",anchor.verificationDiagnostics,failure:error)
            rejectProvenance(error); rejectInPlace(kind,.sourceRejected,rewriteEligibility); return
        }
        cancelTextCapture(); cancelRewritePreview(); previewPresented = false
        let id = UUID().uuidString; inPlaceID = id
        inPlaceHUD = kind == .polish ? .polishing : .structuring
        message = kind == .polish ? "Polishing on this Mac…" : "Structuring on this Mac…"
        let request = OfflineRewriteRequest(id:id,text:anchor.originalText,localeIdentifier:localeIdentifier,vocabulary:preferences.formatting.vocabulary + preferences.formatting.replacements.map(\.replacement),tone:preferences.polishTone,kind:kind)
        let createdAt = receiptCreatedAt
        inPlaceTask = Task { [weak self,clock] in
            let now = await clock.now()
            guard let self, self.inPlaceID == id, !self.closed, !Task.isCancelled else { return }
            // A monotonic, injected clock makes expiry reproducible. Native anchor
            // freshness is independently rechecked before every AX operation.
            let elapsed = createdAt.map { now.subtractingReportingOverflow($0) }
            guard let elapsed, !elapsed.overflow, elapsed.partialValue >= 0, elapsed.partialValue < 120_000 else {
                self.inPlaceTask = nil; self.inPlaceID = nil
                self.rejectProvenance(DictationRewriteValidationFailure.expired)
                self.rejectInPlace(kind,.sourceRejected,self.rewriteEligibility); return
            }
            self.traceRoute(kind,.generationRequested)
            self.generationStatus = .generationRequested; self.crossAppFailure = .notRequested
            self.verificationModelState = "requested"
            self.verificationDetail = String((self.verificationDetail + " · generation=requested").suffix(2048))
            let result = await offlineRewriter.rewrite(request)
            guard self.inPlaceID == id, !Task.isCancelled, !self.closed, self.preferences.inPlaceAIRewrite else { return }
            self.inPlaceTask = nil; self.inPlaceID = nil
            guard self.rewriteAnchor === anchor else {
                self.rejectInPlace(kind,.sourceChanged,self.rewriteEligibility); return
            }
            self.traceRoute(kind,.generationReturned)
            self.generationStatus = .generationCompleted
            #if DEBUG
            self.verificationModelState = result.status.rawValue
            self.verificationDetail += " · model=" + result.status.rawValue
            #endif
            guard result.status == .rewritten || result.status == .unchanged else {
                switch result.status {
                case .resourceBlocked: self.message = "Model memory/resource admission blocked generation. Original retained."
                case .modelUnavailable: self.message = "Local AI or its language support is unavailable. Original retained."
                case .cancelled: self.message = "AI generation cancelled. Original retained."
                case .timedOut: self.message = "AI generation timed out. Original retained."
                default: self.message = "AI output was invalid or incomplete. Original retained."
                }
                self.generationStatus = result.status == .resourceBlocked ? .memoryBlocked : .generationFailed
                self.crossAppFailure = self.generationStatus
                self.inPlaceHUD = .error; self.showHUDFeedback(); return
            }
            do {
                if kind == .polish { try ProtectedRewriteText(request).validateRestored(result.text) }
                else { try PromptEngineeringContract(request).validateRendered(result.text) }
            } catch {
                self.generationStatus = .generationFailed; self.crossAppFailure = .generationFailed
                self.traceRoute(kind,.outputRejected); self.message = "AI output failed preservation checks. Original retained."; self.inPlaceHUD = .error; self.showHUDFeedback(); return
            }
            do { try anchor.validate(); self.recordVerification("afterGeneration",anchor.verificationDiagnostics) } catch {
                self.recordVerification("afterGeneration",anchor.verificationDiagnostics,failure:error)
                self.rejectProvenance(error); self.traceRoute(kind,.sourceChanged); self.message = self.rewriteEligibility; self.inPlaceHUD = .error; self.showHUDFeedback(); return
            }
            if result.text == anchor.originalText {
                self.traceRoute(kind,.unchanged); self.message = "No change needed; original retained."; self.inPlaceHUD = .success; self.showHUDFeedback(); return
            }
            self.invalidateProvenance(.consumed,"No eligible recent dictation; that insertion was already used.")
            self.traceRoute(kind,.replacementRequested)
            let receipt = anchor.replaceValidatedSpan(result.text)
            self.recordVerification("replacement=" + receipt.status.rawValue + " attempted=" + String(receipt.attempted),anchor.verificationDiagnostics,failure:anchor.lastValidationFailure)
            if !receipt.attempted, let failure = anchor.lastValidationFailure { self.rejectProvenance(failure) }
            if receipt.status == .insertedVerified {
                self.replacementResultStatus = .replacementVerified; self.crossAppFailure = .notRequested
                self.traceRoute(kind,.replacementVerified); self.message = "AI replacement verified. Nothing submitted."; self.inPlaceHUD = .success
            } else {
                self.replacementResultStatus = .replacementUncertain
                if receipt.attempted { self.crossAppFailure = .replacementUncertain }
                self.traceRoute(kind,.replacementUncertain); self.message = receipt.attempted ? "Replacement could not be verified. Check the field; nothing retried." : (anchor.lastValidationFailure.map { Self.rewriteSourceExplanation($0) } ?? "Cannot verify inserted text. Original retained.")
                self.inPlaceHUD = .error
            }
            self.showHUDFeedback()
        }
    }
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
    @Published private(set) var speechResourceStatus = "Inspect availability. Installation starts only when you choose Install."
    @Published private(set) var speechDownloadProgress: SpeechDownloadProgress?
    @Published private(set) var speechPreparation: SpeechEnginePreparation?
    @Published private(set) var speechResourceWorking = false
    private let speechResources: AppleSpeechResourceService
    private var speechResourceTask: Task<Void,Never>?
    private var speechResourceTicket: UUID?
    var canInstallSpeechResources: Bool { !preferences.blockNetworkRequests && !closed && !busy && !inPlaceRunning && !isPreviewingRewrite && !speechResourceWorking && speechConfiguration?.installCandidate != nil }
    var canPrepareModernSpeech: Bool { !closed && !busy && !inPlaceRunning && !isPreviewingRewrite && !speechResourceWorking && speechConfiguration?.readyModernEngine != nil }
    func waitForSpeechResourceSetup() async { await speechResourceTask?.value }
    @discardableResult func stopWaitingForSpeechResources() -> Task<Void,Never>? {
        guard speechResourceWorking else { return nil }
        let completion = speechResourceTask
        speechResourceTicket = nil; speechResourceTask?.cancel(); speechResourceTask = nil
        speechResourceWorking = false; speechDownloadProgress = nil; speechPreparation = nil
        speechResourceStatus = "Stopped waiting. macOS may continue an explicitly requested download. Inspect availability to check."
        return completion
    }
    func installSpeechResources() { beginSpeechResourceSetup(install:true) }
    func prepareModernSpeech() { beginSpeechResourceSetup(install:false) }
    private func beginSpeechResourceSetup(install: Bool) {
        guard install ? canInstallSpeechResources : canPrepareModernSpeech else { return }
        guard let configuration = speechConfiguration,
              let engine = install ? configuration.installCandidate : configuration.readyModernEngine else { return }
        let ticket = UUID(); speechResourceTicket = ticket; speechResourceWorking = true
        speechPreparation = nil; speechDownloadProgress = nil
        speechResourceStatus = install ? "Requesting Apple resources for \(localeIdentifier)…" : "Preparing \(engine.label)…"
        speechResourceTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.speechResourceTicket == ticket { self.speechResourceWorking = false; self.speechResourceTask = nil; self.speechResourceTicket = nil }
            }
            do {
                if install {
                    let updated = try await self.speechResources.install(localeIdentifier:self.localeIdentifier,engine:engine) { [weak self] progress in
                        guard let self, self.speechResourceTicket == ticket, !self.closed else { return }
                        self.speechDownloadProgress = progress
                        self.speechResourceStatus = progress.fraction.map { "Apple resource download: \(Int($0*100))% — waiting for installation verification." } ?? "Apple resource download in progress; total size unavailable."
                    }
                    guard self.speechResourceTicket == ticket, !self.closed else { return }
                    self.speechConfiguration = updated
                }
                try Task.checkCancellation()
                guard self.speechResourceTicket == ticket, !self.closed else { return }
                self.speechDownloadProgress = nil; self.speechResourceStatus = "Installed resources verified. Preparing \(engine.label)…"
                let prepared = try await self.speechResources.prepare(localeIdentifier:self.localeIdentifier,engine:engine)
                let updated = await self.speechResources.inspect(localeIdentifier:self.localeIdentifier)
                try Task.checkCancellation()
                guard self.speechResourceTicket == ticket, !self.closed else { return }
                self.speechConfiguration = updated; self.speechPreparation = prepared
                self.speechResourceStatus = "Preparation verified: \(prepared.engine.label), Apple locale \(prepared.resolvedLocale). Hold the selected key to record. Long physical dictation remains unverified."
            } catch {
                guard self.speechResourceTicket == ticket, !self.closed else { return }
                self.speechDownloadProgress = nil; self.speechPreparation = nil
                let native = error as NSError
                let domain = native.domain.prefix(120).filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }
                let reason: String
                switch error {
                case is CancellationError: reason = "Setup cancelled."
                case SpeechResourceFailure.unsupported: reason = "Selected speech resources are unsupported."
                case SpeechResourceFailure.installationIncomplete: reason = "Apple has not confirmed installation. Inspect availability; macOS may retry the requested download."
                case SpeechResourceFailure.notInstalled: reason = "Modern speech resources are not installed."
                case SpeechResourceFailure.preparationMismatch: reason = "Modern engine preparation could not be verified."
                case SpeechResourceFailure.busy: reason = "A previous resource operation is still settling."
                default: reason = "Apple speech installation or preparation failed (\(domain), code \(native.code)). Inspect availability before retrying."
                }
                self.speechResourceStatus = reason + " Selected language unchanged; nothing recorded or inserted."
                let updated = await self.speechResources.inspect(localeIdentifier:self.localeIdentifier)
                if self.speechResourceTicket == ticket, !self.closed { self.speechConfiguration = updated }
            }
        }
    }
    @Published private(set) var clipboardPending = false
    @Published private(set) var shortcutEnabled = false
    @Published var preferences: DictationPreferences { didSet {
        if oldValue.useFocusedTextWhenUnselected != preferences.useFocusedTextWhenUnselected { cancelTextCapture() }
        if oldValue.inPlaceAIRewrite != preferences.inPlaceAIRewrite { cancelTextCapture(); cancelRewritePreview(); previewPresented = false }
        if oldValue.inPlaceAIRewrite != preferences.inPlaceAIRewrite || (oldValue.offlineAIRewriting && !preferences.offlineAIRewriting) || (oldValue.promptEngineeringEnabled && !preferences.promptEngineeringEnabled) { cancelInPlaceRewrite() }
        preferenceStore.save(preferences); networkPolicy.setBlocked(preferences.blockNetworkRequests); networkSnapshot = networkPolicy.snapshot()
        if !oldValue.blockNetworkRequests && preferences.blockNetworkRequests && speechResourceWorking { stopWaitingForSpeechResources() }
        if (previewKind == .polish && !preferences.offlineAIRewriting) || (previewKind == .promptEngineering && !preferences.promptEngineeringEnabled) { cancelTextCapture(); cancelRewritePreview() }
        if oldValue.agentKey != preferences.agentKey || oldValue.agentHotkeyEnabled != preferences.agentHotkeyEnabled || oldValue.activationKey != preferences.activationKey || oldValue.holdFnEnabled != preferences.holdFnEnabled || oldValue.previewShortcutsEnabled != preferences.previewShortcutsEnabled { configureAgentShortcut() }
        if oldValue.previewShortcutsEnabled != preferences.previewShortcutsEnabled || oldValue.offlineAIRewriting != preferences.offlineAIRewriting || oldValue.promptEngineeringEnabled != preferences.promptEngineeringEnabled || oldValue.activationKey != preferences.activationKey || oldValue.holdFnEnabled != preferences.holdFnEnabled { configurePreviewShortcuts() }
    } }
    @Published private(set) var languagePreparationStatus = ""
    @Published private(set) var flowPageRequest:DictationPage?
    @Published private(set) var flowPageRequestID = UUID()
    @Published private(set) var rewriteReadinessNotice = "Not checked. This does not inspect editor contents or start generation."
    @Published private(set) var checkingRewriteReadiness = false
    var inPlaceReadinessDescription:String {
        if !preferences.previewShortcutsEnabled { return "Option+1/2 are disabled. Enable AI shortcuts below." }
        if !preferences.inPlaceAIRewrite { return "In-place rewrite is disabled. Enable it before dictating a new sentence." }
        if !preferences.offlineAIRewriting && !preferences.promptEngineeringEnabled { return "Smart Polish and Prompt Engineering are disabled." }
        if insertion.hasPendingClipboard { return "Resolve pending clipboard recovery before replacement." }
        if rewriteAnchor == nil { return rewriteEligibility }
        return "A recent insertion is eligible. The original editor, text, caret and expiry are rechecked on every shortcut."
    }
    func inspectRewriteReadiness() async {
        guard !closed, !busy, !inPlaceRunning, !isPreviewingRewrite, !checkingRewriteReadiness else { return }
        guard let inspector = offlineRewriter as? any OfflineRewriteReadinessInspecting else { rewriteReadinessNotice = "This provider does not expose readiness inspection."; return }
        checkingRewriteReadiness = true
        let result = await inspector.inspectReadiness(localeIdentifier:localeIdentifier)
        guard !closed, !Task.isCancelled else { checkingRewriteReadiness = false; return }
        rewriteReadinessNotice = result.status.rawValue + ": " + result.explanation
        checkingRewriteReadiness = false
    }
    @discardableResult private func handleFlowVoiceControl(_ text:String) -> Bool {
        guard !busy, !closed, agentQuestion == nil, agentPlan == nil, agentRecipientChoice == nil,
              let command = FlowVoiceControl.parse(text) else { return false }
        switch command {
        case .language(let mode,let policy):
            var next = preferences; next.languageMode = mode
            if let policy { next.teluguRecognitionLanguage = policy }
            preferences = next
            if mode == .teluguRomanised { Task { [weak self] in await self?.prepareSelectedLanguage() } }
        case .navigate(let destination):
            flowPageRequest = switch destination { case .settings:.general;case .dictation:.dictation;case .history:.history;case .dictionary:.dictionary;case .formatting:.smartFormatting;case .commands:.commands }
            flowPageRequestID = UUID()
        case .saveHistory(let enabled): preferences.keepHistory = enabled
        case .spacing(let enabled): preferences.spacingCleanup = enabled
        }
        agentHeard = text; agentInterpretation = command.confirmation; agentCommandText = ""; lastAgentFailure = nil
        phase = .success; agentStatus(command.confirmation,hud:"Settings updated")
        return true
    }
    @Published var search = ""
    @Published private(set) var modelInventory: [ModelDescriptor] = []
    @Published private(set) var modelStatus = "Coding inference is disabled. Ollama model metadata has not been inspected."
    @Published var agentCommandText = ""
    @Published private(set) var agentPlan: PersonalPlan?
    @Published private(set) var agentRecords: [PersonalTaskRecord] = []
    @Published private(set) var agentNotice = "Hold the Agent key and speak. Routine requests run directly; messages need final confirmation."
    @Published var agentMemoryText = ""
    @Published private(set) var agentMemoryEnabled = false
    @Published private(set) var agentMemories: [PersonalMemoryItem] = []
    var personalAgentQueueURL: URL?
    var personalToolRunner: (any PersonalToolRunning)?
    private let personalPlanner: (any PersonalIntentPlanning)?
    private let personalApps: @MainActor () -> [PersonalApp]
    private let personalMessageResolution: @MainActor (PersonalPlan) async throws -> PersonalPlan
    private var agentDialogue=PersonalAgentDialogue()
    private var agentRecipientChoice:PersonalRecipientChoiceRequired?
    private var agentRecipientAttempts=0
    @Published private(set) var agentQuestion:PersonalQuestion?
    @Published var agentReplyText=""
    @Published private(set) var agentHeard=""
    @Published private(set) var agentInterpretation=""
    private var agentPlanningID: String?
    private var personalEngine: PersonalAgentEngine?
    private var personalMemory: PersonalContextMemory?
    private func getPersonalEngine() throws -> PersonalAgentEngine {
        if let personalEngine { return personalEngine }
        if personalAgentQueueURL == nil { try NativeDictationInstanceGuard.requireOwnership() }
        let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WesleyFlow/PersonalAgent")
        let engine = try PersonalAgentEngine(url:personalAgentQueueURL ?? base.appendingPathComponent("queue.json"),runner:personalToolRunner ?? NativePersonalTools(routineURL:agentRoutineStoreURL ?? personalAgentQueueURL?.deletingLastPathComponent().appendingPathComponent("routines.json")),now:wallTime)
        engine.onChange = { [weak self] records in self?.agentRecords = records }
        personalEngine = engine; agentRecords = engine.records
        return engine
    }
    func reviewAgentCommand(_ text: String? = nil) {
        let control=PersonalAgentDialogue.canonical(text ?? agentCommandText).lowercased()
        if ["pause this routine after the current step","pause this routine after current step"].contains(control),let id=agentExecutingID {pauseAgentTask(id);return}
        guard !busy, !closed else { return }
        if handleFlowVoiceControl(text ?? agentCommandText) { return }
        if personalPlanner != nil { interactWithAgent(text ?? agentCommandText); return }
        agentPlan = nil
        do {
            let plan = try PersonalIntentParser.parse(text ?? agentCommandText)
            let engine = try getPersonalEngine()
            try engine.enqueue(plan); agentPlan = plan; agentRecords = engine.records
            agentNotice = "Review the exact actions below. Nothing has run."
        } catch { agentNotice = "Could not plan this request locally. Use the supported examples and explicit dates; nothing ran." }
    }
    func reviewQueuedAgent(_ id: UUID) {
        guard !busy, let record = agentRecords.first(where: { $0.id == id }), record.state == .awaitingApproval else { return }
        agentDialogue.clear();agentQuestion=nil;agentRecipientChoice=nil;agentReplyText=""
        agentPlan = record.plan
        agentInterpretation=record.plan.steps.map { $0.userSummary(apps:personalApps()) }.joined(separator:" → ")
        agentStatus("Reviewing this saved task. Nothing resumes automatically.",hud:"Review required")
    }
    func loadAgentQueue() {
        do { agentRecords = try getPersonalEngine().records;loadScheduledDrafts() }
        catch { agentNotice = "Queue could not be loaded; existing data is preserved." }
    }
    func waitForAgentPlanning() async { await work?.value; if phase == .inserting { await work?.value } }
    private func agentStatus(_ value:String,hud:String) {
        agentNotice=value;agentShortcutStatus=value;message=value;agentHUD=hud;showHUDFeedback()
    }
    private func askAgent(_ question:PersonalQuestion) {
        agentQuestion=question;agentReplyText="";phase = .idle
        agentStatus(question.prompt,hud:"Reply needed");requestAgentReview()
    }
    func submitAgentReply(_ answer:String?=nil,questionID:UUID?=nil) {
        guard !busy,!closed else { return }
        if let questionID,agentQuestion?.id != questionID { agentStatus("That reply belongs to an old question. Nothing ran.",hud:"Reply expired");return }
        let value=answer ?? agentReplyText;agentReplyText=""
        interactWithAgent(value)
    }
    func cancelAgentConversation() {
        if busy { cancel();if busy { return } }
        if let plan=agentPlan {
            do { try getPersonalEngine().cancel(plan.id);agentRecords=personalEngine?.records ?? [] ;agentPlan=nil }
            catch { agentStatus("Cancellation could not be saved. This draft still needs review; nothing was sent.",hud:"Cancellation failed");return }
        }
        for task in closeObservers.values {task.cancel()};closeObservers.removeAll()
        agentDialogue.clear();agentRecipientChoice=nil;agentQuestion=nil;agentReplyText="";agentContinuationSource=nil;phase = .idle
        agentStatus("Request cancelled. Nothing else will run.",hud:"Agent cancelled")
    }
    func showAgentHelp() {
        guard !busy,!closed else { return }
        agentDialogue.clear();agentQuestion=nil;agentRecipientChoice=nil;if agentPlan == nil { agentReplyText="" }
        agentStatus("Supported commands are listed below. Name installed apps, or a folder and its location. Folder deletion moves to Trash and requires exact review, as does sending messages. Cancel rejects a pending action.",hud:"Agent help")
        requestAgentReview()
    }
    @Published private(set) var agentScheduledDrafts:[PersonalScheduledMessage]=[]
    var agentScheduledStoreURL:URL?
    private func scheduledStore()->PersonalScheduledMessageStore {PersonalScheduledMessageStore(url:agentScheduledStoreURL ?? personalAgentQueueURL?.deletingLastPathComponent().appendingPathComponent("scheduled-message-drafts.json") ?? PersonalScheduledMessageStore.defaultURL)}
    func loadScheduledDrafts() {
        do {agentScheduledDrafts=try scheduledStore().records()}
        catch {agentStatus("Scheduled draft data could not be read; it is preserved.",hud:"Check scheduled drafts")}
    }
    func reviewScheduledDraft(_ id:UUID) {
        guard !busy,!closed,agentPlan==nil else {return}
        do {
            let engine=try getPersonalEngine()
            if let existing=engine.records.first(where:{$0.id==id}) {
                if existing.state == .awaitingApproval {reviewQueuedAgent(id)}
                else {agentStatus("This scheduled draft already has a task record. Inspect that record before any retry; no new send attempt was created.",hud:"Inspect saved task")}
                return
            }
            // Persist the one-use claim before enqueueing: a crash cannot create an automatic retry.
            let record=try scheduledStore().claim(id,now:wallTime())
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:[NativeScheduledMessages.notificationID(id)])
            let plan=try PersonalPlan(id:id,steps:[.init(id:id,tool:.message,text:try record.message.encoded())],createdAt:wallTime(),requiresReview:true)
            loadScheduledDrafts();try proposeContextPlan(plan,request:"Review due scheduled message")
        } catch {loadScheduledDrafts();agentStatus("This draft is not due, was already claimed, or needs storage review. Nothing is sent automatically.",hud:"Check scheduled draft")}
    }
    func deleteScheduledDraft(_ id:UUID) {
        guard !busy,!closed else {return}
        do {try scheduledStore().delete(id);loadScheduledDrafts()}
        catch {agentStatus("Cancel the pending scheduled draft first. Its data is preserved.",hud:"Cancel draft first")}
    }
    @Published private(set) var agentEditingRoutine:String?
    @Published var agentRoutineEditText=""
    @Published private(set) var agentRoutineExistingSteps:[String]=[]
    var agentRoutineStoreURL:URL?
    private var agentRoutineReplacing:UUID?
    private var agentContinuationSource:UUID?
    private func routineStore()->PersonalRoutineStore {PersonalRoutineStore(url:agentRoutineStoreURL ?? personalAgentQueueURL?.deletingLastPathComponent().appendingPathComponent("routines.json") ?? PersonalRoutineStore.defaultURL)}
    private func proposeContextPlan(_ plan:PersonalPlan,request:String,source:UUID?=nil) throws {
        if let pending=agentPlan {try getPersonalEngine().cancel(pending.id);agentPlan=nil}
        agentQuestion=nil;agentDialogue.clear();agentContinuationSource=source
        understandAgentCommand(request,proposed:plan)
    }
    private func contextCommand(_ text:String)->Bool {
        let value=PersonalAgentDialogue.canonical(text),lower=value.lowercased(),now=wallTime()
        func capture(_ pattern:String)->String? {guard let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let match=re.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),let range=Range(match.range(at:1),in:value) else {return nil};return String(value[range])}
        do {
            if let time=capture(#"^schedule a reviewed message for (.+)$"#) {
                guard agentReplyText.isEmpty else {agentStatus("Apply or clear the pending message edit before scheduling it.",hud:"Apply edit first");return true}
                guard let current=agentPlan,current.steps.count==1,let step=current.steps.first,step.tool == .message,try getPersonalEngine().records.contains(where:{$0.id==current.id && $0.state == .awaitingApproval}) else {agentStatus("Prepare and review an exact Messages draft first. Already dispatched or uncertain messages cannot be scheduled again.",hud:"Prepare message draft");return true}
                let message=try PersonalMessage.decode(step.text)
                if let date=PersonalRecordCommand.date(time,now:now) {try proposeContextPlan(PersonalMessageSchedule.plan(message:message,date:date,now:now),request:text)}
                else {try getPersonalEngine().cancel(current.id);agentPlan=nil;agentDialogue.clear();if case .ask(let question)=agentDialogue.askScheduleDate(message,now:now) {askAgent(question)}}
                return true
            }
            if lower=="restore the folder i just trashed" {
                let engine=try getPersonalEngine()
                guard let last=engine.records.last,last.state == .completed,last.plan.steps.count==1,let step=last.plan.steps.first,step.tool == .trashFolder,now.timeIntervalSince(last.completedAt ?? last.plan.createdAt)>=0,now.timeIntervalSince(last.completedAt ?? last.plan.createdAt)<=120,let receipt=last.receipts[0],receipt.verified else {agentStatus("Choose the exact recently completed Trash task first, or restore it manually in Finder. No folder was guessed.",hud:"Restore details needed");return true}
                let original=try PersonalFolderCommand.decode(step.text)
                var command=try PersonalFileAction(action:.restore,folder:true,name:URL(fileURLWithPath:receipt.identifier).lastPathComponent,location:original.location,destinationName:original.name,destinationLocation:original.location)
                command.trashPath=receipt.identifier;command.sourceIdentity=original.identity;command.destinationRootIdentity=original.rootIdentity
                try proposeContextPlan(.init(steps:[.init(tool:.fileAction,text:try command.encoded())],createdAt:now,requiresReview:true),request:text)
                return true
            }
            if let name=capture(#"^save these reviewed steps as (.+)$"#) {
                guard agentReplyText.isEmpty else {agentStatus("Apply or clear the pending edit before saving reviewed steps.",hud:"Apply edit first");return true}
                let source:PersonalPlan
                if let current=agentPlan {source=current}
                else {
                    guard let record=try getPersonalEngine().records.last,record.state == .completed,now.timeIntervalSince(record.completedAt ?? record.plan.createdAt)>=0,now.timeIntervalSince(record.completedAt ?? record.plan.createdAt)<=120 else {agentStatus("First run or review the exact steps you want to save, then name the routine.",hud:"Routine details needed");return true};source=record.plan
                }
                let definition=try PersonalRoutineDefinition(name:name,steps:source.steps,createdAt:source.createdAt)
                let save=PersonalRoutineSave(definition:definition)
                try proposeContextPlan(.init(steps:[.init(tool:.routineSave,text:try save.encoded())],createdAt:now,requiresReview:true),request:text)
                return true
            }
            if let name=capture(#"^edit my (.+) routine$"#) {
                guard agentPlan==nil else {agentStatus("Review or reject the pending action before editing a routine.",hud:"Review required");return true}
                let definition=try routineStore().named(name)
                agentEditingRoutine=definition.name;agentRoutineReplacing=definition.id;agentRoutineExistingSteps=definition.steps.map{$0.userSummary(apps:personalApps())};agentRoutineEditText=""
                agentStatus("Enter one complete replacement command per line, then review and save the revised routine. Nothing runs while editing.",hud:"Edit routine");requestAgentReview();return true
            }
            if let name=capture(#"^run my (.+) routine$"#) {
                guard agentPlan==nil else {agentStatus("Review or reject the pending action first.",hud:"Review required");return true}
                try proposeContextPlan(routineStore().named(name).freshPlan(now:now),request:text);return true
            }
            if ["open my development apps together","arrange my work windows"].contains(lower) {
                let name=lower.hasPrefix("open") ? "Development apps":"Work windows"
                guard agentPlan==nil else {agentStatus("Review or reject the pending action first.",hud:"Review required");return true}
                if let definition=try? routineStore().named(name) {try proposeContextPlan(definition.freshPlan(now:now),request:text)}
                else {agentEditingRoutine=name;agentRoutineReplacing=nil;agentRoutineExistingSteps=[];agentRoutineEditText="";agentStatus("Define your exact "+name.lowercased()+" first: enter one complete app or window command per line. Review and save; then ask again to run it.",hud:"Set up routine");requestAgentReview()}
                return true
            }
            if lower=="continue this interrupted routine" {
                let records=try getPersonalEngine().records.filter{[PersonalTaskState.paused,.cancelled,.needsReview].contains($0.state) && $0.supersededBy==nil}
                guard records.count==1,let record=records.first else {agentStatus("Select an interrupted task’s Continue button. No task was guessed or replayed.",hud:"Choose interrupted task");return true}
                continueAgentTask(record.id);return true
            }
        } catch {agentStatus("This routine or context cannot be used safely. Check the exact saved name, supported steps and target; nothing ran.",hud:"Check routine details");return true}
        return false
    }
    func saveAgentRoutineEdits() {
        guard !busy,!closed,let name=agentEditingRoutine else {return}
        do {
            let lines=agentRoutineEditText.split(whereSeparator:{$0.isNewline}).map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
            guard !lines.isEmpty,lines.count<=8 else {throw PersonalAgentError.invalidCommand}
            let now=wallTime(),apps=personalApps()
            let steps=try lines.flatMap{try PersonalConversation.quick(.init(text:$0,locale:localeIdentifier,apps:apps,now:now)).steps}
            if name=="Development apps" {guard steps.allSatisfy({$0.tool == .openInstalledApp || $0.tool == .openApp}) else {throw PersonalAgentError.invalidCommand}}
            if name=="Work windows" {guard steps.allSatisfy({[PersonalTool.layoutApp,.minimizeApp,.restoreApp,.fullScreenApp,.exitFullScreenApp,.maximizeApp].contains($0.tool)}) else {throw PersonalAgentError.invalidCommand}}
            let definition=try PersonalRoutineDefinition(name:name,steps:steps,createdAt:now),save=PersonalRoutineSave(definition:definition,replacing:agentRoutineReplacing)
            let plan=try PersonalPlan(steps:[.init(tool:.routineSave,text:try save.encoded())],createdAt:now,requiresReview:true)
            cancelAgentRoutineEdits();try proposeContextPlan(plan,request:"Save revised routine "+name)
        } catch {agentStatus("Use one complete supported command per line, at most eight total steps. Dated reminders/events and nested routine saves cannot be stored. Nothing changed.",hud:"Check routine steps")}
    }
    func cancelAgentRoutineEdits() {agentEditingRoutine=nil;agentRoutineEditText="";agentRoutineExistingSteps=[];agentRoutineReplacing=nil}
    func confirmObservedAgentStep(_ id:UUID,expectedStep:PersonalStep) {
        guard !busy,!closed else {return}
        do {let engine=try getPersonalEngine();try engine.confirmObservedOutcome(id,expectedStep:expectedStep);agentRecords=engine.records;agentStatus("Your observation was recorded for this exact step. Nothing was replayed. Remaining steps still require a fresh review.",hud:"Observation saved")}
        catch {agentStatus("This step changed or cannot accept an observation now. Its original record is preserved.",hud:"Check saved task")}
    }
    func pauseAgentTask(_ id:UUID) {
        guard !closed else {return}
        do {try getPersonalEngine().pause(id);agentStatus("Pause requested after the current step verifies. No in-flight effect is undone.",hud:"Pausing routine")}
        catch {agentStatus("This task cannot be paused now.",hud:"Check task")}
    }
    func continueAgentTask(_ id:UUID) {
        guard !busy,!closed,agentPlan==nil else {return}
        do {
            let engine=try getPersonalEngine(),plan=try engine.continuationPlan(id,now:wallTime())
            try proposeContextPlan(plan,request:"Continue reviewed remaining steps",source:id)
        } catch {agentStatus("Cannot continue this task automatically: an uncertain/executing effect, changed target or existing continuation needs review. No effect is replayed.",hud:"Inspect interrupted task")}
    }

    private func interactWithAgent(_ text:String) {
        guard !busy,!closed else { return }
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { agentStatus("Please give a request or reply.",hud:"Reply needed");return }
        guard text.utf8.count<=4096 else { agentStatus("That request is too long. Please shorten it; nothing ran.",hud:"Request too long");return }
        if handleFlowVoiceControl(text) { return }
        agentHeard=text;agentInterpretation="";agentCommandText="";lastAgentFailure=nil
        let now=wallTime(),apps=personalApps()
        if PersonalAgentDialogue.isCancel(text) { cancelAgentConversation();return }
        if ["help","what can you do","show examples"].contains(PersonalAgentDialogue.canonical(text).lowercased()) { showAgentHelp();return }
        do {
            if let question=agentQuestion,question.expiresAt<=now || question.expiresAt.timeIntervalSince(now)>120 {
                agentQuestion=nil;agentRecipientChoice=nil;agentDialogue.clear()
                agentStatus("That question expired. Give a complete new request; nothing ran.",hud:"Reply expired");return
            }
            if let choice=agentRecipientChoice,agentQuestion != nil {
                let option:PersonalRecipientOption?
                if let n=PersonalAgentDialogue.ordinal(text,count:choice.options.count) { option=choice.options[n] }
                else if choice.options.filter({$0.name.compare(text,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame}).count == 1 {
                    option=choice.options.first(where:{$0.name.compare(text,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame})
                }
                else if PersonalMessage.validAddress(text.trimmingCharacters(in:.whitespacesAndNewlines)) {
                    guard let step=choice.plan.steps.first(where:{$0.id==choice.stepID}) else { throw PersonalAgentError.invalidCommand }
                    let name:String
                    switch step.tool {
                    case .message:name=try PersonalMessage.decode(step.text).recipient
                    case .contactAction:name=try PersonalObjectCommand.decode(step.text).name
                    case .mailAction:name=try PersonalMailCommand.decode(step.text).recipient
                    default:throw PersonalAgentError.invalidCommand
                    }
                    option=PersonalRecipientOption(name:name,address:text.trimmingCharacters(in:.whitespacesAndNewlines))
                } else { option=nil }
                guard let option else {
                    agentRecipientAttempts+=1
                    if agentRecipientAttempts>=3 { cancelAgentConversation() }
                    else { agentStatus("Choose a listed recipient number or say an exact phone/email. No message has been sent.",hud:"Choose recipient") }
                    return
                }
                let plan=try choice.choosing(option,now:now)
                agentRecipientChoice=nil;agentQuestion=nil
                understandAgentCommand(text,proposed:plan);return
            }
            if agentQuestion==nil && contextCommand(text) {return}
            if let current=agentPlan {
                switch try PersonalAgentDialogue.reviewReply(text,plan:current,now:now) {
                case .reject: cancelAgentConversation()
                case .amend(let amended):
                    try getPersonalEngine().cancel(current.id)
                    agentPlan=nil;agentQuestion=nil;agentDialogue.clear()
                    understandAgentCommand(text,proposed:amended)
                case .keep:
                    if current.steps.count==1,current.steps.first?.tool == .message {
                        agentStatus("This draft is awaiting review. Say ‘change the message to …’, ‘change the recipient to …’, or ‘cancel’. Sending still needs the exact review button.",hud:"Confirm message")
                    } else { agentStatus("Review or reject this saved plan before starting another request. Voice does not approve it.",hud:"Review required") }
                }
                return
            }
            switch try agentDialogue.intake(text,apps:apps,now:now) {
            case .cancel: cancelAgentConversation()
            case .help: showAgentHelp()
            case .ask(let question): askAgent(question)
            case .plan(let plan): agentQuestion=nil;understandAgentCommand(text,proposed:plan)
            case .request(let request): agentQuestion=nil;understandAgentCommand(request)
            }
        } catch {
            agentQuestion=nil;agentRecipientChoice=nil;agentDialogue.clear();phase = .error
            lastAgentFailure="Heard: “" + text + "” · Installed app index: \(apps.count)"
            if PersonalFileIntents.isFolderRequest(text) {
                agentStatus("Use a single folder name and Documents, Desktop or Downloads. Example: Create folder Projects in Documents. Nothing ran.",hud:"Folder details needed")
            } else if let failure=error as? PersonalPlanningFailure,failure == .appNotFound || failure == .appAmbiguous {
                agentStatus(failure == .appAmbiguous ? "More than one installed app matches. Say the full app name. Nothing opened." : "No installed app matched ‘" + text + "’. Installed app index: \(apps.count). Check Your words against the installed name. Nothing opened.",hud:failure == .appAmbiguous ? "App name ambiguous":"App not found")
            } else { agentStatus("I couldn't use that reply safely. Please give a complete request with the exact app, query, recipient or message. Nothing ran.",hud:"Clarify request") }
        }
    }
    private func understandAgentCommand(_ text:String,proposed direct:PersonalPlan?=nil) {
        guard !busy,!closed,personalPlanner != nil || direct != nil else { return }
        let id=UUID().uuidString;agentPlanningID=id;agentPlan=nil;phase = .finalizing;agentHUD="Understanding…"
        agentNotice="Understanding your request on this Mac…";agentShortcutStatus=agentNotice;message=agentNotice
        let apps=personalApps(),request=PersonalIntentRequest(id:id,text:text,locale:localeIdentifier,apps:apps,now:wallTime())
        work=Task { [weak self] in
            guard let self else { return }
            do {
                let proposed:PersonalPlan
                if let direct { proposed=direct }
                else if let planner=self.personalPlanner { proposed=try await planner.plan(request) }
                else { throw PersonalPlanningFailure.unsupported }
                guard self.agentPlanningID == id,!Task.isCancelled,!self.closed else { return }
                let plan=try await self.personalMessageResolution(proposed)
                guard self.agentPlanningID == id,!Task.isCancelled,!self.closed else { return }
                let engine=try self.getPersonalEngine()
                if let source=self.agentContinuationSource {try engine.enqueueContinuation(plan,from:source);self.agentContinuationSource=nil}
                else {try engine.enqueue(plan)}
                self.agentPlanningID=nil;self.phase = .idle;self.agentPlan=plan;self.agentQuestion=nil;self.agentReplyText=""
                self.agentInterpretation=plan.steps.map { $0.userSummary(apps:apps) }.joined(separator:" → ")
                if PersonalAuthorization.routine(plan) { self.runAgentPlan(plan,routine:true) }
                else {
                    if plan.steps.contains(where:{$0.tool == .trashFolder}) {self.agentStatus("Review the exact folder and location before moving it and its contents to Trash. Nothing moved yet.",hud:"Confirm Trash action")}
                    else if plan.steps.contains(where:{$0.tool == .message}) {self.agentStatus("Review the exact recipient and text. You can change either before sending; nothing sent yet.",hud:"Confirm message")}
                    else {self.agentStatus("Review the exact action, item and changes below. Private data access or changes run only after your approval.",hud:"Review action")}
                    self.requestAgentReview()
                }
            } catch {
                guard self.agentPlanningID == id,!self.closed else { return }
                self.agentPlanningID=nil;self.work=nil
                if let choice=error as? PersonalRecipientChoiceRequired {
                    self.agentRecipientChoice=choice;self.agentRecipientAttempts=0;self.agentInterpretation=choice.plan.steps.map { $0.userSummary(apps:apps) }.joined(separator:" → ")
                    self.askAgent(PersonalQuestion(prompt:choice.prompt,options:choice.options.enumerated().map { .init(label:"\($0.offset+1). " + $0.element.label,answer:String($0.offset+1)) },expiresAt:self.wallTime().addingTimeInterval(120)))
                    return
                }
                self.agentContinuationSource=nil
                if (error as? PersonalAgentError) == .permissionDenied {self.phase = .error;self.agentStatus("macOS did not grant the requested app or folder access. No requested action executed. Review the native permission in System Settings.",hud:"Permission needed");return}
                self.phase = .error
                self.agentHUD = switch error as? PersonalPlanningFailure { case .resourceBlocked,.modelUnavailable: "Local AI unavailable";case .timedOut: "AI timed out";case .busy: "Local AI busy";case .recipientAmbiguous: "Choose recipient";case .contactsDenied: "Contacts access needed";default: "Clarify request" }
                self.agentNotice = switch error as? PersonalPlanningFailure {
                case .modelUnavailable: "On-device language model is unavailable. Common direct actions still work; this phrasing needs clarification. Nothing ran."
                case .resourceBlocked: "Local AI planning is blocked by the unchanged 4 GiB memory reserve. Nothing ran. Try a direct request or free memory."
                case .timedOut: "Local understanding timed out. Nothing ran."
                case .busy: "The local model is still settling. Nothing ran; retry when it finishes."
                case .contactsDenied: "Contacts access is unavailable. Say the exact phone number or email, or allow Contacts in System Settings. Nothing sent."
                case .recipientAmbiguous: "Recipient is ambiguous. Say an exact phone/email and message. Nothing sent."
                default: "Request is unsupported or cannot be understood completely. Try separate explicit requests. Nothing ran."
                }
                self.message=self.agentNotice;self.agentShortcutStatus=self.agentNotice;self.showHUDFeedback()
            }
        }
    }
    func applyAgentMessageEdit() {
        guard !busy,!closed,let current=agentPlan,current.steps.count==1,let step=current.steps.first,step.tool == .message else { return }
        let body=agentReplyText
        guard !body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,body.utf8.count<=1200 else { agentStatus("Enter a shorter nonempty message, or clear the edit. Nothing was sent.",hud:"Check message");return }
        do {
            let prior=try PersonalMessage.decode(step.text)
            let text=try PersonalMessage(recipient:prior.recipient,body:body,address:prior.address).encoded()
            let amended=try PersonalPlan(steps:[.init(tool:.message,text:text)],createdAt:wallTime())
            try getPersonalEngine().cancel(current.id)
            agentPlan=nil;agentReplyText="";agentDialogue.clear();agentHeard=body
            understandAgentCommand(body,proposed:amended)
        } catch { agentStatus("The message change could not be saved. Apply a valid shorter edit or clear it before sending. The original draft is still awaiting review.",hud:"Check message") }
    }
    /// Native review buttons pass the exact displayed value; a stale view cannot grant a new draft.
    func approveAgentPlan(expectedPlan:PersonalPlan?=nil) {
        guard !busy, !closed, let plan = agentPlan, personalEngine != nil else { return }
        if let expectedPlan,expectedPlan != plan { agentStatus("This draft changed. Review its current recipient and text before sending.",hud:"Review changed draft");return }
        if plan.steps.contains(where:{$0.tool == .message}),!agentReplyText.isEmpty { agentStatus("Apply or clear the message edit before sending.",hud:"Apply edit first");return }
        runAgentPlan(plan,routine:false)
    }
    var personalCloseObservation:@MainActor (PersonalReceipt) async ->PersonalReceipt? = {await NativeAppClosing.followup($0)}
    private var closeObservers:[UUID:Task<Void,Never>]=[:]
    private var agentOutcomeID:UUID?
    func waitForCloseObservation(_ id:UUID) async {await closeObservers[id]?.value}
    private func observePendingCloses(_ plan:PersonalPlan,engine:PersonalAgentEngine) {
        guard closeObservers[plan.id]==nil,let record=engine.records.first(where:{$0.id==plan.id}),let entry=record.receipts.first(where:{[PersonalAppCloseObservation.Outcome.pending,.refused].contains($0.value.appClose?.outcome ?? .unavailable)}),plan.steps.indices.contains(entry.key) else {return}
        let step=plan.steps[entry.key],observe=personalCloseObservation
        closeObservers[plan.id]=Task { [weak self] in
            let receipt=await observe(entry.value)
            guard let self else {return};defer{self.closeObservers[plan.id]=nil}
            guard !self.closed,!Task.isCancelled,let receipt else {return}
            do {try engine.reconcileAppClose(plan.id,expectedStep:step,receipt:receipt)} catch {return}
            self.agentRecords=engine.records
            guard self.agentOutcomeID==plan.id,["Quit pending","Quit refused"].contains(self.agentHUD),!self.busy,!self.inPlaceRunning,self.agentPlan==nil,self.agentQuestion==nil else {return}
            let complete=engine.records.first(where:{$0.id==plan.id})?.state == .completed
            self.phase=receipt.verified ? (complete ? .success:.idle):.error
            self.agentHUD=receipt.verified ? (complete ? "App closed":"Close confirmed"):(receipt.appClose?.outcome == .reopened ? "App reopened":"Check app")
            if receipt.verified {self.agentDialogue.completed(plan,apps:self.personalApps(),now:self.wallTime())}
            self.agentNotice=receipt.evidence+(receipt.verified && !complete ? " Remaining steps require fresh review; nothing resumed.":"");self.agentShortcutStatus=self.agentNotice;self.message=self.agentNotice;self.showHUDFeedback()
        }
    }
    private func runAgentPlan(_ plan:PersonalPlan,routine:Bool) {
        guard let engine=personalEngine else { return }
        agentPlan = nil; agentExecutingID = plan.id;agentOutcomeID=plan.id; phase = .inserting; agentHUD = plan.steps.allSatisfy({$0.tool == .closeApp}) ? "Closing app":"Processing command"
        agentNotice = routine ? "Running your requested actions…" : "Running the exact actions you confirmed…"
        work = Task { [weak self] in
            guard let self else { return }
            do { if routine { try await engine.runRequestedRoutine(plan) } else { try await engine.approveAndRun(plan) } }
            catch { self.agentNotice = "Execution stopped; inspect the saved task before retrying." }
            self.agentRecords = engine.records
            let state = engine.records.first(where: { $0.id == plan.id })?.state
            self.agentNotice = "Task: " + (state?.rawValue ?? "unknown") + ". Check receipts; uncertain effects are never replayed automatically."
            if state == .completed { self.agentDialogue.completed(plan,apps:self.personalApps(),now:self.wallTime()) }
            self.phase = state == .completed ? .success : .error; self.work = nil
            self.agentExecutingID = nil
            let dispatched=engine.records.first(where:{$0.id == plan.id})?.receipts.values.contains(where:{ !$0.verified }) == true
            self.agentHUD = state == .completed ? (plan.steps.contains(where:{[PersonalTool.searchGoogle,.searchYouTube].contains($0.tool)}) ? "Search opened" : "Done") : dispatched ? (plan.steps.contains(where:{$0.tool == .message}) ? "Message submitted" : plan.steps.contains(where:{$0.tool == .mailAction}) ? "Email submitted":"App handoff") : "Agent needs review"
            if dispatched && plan.steps.contains(where:{$0.tool == .website}) {self.agentHUD="Website opened"}
            if dispatched { self.agentNotice="Request handed to the app; external outcome is unverified. Inspect it before retrying. No automatic replay." }
            if state == .completed,let index=plan.steps.firstIndex(where:{$0.tool == .findFolder}),let receipt=engine.records.first(where:{$0.id==plan.id})?.receipts[index] {
                self.agentNotice=receipt.evidence;self.agentHUD="Folder results"
            }
            if state == .completed,let index=plan.steps.firstIndex(where:{$0.tool == .systemAudio || $0.tool == .browserControl || $0.tool == .macControl || $0.tool == .layoutApp || $0.tool == .ownedTimers || $0.tool == .recordAction || $0.tool == .notesAction || $0.tool == .mediaAction || $0.tool == .contactAction || $0.tool == .fileAction || $0.tool == .screenCapture || $0.tool == .browserExtra || $0.tool == .mailAction || $0.tool == .routineSave || $0.tool == .menuAction || $0.tool == .messageSchedule}),let receipt=engine.records.first(where:{$0.id==plan.id})?.receipts[index] {
                self.agentNotice=receipt.evidence;self.agentHUD = "Command result"
            }
            if plan.steps.allSatisfy({$0.tool == .closeApp}),state == .completed {self.agentHUD="App closed"}
            if let receipt=engine.records.first(where:{$0.id==plan.id})?.receipts.values.first(where:{!$0.verified && $0.appClose != nil}),let close=receipt.appClose {
                self.agentNotice=receipt.evidence
                if !receipt.verified {
                    self.agentHUD=switch close.outcome {case .pending:"Quit pending";case .refused:"Quit refused";case .reopened:"App reopened";case .unavailable:"Can't check app";case .unconfirmed:"Check app";case .closed:"Check app"}
                    if [.pending,.refused].contains(close.outcome) {self.phase = .idle;self.observePendingCloses(plan,engine:engine)}
                }
            }
            if plan.steps.contains(where:{$0.tool == .messageSchedule}) {self.loadScheduledDrafts()}
            if state == .paused {self.phase = .idle;self.agentHUD="Routine paused";self.agentNotice="Paused after verified steps. Continue requires a fresh review; uncertain effects are never replayed."}
            self.agentShortcutStatus=self.agentNotice
            self.message = self.agentNotice; self.showHUDFeedback()
        }
    }
    func cancelAgentTask(_ id: UUID) {
        do { try personalEngine?.cancel(id); agentRecords = personalEngine?.records ?? [] }
        catch { agentNotice = "Cancellation could not be saved. The draft is still awaiting review."; return }
        if agentPlan?.id == id { agentPlan = nil; agentHUD = "Agent cancelled"; showHUDFeedback() }
    }
    func deleteAgentTask(_ id: UUID) {
        guard !busy else { return }
        do { try personalEngine?.delete(id);closeObservers.removeValue(forKey:id)?.cancel(); agentRecords = personalEngine?.records ?? [] }
        catch { agentNotice = "Task could not be deleted." }
        if agentPlan?.id == id { agentPlan = nil; agentHUD = "Agent cancelled"; showHUDFeedback() }
    }
    private func getPersonalMemory() throws -> PersonalContextMemory {
        if let personalMemory { return personalMemory }
        let url = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WesleyFlow/PersonalAgent/memory.json")
        let memory = try PersonalContextMemory(url:url); personalMemory = memory; return memory
    }
    func setAgentMemory(_ enabled: Bool) {
        do { let memory = try getPersonalMemory(); memory.setEnabled(enabled); agentMemoryEnabled = enabled; agentMemories = try memory.search("") }
        catch { agentNotice = "Memory unavailable." }
    }
    func rememberAgentText() {
        do { let memory = try getPersonalMemory(); try memory.remember(agentMemoryText); agentMemoryText = ""; agentMemories = try memory.search("") }
        catch { agentNotice = "Memory needs opt-in and bounded explicit text." }
    }
    func searchAgentMemory() {
        do { agentMemories = try getPersonalMemory().search(agentMemoryText) }
        catch { agentNotice = "Memory search failed." }
    }
    func correctAgentMemory(_ id: UUID) {
        do { let memory = try getPersonalMemory(); try memory.correct(id,text:agentMemoryText); agentMemories = try memory.search("") }
        catch { agentNotice = "Enter replacement text first." }
    }
    func deleteAgentMemory(_ id: UUID? = nil) {
        do { let memory = try getPersonalMemory(); try memory.delete(id); agentMemories = try memory.search("") }
        catch { agentNotice = "Memory deletion failed." }
    }
    @Published private(set) var commandArmed = false
    @Published private(set) var commandStatus = "Use the separate Agent hold-to-talk key for commands; dictation always inserts text."
    private var commandSession = false
    private let appOpener: @MainActor (AppOpeningCommand) async throws -> Void
    func armCommand() { enableAgentShortcut() }
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
    @Published private(set) var previewNotice = "Explicit preview: supply text or select a completed dictation in Settings. AI shortcuts never open this editor."
    @Published private(set) var previewPresented = false
    @Published private(set) var previewCaptureDiagnostic = "Not requested"
    @Published private(set) var shortcutSource: FocusedTextSource = .manual
    @Published private(set) var isResolvingShortcutText = false
    @Published var shortcutInputText = "" { didSet { if oldValue != shortcutInputText { cancelRewritePreview(); if !isResolvingShortcutText { shortcutSource = .manual } } } }
    private let focusedTextResolver: (any FocusedTextResolving)?
    private(set) var captureTask: Task<Void,Never>?
    private var captureTicket: UUID?
    func cancelTextCapture() { captureTicket = nil; captureTask?.cancel(); captureTask = nil; isResolvingShortcutText = false }
    func waitForTextCapture() async { await captureTask?.value }
    @discardableResult func generateShortcutPreview() -> Task<Void,Never>? {
        guard !closed, !busy, !inPlaceRunning, !isResolvingShortcutText, !isPreviewingRewrite,
              (previewKind == .polish ? preferences.offlineAIRewriting : preferences.promptEngineeringEnabled),
              !shortcutInputText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              shortcutInputText.utf8.count <= 2048 else { return nil }
        return beginPreview(previewKind,text:shortcutInputText,sourceID:nil,latestOnly:false)
    }
    // Development-only bounded metadata. Never retain input, clipboard, prompts or app identities.
    enum PreviewDiagnostic: Equatable { case disabled, registrationRequested, registered, registrationFailed, activated, requested, presented, hidden }
    private(set) var previewDiagnostics: [PreviewDiagnostic] = []
    func recordPreviewDiagnostic(_ event: PreviewDiagnostic) {
        #if DEBUG
        if previewDiagnostics.count == 32 { previewDiagnostics.removeFirst() }
        previewDiagnostics.append(event)
        #endif
    }
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
        !busy && !closed && !inPlaceRunning && !isResolvingShortcutText && !isPreviewingRewrite && offlineRewriter != nil && permittedPreviewText != nil && (kind == .polish ? preferences.offlineAIRewriting : preferences.promptEngineeringEnabled)
    }
    var canPreviewRewrite: Bool { !busy && !closed && !inPlaceRunning && !isResolvingShortcutText && !isPreviewingRewrite && preferences.offlineAIRewriting && offlineRewriter != nil && latest?.id == reliableFinalID && latest != nil }
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
        cancelTextCapture(); cancelRewritePreview(); shortcutInputText = ""; previewOriginalText = ""; shortcutSource = .manual; previewPresented = false; previewOriginProcessIdentifier = nil
    }
    /// Global AI gestures have no path to the explicit preview presenter.
    func invokeAIShortcut(_ kind: OfflinePreviewKind, originProcessIdentifier: Int32? = nil) {
        lastAIShortcutFailure = nil
        traceRoute(kind,.received)
        // Fence a pending explicit capture/result and hide an already-open manual
        // editor. A late capture must not open it after this gesture.
        cancelTextCapture(); cancelRewritePreview(); previewPresented = false
        guard !closed else { traceRoute(kind,.ignoredBusy); return }
        guard !busy, !inPlaceRunning else {
            let explanation = busy
                ? "Shortcut ignored while dictation was still active. Wait for the inserted text, then press Option+1 or Option+2 again."
                : "Local AI is already rewriting this dictation. Wait for it to finish; no second request was started."
            lastAIShortcutFailure = explanation; previewShortcutStatus = explanation
            traceRoute(kind,.ignoredBusy); return
        }
        guard preferenceStore.load().inPlaceAIRewrite == preferences.inPlaceAIRewrite else {
            cancelInPlaceRewrite()
            rejectInPlace(kind,.settingsDisagree,"In-place settings changed in another app instance. Reopen this build safely. Nothing replaced."); return
        }
        guard preferences.inPlaceAIRewrite else {
            rejectInPlace(kind,.featureDisabled,"Enable in-place AI rewrite in Settings."); return
        }
        traceRoute(kind,.inPlaceSelected)
        invokeInPlaceRewrite(kind,originProcessIdentifier:originProcessIdentifier)
    }
    private let previewPresentationRequest: @MainActor (OfflinePreviewKind) -> Void
    private func requestExplicitPreviewPresentation() {
        previewPresentationRequest(previewKind)
        previewPresented = true
    }
    /// Explicit Settings command only; never a keyboard-shortcut fallback.
    func openExplicitPreview(_ kind: OfflinePreviewKind, originProcessIdentifier: Int32? = nil) {
        guard !closed, !busy, !inPlaceRunning else { return }
        recordPreviewDiagnostic(.requested)
        guard !isResolvingShortcutText else { return }
        guard !isPreviewingRewrite else { requestExplicitPreviewPresentation(); return }
        previewOriginProcessIdentifier = originProcessIdentifier
        previewKind = kind; rewritePreview = nil; promptPreview = nil
        previewOriginalText = permittedPreviewText ?? ""
        shortcutInputText = previewOriginalText; shortcutSource = .manual
        guard let focusedTextResolver, let process = originProcessIdentifier,
              preferences.previewShortcutsEnabled,
              (kind == .polish ? preferences.offlineAIRewriting : preferences.promptEngineeringEnabled) else {
            requestExplicitPreviewPresentation()
            previewNotice = "Enter text here, then choose Generate preview. Nothing is inserted automatically."
            previewCaptureDiagnostic = "manual · notRequested"
            return
        }
        let ticket = UUID(); captureTicket = ticket; isResolvingShortcutText = true
        previewNotice = "Reading only the original focused editor. Nothing will be inserted."
        let allowUnselected = preferences.useFocusedTextWhenUnselected
        captureTask = Task { [weak self] in
            let result = await focusedTextResolver.resolve(processID:process,allowUnselected:allowUnselected)
            guard let self, !Task.isCancelled, self.captureTicket == ticket, !self.closed, !self.busy,
                  self.preferences.previewShortcutsEnabled,
                  (kind == .polish ? self.preferences.offlineAIRewriting : self.preferences.promptEngineeringEnabled) else { return }
            self.captureTicket = nil; self.captureTask = nil; self.isResolvingShortcutText = false
            if !result.text.isEmpty, result.text.utf8.count <= 2048,
               result.source == .selection || (allowUnselected && result.source != .manual) {
                self.shortcutInputText = result.text; self.shortcutSource = result.source
            }
            self.previewOriginalText = self.shortcutInputText
            self.previewNotice = result.status.explanation
            self.previewCaptureDiagnostic = "\(result.status.rawValue) · \(result.stage.rawValue)"
            self.requestExplicitPreviewPresentation()
        }
    }
    func configurePreviewShortcuts() {
        guard !closed, preferences.previewShortcutsEnabled, let previewRegistrar else {
            recordPreviewDiagnostic(.disabled)
            cancelInPlaceRewrite(); cancelTextCapture()
            self.previewRegistrar?.disable(); registeredPreviewKinds = []; if previewPresented { dismissShortcutPreview() }; previewShortcutStatus = "Preview shortcuts are disabled."; return
        }
        guard !(preferences.activationKey == .rightOption && preferences.holdFnEnabled) else {
            previewRegistrar.disable(); registeredPreviewKinds = []; previewShortcutStatus = "Conflict with right-Option hold-to-talk. Choose Fn or right Command first."; return
        }
        var kinds = Set<OfflinePreviewKind>()
        if preferences.offlineAIRewriting { kinds.insert(.polish) }; if preferences.promptEngineeringEnabled { kinds.insert(.promptEngineering) }
        guard !kinds.isEmpty else { previewRegistrar.disable(); registeredPreviewKinds = []; previewShortcutStatus = "Enable a preview feature before registering its shortcut."; return }
        if kinds == registeredPreviewKinds { return }
        recordPreviewDiagnostic(.registrationRequested)
        do {
            try previewRegistrar.enable(kinds:kinds) { [weak self] signal in
                guard let self, !self.closed, self.preferences.previewShortcutsEnabled else { return }
                switch signal {
                case .invoke(let kind): self.recordPreviewDiagnostic(.activated); self.invokeAIShortcut(kind)
                case .invokeFrom(let kind, let process): self.recordPreviewDiagnostic(.activated); self.invokeAIShortcut(kind,originProcessIdentifier:process)
                case .suspended: self.cancelInPlaceRewrite(); self.cancelTextCapture(); self.cancelRewritePreview(); self.previewShortcutStatus = "Mac sleeping: pending preview cancelled; shortcuts suspended."
                case .resumed: self.previewShortcutStatus = "Shortcuts re-registered after wake. Physical delivery remains unverified."
                case .secureInput: self.cancelInPlaceRewrite(); self.cancelTextCapture(); self.cancelRewritePreview(); self.previewShortcutStatus = "Secure Input active: preview gesture ignored."
                case .unavailable: self.cancelInPlaceRewrite(); self.cancelTextCapture(); self.cancelRewritePreview(); self.registeredPreviewKinds = []; self.previewShortcutStatus = "Shortcut delivery or keyboard layout became unavailable. Disable and re-enable to retry."
                }
            }
            recordPreviewDiagnostic(.registered)
            registeredPreviewKinds = kinds
            previewShortcutStatus = "Registered: " + kinds.sorted(by:{$0.rawValue < $1.rawValue}).map { $0 == .polish ? "Option+1" : "Option+2" }.joined(separator:", ") + ". Physical cross-app delivery remains unverified."
        } catch {
            recordPreviewDiagnostic(.registrationFailed)
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
    private var activeLanguageMode: DictationLanguageMode = .english
    private var activeTeluguOverrides: [DictationPhraseReplacement] = []
    private var activeTeluguWhitespace = true
    private let input: any DictationInput
    private let targets: any InsertionTargetCapturing
    private let insertion: any DictationTextInserting
    private let shortcut: any DictationShortcutMonitoring
    private let agentShortcut: any DictationShortcutMonitoring
    private let agentCaptureValidation: @MainActor () throws -> Void
    private let agentConflict: @MainActor (DictationActivationKey) throws -> Bool
    @Published private(set) var agentShortcutEnabled = false
    @Published private(set) var agentShortcutDiagnostics = "Agent monitor has not started."
    @Published private(set) var agentShortcutStatus = "Agent shortcut is awaiting authorization."
    @Published private(set) var agentHUD: String?
    @Published private(set) var lastAgentFailure:String?
    private var agentMonitoringRequested = false
    private var agentExecutingID: UUID?
    @Published private(set) var agentReviewRequest = UUID()
    private var agentStartupBegan:Double?
    @Published private(set) var agentStartupMilliseconds:Int?
    private var agentHeld = false
    private var agentShortcutGeneration = 0
    private let minimumHoldMilliseconds: Int64
    private let hudClock: any TaskClock
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
    var pillVisible: Bool { (preferences.showPill || commandSession || agentExecutingID != nil || agentPlan != nil || agentQuestion != nil || (agentHUD != nil && hudFeedbackVisible)) && ((preferences.idlePillEnabled && !closed) || (startedFromShortcut && busy) || ((agentPlan != nil || agentQuestion != nil) && agentHUD != nil) || hudFeedbackVisible || inPlaceHUD != .idle) }
    var keepsAppRunningAfterWindowClose: Bool { preferences.holdFnEnabled || preferences.agentHotkeyEnabled || preferences.idlePillEnabled || preferences.previewShortcutsEnabled || busy }
    var isPreparingTelugu: Bool { phase == .preparing && activeLanguageMode == .teluguRomanised }
    var busy: Bool { [.preparing,.recording,.finalizing,.inserting].contains(phase) }
    var filteredHistory: [DictationHistoryEntry] { DictationHistoryQuery.filter(entries,search:search) }
    var groupedHistory: [(date:Date,entries:[DictationHistoryEntry])] { DictationHistoryQuery.groups(filteredHistory,calendar:.current) }
    init(input: any DictationInput, targets: any InsertionTargetCapturing, insertion: any DictationTextInserting,
         shortcut: any DictationShortcutMonitoring,
         agentShortcut: any DictationShortcutMonitoring = NativeDictationShortcut(),
         agentCaptureValidation: @escaping @MainActor () throws -> Void = NativeDictationShortcut.validateAgentCapture,
         agentConflict: @escaping @MainActor (DictationActivationKey) throws -> Bool = NativeDictationShortcut.conflictsWithSystem,
         clock: any TaskClock = SystemTaskClock(),
         hudClock: any TaskClock = SystemTaskClock(),
         preferenceStore: DictationPreferenceStore = DictationPreferenceStore(),
         networkPolicy: ApplicationNetworkPolicy = .shared,
         history: (any DictationHistoryStore)? = nil,
         historyFactory: (@Sendable () async throws -> any DictationHistoryStore)? = nil,
         personalPlanner: (any PersonalIntentPlanning)? = nil,
         personalApps: @escaping @MainActor () -> [PersonalApp] = NativePersonalApps.catalog,
         personalMessageResolution: @escaping @MainActor (PersonalPlan) async throws -> PersonalPlan = NativePersonalMessages.resolve,
         appOpener: @escaping @MainActor (AppOpeningCommand) async throws -> Void = NativeAppOpening.open,
         modelInspector: (@Sendable () async throws -> [ModelDescriptor])? = nil,
         offlineRewriter: (any OfflineTranscriptRewriting)? = nil,
         previewRegistrar: (any PreviewShortcutRegistering)? = nil,
         previewPresentationRequest: @escaping @MainActor (OfflinePreviewKind) -> Void = { _ in },
         focusedTextResolver: (any FocusedTextResolving)? = nil,
         historyCopy: @escaping @MainActor (String) -> Bool = HistoryClipboard.write,
         localeIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier,
         speechResources: AppleSpeechResourceService = AppleSpeechResourceService(),
         minimumHoldMilliseconds: Int64 = 0,
         wallTime: @escaping @Sendable () -> Date = { Date() }) {
        self.networkPolicy = networkPolicy; self.networkSnapshot = networkPolicy.snapshot()
        self.focusedTextResolver = focusedTextResolver
        self.previewPresentationRequest = previewPresentationRequest
        self.offlineRewriter = offlineRewriter; self.previewRegistrar = previewRegistrar
        self.historyCopy = historyCopy; self.speechResources = speechResources
        self.minimumHoldMilliseconds = min(1000,max(0,minimumHoldMilliseconds))
        self.personalPlanner=personalPlanner;self.personalApps=personalApps;self.personalMessageResolution=personalMessageResolution
        self.appOpener = appOpener
        self.agentShortcut = agentShortcut; self.agentCaptureValidation = agentCaptureValidation; self.agentConflict = agentConflict
        self.input = input; self.targets = targets; self.insertion = insertion; self.shortcut = shortcut
        self.hudClock = hudClock; self.clock = clock; self.preferenceStore = preferenceStore; self.history = history; self.historyFactory = historyFactory
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
        if agentDialogue.expire(now:wallTime()),agentQuestion != nil,agentRecipientChoice == nil { agentQuestion=nil;agentReplyText="";agentStatus("Question expired. Start a complete new request.",hud:"Reply expired") }
        if let question=agentQuestion,(question.expiresAt<=wallTime() || question.expiresAt.timeIntervalSince(wallTime())>120) { agentDialogue.markExpired();agentQuestion=nil;agentRecipientChoice=nil;agentReplyText="";agentStatus("Question expired. Start a complete new request.",hud:"Reply expired") }
        networkSnapshot = networkPolicy.snapshot()
        agentShortcutDiagnostics = agentShortcut.diagnosticSummary
        reconcileClipboard()
        accessibilityAllowed = DictationAccess.accessibilityGranted
        let value = AppleSpeechConfiguration.permissionSummary(); microphoneStatus = value.microphone; speechStatus = value.speech
        if shortcutEnabled && !shortcut.authorizationReady { stopShortcutMonitoring(); cancel() }
        if agentShortcutEnabled && !agentShortcut.authorizationReady { stopAgentShortcut(); if commandSession { cancel() } }
    }
    func requestAccessibility() { _ = DictationAccess.requestAccessibility(); resumeShortcutIfAuthorized() }
    func resumeShortcutIfAuthorized() {
        refreshPermissions(); configurePreviewShortcuts()
        if !closed, preferenceStore.error == nil, preferences.agentHotkeyEnabled, agentShortcut.authorizationReady { agentMonitoringRequested = true; if !agentShortcutEnabled { configureAgentShortcut() } }
        guard !closed, preferenceStore.error == nil, preferences.holdFnEnabled, shortcut.authorizationReady else { return }
        startShortcutMonitoring()
    }
    func inspectModels() async {
        guard let modelInspector else { modelStatus = "Model metadata inspection is unavailable. Inference remains disabled."; return }
        do { modelInventory = try await modelInspector(); modelStatus = "Ollama metadata observed; its coding and prompt inference remain disabled and memory-gated. Apple dictation previews are separately opt-in." }
        catch { modelStatus = "Local model metadata is unavailable. No service or model was started." }
    }
    /// Runs from the language selector's cancellable view task, never from a hotkey callback.
    func prepareSelectedLanguage() async {
        guard !closed, !busy else { return }
        guard preferences.languageMode == .teluguRomanised, let routing = input as? LanguageDictationInput else { languagePreparationStatus = ""; return }
        let policy = preferences.teluguRecognitionLanguage
        languagePreparationStatus = "Preparing offline Telugu…"
        do {
            try await routing.prepareTelugu(language:policy)
            guard !closed, !Task.isCancelled, preferences.languageMode == .teluguRomanised, preferences.teluguRecognitionLanguage == policy else { return }
            languagePreparationStatus = "Offline Telugu ready."
        } catch {
            guard !closed, !Task.isCancelled, preferences.languageMode == .teluguRomanised, preferences.teluguRecognitionLanguage == policy else { return }
            languagePreparationStatus = "Offline model preparation failed. Start dictation to see the setup error."
        }
    }
    func inspectSpeech() async {
        guard !closed, !busy, !speechResourceWorking else { return }
        let ticket = UUID(); speechResourceTicket = ticket; speechResourceWorking = true
        let configuration = await speechResources.inspect(localeIdentifier:localeIdentifier)
        guard speechResourceTicket == ticket, !closed else { return }
        speechConfiguration = configuration; speechPreparation = nil; speechResourceWorking = false; speechResourceTicket = nil
        speechResourceStatus = configuration.recommendedEngineLabel + ". Requested locale: " + localeIdentifier + ". No download started by inspection."
        refreshPermissions()
    }
    func requestAgentReview() { agentReviewRequest = UUID() }
    func pillClicked(clickCount: Int = 1) {
        guard clickCount == 1, !closed else { return }
        if inPlaceRunning { cancelInPlaceRewrite(); return }
        if phase == .recording { stop(); return }
        if agentPlan != nil || agentQuestion != nil || (!commandSession && agentHUD != nil) { requestAgentReview(); return }
        guard !busy else { return }
        begin(manual:false)
    }
    func startManual() { guard !busy, !closed else { return }; begin(manual:true) }
    private func begin(manual: Bool, fromShortcut: Bool = false, activation:DictationActivationContext?=nil, agent:Bool = false) {
        guard !speechResourceWorking else { message = "Speech resource setup is in progress. Finish or stop waiting before recording."; return }
        commandSession = agent; agentHUD = agent ? "Starting mic…" : nil
        if agent { agentStartupBegan=ProcessInfo.processInfo.systemUptime;agentStartupMilliseconds=nil }
        captureActivation=activation;captureObservedIdentity=nil
        cancelInPlaceRewrite()
        audioCaptureResult = .pending; transcriptionResult = .pending; targetCaptureResult = .notStarted
        targetValidationResult = .notStarted; pasteboardLeaseResult = .notStarted; insertionDispatchResult = .notStarted
        destinationBundleIdentifier = nil; speechFailureCode = "NONE"; terminalSpeechFailure = nil; speechFailureDiagnostics = nil; unmergedSpeechRecoveryEntry = nil
        lastAIShortcutFailure = nil
        diagnosticOperation = UUID().uuidString; captureElapsedMilliseconds = nil; insertionElapsedMilliseconds = nil
        activeCaptureDiagnostics = []; insertionTraceSummary = "No insertion readback for this operation"
        insertionLookupSummary = "No shortcut receipt lookup"; verificationDetail = "No rewrite verification for this operation"
        latestInsertionOutcome = "none"; verifiedReceiptCreated = false
        deliveryStatus = .notRequested; readbackStatus = .notRequested; replacementCapabilityStatus = .unknown
        generationStatus = .notRequested; replacementResultStatus = .notRequested; crossAppFailure = .notRequested
        latestReplacementCapability = .unknown; latestTargetProcessIdentifier = nil
        verificationModelState = "notRequested"
        invalidateProvenance(.invalidated,"A new dictation session invalidated the previous insertion. Dictate again with in-place mode enabled."); feedbackTask?.cancel(); hudFeedbackVisible = false; stopAudioVisualization()
        cancelTextCapture(); cancelRewritePreview(); reliableFinalID = nil
        reconcileClipboard()
        if !manual && !agent && insertion.hasPendingClipboard {
            audioCaptureResult = .notStarted; transcriptionResult = .notStarted; pasteboardLeaseResult = .recoveryPending
            clipboardPending = true; phase = .error; startedFromShortcut = false
            message = (insertion.failureExplanation.map { $0 + " " } ?? "") + "Recording was not started. Review clipboard restoration before another dictation."
            showHUDFeedback()
            return
        }
        commandArmed = false
        if agent {
            do {
                try agentCaptureValidation()
                if let activation { try NativeDictationShortcut.validateAgentActivation(activation) }
            } catch {
                commandSession = false; phase = .error; agentHUD = "Agent unavailable"
                agentNotice = "Agent capture blocked: secure input, focus or Accessibility could not be verified. Nothing recorded."
                let reason = switch error as? TextTargetError { case .secure: "Secure input is active."; case .denied: "Accessibility permission is unavailable."; case .changed: "Foreground app changed during key delivery."; default: "Foreground app security could not be checked. The app may be unresponsive or deny Accessibility." }
                agentNotice = "Agent key received. " + reason + " Nothing recorded."
                agentShortcutStatus = agentNotice; message = agentNotice; showHUDFeedback(); return
            }
        }
        startedFromShortcut = fromShortcut || preferences.idlePillEnabled; captureExplanation = nil
        let id = UUID().uuidString
        destination = nil; fallback = .init(.unsupportedTarget,.manualOnly)
        if !manual && !commandSession {
            do { destination = try captureDestination(session:id) }
            catch TextTargetError.secure { audioCaptureResult = .notStarted; transcriptionResult = .notStarted; deliveryStatus = .notDelivered; crossAppFailure = .notDelivered; phase = .error; message = "Password and secure fields are excluded. Nothing was recorded."; return }
            catch TextTargetError.denied { fallback = .init(.denied,.permission) }
            catch TextTargetError.changed { fallback = .init(.targetChanged,.changed) }
            catch { fallback = .init(.unsupportedTarget,.unsupported) }
        }
        if destination == nil && !manual { captureExplanation = targets.failureExplanation }
        activeLanguageMode = commandSession ? .english : preferences.languageMode
        activeTeluguOverrides = preferences.formatting.replacements
        activeTeluguWhitespace = preferences.spacingCleanup
        if let routing = input as? LanguageDictationInput { routing.mode = activeLanguageMode; routing.recognitionLanguage = preferences.teluguRecognitionLanguage }
        session = id; timestamp = wallTime(); recordingBegan = nil; historyConsentAtStart = preferences.keepHistory
        raw = ""; cleaned = ""; engine = nil; phase = .preparing
        message = "Preparing on-device speech. Allow microphone and speech access if asked."
        startup = Task { [weak self] in
            guard let self, self.session == id, !Task.isCancelled else { return }
            do {
                if fromShortcut && !self.commandSession && self.minimumHoldMilliseconds > 0 {
                    let now = await self.clock.now()
                    let deadline = now.addingReportingOverflow(self.minimumHoldMilliseconds)
                    guard !deadline.overflow else { throw CancellationError() }
                    try await self.clock.sleep(until:deadline.partialValue)
                    guard self.session == id, !Task.isCancelled else { return }
                }
                let info:DictationInfo
                if self.commandSession,let agentInput=self.input as? any AgentDictationInput {
                    (agentInput as? any AgentApplicationNameHinting)?.setAgentApplicationNames(self.personalApps().flatMap { [$0.name]+$0.aliases })
                    info=try await agentInput.startAgent(localeIdentifier:self.localeIdentifier) { [weak self] event in self?.receive(event,id:id) }
                } else { info=try await self.input.start(localeIdentifier:self.localeIdentifier) { [weak self] event in self?.receive(event,id:id) } }
                guard self.session == id, self.phase == .preparing, !Task.isCancelled else { return }
                self.audioCaptureResult = .recording
                self.recordingBegan = await self.clock.now()
                guard self.session == id, self.phase == .preparing, !Task.isCancelled else { return }
                self.engine = info; self.phase = .recording
                if self.commandSession {
                    if let began=self.agentStartupBegan { self.agentStartupMilliseconds=Int(max(0,ProcessInfo.processInfo.systemUptime-began)*1000) }
                    self.agentHUD = "Agent listening";self.agentShortcutStatus = "Agent listening. Microphone ready in \(self.agentStartupMilliseconds ?? 0) ms. Release the Agent key to process."
                }
                self.message = self.commandSession ? "Agent listening. Release to review the personal command." : (self.destination == nil ? "Listening. Release the key to finish; this field is unavailable, so text will remain for copy." : "Listening into the captured field. Release the key to insert.")
                self.startAudioVisualization(id:id)
            } catch {
                guard self.session == id, self.phase == .preparing else { return }
                self.recordSpeechRun("startupFailure",failure:error as? DictationFailure ?? .recognitionFailed)
                if self.commandSession { self.agentHUD = "Agent speech failed"; self.commandSession = false; self.showHUDFeedback() }
                self.input.cancel(); self.session = nil; self.destination = nil; self.phase = .error
                self.audioCaptureResult = Task.isCancelled ? .cancelled : .failed
                self.transcriptionResult = Task.isCancelled ? .cancelled : .failed
                self.speechFailureCode = String(describing:error as? DictationFailure ?? .recognitionFailed)
                self.message = self.activeLanguageMode == .teluguRomanised && (error as? DictationFailure) == .assetsMissing
                    ? "Offline Small model files are missing or failed verification. Install the Telugu specialist and multilingual model using the Telugu setup guide. No microphone audio was captured."
                    : (self.speechFailureDiagnostics?.failureDescription ?? DictationModel.description(error as? DictationFailure ?? .recognitionFailed))
                if self.agentHUD != nil { self.agentShortcutStatus = "Agent speech failed: " + self.message }
            }
            if self.session == id { self.startup = nil }
            self.refreshPermissions()
        }
    }
    private func receive(_ event: DictationEvent,id: String) {
        guard session == id, [.preparing,.recording,.finalizing].contains(phase) else { return }
        switch event {
        case .transcript(let text):
            if commandSession { do { try agentCaptureValidation() } catch { cancel(); return } }
            guard text.utf8.count <= DictationText.maximumBytes else { speechFailureCode = "overflow"; recordSpeechRun("textOverflow",failure:.overflow,stage:.transcriptMerge); input.cancel(); finish(id:id,forced:.init(.denied,.speechFailed)); return }
            if !commandSession && activeLanguageMode == .teluguRomanised, let failure = TeluguRecognitionQuality.failure(in:text) {
                receive(.failed(failure),id:id); return
            }
            raw = text
        case .finished:
            guard phase == .finalizing else {
                speechFailureCode = "providerEnded"; recordSpeechRun("unexpectedCompletion",failure:.providerEnded); input.cancel()
                finish(id:id,forced:.init(.denied,.speechFailed)); return
            }
            recordSpeechRun("providerCompleted")
            finish(id:id)
        case .failed(let error): transcriptionResult = .failed; speechFailureCode = String(describing:error); recordSpeechRun("providerFailed",failure:error); input.cancel(); message = speechFailureDiagnostics?.failureDescription ?? DictationModel.description(error); finish(id:id,forced:.init(.denied,.speechFailed))
        }
    }
    func stop() {
        guard let id = session, phase == .recording else { return }
        stopAudioVisualization()
        if commandSession { agentHUD = "Processing command"; agentShortcutStatus = "Agent released. Processing command…" }
        phase = .finalizing; message = "Transcribing…"; timer?.cancel(); input.stop()
        if phase == .finalizing { armTimer(activeLanguageMode == .teluguRomanised ? 60_000 : 8000,id:id,finishing:true) }
    }
    func cancel() {
        stopAudioVisualization(); cancelInPlaceRewrite()
        cancelRewritePreview()
        if let id=agentPlanningID {
            agentPlanningID=nil;work?.cancel();work=nil
            if let personalPlanner { Task { await personalPlanner.cancel(id:id) } }
            phase = .idle;agentHUD="Agent cancelled";agentNotice="Request cancelled. Nothing ran.";message=agentNotice;agentShortcutStatus=agentNotice;showHUDFeedback();return
        }
        guard let id = session else { if let id = agentExecutingID { cancelAgentTask(id); message = "Cancelling remaining Agent steps; inspect receipts." }; return }
        input.cancel(); if phase != .inserting { recordSpeechRun("userCancelled") }; startup?.cancel(); timer?.cancel(); shortcutHeld = false
        if phase == .inserting { work?.cancel(); message = "Cancelling; preserving the actual insertion outcome."; return }
        finish(id:id,forced:.init(.cancelled,.cancelled))
    }
    private func armTimer(_ delay: Int64,id: String,finishing: Bool) {
        timer?.cancel()
        timer = Task { [weak self,clock] in
            let now = await clock.now()
            guard now >= 0, now <= Int64.max-delay else {
                guard let self, self.session == id else { return }
                self.input.cancel(); self.recordSpeechRun("finalizationWatchdog",failure:.timedOut,stage:.finalizationWatchdog); self.finish(id:id,forced:.init(.timedOut,.deadline)); return
            }
            do { try await clock.sleep(until:now+delay) } catch { return }
            guard let self, self.session == id, !Task.isCancelled else { return }
            if finishing { self.input.cancel(); self.recordSpeechRun("finalizationWatchdog",failure:.timedOut,stage:.finalizationWatchdog); self.finish(id:id,forced:.init(.timedOut,.deadline)) } else { self.stop() }
        }
    }
    private func finish(id: String,forced: TextInsertionReceipt? = nil) {
        guard session == id, phase != .inserting else { return }
        stopAudioVisualization()
        timer?.cancel(); timer = nil; startup = nil
        if !commandSession && activeLanguageMode == .teluguRomanised {
            cleaned = TeluguDictationText.render(raw,overrides:activeTeluguOverrides,whitespace:activeTeluguWhitespace)
        } else {
            cleaned = commandSession ? DictationText.cleaned(raw) : NativeDictationFormatting.format(raw,options:preferences.formatting,whitespace:preferences.spacingCleanup,locale:localeIdentifier)
        }
        if cleaned.utf8.count > DictationText.maximumBytes {
            input.cancel(); session = nil; destination = nil; phase = .error
            cleaned = ""; message = "Romanised text exceeds the 64 KiB limit. Raw text is retained; nothing inserted."; return
        }
        audioCaptureResult = forced?.outcome == .cancelled ? .cancelled : (audioCaptureResult == .recording && forced?.reason != .speechFailed ? .success : .failed)
        transcriptionResult = forced?.outcome == .cancelled ? .cancelled : (forced == nil && !cleaned.isEmpty ? .success : .failed)
        if forced?.reason == .deadline { speechFailureCode = "timedOut" }
        if commandSession {
            commandSession = false; session = nil; destination = nil; input.cancel()
            do { try agentCaptureValidation() } catch { phase = .error; agentHUD = "Agent blocked"; message = "Secure input or focus unavailable. Nothing ran."; showHUDFeedback(); return }
            cleaned = DictationText.cleaned(raw)
            guard forced == nil, !cleaned.isEmpty else {
                phase = forced?.outcome == .cancelled ? .idle : .error
                agentHUD = forced?.outcome == .cancelled ? "Agent cancelled" : "Agent speech failed"
                agentNotice = "Command incomplete or cancelled. Nothing ran. Partial speech is never executed."
                agentShortcutStatus = agentNotice; message = agentNotice; showHUDFeedback(); return
            }
            phase = .idle; agentCommandText = cleaned
            if handleFlowVoiceControl(cleaned) { return }
            if personalPlanner != nil { interactWithAgent(cleaned); return }
            reviewAgentCommand(cleaned)
            phase = agentPlan == nil ? .error : .success
            agentHUD = agentPlan == nil ? "Command unsupported" : "Approval required"
            commandStatus = agentNotice; agentShortcutStatus = agentNotice; message = agentNotice; showHUDFeedback()
            if agentPlan != nil { requestAgentReview() }
            return
        }
        guard !cleaned.isEmpty else {
            input.cancel(); session = nil; destination = nil; phase = forced?.outcome == .cancelled ? .idle : .error
            if forced?.outcome == .cancelled { message = "Cancelled. Nothing inserted." }
            else if forced?.reason == .deadline { message = DictationModel.description(.timedOut) }
            else if forced?.reason == .speechFailed, let failure = terminalSpeechFailure {
                message = activeLanguageMode == .teluguRomanised ? DictationModel.description(failure) : (speechFailureDiagnostics?.failureDescription ?? DictationModel.description(failure))
            } else if forced?.reason != .speechFailed {
                message = speechFailureDiagnostics?.failureDescription ?? "No words were recognised. Hold the dictation key until the waveform appears, speak, then release. Check General → Language and the Mac’s selected sound input."
            }
            // A provider failure already supplied its specific error; do not overwrite it with an empty-result warning.
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
            let completedAt = await self.clock.now()
            self.clipboardPending = self.insertion.hasPendingClipboard
            if self.session == id, !self.closed {
                // Observed delivery remains a fact even when cancellation prevents eligibility.
                self.latestInsertionOutcome = receipt.status.rawValue
                self.verifiedReceiptCreated = receipt.status == .insertedVerified
                self.classifyInsertion(receipt,target:target)
                let elapsed = completedAt.subtractingReportingOverflow(now)
                self.insertionElapsedMilliseconds = !elapsed.overflow && elapsed.partialValue >= 0 ? elapsed.partialValue : nil
            }
            // A cancelled/closed or superseded asynchronous insertion cannot publish
            // an edit capability. Its actual receipt may still be retained in history.
            if self.session == id, !self.closed, !Task.isCancelled {
                self.latestInsertionOutcome = receipt.status.rawValue
                self.verifiedReceiptCreated = receipt.status == .insertedVerified
                self.targetVerificationAvailable = false
                if receipt.status != .insertedVerified {
                    let uncertain = receipt.status == .uncertain || receipt.status == .dispatchedUnverified
                    self.invalidateProvenance(uncertain ? .uncertain : .failed,uncertain
                        ? "The last insertion is uncertain. Check the field; automatic replacement is unavailable."
                        : "The last insertion was not verified. Nothing can be replaced automatically.")
                } else if !self.preferences.inPlaceAIRewrite {
                    self.invalidateProvenance(.disabled,"In-place capture was disabled at insertion. Enable it and dictate a new sentence.")
                } else if receipt.clipboardPending || self.insertion.hasPendingClipboard {
                    self.invalidateProvenance(.clipboard,"Resolve pending clipboard recovery, then dictate again. Original retained.")
                } else if self.latestReplacementCapability == .unavailable {
                    self.crossAppFailure = .replacementUnsupported
                    self.invalidateProvenance(.replacementUnsupported,"Destination editor is unsupported for precise replacement. Dictated text is retained. Use Smart Formatting’s manual preview and Copy instead.")
                } else if let provider = target as? any DictationRewriteAnchorProviding {
                    do {
                        let anchor = try provider.verifiedRewriteAnchor(insertedText:text)
                        guard anchor.sessionID == id, anchor.originalText.utf16.elementsEqual(text.utf16), anchor.processID == target?.info.processID else { throw TextTargetError.changed }
                        self.rewriteAnchor = anchor; self.receiptCreatedAt = completedAt; self.provenanceReason = .none; self.targetVerificationAvailable = true
                        self.armReceiptExpiration(sessionID:id,createdAt:completedAt)
                        self.recordVerification("afterInsertion",anchor.verificationDiagnostics)
                    } catch {
                        self.recordVerification("afterInsertion",provider.rewriteVerificationDiagnostics,failure:error)
                        self.rejectProvenance(error)
                    }
                } else {
                    self.invalidateProvenance(.rangeUnavailable,"Original text location unavailable. This target cannot provide a safe replacement range.")
                }
            } else {
                self.invalidateProvenance(.invalidated,"The insertion session was cancelled or closed. No eligible replacement receipt.")
            }
            self.recordInsertionTrace(target,receipt:receipt)
            #if DEBUG
            self.insertionTraceSummary += self.eligibleReceiptPresent ? " · INSERTION_RECEIPT_CREATED" : " · ELIGIBLE_RECEIPT_WITHHELD reason=" + self.provenanceReason.rawValue
            #endif
            let duration = began.map { start -> Int64 in
                let delta = now.subtractingReportingOverflow(start)
                return delta.overflow ? 0 : max(0,min(DictationText.maximumDurationMilliseconds,delta.partialValue))
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
            else { self.phase = .error; self.message = self.speechFailureDiagnostics != nil && forced?.reason == .speechFailed ? self.speechFailureDiagnostics!.failureDescription : self.speechFailureCode == "providerEnded" ? DictationModel.description(.providerEnded) : receipt == fallback ? (captureExplanation ?? Self.insertionExplanation(receipt)) : (((receipt.reason == .clipboardUnsupported || receipt.outcome == .uncertain) ? self.insertion.failureExplanation : nil) ?? Self.insertionExplanation(receipt)) }
            if self.startedFromShortcut || self.preferences.idlePillEnabled { self.showHUDFeedback() }
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
        cancelTextCapture(); cancelRewritePreview(); reliableFinalID = nil
        do { let store = try await getHistory(); try await store.clear(); latest = nil; await loadHistory() }
        catch { historyError = "History could not be cleared." }
    }
    func restoreClipboardAfterConfirmation(expectedRecoveryID: String?) {
        guard let expectedRecoveryID else { message = "That recovery request is no longer available. No clipboard was changed."; return }
        let result = insertion.restoreAfterUserConfirmation(expectedRecoveryID:expectedRecoveryID); clipboardPending = insertion.hasPendingClipboard
        pasteboardLeaseResult = result == .restored ? .restored : (result == .preservedNewer ? .preservedNewer : .recoveryPending)
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
                    guard !self.shortcutHeld, !self.busy, !self.agentHeld else { return }; self.shortcutHeld = true; self.begin(manual:false,fromShortcut:true,activation:self.shortcut.activationContext)
                case .released:
                    guard self.shortcutHeld else { return }; self.shortcutHeld = false
                    if self.phase == .recording { self.stop() } else if self.phase == .preparing { self.cancel() }
                case .cancelled: if !self.commandSession { self.cancel() }; self.shortcutHeld = false
                case .unavailable: self.stopShortcutMonitoring(); if !self.commandSession { self.cancel() }
                }
            }
            shortcutEnabled = true
        } catch { message = "Allow Accessibility for hold-to-talk dictation, then enable it again. Hold the selected key to speak." }
        refreshPermissions()
    }
    func changeActivationKey(_ key: DictationActivationKey) {
        guard !busy, !(preferences.agentHotkeyEnabled && key == preferences.agentKey) else { message = "Shortcut conflict: choose separate Dictation and Agent keys."; return }
        let enabled = shortcutEnabled; stopShortcutMonitoring(); cancel()
        preferences.activationKey = key
        if enabled { startShortcutMonitoring() }
    }
    func enableAgentShortcut() { agentMonitoringRequested = true; preferences.agentHotkeyEnabled = true; configureAgentShortcut() }
    func disableAgentShortcut() { agentMonitoringRequested = false; preferences.agentHotkeyEnabled = false; stopAgentShortcut(); if commandSession { cancel() } }
    func changeAgentKey(_ key: DictationActivationKey) {
        guard !busy else { return }
        guard !(preferences.holdFnEnabled && key == preferences.activationKey), !(preferences.previewShortcutsEnabled && key == .rightOption) else { agentShortcutStatus = "Shortcut conflict: choose another Agent key."; return }
        do { guard try !agentConflict(key) else { agentShortcutStatus = "Conflict with a macOS shortcut."; return } }
        catch { agentShortcutStatus = "Could not validate system shortcuts."; return }
        preferences.agentKey = key
    }
    private func stopAgentShortcut() {
        agentShortcutGeneration += 1; agentShortcutEnabled = false; agentHeld = false; agentShortcut.disable()
    }
    private func configureAgentShortcut() {
        defer { agentShortcutDiagnostics = agentShortcut.diagnosticSummary }
        if commandSession { cancel() }
        stopAgentShortcut()
        guard agentMonitoringRequested, !closed, preferenceStore.error == nil, preferences.agentHotkeyEnabled else { return }
        guard !(preferences.holdFnEnabled && preferences.agentKey == preferences.activationKey), !(preferences.previewShortcutsEnabled && preferences.agentKey == .rightOption) else { agentShortcutStatus = "Shortcut conflict: Agent is disabled until separate keys are selected."; return }
        do {
            guard try !agentConflict(preferences.agentKey) else { agentShortcutStatus = "Conflict with a macOS shortcut."; return }
            agentShortcut.configure(key:preferences.agentKey)
            let generation = agentShortcutGeneration
            try agentShortcut.enable { [weak self] event in
                guard let self, !self.closed, self.agentShortcutEnabled, self.agentShortcutGeneration == generation else { return }
                self.agentShortcutDiagnostics = self.agentShortcut.diagnosticSummary
                switch event {
                case .pressed:
                    guard !self.agentHeld else { return }; self.agentHeld = true
                    guard !self.busy, !self.shortcutHeld, !self.inPlaceRunning, (self.agentPlan == nil || self.personalPlanner != nil) else {
                        self.agentShortcutStatus = self.agentPlan != nil ? "Agent key received: review or reject the pending plan first." : "Agent key received: another recording or operation owns audio. Release and retry when it finishes."
                        return
                    }
                    self.agentShortcutStatus = "Agent key received. Starting microphone…"
                    self.begin(manual:false,fromShortcut:true,activation:self.agentShortcut.activationContext,agent:true)
                case .released:
                    guard self.agentHeld else { return }; self.agentHeld = false
                    guard self.commandSession else { return }
                    if self.phase == .recording { self.stop() } else if self.phase == .preparing { self.cancel() }
                case .cancelled:
                    self.agentHeld = false
                    if self.commandSession || self.agentExecutingID != nil { self.cancel() }
                    else if self.agentQuestion != nil || self.agentPlan != nil { self.cancelAgentConversation() }
                case .unavailable:
                    if self.commandSession { self.cancel() }; self.stopAgentShortcut()
                    self.agentShortcutStatus = "Agent shortcut unavailable; enable again after checking permissions."
                }
            }
            agentShortcutEnabled = true
            agentShortcutStatus = "Hold \(preferences.agentKey.label) for Agent; release to review. Escape cancels."
        } catch { agentShortcutStatus = "Allow Accessibility/Input Monitoring, then enable Agent again." }
    }
    func disableShortcut() { commandArmed = false; preferences.holdFnEnabled = false; stopShortcutMonitoring(); cancel() }
    private func stopShortcutMonitoring() { shortcutGeneration += 1; shortcutEnabled = false; shortcutHeld = false; shortcut.disable() }
    /// Normal Quit must not silently discard an in-flight insertion or its RAM clipboard backup.
    func canTerminateSafely() -> Bool {
        reconcileClipboard()
        if busy { message = "Finish or cancel dictation before quitting."; return false }
        if speechResourceWorking { message = "Finish speech resource setup or choose Stop waiting before quitting."; return false }
        if insertion.hasPendingClipboard { clipboardPending = true; message = "Review clipboard restoration before quitting; the saved clipboard is held in memory."; return false }
        return true
    }
    func close() {
        for task in closeObservers.values {task.cancel()};closeObservers.removeAll()
        agentDialogue.clear();agentQuestion=nil;agentRecipientChoice=nil;agentReplyText="";agentHeard="";agentInterpretation=""
        unmergedSpeechRecoveryEntry = nil
        stopWaitingForSpeechResources()
        stopAudioVisualization(); cancelInPlaceRewrite(); feedbackTask?.cancel(); hudFeedbackVisible = false; invalidateProvenance(.invalidated,"Application closed. Dictate again in a new process.")
        cancelTextCapture(); shortcutInputText = ""; previewOriginalText = ""
        previewPresented = false; previewOriginProcessIdentifier = nil
        cancelRewritePreview(); previewRegistrar?.disable(); registeredPreviewKinds = []; closed = true; commandArmed = false; stopShortcutMonitoring(); stopAgentShortcut(); cancel(); work?.cancel(); timer?.cancel()
        let store = history
        Task { await store?.close() }
    }
}
