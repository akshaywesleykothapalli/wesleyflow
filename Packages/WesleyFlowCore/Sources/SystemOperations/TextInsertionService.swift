import Domain
import Foundation

/// Effects and verification are separate: dispatched keyboard events are never success evidence.
@MainActor public final class TextInsertionService: DictationTextInserting {
    public private(set) var failureExplanation: String?
    private let clipboard: any DictationPasteboard
    private let clock: any TaskClock
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
        return .preservedNewer
    }
    public func restoreAfterUserConfirmation(expectedRecoveryID: String) -> ClipboardRestoration {
        guard !active, let pending, pending.recovery.id == expectedRecoveryID else { return .unavailable }
        let result = clipboard.restore(pending.snapshot,ifOwned:pending.ownership)
        if result != .unavailable { self.pending = nil }
        return result
    }
    public func insert(_ text: String, target: any InsertionTarget, session: String) async -> TextInsertionReceipt {
        guard !active else { return .init(.denied,.clipboardPending) }
        reconcileClipboardState()
        failureExplanation = nil
        active = true; defer { active = false }
        guard !Task.isCancelled else { return .init(.cancelled,.cancelled) }
        let start = await clock.now()
        guard start >= 0, start <= Int64.max - 1500 else { return .init(.timedOut,.deadline) }
        let deadline = start + 1500
        guard !Task.isCancelled else { return .init(.cancelled,.cancelled) }
        guard target.info.session == session else { return .init(.targetChanged,.changed) }
        guard !text.isEmpty, text.utf8.count <= DictationText.maximumBytes,
              let expected = target.original.selection.replacing(in:target.original.text,with:text) else { return .init(.unsupportedTarget,.unsupported) }
        do { try target.validate() } catch { return Self.failure(error) }
        guard await clock.now() < deadline else { return .init(.timedOut,.deadline) }
        guard !Task.isCancelled else { return .init(.cancelled,.cancelled) }
        if target.canReplaceSelection() {
            do { try target.replaceSelection(text) }
            catch { failureExplanation = "The app did not confirm its direct text update. Nothing was retried; check the field before trying again."; return .init(.uncertain,.verificationUnavailable,attempted:true) }
            if target.observedText() == expected { return .init(.inserted,.verified,attempted:true) }
            failureExplanation = "The app's direct text update did not produce the expected readable text. Nothing was retried; check the field before trying again."
            return .init(.uncertain,.verificationUnavailable,attempted:true)
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
            guard target.postText(text,budgetMilliseconds:deadline-now) else { return .init(.unsupportedTarget,.clipboardUnsupported) }
            failureExplanation = nil
            // No clipboard was cleared or published. Partial/unacknowledged input remains uncertain.
            for _ in 0..<32 {
                if target.observedText() == expected { return .init(.inserted,.verified,attempted:true) }
                if Task.isCancelled { return .init(.uncertain,.cancelled,attempted:true) }
                let current = await clock.now()
                guard current < deadline else { break }
                do { try await clock.sleep(until:min(deadline,current+50)) }
                catch { return .init(.uncertain,.cancelled,attempted:true) }
            }
            failureExplanation = "Keyboard typing was attempted because the clipboard could not be safely backed up, but the app did not confirm the expected text. Nothing was retried; check the field before trying again."
            return .init(.uncertain,.verificationUnavailable,attempted:true)
        }
        do { ownership = try clipboard.install(text,replacing:snapshot) }
        catch let failure as ClipboardPublicationFailure { return restoreBeforeDispatch(snapshot,failure.ownership,.denied,.clipboardChanged,session:session) }
        catch { return .init(.denied,.clipboardChanged) }
        guard !Task.isCancelled else { return restoreBeforeDispatch(snapshot,ownership,.cancelled,.cancelled,session:session) }
        guard await clock.now() < deadline else { return restoreBeforeDispatch(snapshot,ownership,.timedOut,.deadline,session:session) }
        guard clipboard.owns(ownership) else { return .init(.denied,.clipboardChanged) }
        do { try target.validate(); try target.postPaste(whileClipboardOwned:{ self.clipboard.owns(ownership) }) }
        catch {
            let receipt = Self.failure(error)
            return restoreBeforeDispatch(snapshot,ownership,receipt.outcome,receipt.reason,session:session)
        }
        // Bound polling uses target observations, never a fixed delay as a paste acknowledgement.
        var lastObserved: String?
        for _ in 0..<32 {
            lastObserved = target.observedText()
            if lastObserved == expected {
                let restored = clipboard.restore(snapshot,ifOwned:ownership)
                if restored == .unavailable { retain(snapshot,ownership,session:session) }
                return .init(.inserted,.verified,attempted:true,clipboardPending:pending != nil)
            }
            if Task.isCancelled {
                retain(snapshot,ownership,session:session); return .init(.uncertain,.cancelled,attempted:true,clipboardPending:true)
            }
            let now = await clock.now()
            guard now < deadline else { break }
            do { try await clock.sleep(until:min(deadline,now+50)) }
            catch { retain(snapshot,ownership,session:session); return .init(.uncertain,.cancelled,attempted:true,clipboardPending:true) }
        }
        // An unacknowledged paste may still be queued. Retain the bounded backup in RAM;
        // restoration now needs explicit human confirmation and still checks clipboard ownership.
        retain(snapshot,ownership,session:session)
        failureExplanation = "Paste was attempted. " + Self.observationExplanation(lastObserved, original:target.original.text, expected:expected) + " Nothing was retried. Check the field and review the saved clipboard before another paste."
        return .init(.uncertain,.deadline,attempted:true,clipboardPending:true)
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
