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
    @Published private(set) var inPlaceHUD: InPlaceHUD = .idle
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
    private var pipelineSummary:String {
        let bundle:String
        if let value = destinationBundleIdentifier, value.utf8.count <= 255,
           value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) { bundle = value }
        else { bundle = "unknown" }
        return ["destinationBundle="+bundle,"CAPTURE_RESULT="+audioCaptureResult.rawValue,
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
    private func captureDestination(session:String) throws -> any InsertionTarget {
        let began = ContinuousClock.now
        defer {
            let elapsed = began.duration(to:.now).components
            let seconds = elapsed.seconds.multipliedReportingOverflow(by:1000)
            let total = seconds.partialValue.addingReportingOverflow(elapsed.attoseconds / 1_000_000_000_000_000)
            activeCaptureDiagnostics = targets.captureDiagnostics
            if let bundle = targets.captureBundleIdentifier { destinationBundleIdentifier = bundle }
            captureElapsedMilliseconds = !seconds.overflow && !total.overflow && total.partialValue >= 0 ? total.partialValue : nil
        }
        do {
            let target = try targets.capture(session:session)
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
        guard input is any DictationAudioMetering else { return }
        meterTask = Task { [weak self] in
            var envelope = DictationAudioEnvelope()
            while !Task.isCancelled {
                guard let self, self.session == id, self.phase == .recording else { return }
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
            ? "37R2 · Option+1/2 request in-place AI only. A new verified dictation and supported unchanged editor are required. No preview opens on failure. Nothing is submitted."
            : "37R2 · Option+1/2 show only the pill while this switch is OFF. Enable before a new verified dictation. Manual preview is available only through Settings."
    }
    @Published private var verificationDetail = "No verification requested"
    var verificationDiagnosticSummary: String {
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"
        return "37R2 build=" + build + " lifecycle=" + (closed ? "closed" : phase.rawValue)
            + " outcome=" + latestInsertionOutcome + " verifiedReceipt=" + String(verifiedReceiptCreated)
            + " eligibleReceipt=" + String(eligibleReceiptPresent) + " reason=" + provenanceReason.rawValue
            + " expiration=" + (provenanceReason == .expired ? "expired" : (eligibleReceiptPresent ? "native120sRecheckedOnUse" : "noActiveAnchor"))
            + " targetMatched=" + targetIdentityMatched + " verificationAvailable=" + String(targetVerificationAvailable)
            + " operation=" + shortcutOperation + " model=" + verificationModelState + " · " + verificationDetail + " · insertion: " + insertionTraceSummary + " · " + insertionLookupSummary + " · " + crossAppSummary + " · " + pipelineSummary
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
        guard preferences.inPlaceAIRewrite,
              kind == .polish ? preferences.offlineAIRewriting : preferences.promptEngineeringEnabled else {
            rejectInPlace(kind,.featureDisabled,"Enable the requested AI feature and In-place AI rewrite first. Original retained."); return
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
    @Published private(set) var clipboardPending = false
    @Published private(set) var shortcutEnabled = false
    @Published var preferences: DictationPreferences { didSet {
        if oldValue.useFocusedTextWhenUnselected != preferences.useFocusedTextWhenUnselected { cancelTextCapture() }
        if oldValue.inPlaceAIRewrite != preferences.inPlaceAIRewrite { cancelTextCapture(); cancelRewritePreview(); previewPresented = false }
        if oldValue.inPlaceAIRewrite != preferences.inPlaceAIRewrite || (oldValue.offlineAIRewriting && !preferences.offlineAIRewriting) || (oldValue.promptEngineeringEnabled && !preferences.promptEngineeringEnabled) { cancelInPlaceRewrite() }
        preferenceStore.save(preferences); networkPolicy.setBlocked(preferences.blockNetworkRequests); networkSnapshot = networkPolicy.snapshot()
        if (previewKind == .polish && !preferences.offlineAIRewriting) || (previewKind == .promptEngineering && !preferences.promptEngineeringEnabled) { cancelTextCapture(); cancelRewritePreview() }
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
        traceRoute(kind,.received)
        // Fence a pending explicit capture/result and hide an already-open manual
        // editor. A late capture must not open it after this gesture.
        cancelTextCapture(); cancelRewritePreview(); previewPresented = false
        guard !closed, !busy else { traceRoute(kind,.ignoredBusy); return }
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
    private let input: any DictationInput
    private let targets: any InsertionTargetCapturing
    private let insertion: any DictationTextInserting
    private let shortcut: any DictationShortcutMonitoring
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
    var pillVisible: Bool { preferences.showPill && ((preferences.idlePillEnabled && !closed) || (startedFromShortcut && busy) || hudFeedbackVisible || inPlaceHUD != .idle) }
    var busy: Bool { [.preparing,.recording,.finalizing,.inserting].contains(phase) }
    var filteredHistory: [DictationHistoryEntry] { DictationHistoryQuery.filter(entries,search:search) }
    var groupedHistory: [(date:Date,entries:[DictationHistoryEntry])] { DictationHistoryQuery.groups(filteredHistory,calendar:.current) }
    init(input: any DictationInput, targets: any InsertionTargetCapturing, insertion: any DictationTextInserting,
         shortcut: any DictationShortcutMonitoring, clock: any TaskClock = SystemTaskClock(),
         hudClock: any TaskClock = SystemTaskClock(),
         preferenceStore: DictationPreferenceStore = DictationPreferenceStore(),
         networkPolicy: ApplicationNetworkPolicy = .shared,
         history: (any DictationHistoryStore)? = nil,
         historyFactory: (@Sendable () async throws -> any DictationHistoryStore)? = nil,
         appOpener: @escaping @MainActor (AppOpeningCommand) async throws -> Void = NativeAppOpening.open,
         modelInspector: (@Sendable () async throws -> [ModelDescriptor])? = nil,
         offlineRewriter: (any OfflineTranscriptRewriting)? = nil,
         previewRegistrar: (any PreviewShortcutRegistering)? = nil,
         previewPresentationRequest: @escaping @MainActor (OfflinePreviewKind) -> Void = { _ in },
         focusedTextResolver: (any FocusedTextResolving)? = nil,
         historyCopy: @escaping @MainActor (String) -> Bool = HistoryClipboard.write,
         localeIdentifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier,
         minimumHoldMilliseconds: Int64 = 0,
         wallTime: @escaping @Sendable () -> Date = { Date() }) {
        self.networkPolicy = networkPolicy; self.networkSnapshot = networkPolicy.snapshot()
        self.focusedTextResolver = focusedTextResolver
        self.previewPresentationRequest = previewPresentationRequest
        self.offlineRewriter = offlineRewriter; self.previewRegistrar = previewRegistrar
        self.historyCopy = historyCopy
        self.minimumHoldMilliseconds = min(1000,max(0,minimumHoldMilliseconds))
        self.appOpener = appOpener
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
        if inPlaceRunning { cancelInPlaceRewrite(); return }
        if phase == .recording { stop(); return }
        guard !busy else { return }
        begin(manual:false)
    }
    func startManual() { guard !busy, !closed else { return }; begin(manual:true) }
    private func begin(manual: Bool, fromShortcut: Bool = false) {
        cancelInPlaceRewrite()
        audioCaptureResult = .pending; transcriptionResult = .pending; targetCaptureResult = .notStarted
        targetValidationResult = .notStarted; pasteboardLeaseResult = .notStarted; insertionDispatchResult = .notStarted
        destinationBundleIdentifier = nil; speechFailureCode = "NONE"
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
        if !manual && !(fromShortcut && commandArmed) && insertion.hasPendingClipboard {
            audioCaptureResult = .notStarted; transcriptionResult = .notStarted; pasteboardLeaseResult = .recoveryPending
            clipboardPending = true; phase = .error; startedFromShortcut = false
            message = (insertion.failureExplanation.map { $0 + " " } ?? "") + "Recording was not started. Review clipboard restoration before another dictation."
            return
        }
        commandSession = fromShortcut && commandArmed; commandArmed = false
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
                self.audioCaptureResult = .recording
                self.engine = info; self.phase = .recording; self.recordingBegan = await self.clock.now()
                guard self.session == id, self.phase == .recording else { return }
                self.message = self.commandSession ? "Listening for an app-opening command. Release the key to open it." : (self.destination == nil ? "Listening. Release the key to finish; this field is unavailable, so text will remain for copy." : "Listening into the captured field. Release the key to insert.")
                self.startAudioVisualization(id:id)
                self.armTimer(60_000,id:id,finishing:false)
            } catch {
                guard self.session == id else { return }
                self.input.cancel(); self.session = nil; self.destination = nil; self.phase = .error
                self.audioCaptureResult = Task.isCancelled ? .cancelled : .failed
                self.transcriptionResult = Task.isCancelled ? .cancelled : .failed
                self.speechFailureCode = String(describing:error as? DictationFailure ?? .recognitionFailed)
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
        case .failed(let error): transcriptionResult = .failed; speechFailureCode = String(describing:error); input.cancel(); message = DictationModel.description(error); finish(id:id,forced:.init(.denied,.speechFailed))
        }
    }
    func stop() {
        guard let id = session, phase == .recording else { return }
        stopAudioVisualization()
        phase = .finalizing; message = "Transcribing…"; timer?.cancel(); input.stop()
        if phase == .finalizing { armTimer(8000,id:id,finishing:true) }
    }
    func cancel() {
        stopAudioVisualization(); cancelInPlaceRewrite()
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
        stopAudioVisualization()
        timer?.cancel(); timer = nil; startup = nil
        cleaned = NativeDictationFormatting.format(raw,options:preferences.formatting,whitespace:preferences.spacingCleanup,locale:localeIdentifier)
        audioCaptureResult = forced?.outcome == .cancelled ? .cancelled : (audioCaptureResult == .recording ? .success : .failed)
        transcriptionResult = forced?.outcome == .cancelled ? .cancelled : (forced == nil && !cleaned.isEmpty ? .success : .failed)
        if forced?.reason == .deadline { speechFailureCode = "timedOut" }
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
        stopAudioVisualization(); cancelInPlaceRewrite(); feedbackTask?.cancel(); hudFeedbackVisible = false; invalidateProvenance(.invalidated,"Application closed. Dictate again in a new process.")
        cancelTextCapture(); shortcutInputText = ""; previewOriginalText = ""
        previewPresented = false; previewOriginProcessIdentifier = nil
        cancelRewritePreview(); previewRegistrar?.disable(); registeredPreviewKinds = []; closed = true; commandArmed = false; stopShortcutMonitoring(); cancel(); work?.cancel(); timer?.cancel()
        let store = history
        Task { await store?.close() }
    }
}
