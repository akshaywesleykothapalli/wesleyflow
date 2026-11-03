import Domain
import Foundation

/// Effects and verification are separate: dispatched keyboard events are never success evidence.
@MainActor public final class TextInsertionService: DictationTextInserting {
    public private(set) var failureExplanation: String?
    private let clipboard: any DictationPasteboard
    private let clock: any TaskClock
    public private(set) var verificationSession:String?
    public private(set) var verificationDiagnostics:[InsertionVerificationDiagnostic] = []
    private func record(_ value:InsertionVerificationDiagnostic) {
        if verificationDiagnostics.count == 32 { verificationDiagnostics.remove(at:6) }
        verificationDiagnostics.append(value)
    }
    private func recordRestoration(_ result:ClipboardRestoration) {
        switch result {
        case .restored: record(.init(.clipboard,.clipboardRestored,.success,timing:.terminal))
        case .preservedNewer: record(.init(.clipboard,.clipboardSuperseded,.success,timing:.terminal))
        case .unavailable: record(.init(.clipboard,.clipboardRetained,.pending,timing:.terminal))
        }
    }
    private var active = false
    private struct PendingClipboard {
        let snapshot: ClipboardSnapshot
        let ownership: ClipboardOwnership
        let recovery: ClipboardRecovery
    }
    private var pending: PendingClipboard?
    public var pendingClipboardRecovery: ClipboardRecovery? { pending?.recovery }
    public var hasPendingClipboard: Bool { pending != nil }
    public init(clipboard: any DictationPasteboard, clock: any TaskClock) { self.clipboard = clipboard; self.clock = clock }
    @discardableResult public func reconcileClipboardState() -> ClipboardRestoration? {
        guard !active, let pending, clipboard.isSuperseded(pending.ownership) else { return nil }
        // A newer copy has superseded this lease. Keep it untouched; do not retry old text.
        self.pending = nil
        recordRestoration(.preservedNewer)
        return .preservedNewer
    }
    public func restoreAfterUserConfirmation(expectedRecoveryID: String) -> ClipboardRestoration {
        guard !active, let pending, pending.recovery.id == expectedRecoveryID else { return .unavailable }
        let result = clipboard.restore(pending.snapshot,ifOwned:pending.ownership)
        recordRestoration(result)
        if result != .unavailable { self.pending = nil }
        return result
    }
    public func insert(_ text: String, target: any InsertionTarget, session: String) async -> TextInsertionReceipt {
        guard !active else { return .init(.denied,.clipboardPending) }
        reconcileClipboardState()
        failureExplanation = nil; verificationDiagnostics = []; verificationSession = session
        record(.init(.target,.targetAcquired,.success))
        record(.init(.target,.originalElement,.success))
        if let original = target.original { record(.init(.selection,.selectionCaptured,.success,range:original.selection)) }
        else { record(.init(.selection,.identityOnly,.unsupported)) }
        record(.init(.formatted,.formatted,.success,expected:text.utf16.count))
        active = true; defer { active = false }
        guard !Task.isCancelled else { return .init(.cancelled,.cancelled) }
        let start = await clock.now()
        guard start >= 0, start <= Int64.max - 1500 else { return .init(.timedOut,.deadline) }
        let deadline = start + 1500
        guard !Task.isCancelled else { return .init(.cancelled,.cancelled) }
        guard target.info.session == session else { return .init(.targetChanged,.changed) }
        guard !text.isEmpty, text.utf8.count <= DictationText.maximumBytes else { return .init(.unsupportedTarget,.unsupported) }
        let expectation:DictationInsertionExpectation?
        if let original = target.original {
            guard let value = try? DictationInsertionExpectation(original:original,insertedText:text) else { return .init(.unsupportedTarget,.unsupported) }
            expectation = value
        } else { expectation = nil }
        do { try target.validate() } catch { return Self.failure(error) }
        guard await clock.now() < deadline else { return .init(.timedOut,.deadline) }
        guard !Task.isCancelled else { return .init(.cancelled,.cancelled) }
        if let expectation, (target as? any ClipboardFreeInsertionTarget)?.requiresGuardedPaste != true, target.canReplaceSelection() {
            var acknowledged = true
            do { try target.replaceSelection(text) }
            catch DirectTextUpdateFailure.dispatchUnconfirmed {
                acknowledged = false
                record(.init(.dispatch,.directDispatched,.pending))
            }
            catch { failureExplanation = "The app did not confirm its direct text update. Nothing was retried; check the field before trying again."; return .init(.uncertain,.verificationUnavailable,attempted:true) }
            if acknowledged { record(.init(.dispatch,.directDispatched,.success)) }
            let result = await verify(expectation,target:target,deadline:deadline,settleMismatch:false)
            if result.verified { return .init(.inserted,.verified,attempted:true) }
            record(.init(.receipt,.uncertain,.failure,timing:.terminal))
            failureExplanation = "The app's direct text update could not be verified. " + Self.readbackExplanation(result.failure) + " Nothing was retried; check the field before trying again."
            return .init(.uncertain,result.failure == .cancelled ? .cancelled : .verificationUnavailable,attempted:true)
        }
        if let native=target as? any ClipboardFreeInsertionTarget, !native.requiresGuardedPaste {
            guard native.supportsClipboardFreeText(text) else {
                failureExplanation="Clipboard-free delivery supports single-line text up to 4 KiB. This text was retained for manual copy; no clipboard was changed."
                return .init(.unsupportedTarget,.clipboardUnsupported)
            }
            let now=await clock.now()
            guard !Task.isCancelled,now<deadline else { return .init(.cancelled,.cancelled) }
            do { try target.validate() } catch { return Self.failure(error) }
            guard target.postText(text,budgetMilliseconds:deadline-now) else {
                failureExplanation="The bound editor could not accept clipboard-free text. Nothing was retried; use manual copy."
                return .init(.unsupportedTarget,.clipboardUnsupported)
            }
            record(.init(.dispatch,.typingDispatched,.success))
            if let expectation {
                let result=await verify(expectation,target:target,deadline:deadline,settleMismatch:true)
                if result.verified { return .init(.inserted,.verified,attempted:true) }
            }
            failureExplanation="Text events were sent once to the captured editor. Delivery could not be verified; no clipboard was used and nothing was retried."
            return .init(.uncertain,.verificationUnavailable,attempted:true)
        }
        if (target as? any ClipboardFreeInsertionTarget)?.requiresGuardedPaste == true, expectation == nil {
            failureExplanation = "Guarded paste requires readable text and selection so insertion can be verified. No paste was attempted; the transcript remains available for copy."
            return .init(.unsupportedTarget,.unsupported)
        }
        guard pending == nil else { return .init(.denied,.clipboardPending,clipboardPending:true) }
        let snapshot: ClipboardSnapshot, ownership: ClipboardOwnership
        do { snapshot = try clipboard.snapshot() }
        catch {
            failureExplanation = clipboard.snapshotFailureExplanation
            guard !Task.isCancelled else { return .init(.cancelled,.cancelled) }
            let now = await clock.now()
            guard now < deadline else { return .init(.timedOut,.deadline) }
            do { try target.validate() } catch { return Self.failure(error) }
            guard let expectation else {
                failureExplanation = "This editor has no exact readback and the clipboard cannot be safely backed up. No insertion was attempted; review and copy the transcript explicitly."
                return .init(.unsupportedTarget,.clipboardUnsupported)
            }
            guard (target as? any ClipboardFreeInsertionTarget)?.requiresGuardedPaste != true, target.postText(text,budgetMilliseconds:deadline-now) else { return .init(.unsupportedTarget,.clipboardUnsupported) }
            failureExplanation = nil
            // No clipboard was cleared or published. Partial/unacknowledged input remains uncertain.
            record(.init(.dispatch,.typingDispatched,.success))
            let result = await verify(expectation,target:target,deadline:deadline,settleMismatch:true)
            if result.verified { return .init(.inserted,.verified,attempted:true) }
            if result.failure == .cancelled { return .init(.uncertain,.cancelled,attempted:true) }
            failureExplanation = "Keyboard typing was attempted because the clipboard could not be safely backed up, but the app did not confirm the expected text. Nothing was retried; check the field before trying again."
            return .init(.uncertain,.verificationUnavailable,attempted:true)
        }
        do { ownership = try clipboard.install(text,replacing:snapshot) }
        catch let failure as ClipboardPublicationFailure { return restoreBeforeDispatch(snapshot,failure.ownership,.denied,.clipboardChanged,session:session) }
        catch { return .init(.denied,.clipboardChanged) }
        record(.init(.clipboard,.clipboardAcquired,.success))
        guard !Task.isCancelled else { return restoreBeforeDispatch(snapshot,ownership,.cancelled,.cancelled,session:session) }
        guard await clock.now() < deadline else { return restoreBeforeDispatch(snapshot,ownership,.timedOut,.deadline,session:session) }
        guard clipboard.owns(ownership) else { return .init(.denied,.clipboardChanged) }
        guard !Task.isCancelled else { return restoreBeforeDispatch(snapshot,ownership,.cancelled,.cancelled,session:session) }
        do { try target.validate(); try Task.checkCancellation(); try target.postPaste(whileClipboardOwned:{ self.clipboard.owns(ownership) }) }
        catch is CancellationError { return restoreBeforeDispatch(snapshot,ownership,.cancelled,.cancelled,session:session) }
        catch {
            let receipt = Self.failure(error)
            return restoreBeforeDispatch(snapshot,ownership,receipt.outcome,receipt.reason,session:session)
        }
        record(.init(.dispatch,.pasteDispatched,.success))
        guard let expectation else {
            // Identity-bound ordinary paste is allowed without exact text/range
            // APIs. Dispatch is not proof of acceptance; preserve its backup.
            retain(snapshot,ownership,session:session)
            record(.init(.readback,.readbackUnsupported,.unsupported,timing:.terminal))
            record(.init(.receipt,.uncertain,.pending,timing:.terminal))
            failureExplanation = "Paste was dispatched to the original editable field, but this editor exposes no exact readback. Check the draft and review clipboard restoration before another paste. The transcript remains available for explicit Copy."
            return .init(.uncertain,.verificationUnavailable,attempted:true,clipboardPending:true)
        }
        let result = await verify(expectation,target:target,deadline:deadline,settleMismatch:true)
        if result.verified {
            let restored = clipboard.restore(snapshot,ifOwned:ownership)
            recordRestoration(restored)
            if restored == .unavailable { retain(snapshot,ownership,session:session) }
            return .init(.inserted,.verified,attempted:true,clipboardPending:pending != nil)
        }
        if result.failure == .cancelled {
            retain(snapshot,ownership,session:session)
            return .init(.uncertain,.cancelled,attempted:true,clipboardPending:true)
        }
        // An unacknowledged paste may still be queued. Retain the bounded backup in RAM;
        // restoration now needs explicit human confirmation and still checks clipboard ownership.
        retain(snapshot,ownership,session:session)
        failureExplanation = "Paste was attempted. " + Self.observationExplanation(result.observed, original:target.original?.text ?? "", expected:expectation.document) + " Nothing was retried. Check the field and review the saved clipboard before another paste."
        record(.init(.receipt,.uncertain,.failure,timing:.terminal))
        return .init(.uncertain,result.failure == .timeout ? .deadline : .verificationUnavailable,attempted:true,clipboardPending:true)
    }
    private enum VerificationFailure { case timeout, cancelled, denied, unsupported, temporary, rangeUnavailable, rangeInvalid, changed, mismatch, secure }
    private struct VerificationResult {
        let verified:Bool
        let observed:String?
        let failure:VerificationFailure?
    }
    /// Read-only settling: at most32 observations,50ms cadence, and the original
    ///1500ms operation deadline. Never sends a second write, paste or keystroke.
    private func verify(_ expectation:DictationInsertionExpectation,target:any InsertionTarget,deadline:Int64,settleMismatch:Bool) async -> VerificationResult {
        var observed:String?
        for attempt in 0..<32 {
            if Task.isCancelled { record(.init(.readback,.cancelled,.failure,timing:.terminal)); return .init(verified:false,observed:observed,failure:.cancelled) }
            guard await clock.now() < deadline else { break }
            let timing:InsertionVerificationDiagnostic.Timing = attempt == 0 ? .initial : .settling
            let observedAt = await clock.now()
            let elapsedDelta = observedAt.subtractingReportingOverflow(deadline-1500)
            let elapsed:Int64? = !elapsedDelta.overflow && elapsedDelta.partialValue >= 0 ? elapsedDelta.partialValue : nil
            do {
                observed = try target.readbackText()
                record(.init(.readback,.readbackSupported,.success,timing:timing,expected:expectation.document.utf16.count,observed:observed?.utf16.count,elapsedMilliseconds:elapsed))
                guard !Task.isCancelled else { return .init(verified:false,observed:observed,failure:.cancelled) }
                guard await clock.now() < deadline else { break }
                do {
                    _ = try expectation.verified(observed)
                    record(.init(.span,.verified,.success,timing:timing,expected:expectation.insertedText.utf16.count,observed:observed?.utf16.count,range:expectation.span,elapsedMilliseconds:elapsed))
                    return .init(verified:true,observed:observed,failure:nil)
                } catch {
                    let original = observed.map { observed in target.original.map { original in DictationInsertionExpectation.exact(observed,original.text) } ?? false } ?? false
                    let code:InsertionVerificationDiagnostic.Code = original ? .preInsertionText : ((error as? DictationRewriteValidationFailure) == .invalidRange ? .rangeInvalid : ((error as? DictationRewriteValidationFailure) == .contextChanged ? .contextMismatch : .textMismatch))
                    record(.init(.span,code,original ? .pending : .failure,timing:timing,expected:expectation.document.utf16.count,observed:observed?.utf16.count,range:expectation.span,elapsedMilliseconds:elapsed))
                    // A concrete different direct result is not assumed to be a
                    // deferred acknowledgement. Paste retains its existing window.
                    if !settleMismatch && !original { return .init(verified:false,observed:observed,failure:.mismatch) }
                }
            } catch {
                let failure:VerificationFailure, code:InsertionVerificationDiagnostic.Code
                switch error as? InsertionReadbackFailure {
                case .denied: failure = .denied; code = .readbackDenied
                case .unsupported: failure = .unsupported; code = .readbackUnsupported
                case .rangeUnavailable: failure = .rangeUnavailable; code = .rangeUnavailable
                case .rangeInvalid: failure = .rangeInvalid; code = .rangeInvalid
                case .targetChanged: failure = .changed; code = .targetChanged
                case .secure: failure = .secure; code = .readbackDenied
                default: failure = .temporary; code = .readbackTemporary
                }
                record(.init(.readback,code,failure == .temporary ? .pending : .failure,timing:timing))
                if failure != .temporary { return .init(verified:false,observed:observed,failure:failure) }
            }
            let now = await clock.now()
            guard now < deadline else { break }
            do { try await clock.sleep(until:min(deadline,now+50)) }
            catch { record(.init(.readback,.cancelled,.failure,timing:.terminal)); return .init(verified:false,observed:observed,failure:.cancelled) }
        }
        record(.init(.readback,.readbackTimeout,.failure,timing:.terminal))
        return .init(verified:false,observed:observed,failure:.timeout)
    }
    private static func readbackExplanation(_ failure:VerificationFailure?) -> String {
        switch failure {
        case .denied: "Accessibility readback was denied."
        case .unsupported: "The original editor does not support readback."
        case .rangeUnavailable: "The original range is unavailable."
        case .rangeInvalid: "The original range is invalid."
        case .changed: "The original target identity changed."
        case .secure: "Secure input prevents readback."
        case .timeout: "The bounded readback window expired."
        case .cancelled: "Verification was cancelled."
        default: "The expected exact text was not confirmed."
        }
    }
    /// Capability/size metadata only: never include editor contents in diagnostics.
    private static func observationExplanation(_ observed: String?, original: String, expected: String) -> String {
        guard let observed else { return "The original field stopped exposing readable text." }
        if observed == original { return "The original field still reports its pre-paste text." }
        return "The original field reports a different result (expected \(expected.utf16.count) UTF-16 units; observed \(observed.utf16.count))."
    }
    private func restoreBeforeDispatch(_ snapshot: ClipboardSnapshot,_ ownership: ClipboardOwnership,_ outcome: TextInsertionOutcome,_ reason: InsertionReason, session: String) -> TextInsertionReceipt {
        if clipboard.restore(snapshot,ifOwned:ownership) == .unavailable { retain(snapshot,ownership,session:session,dispatched:false) }
        return .init(outcome,reason,clipboardPending:pending != nil)
    }
    private func retain(_ snapshot: ClipboardSnapshot,_ ownership: ClipboardOwnership,session: String,dispatched: Bool = true) {
        record(.init(.clipboard,.clipboardRetained,.pending,timing:.terminal))
        pending = .init(snapshot:snapshot,ownership:ownership,recovery:.init(id:UUID().uuidString,session:session,dispatched:dispatched))
    }
    private static func failure(_ error: any Error) -> TextInsertionReceipt {
        switch error as? TextTargetError {
        case .denied: .init(.denied,.permission)
        case .secure: .init(.unsupportedTarget,.secureField)
        case .changed: .init(.targetChanged,.changed)
        case .clipboardChanged: .init(.denied,.clipboardChanged)
        default: .init(.unsupportedTarget,.unsupported)
        }
    }
}
