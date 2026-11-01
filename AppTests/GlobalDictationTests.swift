import Darwin
import UserNotifications
import AppKit
import ApplicationServices
import Combine
import SwiftUI
import Foundation
import Domain
import VoiceInput
import Testing
@testable import ModelProviders
@testable import WesleyFlow
@testable import SystemOperations
@testable import Persistence

private actor GClock: TaskClock {
    var value: Int64 = 1000
    var waits: [UUID:(Int64,CheckedContinuation<Void,any Error>)] = [:]
    var observers: [(Int64,CheckedContinuation<Void,Never>)] = []
    func now() -> Int64 { value }
    func sleep(until deadline: Int64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void,any Error>) in
                if Task.isCancelled { c.resume(throwing:CancellationError()); return }
                if deadline <= value { c.resume(); return }
                waits[id] = (deadline,c)
                let ready = observers.filter { $0.0 == deadline }; observers.removeAll { $0.0 == deadline }; ready.forEach { $0.1.resume() }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func cancel(_ id: UUID) { waits.removeValue(forKey:id)?.1.resume(throwing:CancellationError()) }
    func waitForSleep(_ deadline: Int64) async {
        if waits.values.contains(where: { $0.0 == deadline }) { return }
        await withCheckedContinuation { observers.append((deadline,$0)) }
    }
    func advance(_ value: Int64) { self.value = value; for id in waits.keys.filter({ waits[$0]!.0 <= value }) { waits.removeValue(forKey:id)?.1.resume() } }
}
@MainActor private final class GTarget: InsertionTarget, DictationRewriteAnchorProviding {
    let info: InsertionTargetInfo
    let capturedOriginal: TargetTextState
    var hasOriginalContext = true
    var original:TargetTextState? { hasOriginalContext ? capturedOriginal : nil }
    var value: String?
    var validationError: TextTargetError?
    var replacementCapability:EditorReplacementCapability = .unknown
    var writable = true, failWrite = false, acknowledgePaste = true
    var replacements = 0, pastes = 0
    var unicodeSupported = false, unicodeAcknowledged = true
    var unicodePosts = 0
    var pasted = "X"
    var beforePaste: (() -> Void)?
    var observedOverride:String?
    var readbackFailure:InsertionReadbackFailure?
    var deferDirectReadback = false
    var unconfirmedDirectWrite = false
    var readbacks = 0
    init(session: String = "s", text: String = "abc", selection: Domain.TextSelection = .init(location:1,length:0)) {
        info = .init(session:session,applicationName:"Fixture Editor",processID:42,windowIdentity:"w",elementIdentity:"e",role:"AXTextArea")
        capturedOriginal = .init(text:text,selection:selection); value = text
    }
    func validate() throws { if let validationError { throw validationError } }
    var rewriteCreationFailure: DictationRewriteValidationFailure?
    var rewriteFixture: GRewriteAnchor?
    func verifiedRewriteAnchor(insertedText:String) throws -> any DictationRewriteAnchor {
        if let rewriteCreationFailure { throw rewriteCreationFailure }
        guard original != nil else { throw DictationRewriteValidationFailure.invalidRange }
        let anchor = GRewriteAnchor(target:self,text:insertedText)
        rewriteFixture = anchor; return anchor
    }
    func canReplaceSelection() -> Bool { writable }
    func replaceSelection(_ text: String) throws { replacements += 1; if failWrite { throw TextTargetError.unsupported }; if !deferDirectReadback { value = capturedOriginal.selection.replacing(in:capturedOriginal.text,with:text) }; if unconfirmedDirectWrite { throw DirectTextUpdateFailure.dispatchUnconfirmed } }
    func postPaste(whileClipboardOwned: () -> Bool) throws {
        beforePaste?(); try validate(); guard whileClipboardOwned() else { throw TextTargetError.clipboardChanged }
        pastes += 1
        if acknowledgePaste { value = capturedOriginal.selection.replacing(in:capturedOriginal.text,with:pasted) }
    }
    func observedText() -> String? { observedOverride ?? value }
    func readbackText() throws -> String {
        readbacks += 1
        if let readbackFailure { throw readbackFailure }
        guard let value = observedText() else { throw InsertionReadbackFailure.temporarilyUnavailable }
        return value
    }
    func postText(_ text: String, budgetMilliseconds: Int64) -> Bool {
        guard unicodeSupported else { return false }
        unicodePosts += 1
        if unicodeAcknowledged { value = capturedOriginal.selection.replacing(in:capturedOriginal.text,with:text) }
        return true
    }
}
@MainActor private final class GClipboard: DictationPasteboard {
    var count = 1
    var beforeSnapshot: (() -> Void)?
    var text = "original"
    var token: String?
    var installed = 0, restores = 0, restorationAttempts = 0
    var ownershipReadable = true
    var unsupported = false, changedBeforeInstall = false, restoreFails = false
    func snapshot() throws -> ClipboardSnapshot { beforeSnapshot?(); if unsupported { throw TextTargetError.unsupported }; return .init(changeCount:count,items:[["public.utf8-plain-text":Array(text.utf8)]]) }
    func install(_ text: String, replacing snapshot: ClipboardSnapshot) throws -> ClipboardOwnership {
        if changedBeforeInstall { externalCopy("new user clipboard") }
        guard snapshot.changeCount == count else { throw TextTargetError.changed }
        self.text = text; count += 1; token = "owned"; installed += 1; return .init(changeCount:count,token:"owned")
    }
    func owns(_ ownership: ClipboardOwnership) -> Bool { ownershipReadable && count == ownership.changeCount && token == ownership.token }
    func isSuperseded(_ ownership: ClipboardOwnership) -> Bool { count != ownership.changeCount }
    func restore(_ snapshot: ClipboardSnapshot, ifOwned ownership: ClipboardOwnership) -> ClipboardRestoration {
        restorationAttempts += 1
        guard owns(ownership) else { return isSuperseded(ownership) ? .preservedNewer : .unavailable }
        if restoreFails { return .unavailable }
        restores += 1; text = String(decoding:snapshot.items.first?["public.utf8-plain-text"] ?? [],as:UTF8.self); count += 1; token = nil; return .restored
    }
    func externalCopy(_ text: String) { self.text = text; count += 1; token = nil }
}
@MainActor private final class GCapture: InsertionTargetCapturing {
    var failure: TextTargetError?
    var failureExplanation: String?
    var count = 0
    var configure:(@MainActor (GTarget)->Void)?
    var target: GTarget?
    func capture(session: String) throws -> any InsertionTarget { count += 1; if let failure { throw failure }; let t = GTarget(session:session); configure?(t); target = t; return t }
}
@MainActor private final class GInput: DictationInput, DictationCaptureReporting, DictationRecoveryProviding {
    var unmergedRecognitionText: String?
    var injectedSpeechDiagnostics: DictationSpeechDiagnostics?
    var speechDiagnostics: DictationSpeechDiagnostics? { injectedSpeechDiagnostics }
    var captureDiagnosticSummary: String { injectedSpeechDiagnostics?.summary ?? "fixtureTelemetry=unavailable" }
    var starts = 0, stops = 0, cancels = 0
    var hold = false
    var startFailure: DictationFailure?
    var receive: (@MainActor @Sendable (DictationEvent) -> Void)?
    var waiter: CheckedContinuation<DictationInfo,any Error>?
    var entered: CheckedContinuation<Void,Never>?
    func start(localeIdentifier: String, receive: @escaping @MainActor @Sendable (DictationEvent) -> Void) async throws -> DictationInfo {
        starts += 1; self.receive = receive; entered?.resume(); entered = nil
        if let startFailure { throw startFailure }
        if hold { return try await withCheckedThrowingContinuation { waiter = $0 } }
        return .init(engine:"Fixture Apple Speech",localeIdentifier:localeIdentifier)
    }
    func stop() { stops += 1 }
    func cancel() { cancels += 1 }
    func waitForStart() async { if starts == 0 { await withCheckedContinuation { entered = $0 } } }
    func resolve() { waiter?.resume(returning:.init(engine:"Fixture",localeIdentifier:"en-IN")); waiter = nil }
}
@MainActor private final class GShortcut: DictationShortcutMonitoring {
    var activationContext:DictationActivationContext?
    var receive: (@MainActor @Sendable (DictationShortcutEvent) -> Void)?
    var authorizationReady = true
    var enables = 0, disables = 0
    var configuredKey: DictationActivationKey = .fn
    func configure(key: DictationActivationKey) { configuredKey = key }
    func enable(receive: @escaping @MainActor @Sendable (DictationShortcutEvent) -> Void) throws { enables += 1; guard authorizationReady else { throw DictationShortcutFailure.permissionRequired }; self.receive = receive }
    func disable() { disables += 1; receive = nil }
}
private actor GHistory: DictationHistoryStore {
    var entries: [DictationHistoryEntry] = []
    var observer: CheckedContinuation<Void,Never>?
    var fail = false
    func load() throws -> [DictationHistoryEntry] { if fail { throw DictationHistoryFailure.unavailable }; return entries }
    func append(_ entry: DictationHistoryEntry) throws { if fail { throw DictationHistoryFailure.unavailable }; entries.append(entry); observer?.resume(); observer = nil }
    func delete(id: String) { entries.removeAll { $0.id == id } }
    func clear() { entries = [] }
    func close() {}
    func waitForEntry() async { if entries.isEmpty { await withCheckedContinuation { observer = $0 } } }
    func setFailure() { fail = true }
}
@MainActor private final class GPublicationState { var reject = false }
@MainActor private func preferences() -> DictationPreferenceStore {
    let suite = "WesleyFlow-GlobalTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName:suite)!
    defaults.removePersistentDomain(forName:suite)
    return DictationPreferenceStore(defaults:defaults)
}
@Suite("Verified text insertion",.serialized,.timeLimit(.minutes(1)))
@MainActor struct GlobalInsertionTests {
    @Test(arguments:[Domain.TextSelection(location:0,length:0),.init(location:1,length:1),.init(location:3,length:0)])
    func insertsAtCaretOrSelectionWithoutReplacingWholeField(_ selection: Domain.TextSelection) async {
        let target = GTarget(selection:selection), clipboard = GClipboard()
        let service = TextInsertionService(clipboard:clipboard,clock:GClock())
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(receipt.outcome == .inserted); #expect(target.value == selection.replacing(in:"abc",with:"X"))
        #expect(target.replacements == 1); #expect(clipboard.installed == 0)
    }
    @Test func missingAppAndSystemFocusCanUseAnOwnedWindowFocus() throws {
        let found = try NativeFocusedElementResolver.resolve(processID:42,application:{ Optional<Int>.none },system:{ nil },window:{ 7 },owner:{ _ in 42 })
        #expect(found == 7)
        #expect(throws:TextTargetError.changed) { try NativeFocusedElementResolver.resolve(processID:42,application:{ Optional<Int>.none },system:{ nil },window:{ 7 },owner:{ _ in 99 }) }
    }
    @Test func descendantFocusSearchNeverSelectsAnUnfocusedEditor() {
        #expect(FocusedDescendantSearch.find(root:0,focusedEditor:{ $0 == 3 },children:{ node,_ in node == 0 ? [1,2,3] : [] }) == 3)
        #expect(FocusedDescendantSearch.find(root:0,focusedEditor:{ _ in false },children:{ _,_ in [1,2] }) == nil)
        #expect(FocusedDescendantSearch.find(root:0,permitted:{ false },focusedEditor:{ _ in true },children:{ _,_ in [] }) == nil)
    }
    @Test func descendantFocusSearchBoundsCyclesAndHostileChildCounts() {
        var visits = 0
        #expect(FocusedDescendantSearch.find(root:0,focusedEditor:{ _ in visits += 1; return false },children:{ _,_ in Array(0..<1000) }) == nil)
        #expect(visits <= 64)
        #expect(FocusedDescendantSearch.find(root:0,maximumDepth:0,focusedEditor:{ $0 == 1 },children:{ _,_ in [1] }) == nil)
        #expect(FocusedDescendantSearch.find(root:0,limit:257,focusedEditor:{ _ in true },children:{ _,_ in [] }) == nil)
    }
    @Test func invalidUnicodeCaretIsRejectedWithoutEffects() async {
        let target = GTarget(text:"😀x",selection:.init(location:1,length:0))
        let service = TextInsertionService(clipboard:GClipboard(),clock:GClock())
        #expect(await service.insert("X",target:target,session:"s").outcome == .unsupportedTarget)
        #expect(target.replacements == 0)
        #expect(Domain.TextSelection(location:0,length:2).replacing(in:"😀x",with:"Y") == "Yx")
    }
    @Test(arguments:[TextTargetError.denied,.secure,.unsupported,.changed])
    func changedDeniedSecureAndUnsupportedNeverWrite(_ error: TextTargetError) async {
        let target = GTarget(), clipboard = GClipboard(); target.validationError = error
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(receipt.outcome != .inserted); #expect(!receipt.attempted)
        #expect(target.replacements == 0); #expect(target.pastes == 0); #expect(clipboard.installed == 0)
    }
    @Test func foreignGenerationCannotInsert() async {
        let target = GTarget()
        #expect(await TextInsertionService(clipboard:GClipboard(),clock:GClock()).insert("X",target:target,session:"different").outcome == .targetChanged)
        #expect(target.replacements == 0)
    }
    @Test func failedAXWriteIsUncertainAndNeverRetriesByPaste() async {
        let target = GTarget(); target.failWrite = true
        let receipt = await TextInsertionService(clipboard:GClipboard(),clock:GClock()).insert("X",target:target,session:"s")
        #expect(receipt.outcome == .uncertain); #expect(receipt.attempted); #expect(target.pastes == 0)
    }
    @Test func verifiedPasteRestoresPreviousClipboard() async {
        let target = GTarget(), clipboard = GClipboard(); target.writable = false
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(receipt.outcome == .inserted); #expect(target.pastes == 1); #expect(clipboard.text == "original"); #expect(clipboard.restores == 1)
    }
    @Test func unsupportedClipboardIsNotCleared() async {
        let target = GTarget(), clipboard = GClipboard(); target.writable = false; clipboard.unsupported = true
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(receipt.reason == .clipboardUnsupported); #expect(clipboard.text == "original"); #expect(target.pastes == 0)
    }
    @Test func externalClipboardChangeBeforePublishIsPreserved() async {
        let target = GTarget(), clipboard = GClipboard(); target.writable = false; clipboard.changedBeforeInstall = true
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(receipt.outcome == .denied); #expect(target.pastes == 0); #expect(clipboard.text == "new user clipboard")
    }
    @Test func externalClipboardChangeAtDispatchPreventsPaste() async {
        let target = GTarget(), clipboard = GClipboard(); target.writable = false
        target.beforePaste = { clipboard.externalCopy("newer") }
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(receipt.outcome == .denied); #expect(target.pastes == 0); #expect(clipboard.text == "newer")
    }
    @Test func unacknowledgedPasteRetainsBackupAndNeverClaimsSuccess() async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock(); target.writable = false; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500)
        let receipt = await task.value
        #expect(receipt.outcome == .uncertain); #expect(receipt.reason == .deadline); #expect(service.hasPendingClipboard)
        #expect(clipboard.restores == 0); #expect(clipboard.text == "X")
        clipboard.externalCopy("newer user data")
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:service.pendingClipboardRecovery?.id ?? "missing") == .preservedNewer); #expect(clipboard.text == "newer user data")
    }
    @Test func cancellationAfterPasteRetainsUncertaintyAndRestoresOnlyAfterConfirmation() async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock(); target.writable = false; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); task.cancel()
        let result = await task.value
        #expect(result.outcome == .uncertain); #expect(result.reason == .cancelled); #expect(clipboard.restores == 0)
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:service.pendingClipboardRecovery?.id ?? "missing") == .restored); #expect(clipboard.text == "original")
    }
    @Test func cancellationBeforeDispatchHasNoEffects() async {
        let target = GTarget(), service = TextInsertionService(clipboard:GClipboard(),clock:GClock())
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return await service.insert("X",target:target,session:"s") }
        #expect(await task.value.outcome == .cancelled); #expect(target.replacements == 0); #expect(target.pastes == 0)
    }
    @Test func externallyReplacedClipboardMustNotBlockAFreshDictation() async {
        let first = GTarget(), clipboard = GClipboard(), clock = GClock(); first.writable = false; first.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let initial = Task { await service.insert("X",target:first,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); let uncertain = await initial.value
        #expect(uncertain.outcome == .uncertain); #expect(service.hasPendingClipboard)
        clipboard.externalCopy("new user copy")
        let fresh = GTarget(session:"fresh"); fresh.writable = false
        let result = await service.insert("X",target:fresh,session:"fresh")
        #expect(result.outcome == .inserted); #expect(!service.hasPendingClipboard)
        #expect(fresh.pastes == 1); #expect(first.pastes == 1)
        #expect(clipboard.text == "new user copy"); #expect(clipboard.restores == 1)
    }
    @Test(arguments:[3,10])
    func consecutivePasteSessionsRestoreClipboardAndNeverReplayAnOldTarget(_ count: Int) async {
        let clipboard = GClipboard(), service = TextInsertionService(clipboard:clipboard,clock:GClock())
        var text = "prefix ", expected = text
        var previous: GTarget?
        for index in 0..<count {
            let fragment = "insertion-\(index). "
            let target = GTarget(session:"repeat-\(index)",text:text,selection:.init(location:text.utf16.count,length:0)); target.writable = false; target.pasted = fragment
            let receipt = await service.insert(fragment,target:target,session:target.info.session)
            expected += fragment; text = target.value ?? ""
            #expect(receipt.status == .insertedVerified); #expect(text == expected)
            #expect(!service.hasPendingClipboard); #expect(clipboard.text == "original")
            #expect(clipboard.installed == index+1); #expect(clipboard.restores == index+1); #expect(target.pastes == 1)
            if let previous {
                previous.validationError = .changed // simulated old AX node invalidation/rerender
                let stale = await service.insert("stale",target:previous,session:previous.info.session)
                #expect(stale.status == .targetChanged); #expect(previous.pastes == 1)
                #expect(clipboard.text == "original"); #expect(target.value == expected)
            }
            previous = target
        }
    }
    @Test func anOldConfirmationCannotRestoreTheNextSessionsClipboard() async throws {
        let clipboard = GClipboard(), clock = GClock()
        // One controlled clock for independent pending dispatches.
        let firstService = TextInsertionService(clipboard:clipboard,clock:clock)
        let first = GTarget(); first.writable = false; first.acknowledgePaste = false
        let a = Task { await firstService.insert("X",target:first,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); _ = await a.value
        let old = try #require(firstService.pendingClipboardRecovery)
        #expect(firstService.restoreAfterUserConfirmation(expectedRecoveryID:old.id) == .restored)
        let second = GTarget(session:"second"); second.writable = false; second.acknowledgePaste = false
        let b = Task { await firstService.insert("X",target:second,session:"second") }
        await clock.waitForSleep(2550); await clock.advance(4000); _ = await b.value
        let current = try #require(firstService.pendingClipboardRecovery), attempts = clipboard.restorationAttempts
        #expect(current.session == "second"); #expect(current.dispatched); #expect(current.id != old.id)
        #expect(firstService.restoreAfterUserConfirmation(expectedRecoveryID:old.id) == .unavailable)
        #expect(firstService.pendingClipboardRecovery == current); #expect(clipboard.restorationAttempts == attempts); #expect(clipboard.text == "X")
        #expect(firstService.restoreAfterUserConfirmation(expectedRecoveryID:current.id) == .restored)
        #expect(clipboard.text == "original"); #expect(!firstService.hasPendingClipboard)
    }
    @Test func unreadableOwnershipWithoutANewRevisionDoesNotRetireBackup() async throws {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock(); target.writable = false; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); _ = await task.value
        let recovery = try #require(service.pendingClipboardRecovery)
        clipboard.ownershipReadable = false
        #expect(service.reconcileClipboardState() == nil); #expect(service.hasPendingClipboard)
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:recovery.id) == .unavailable)
        #expect(service.pendingClipboardRecovery == recovery); #expect(clipboard.text == "X")
        clipboard.ownershipReadable = true
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:recovery.id) == .restored)
    }
    @Test func anActivePasteCannotBeOverlappedOrRestoredByAnotherSession() async {
        let first = GTarget(), clipboard = GClipboard(), clock = GClock(); first.writable = false; first.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:first,session:"s") }
        await clock.waitForSleep(1050)
        let second = GTarget(session:"second"); second.writable = false
        let blocked = await service.insert("X",target:second,session:"second")
        #expect(!blocked.attempted); #expect(second.pastes == 0); #expect(clipboard.installed == 1)
        #expect(service.reconcileClipboardState() == nil)
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:"stale") == .unavailable)
        task.cancel(); let receipt = await task.value
        #expect(receipt.outcome == .uncertain); #expect(receipt.reason == .cancelled)
        #expect(service.pendingClipboardRecovery?.session == "s"); #expect(first.pastes == 1)
    }
    @Test(arguments:[
        (TextInsertionReceipt(.inserted,.verified,attempted:true),TextInsertionStatus.insertedVerified),
        (.init(.uncertain,.deadline,attempted:true),.dispatchedUnverified),
        (.init(.targetChanged,.changed),.targetChanged),(.init(.unsupportedTarget,.unsupported),.unsupportedTarget),
        (.init(.denied,.permission),.permissionDenied),(.init(.cancelled,.cancelled),.cancelled),
        (.init(.denied,.clipboardPending),.failed),(.init(.uncertain,.cancelled,attempted:true),.uncertain)
    ])
    func explicitStatusDoesNotConfuseDispatchWithVerification(_ item: (TextInsertionReceipt,TextInsertionStatus)) throws {
        #expect(item.0.status == item.1)
        let decoded = try JSONDecoder().decode(TextInsertionReceipt.self,from:JSONEncoder().encode(item.0))
        #expect(decoded == item.0); #expect(decoded.status == item.1)
    }
    @Test func pendingPasteBlocksAnotherClipboardOverwrite() async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock(); target.writable = false; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); _ = await task.value
        let next = GTarget(); next.writable = false
        let receipt = await service.insert("second",target:next,session:"s")
        #expect(receipt.reason == .clipboardPending); #expect(clipboard.installed == 1); #expect(next.pastes == 0)
    }
    @Test func unavailableRestorationRetainsBackupUntilConfirmedRetry() async {
        let target = GTarget(), clipboard = GClipboard(); target.writable = false; clipboard.restoreFails = true
        let service = TextInsertionService(clipboard:clipboard,clock:GClock())
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(receipt.outcome == .inserted); #expect(receipt.clipboardPending); #expect(service.hasPendingClipboard)
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:service.pendingClipboardRecovery?.id ?? "missing") == .unavailable)
        clipboard.restoreFails = false
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:service.pendingClipboardRecovery?.id ?? "missing") == .restored); #expect(!service.hasPendingClipboard)
    }
    @Test func systemFocusFallbackNeverCrossesTheCapturedProcess() throws {
        let element = try NativeFocusedElementResolver.resolve(processID:42,application:{ nil as Int? },system:{ 7 },owner:{ _ in 42 })
        #expect(element == 7)
        #expect(throws:TextTargetError.self) { try NativeFocusedElementResolver.resolve(processID:42,application:{ nil as Int? },system:{ 7 },owner:{ _ in 99 }) }
        #expect(throws:TextTargetError.self) { try NativeFocusedElementResolver.resolve(processID:42,application:{ 5 },system:{ 7 },owner:{ $0 == 5 ? 99 : 42 }) }
        #expect(throws:TextTargetError.self) { try NativeFocusedElementResolver.resolve(processID:42,application:{ nil as Int? },system:{ nil },owner:{ _ in nil }) }
        let direct = try NativeFocusedElementResolver.resolve(processID:42,application:{ 5 },system:{ Issue.record("Must not redirect an existing focus observation"); return 7 },owner:{ _ in 42 })
        #expect(direct == 5)
    }
    @Test func selectionEditableFieldCanUseVerifiedPasteWithoutAXTextWrites() async {
        #expect(NativeEditorCapability.accepts(enabled:true,editable:nil,writableText:false,writableSelection:true,console:false))
        let target = GTarget(), clipboard = GClipboard(); target.writable = false
        let result = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(result.outcome == .inserted); #expect(target.pastes == 1); #expect(target.replacements == 0)
        #expect(clipboard.restores == 1); #expect(target.value == "aXbc")
    }
    @Test(arguments:[false,true])
    func explicitReadOnlyAndDisabledFieldsStayExcluded(_ disabled: Bool) {
        #expect(!NativeEditorCapability.accepts(enabled:disabled ? false : true,editable:disabled ? nil : false,writableText:true,writableSelection:true,console:false))
    }
    @Test func missingCapabilitiesAndConsoleSelectionAreNotEditorAuthority() {
        #expect(!NativeEditorCapability.accepts(enabled:nil,editable:nil,writableText:false,writableSelection:false,console:false))
        #expect(!NativeEditorCapability.accepts(enabled:true,editable:nil,writableText:false,writableSelection:true,console:true))
        #expect(NativeEditorCapability.isConsole("com.apple.Terminal")); #expect(NativeEditorCapability.isConsole("com.googlecode.iterm2"))
        #expect(!NativeEditorCapability.isConsole(nil))
    }
    @Test func chatGPTSelectsPasteBeforeAnyDirectAttempt() async {
        let target = GTarget(), clipboard = GClipboard()
        target.writable = NativeEditorCapability.allowsDirectTextReplacement("com.openai.codex"); target.failWrite = true
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(receipt.outcome == .inserted); #expect(target.replacements == 0); #expect(target.pastes == 1); #expect(target.unicodePosts == 0)
        #expect(clipboard.text == "original"); #expect(clipboard.restores == 1)
        #expect(NativeEditorCapability.allowsDirectTextReplacement("net.whatsapp.WhatsApp"))
        #expect(NativeEditorCapability.allowsDirectTextReplacement(nil))
    }
    @Test func uncertainChatGPTPasteDoesNotRetryAnotherMethod() async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.writable = NativeEditorCapability.allowsDirectTextReplacement("com.openai.codex")
        target.acknowledgePaste = false; target.unicodeSupported = true
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); let receipt = await task.value
        #expect(receipt.outcome == .uncertain); #expect(receipt.clipboardPending)
        #expect(target.pastes == 1); #expect(target.unicodePosts == 0); #expect(target.replacements == 0)
        #expect(service.failureExplanation?.hasPrefix("Paste was attempted") == true)
    }
    @Test func uncertainDirectUpdateReportsRouteWithoutRetrying() async {
        let target = GTarget(), clipboard = GClipboard(); target.failWrite = true; target.unicodeSupported = true
        let service = TextInsertionService(clipboard:clipboard,clock:GClock())
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(receipt.outcome == .uncertain); #expect(target.replacements == 1)
        #expect(target.pastes == 0); #expect(target.unicodePosts == 0)
        #expect(service.failureExplanation?.contains("direct text update") == true)
    }
    @Test(arguments:[0,1,2])
    func pasteObservationDiagnosticsNeverExposeText(_ observation: Int) async {
        let target = GTarget(text:"PRIVATE ORIGINAL",selection:.init(location:0,length:0)), clipboard = GClipboard(), clock = GClock()
        target.writable = false; target.acknowledgePaste = false
        if observation == 1 { target.value = nil }; if observation == 2 { target.value = "PRIVATE DIFFERENT" }
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("PRIVATE INSERT",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); let receipt = await task.value
        let explanation = service.failureExplanation ?? ""
        #expect(receipt.outcome == .uncertain); #expect(receipt.clipboardPending)
        #expect(!explanation.contains("PRIVATE")); #expect(target.pastes == 1); #expect(clipboard.restores == 0)
        if observation == 0 { #expect(explanation.contains("pre-paste text")) }
        if observation == 1 { #expect(explanation.contains("stopped exposing readable text")) }
        if observation == 2 { #expect(explanation.contains("expected 30 UTF-16 units; observed 17")) }
    }
    @Test func boundUnicodeDeliveryNeverRetargetsAfterIdentityLoss() {
        var posted: [Int] = []
        #expect(NativeBoundTextDelivery.dispatch(count:3,permitted:{ posted.isEmpty },send:{ posted.append($0) }))
        #expect(posted == [0])
        #expect(!NativeBoundTextDelivery.dispatch(count:3,permitted:{ false },send:{ _ in Issue.record("No dispatch before validation") }))
        #expect(!NativeBoundTextDelivery.dispatch(count:257,permitted:{ true },send:{ _ in Issue.record("Bound exceeded") }))
    }
    @Test func boundUnicodeDeliveryStopsOnCancellationOrDeadlineSignal() {
        var allowed = true, posted = 0
        #expect(NativeBoundTextDelivery.dispatch(count:3,permitted:{ allowed },send:{ _ in posted += 1; allowed = false }))
        #expect(posted == 1)
        #expect(!NativeBoundTextDelivery.dispatch(count:0,permitted:{ true },send:{ _ in Issue.record("Empty input") }))
    }
    @Test func targetChangeDuringClipboardInspectionStopsTyping() async {
        let target = GTarget(), clipboard = GClipboard(); target.writable = false; target.unicodeSupported = true; clipboard.unsupported = true
        clipboard.beforeSnapshot = { target.validationError = .changed }
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("draft",target:target,session:"s")
        #expect(receipt.outcome == .targetChanged); #expect(!receipt.attempted); #expect(target.unicodePosts == 0)
        #expect(clipboard.installed == 0); #expect(clipboard.text == "original")
    }
    @Test func unsupportedClipboardCanUseVerifiedTypingWithoutChangingClipboard() async {
        let target = GTarget(), clipboard = GClipboard(); target.writable = false; target.unicodeSupported = true; clipboard.unsupported = true
        let service = TextInsertionService(clipboard:clipboard,clock:GClock())
        let receipt = await service.insert("draft",target:target,session:"s")
        #expect(receipt.outcome == .inserted); #expect(receipt.attempted); #expect(!receipt.clipboardPending)
        #expect(target.value == "adraftbc"); #expect(target.unicodePosts == 1); #expect(target.pastes == 0)
        #expect(clipboard.text == "original"); #expect(clipboard.installed == 0); #expect(clipboard.restores == 0)
    }
    @Test func unacknowledgedTypingDoesNotClaimSuccessOrCreateClipboardLease() async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.writable = false; target.unicodeSupported = true; target.unicodeAcknowledged = false; clipboard.unsupported = true
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("draft",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500)
        let receipt = await task.value
        #expect(receipt.outcome == .uncertain); #expect(receipt.attempted); #expect(!receipt.clipboardPending)
        #expect(!service.hasPendingClipboard); #expect(clipboard.text == "original")
    }
    @Test func cancelledTypingRetainsUncertaintyWithoutClipboardMutation() async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.writable = false; target.unicodeSupported = true; target.unicodeAcknowledged = false; clipboard.unsupported = true
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("draft",target:target,session:"s") }
        await clock.waitForSleep(1050); task.cancel(); let receipt = await task.value
        #expect(receipt.outcome == .uncertain); #expect(receipt.reason == .cancelled); #expect(receipt.attempted)
        #expect(!service.hasPendingClipboard); #expect(clipboard.installed == 0)
    }
    @Test(arguments:["hello","नमस्ते","abc😀👩‍💻"+String(repeating:"x",count:40)])
    func nativeUnicodeConstructionPreservesTextWithoutReturnOrModifiers(_ text: String) throws {
        let pairs = try #require(NativeUnicodeKeystrokes.make(text)); var reconstructed: [UniChar] = []
        for (down,up) in pairs {
            #expect(down.type == .keyDown); #expect(up.type == .keyUp)
            #expect(down.flags.isEmpty); #expect(up.flags.isEmpty)
            #expect(down.getIntegerValueField(.keyboardEventKeycode) == 0)
            var units = [UniChar](repeating:0,count:16), count = 0
            down.keyboardGetUnicodeString(maxStringLength:16,actualStringLength:&count,unicodeString:&units)
            #expect(count > 0 && count <= 16); reconstructed.append(contentsOf:units.prefix(count))
            #expect(String(bytes:units.prefix(count).flatMap { [UInt8($0&255),UInt8($0>>8)] },encoding:.utf16LittleEndian) != nil)
        }
        #expect(String(decoding:reconstructed,as:UTF16.self) == text)
    }
    @Test(arguments:["","line\nbreak","line\rbreak","\t","\u{1B}","\u{7F}","\u{85}","\u{2028}","\u{2029}",String(repeating:"a",count:4097)])
    func nativeUnicodeRejectsControlsAndOversizedInput(_ text: String) { #expect(NativeUnicodeKeystrokes.make(text) == nil) }
    @Test func appleTerminalManualCopyPolicyIsExplicit() {
        #expect(!NativeEditorCapability.allowsAutomaticInsertion("com.apple.Terminal"))
        #expect(NativeEditorCapability.allowsAutomaticInsertion("com.openai.chat"))
    }
    @Test func previousSessionClipboardMarkerRoundTripsWithoutAdoptingAuthority() throws {
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        pb.setString("before",forType:.string)
        let first = NativeDictationPasteboard(pasteboard:pb)
        let original = try first.snapshot(), old = try first.install("pending draft",replacing:original)
        let second = NativeDictationPasteboard(pasteboard:pb), recovered = try second.snapshot()
        #expect(recovered.items.first?["local.wesleyflow.dictation-owner"] != nil)
        let current = try second.install("new draft",replacing:recovered)
        #expect(current.token != old.token); #expect(!first.owns(old)); #expect(second.owns(current))
        #expect(second.restore(recovered,ifOwned:current) == .restored)
        #expect(pb.string(forType:.string) == "pending draft"); #expect(!first.owns(old)); #expect(!second.owns(current))
    }
    @Test func privateClipboardFormatsAreRejectedBeforeReadingOrClearingPayload() {
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem(); let type = NSPasteboard.PasteboardType("com.example.private-format")
        item.setData(Data("synthetic private payload".utf8),forType:type); pb.writeObjects([item]); let before = pb.changeCount
        let native = NativeDictationPasteboard(pasteboard:pb)
        #expect(throws:(any Error).self) { try native.snapshot() }
        #expect(pb.changeCount == before); #expect(native.snapshotFailureExplanation?.contains(type.rawValue) == true)
        #expect(native.snapshotFailureExplanation?.contains("synthetic private payload") == false)
        #expect(pb.data(forType:type) == Data("synthetic private payload".utf8))
    }
    @Test func invalidPreviousOwnerMarkerIsRejectedWithoutClipboardChanges() {
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem(); item.setString("draft",forType:.string)
        item.setString("not a UUID",forType:.init("local.wesleyflow.dictation-owner")); pb.writeObjects([item]); let before = pb.changeCount
        let native = NativeDictationPasteboard(pasteboard:pb)
        #expect(throws:(any Error).self) { try native.snapshot() }; #expect(pb.changeCount == before)
        #expect(native.snapshotFailureExplanation?.contains("invalid Wesley Flow marker") == true)
    }
    @Test func standardUTF16RepresentationRoundTrips() throws {
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("public.utf16-plain-text"), item = NSPasteboardItem()
        let bytes = Data([0x41,0,0x42,0]); item.setData(bytes,forType:type); pb.writeObjects([item])
        let native = NativeDictationPasteboard(pasteboard:pb), snapshot = try native.snapshot()
        let ownership = try native.install("draft",replacing:snapshot)
        #expect(native.restore(snapshot,ifOwned:ownership) == .restored); #expect(pb.data(forType:type) == bytes)
    }
    @Test func explicitlyEmptyEditorDoesNotRequireAZeroLengthRangeResponse() {
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ 0 },range:{ _ in Issue.record("Zero-length range must not be needed"); return nil }) == "")
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ nil },range:{ _ in "" }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ 1 },range:{ _ in "" }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:-1,value:{ "" },characterCount:{ 0 },range:{ _ in "" }) == nil)
    }
    @Test(arguments:["abc","😀","नमस्ते"])
    func attributedRangeFallbackRequiresCompleteText(_ text: String) {
        #expect(NativeFieldTextReader.read(maximumBytes:64,value:{ nil },characterCount:{ text.utf16.count },range:{ _ in nil },attributedRange:{ $0 == text.utf16.count ? text : nil }) == text)
        #expect(NativeFieldTextReader.read(maximumBytes:64,value:{ nil },characterCount:{ text.utf16.count+1 },range:{ _ in nil },attributedRange:{ _ in text }) == nil)
    }
    @Test func attributedFallbackCannotHidePartialOrOversizedValues() {
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ 3 },range:{ _ in "ab" },attributedRange:{ _ in Issue.record("Partial primary result must fail closed"); return "abc" }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:3,value:{ nil },characterCount:{ 2 },range:{ _ in nil },attributedRange:{ _ in "😀" }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:3,value:{ "abcd" },characterCount:{ 3 },range:{ _ in "abc" },attributedRange:{ _ in "abc" }) == nil)
    }
    @Test func characterCountMustBeAnExactNumberRatherThanBooleanOrFraction() {
        #expect(NativeFieldTextReader.characterCount(NSNumber(value:0)) == 0)
        #expect(NativeFieldTextReader.characterCount(NSNumber(value:3)) == 3)
        #expect(NativeFieldTextReader.characterCount(kCFBooleanFalse) == nil)
        #expect(NativeFieldTextReader.characterCount(NSNumber(value:0.5)) == nil)
        #expect(NativeFieldTextReader.characterCount(NSNumber(value:Double.infinity)) == nil)
        #expect(NativeFieldTextReader.characterCount(nil) == nil)
    }
    @Test func attributedValueTypeAndReadFailureDiagnosticsAreSafe() throws {
        let value = try #require(CFAttributedStringCreate(nil,"hello 😀" as CFString,nil))
        #expect(NativeFieldTextReader.plainAttributedText(value) == "hello 😀")
        #expect(NativeFieldTextReader.plainAttributedText("not attributed" as CFString) == nil)
        #expect(NativeFieldTextReader.plainAttributedText(nil) == nil)
        var message = ""
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ nil },range:{ _ in nil },failure:{ message = $0 }) == nil)
        #expect(message.contains("character count"))
        message = ""
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ "private transcript" },characterCount:{ nil },range:{ _ in nil },failure:{ message = $0 }) == nil)
        #expect(!message.contains("private transcript")); #expect(message.contains("size limit"))
    }
    @Test func rangeTextFallbackRequiresCompleteBoundedUTF16Representation() {
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ "abc" },characterCount:{ Issue.record("Existing value must not trigger another read"); return nil },range:{ _ in nil }) == "abc")
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ 3 },range:{ $0 == 3 ? "abc" : nil }) == "abc")
        #expect(NativeFieldTextReader.read(maximumBytes:4,value:{ nil },characterCount:{ 2 },range:{ _ in "😀" }) == "😀")
        #expect(NativeFieldTextReader.read(maximumBytes:3,value:{ nil },characterCount:{ 2 },range:{ _ in "😀" }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ 9 },range:{ _ in Issue.record("Oversized range must never be queried"); return nil }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ -1 },range:{ _ in Issue.record("Negative range must never be queried"); return nil }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ 3 },range:{ _ in "ab" }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:8,value:{ nil },characterCount:{ 3 },range:{ _ in nil }) == nil)
        #expect(NativeFieldTextReader.read(maximumBytes:2,value:{ "abc" },characterCount:{ 2 },range:{ _ in Issue.record("Do not hide an oversized value by truncating it"); return "ab" }) == nil)
    }
    @Test func nativePasteEventsContainOnlyCommandVAndNoReturn() throws {
        let events = try NativePasteKeystrokes.make()
        #expect(events.count == 2); #expect(events.map(\.type) == [.keyDown,.keyUp])
        #expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 9 && $0.flags == .maskCommand })
    }
    @Test func nativePublicationFailureRestoresBackupWithoutDispatch() async throws {
        let pb = NSPasteboard(name:.init("WesleyFlow-Fixture-\(UUID().uuidString)")); defer { pb.releaseGlobally() }
        pb.clearContents(); pb.setString("previous",forType:.string)
        let publication = GPublicationState(); publication.reject = true
        let native = NativeDictationPasteboard(pasteboard:pb,publication: { items in
            if publication.reject { publication.reject = false; return false }; return pb.writeObjects(items)
        })
        let target = GTarget(); target.writable = false
        let service = TextInsertionService(clipboard:native,clock:GClock())
        let result = await service.insert("X",target:target,session:"s")
        #expect(result.outcome == .denied); #expect(target.pastes == 0); #expect(pb.string(forType:.string) == "previous"); #expect(!service.hasPendingClipboard)
    }
    @Test func nativeRestoreFailureCanRetryWithoutOverwritingNewerContent() throws {
        let pb = NSPasteboard(name:.init("WesleyFlow-Fixture-\(UUID().uuidString)")); defer { pb.releaseGlobally() }
        pb.clearContents(); pb.setString("previous",forType:.string)
        let publication = GPublicationState()
        let native = NativeDictationPasteboard(pasteboard:pb,publication: { items in publication.reject ? false : pb.writeObjects(items) })
        let snapshot = try native.snapshot(), lease = try native.install("X",replacing:snapshot)
        publication.reject = true; #expect(native.restore(snapshot,ifOwned:lease) == .unavailable); #expect(native.owns(lease))
        publication.reject = false; #expect(native.restore(snapshot,ifOwned:lease) == .restored); #expect(pb.string(forType:.string) == "previous")
        let next = try native.snapshot(), nextLease = try native.install("Y",replacing:next)
        publication.reject = true; #expect(native.restore(next,ifOwned:nextLease) == .unavailable)
        pb.clearContents(); pb.setString("newer",forType:.string); publication.reject = false
        #expect(native.restore(next,ifOwned:nextLease) == .preservedNewer); #expect(pb.string(forType:.string) == "newer")
    }
    @Test func nativePrivatePasteboardPreservesMultipleRepresentationsAndNewerCopies() throws {
        let pb = NSPasteboard(name:.init("WesleyFlow-Fixture-\(UUID().uuidString)")); defer { pb.releaseGlobally() }
        let item = NSPasteboardItem(); item.setString("previous",forType:.string); item.setString("<b>previous</b>",forType:.html)
        pb.clearContents(); #expect(pb.writeObjects([item]))
        let native = NativeDictationPasteboard(pasteboard:pb), snapshot = try native.snapshot()
        let ownership = try native.install("dictation",replacing:snapshot)
        #expect(native.restore(snapshot,ifOwned:ownership) == .restored)
        #expect(pb.string(forType:.string) == "previous"); #expect(pb.string(forType:.html) == "<b>previous</b>")
        let next = try native.snapshot(), lease = try native.install("dictation",replacing:next)
        pb.clearContents(); pb.setString("external update",forType:.string)
        #expect(native.restore(next,ifOwned:lease) == .preservedNewer); #expect(pb.string(forType:.string) == "external update")
    }
}
@Suite("Global dictation coordination",.serialized,.timeLimit(.minutes(1)))
@MainActor struct GlobalCoordinatorTests {
    private func world(input: GInput = GInput(), capture: GCapture = GCapture(), clock: GClock = GClock(), history: GHistory = GHistory()) -> SystemWideDictationCoordinator {
        SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history)
    }
    private func waitForTerminal(_ coordinator: SystemWideDictationCoordinator) async {
        await coordinator.waitForInsertionCompletion()
    }
    @Test func pendingClipboardStopsRecordingBeforeAnyCaptureAndPreservesDiagnosis() async throws {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.writable = false; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); _ = await task.value
        let input = GInput(), capture = GCapture(), shortcut = GShortcut(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:service,shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        coordinator.enableShortcut(); shortcut.receive?(.pressed); shortcut.receive?(.released)
        #expect(coordinator.phase == .error); #expect(!coordinator.busy); #expect(coordinator.pillVisible); #expect(coordinator.pillContent == .label("Review clipboard"))
        #expect(coordinator.clipboardPending); #expect(input.starts == 0); #expect(capture.count == 0)
        #expect(coordinator.message.contains("pre-paste text")); #expect(coordinator.message.contains("Recording was not started"))
        #expect(try await history.load().isEmpty); #expect(clipboard.restores == 0)
        #expect(!coordinator.canTerminateSafely()); #expect(service.hasPendingClipboard)
        coordinator.restoreClipboardAfterConfirmation(expectedRecoveryID:coordinator.clipboardRecoveryID); #expect(!coordinator.clipboardPending)
        #expect(coordinator.canTerminateSafely())
        #expect(clipboard.text == "original"); coordinator.close()
    }
    @Test func shortHoldCancelsBeforeMicrophoneAndHeldGestureStartsOnce() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history,minimumHoldMilliseconds:250)
        coordinator.enableShortcut(); shortcut.receive?(.pressed); await clock.waitForSleep(1250)
        #expect(capture.count == 1); #expect(input.starts == 0); #expect(coordinator.pillVisible)
        shortcut.receive?(.released); await waitForTerminal(coordinator)
        #expect(input.starts == 0); #expect(capture.target?.replacements == 0)
        await clock.advance(2000)
        shortcut.receive?(.pressed); shortcut.receive?(.pressed); await clock.waitForSleep(2250)
        await clock.advance(2250); await coordinator.waitUntilRecording()
        #expect(input.starts == 1); #expect(capture.count == 2)
        input.receive?(.transcript("hello")); shortcut.receive?(.released); input.receive?(.finished); await waitForTerminal(coordinator)
        #expect(capture.target?.replacements == 1); coordinator.close()
    }
    @Test func optionalPillCapturesBeforeStartupWithoutActivatingAWindow() async {
        let input = GInput(), capture = GCapture(), clock = GClock()
        let coordinator = world(input:input,capture:capture,clock:clock)
        #expect(!coordinator.pillVisible); coordinator.preferences.idlePillEnabled = true
        #expect(coordinator.pillVisible); coordinator.pillClicked(); #expect(capture.count == 1)
        await coordinator.waitUntilRecording(); coordinator.pillClicked(); input.receive?(.transcript("hello")); input.receive?(.finished)
        await waitForTerminal(coordinator); #expect(capture.target?.value == "ahellobc")
        #expect(coordinator.pillVisible); coordinator.close(); #expect(!coordinator.pillVisible)
    }
    @Test func finalFormattingKeepsRawAndNeverInsertsHypotheses() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory()
        let coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.preferences.formatting.spokenPunctuation = true; coordinator.preferences.formatting.sentenceCapitalization = true
        coordinator.pillClicked(); await coordinator.waitUntilRecording()
        input.receive?(.transcript("volatile")); input.receive?(.transcript("hello comma world"))
        #expect(capture.target?.replacements == 0); coordinator.stop(); input.receive?(.finished)
        await waitForTerminal(coordinator)
        #expect(coordinator.latest?.raw == "hello comma world"); #expect(coordinator.latest?.cleaned == "Hello, world")
        #expect(capture.target?.replacements == 1); coordinator.close()
    }
    @Test func changingKeyFencesOldCallbacksAndPermissionLossStopsNewGeneration() {
        let capture = GCapture(), shortcut = GShortcut()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        coordinator.enableShortcut(); let old = shortcut.receive
        coordinator.changeActivationKey(.rightCommand)
        #expect(shortcut.configuredKey == .rightCommand); #expect(coordinator.shortcutEnabled)
        old?(.pressed); #expect(capture.count == 0)
        shortcut.authorizationReady = false; coordinator.refreshPermissions()
        #expect(!coordinator.shortcutEnabled); shortcut.receive?(.pressed); #expect(capture.count == 0)
        coordinator.close()
    }
    @Test func repeatedSessionsIgnoreOldSpeechCompletionsAndRetainCurrentTarget() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory()
        let coordinator = world(input:input,capture:capture,clock:clock,history:history)
        var old: (@MainActor @Sendable (DictationEvent) -> Void)?
        for index in 0..<3 {
            coordinator.pillClicked()
            await coordinator.waitUntilRecording()
            let target = capture.target
            input.receive?(.transcript("fresh \(index)")); old?(.transcript("STALE")); old?(.finished)
            #expect(coordinator.raw == "fresh \(index)"); #expect(target?.replacements == 0)
            old = input.receive
            coordinator.stop(); input.receive?(.finished); await waitForTerminal(coordinator)
            #expect(target?.value == "afresh \(index)bc"); #expect(target?.replacements == 1)
            #expect(coordinator.latest?.insertion.status == .insertedVerified)
        }
        #expect(capture.count == 3); coordinator.close()
    }
    @Test func focusLossAfterTranscriptionNeverRedirectsToTheNextField() async {
        let input = GInput(), capture = GCapture(), clock = GClock()
        let coordinator = world(input:input,capture:capture,clock:clock)
        coordinator.pillClicked(); await coordinator.waitUntilRecording()
        input.receive?(.transcript("synthetic draft")); capture.target?.validationError = .changed
        coordinator.stop(); input.receive?(.finished); await waitForTerminal(coordinator)
        #expect(coordinator.latest?.insertion.status == .targetChanged)
        #expect(capture.count == 1); #expect(capture.target?.replacements == 0); #expect(capture.target?.pastes == 0)
        coordinator.close()
    }
    @Test func aNewCopyUnblocksRecordingWithoutRetryingTheOldTranscript() async {
        let old = GTarget(), clipboard = GClipboard(), clock = GClock(); old.writable = false; old.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let initial = Task { await service.insert("X",target:old,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); _ = await initial.value
        let input = GInput(), capture = GCapture(), shortcut = GShortcut()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:service,shortcut:shortcut,clock:clock,preferenceStore:preferences())
        coordinator.enableShortcut(); shortcut.receive?(.pressed); shortcut.receive?(.released)
        #expect(input.starts == 0); #expect(coordinator.clipboardPending)
        clipboard.externalCopy("newer clipboard")
        shortcut.receive?(.pressed); await coordinator.waitUntilRecording()
        input.receive?(.transcript("fresh")); shortcut.receive?(.released); input.receive?(.finished)
        await waitForTerminal(coordinator)
        #expect(coordinator.latest?.raw == "fresh"); #expect(coordinator.latest?.insertion.status == .insertedVerified)
        #expect(input.starts == 1); #expect(capture.count == 1); #expect(old.pastes == 1)
        #expect(clipboard.text == "newer clipboard"); #expect(clipboard.restores == 0)
        #expect(!coordinator.clipboardPending); coordinator.close()
    }
    @Test(arguments:AppOpeningCommand.allCases)
    func exactAppCommandsOnly(_ command: AppOpeningCommand) {
        #expect(AppOpeningCommand.parse("  OPEN \(command.rawValue)!  ") == command)
    }
    @Test(arguments:["open WhatsApp and send hello","open /bin/sh","open https://example.com","delete files","open Terminal","open browser; rm -rf /","please open settings",String(repeating:"a",count:129)])
    func unregisteredCommandsAreRejected(_ text: String) { #expect(AppOpeningCommand.parse(text) == nil) }
    @Test func appLaunchFailureIsReportedWithoutSuccess() async {
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),appOpener:{ command in requests.append(command); throw CocoaError(.fileNoSuchFile) })
        await coordinator.openApp(.whatsapp)
        #expect(requests == [.whatsapp]); #expect(coordinator.phase == .error)
        #expect(coordinator.commandStatus.contains("Could not open")); coordinator.close()
    }
    @Test func separateAgentGestureNeverInsertsCommandText() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), agent = GShortcut(), history = GHistory()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },clock:clock,preferenceStore:preferences(),history:history,appOpener:{ requests.append($0) })
        coordinator.personalAgentQueueURL = FileManager.default.temporaryDirectory.appendingPathComponent("wesley39-voice-" + UUID().uuidString).appendingPathComponent("queue.json")
        defer { if let url = coordinator.personalAgentQueueURL { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) } }
        coordinator.enableShortcut(); coordinator.enableAgentShortcut()
        agent.receive?(.pressed); await coordinator.waitUntilRecording()
        #expect(!coordinator.commandArmed); #expect(capture.count == 0); #expect(coordinator.message.contains("Agent listening"))
        input.receive?(.transcript("open WhatsApp")); agent.receive?(.released); input.receive?(.finished)
        await waitForTerminal(coordinator)
        #expect(requests.isEmpty); #expect(coordinator.agentPlan?.steps.first?.tool == .openApp); #expect(coordinator.phase == .success); #expect(try await history.load().isEmpty)
        #expect(!coordinator.commandArmed); coordinator.close()
    }
    @Test func unarmedCommandWordsRemainDictation() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), agent = GShortcut(), history = GHistory()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },clock:clock,preferenceStore:preferences(),history:history,appOpener:{ requests.append($0) })
        coordinator.enableShortcut(); shortcut.receive?(.pressed); await coordinator.waitUntilRecording()
        input.receive?(.transcript("open browser")); shortcut.receive?(.released); input.receive?(.finished)
        await waitForTerminal(coordinator)
        #expect(requests.isEmpty); #expect(capture.count == 1)
        #expect(capture.target?.value == "aopen browserbc"); coordinator.close()
    }
    @Test func closingBeforeQueuedVoiceDispatchPreventsOpening() async {
        let input = GInput(), clock = GClock(), shortcut = GShortcut(), agent = GShortcut()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },clock:clock,preferenceStore:preferences(),appOpener:{ requests.append($0) })
        coordinator.personalAgentQueueURL = FileManager.default.temporaryDirectory.appendingPathComponent("wesley39-voice-" + UUID().uuidString).appendingPathComponent("queue.json")
        defer { if let url = coordinator.personalAgentQueueURL { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) } }
        coordinator.enableShortcut(); coordinator.enableAgentShortcut(); agent.receive?(.pressed); await coordinator.waitUntilRecording()
        input.receive?(.transcript("open settings")); agent.receive?(.released); input.receive?(.finished); coordinator.close()
        // Join the cancelled dispatch task explicitly; no sleeps or scheduler guesses.
        await coordinator.waitForCommandDispatch()
        #expect(requests.isEmpty)
    }
    @Test(arguments:[false,true])
    func unknownOrCancelledVoiceCommandsHaveNoEffects(_ cancelled: Bool) async {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), agent = GShortcut()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },clock:clock,preferenceStore:preferences(),appOpener:{ requests.append($0) })
        coordinator.personalAgentQueueURL = FileManager.default.temporaryDirectory.appendingPathComponent("wesley39-voice-" + UUID().uuidString).appendingPathComponent("queue.json")
        defer { if let url = coordinator.personalAgentQueueURL { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) } }
        coordinator.enableShortcut(); coordinator.enableAgentShortcut(); agent.receive?(.pressed); await coordinator.waitUntilRecording()
        input.receive?(.transcript(cancelled ? "open settings" : "open settings and delete everything"))
        if cancelled { coordinator.cancel() } else { agent.receive?(.released); input.receive?(.finished) }
        await coordinator.waitForCommandDispatch()
        #expect(requests.isEmpty); #expect(capture.count == 0); #expect(!coordinator.commandArmed); coordinator.close()
    }
    @Test func disablingAgentDoesNotDisableDictation() {
        let input = GInput(), dictation = GShortcut(), agent = GShortcut()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:dictation,agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },preferenceStore:preferences())
        coordinator.enableShortcut(); coordinator.enableAgentShortcut(); coordinator.disableAgentShortcut()
        #expect(coordinator.shortcutEnabled); #expect(!coordinator.agentShortcutEnabled); coordinator.close()
    }
    @Test func holdFnCapturesOnceStopsOnReleaseAndHidesPillAtTerminal() async throws {
        let hudClock = GClock()
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,hudClock:hudClock,preferenceStore:preferences(),history:history)
        #expect(!coordinator.pillVisible)
        let pill = ClickableDictationPill(coordinator:coordinator); #expect(!pill.panel.isVisible)
        coordinator.resumeShortcutIfAuthorized(); #expect(shortcut.enables == 1); #expect(input.starts == 0)
        shortcut.receive?(.pressed); #expect(capture.count == 1); #expect(coordinator.pillVisible)
        shortcut.receive?(.pressed); await coordinator.waitUntilRecording(); #expect(input.starts == 1)
        input.receive?(.transcript("Fn words")); shortcut.receive?(.released); shortcut.receive?(.released)
        #expect(input.stops == 1); #expect(coordinator.phase == .finalizing); #expect(coordinator.pillVisible)
        input.receive?(.finished); await waitForTerminal(coordinator)
        #expect(coordinator.phase == .success); #expect(coordinator.pillVisible)
        await hudClock.waitForSleep(2200); await hudClock.advance(2200); await coordinator.waitForHUDFeedback()
        #expect(!coordinator.pillVisible)
        #expect(capture.target?.value == "aFn wordsbc"); #expect(capture.target?.replacements == 1)
        #expect(try await history.load().count == 1)
        pill.close(); coordinator.close()
    }
    @Test func releasingFnDuringStartupCancelsAndFencesLateSpeech() async {
        let input = GInput(), shortcut = GShortcut(); input.hold = true
        let coordinator = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        coordinator.resumeShortcutIfAuthorized(); shortcut.receive?(.pressed); await input.waitForStart()
        #expect(coordinator.pillVisible); shortcut.receive?(.released); #expect(!coordinator.pillVisible)
        input.resolve(); input.receive?(.transcript("late")); input.receive?(.finished)
        #expect(coordinator.latest == nil); #expect(coordinator.phase == .idle); coordinator.close()
    }
    @Test func restoringMonitoringNeverPromptsWithoutExistingAuthorization() {
        let shortcut = GShortcut(); shortcut.authorizationReady = false
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        coordinator.resumeShortcutIfAuthorized(); #expect(shortcut.enables == 0); #expect(!coordinator.shortcutEnabled)
        shortcut.authorizationReady = true; coordinator.resumeShortcutIfAuthorized(); #expect(shortcut.enables == 1)
        coordinator.refreshPermissions(); #expect(shortcut.enables == 1)
        shortcut.authorizationReady = false; coordinator.refreshPermissions()
        #expect(!coordinator.shortcutEnabled); #expect(coordinator.preferences.holdFnEnabled)
        coordinator.close(); #expect(coordinator.preferences.holdFnEnabled)
    }
    @Test func explicitDisablePersistsAndDoesNotRearmOnActivation() {
        let shortcut = GShortcut(), store = preferences()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:shortcut,preferenceStore:store)
        coordinator.resumeShortcutIfAuthorized(); coordinator.disableShortcut(); coordinator.resumeShortcutIfAuthorized()
        #expect(shortcut.enables == 1); #expect(!coordinator.shortcutEnabled); #expect(!store.load().holdFnEnabled)
        coordinator.close(); #expect(!store.load().holdFnEnabled)
    }
    @Test func oldPreferencesMigrateFnChoiceWithoutDroppingExistingSettings() throws {
        let data = Data("{\"version\":1,\"keepHistory\":false,\"spacingCleanup\":false,\"showPill\":true,\"appearance\":\"dark\"}".utf8)
        let value = try JSONDecoder().decode(DictationPreferences.self,from:data)
        #expect(value.holdFnEnabled); #expect(!value.keepHistory); #expect(!value.spacingCleanup); #expect(value.appearance == .dark)
        #expect(try JSONDecoder().decode(DictationPreferences.self,from:JSONEncoder().encode(value)) == value)
    }
    @Test func unsupportedFieldExplainsFailureAndDoesNotLeaveAnIdleWarningPill() async {
        let hudClock = GClock()
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), shortcut = GShortcut()
        capture.failure = .unsupported; capture.failureExplanation = "The field does not expose a readable caret or selection. Copy from History."
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,hudClock:hudClock,preferenceStore:preferences(),history:history)
        coordinator.resumeShortcutIfAuthorized(); shortcut.receive?(.pressed); await coordinator.waitUntilRecording()
        input.receive?(.transcript("retained words")); shortcut.receive?(.released); input.receive?(.finished); await waitForTerminal(coordinator)
        #expect(coordinator.phase == .error); #expect(coordinator.pillVisible); #expect(coordinator.message == capture.failureExplanation)
        await hudClock.waitForSleep(2200); await hudClock.advance(2200); await coordinator.waitForHUDFeedback()
        #expect(!coordinator.pillVisible)
        #expect(coordinator.latest?.cleaned == "retained words"); #expect(coordinator.latest?.insertion.attempted == false); coordinator.close()
    }
    @Test func speechFailureTakesPrecedenceOverEarlierTargetDiagnostic() async {
        let hudClock = GClock()
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), shortcut = GShortcut()
        capture.failure = .unsupported; capture.failureExplanation = "Target diagnostic"
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,hudClock:hudClock,preferenceStore:preferences(),history:history)
        coordinator.resumeShortcutIfAuthorized(); shortcut.receive?(.pressed); await coordinator.waitUntilRecording()
        input.receive?(.transcript("partial")); input.receive?(.failed(.recognitionFailed)); await waitForTerminal(coordinator)
        #expect(coordinator.latest?.insertion.reason == .speechFailed); #expect(coordinator.message.contains("Speech")); #expect(coordinator.pillVisible)
        await hudClock.waitForSleep(2200); await hudClock.advance(2200); await coordinator.waitForHUDFeedback()
        #expect(!coordinator.pillVisible); coordinator.close()
    }
    @Test func nonFnManualCaptureNeverShowsPill() async {
        let input = GInput(), clock = GClock(), coordinator = world(input:input,clock:clock)
        coordinator.startManual(); await coordinator.waitUntilRecording(); #expect(!coordinator.pillVisible)
        coordinator.cancel(); #expect(!coordinator.pillVisible); coordinator.close()
    }
    @Test func pillCapturesTargetBeforeSpeechAndDoubleClicksCannotStartAnotherSession() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), coordinator = world(input:input,capture:capture,clock:clock)
        coordinator.pillClicked(); #expect(capture.count == 1)
        coordinator.pillClicked(clickCount:2); #expect(capture.count == 1)
        await coordinator.waitUntilRecording(); #expect(input.starts == 1)
        coordinator.pillClicked(); #expect(input.stops == 1); coordinator.pillClicked(); #expect(input.starts == 1)
        coordinator.cancel()
    }
    @Test func finalTextIsCleanedInsertedOnceAndSavedWithVerifiedOutcome() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await coordinator.waitUntilRecording()
        input.receive?(.transcript("one")); input.receive?(.transcript("one   two"))
        coordinator.stop(); input.receive?(.finished); input.receive?(.finished)
        await history.waitForEntry()
        let rows = try? await history.load(); #expect(rows?.count == 1); #expect(rows?.first?.raw == "one   two")
        #expect(rows?.first?.cleaned == "one two"); #expect(rows?.first?.insertion.outcome == .inserted)
        #expect(capture.target?.value == "aone twobc"); #expect(capture.target?.replacements == 1)
        coordinator.close()
    }
    @Test(arguments:[TextTargetError.denied,.unsupported])
    func deniedAndUnsupportedTargetsStillAllowManualDictation(_ failure: TextTargetError) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(); capture.failure = failure
        let coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await coordinator.waitUntilRecording()
        input.receive?(.transcript("copy me")); coordinator.stop(); input.receive?(.finished); await history.waitForEntry()
        #expect(input.starts == 1); #expect(try await history.load().first?.insertion.outcome != .inserted); #expect(coordinator.latest?.cleaned == "copy me")
        coordinator.close()
    }
    @Test func secureTargetNeverStartsRecording() {
        let input = GInput(), capture = GCapture(); capture.failure = .secure
        let coordinator = world(input:input,capture:capture); coordinator.pillClicked()
        #expect(input.starts == 0); #expect(coordinator.phase == .error); #expect(coordinator.message.contains("secure")); coordinator.close()
    }
    @Test func targetChangedDuringRecordingIsNotReplaced() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await coordinator.waitUntilRecording(); capture.target?.validationError = .changed
        input.receive?(.transcript("safe")); coordinator.stop(); input.receive?(.finished); await history.waitForEntry()
        #expect(try await history.load().first?.insertion.outcome == .targetChanged); #expect(capture.target?.replacements == 0); coordinator.close()
    }
    @Test func cancellationDuringPermissionWaitFencesLateResults() async {
        let input = GInput(); input.hold = true
        let coordinator = world(input:input); coordinator.pillClicked(); await input.waitForStart()
        coordinator.cancel(); input.resolve(); input.receive?(.transcript("late")); input.receive?(.finished)
        #expect(coordinator.raw.isEmpty); #expect(coordinator.phase == .idle); #expect(coordinator.latest == nil); coordinator.close()
    }
    @Test func finalizationTimeoutDoesNotInsertPartialText() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await coordinator.waitUntilRecording(); input.receive?(.transcript("partial")); coordinator.stop()
        await clock.waitForSleep(9000); await clock.advance(9000); await history.waitForEntry()
        #expect(try await history.load().first?.insertion.outcome == .timedOut); #expect(capture.target?.replacements == 0); coordinator.close()
    }
    @Test func historyOptOutAndSpacingControlAreConnected() async throws {
        let input = GInput(), clock = GClock(), history = GHistory(), coordinator = world(input:input,clock:clock,history:history)
        coordinator.preferences.keepHistory = false; coordinator.preferences.spacingCleanup = false
        coordinator.startManual(); await coordinator.waitUntilRecording(); input.receive?(.transcript("x   y")); coordinator.stop(); input.receive?(.finished)
        // The manual path finishes without a persistence await; wait for its owned work through the clock actor.
        await coordinator.loadHistory()
        #expect(try await history.load().isEmpty); #expect(coordinator.cleaned == "x   y"); coordinator.close()
    }
    @Test(arguments:[false,true])
    func cancellationDuringRecordingAndFinalizationNeverInserts(_ finalizing: Bool) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await coordinator.waitUntilRecording(); input.receive?(.transcript("cancelled draft"))
        if finalizing { coordinator.stop() }
        coordinator.cancel(); input.receive?(.transcript("late")); input.receive?(.finished); await history.waitForEntry()
        let row = try await history.load().first
        #expect(row?.insertion.outcome == .cancelled); #expect(row?.raw == "cancelled draft"); #expect(capture.target?.replacements == 0)
        coordinator.close()
    }
    @Test func cancellationDuringInsertionRetainsActualUncertainOutcome() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await coordinator.waitUntilRecording()
        capture.target?.writable = false; capture.target?.acknowledgePaste = false
        input.receive?(.transcript("X")); coordinator.stop(); input.receive?(.finished)
        await clock.waitForSleep(1050); coordinator.cancel(); await history.waitForEntry()
        let row = try await history.load().first
        #expect(row?.insertion.outcome == .uncertain); #expect(row?.insertion.reason == .cancelled); #expect(row?.insertion.attempted == true)
        #expect(capture.target?.pastes == 1); #expect(coordinator.clipboardPending); coordinator.close()
    }
    @Test func nativePagesInstantiateInBothAppearancesWithoutStartingSpeech() async throws {
        let input = GInput(), coordinator = world(input:input)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WesleyFlow-RenderedPages-\(UUID().uuidString)",isDirectory:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        for appearance in [DictationAppearance.light,.dark] {
            coordinator.preferences.appearance = appearance
            for page in DictationPage.allCases {
                let window = NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:520),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
                window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named:appearance == .dark ? .darkAqua : .aqua)
                let controller = NSHostingController(rootView:GlobalDictationView(coordinator:coordinator,initialPage:page))
                let view = controller.view
                window.contentView = view; view.frame = NSRect(x:0,y:0,width:800,height:520); window.orderFront(nil)
                // Allow AppKit/SwiftUI layout transactions to commit; no timed sleep or audio input.
                await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
                await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
                view.layoutSubtreeIfNeeded(); window.displayIfNeeded(); view.displayIfNeeded()
                #expect(view.fittingSize.width >= 800); #expect(view.fittingSize.height >= 520)
                #expect(controller.sizeThatFits(in:.zero) == CGSize(width:800,height:520))
                #expect(controller.sizeThatFits(in:CGSize(width:800,height:520)) == CGSize(width:800,height:520))
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in:view.bounds)); view.cacheDisplay(in:view.bounds,to:bitmap)
                let data = try #require(bitmap.representation(using:.png,properties:[:]))
                #expect(bitmap.pixelsWide >= 800); #expect(bitmap.pixelsHigh >= 520); #expect(data.count > 1000)
                try data.write(to:root.appendingPathComponent("\(page.rawValue)-\(appearance.rawValue).png"))
                window.close()
            }
        }
        #expect(input.starts == 0); #expect(coordinator.modelInventory.isEmpty); coordinator.close()
    }
    @Test func compactPagesAccommodateLargerTextWithoutExpandingTheMinimumWindow() async throws {
        let input = GInput(), coordinator = world(input:input)
        for page in DictationPage.allCases {
            let controller = NSHostingController(rootView:GlobalDictationView(coordinator:coordinator,initialPage:page).dynamicTypeSize(.accessibility2))
            #expect(controller.sizeThatFits(in:CGSize(width:800,height:520)) == CGSize(width:800,height:520))
        }
        #expect(input.starts == 0); coordinator.close()
    }
    @Test func compactNavigationRestoresLegacySelectionAndPreservesHistoryParent() {
        #expect(DictationPage.restoring(nil) == .dictation)
        #expect(DictationPage.restoring("Workspace") == .dictation)
        #expect(DictationPage.restoring("Unknown") == .dictation)
        #expect(DictationPage.restoring("General") == .general)
        #expect(!DictationPage.allCases.map(\.rawValue).contains("Workspace"))
        #expect(DictationPage.history.sidebarSelection == .dictation)
        #expect(DictationPage.privacy.symbol == "shield")
        #expect(DictationPage.dictation.moving(-1) == .dictation)
        #expect(DictationPage.general.moving(1) == .general)
        #expect(DictationPage.dictation.moving(1) == .insights)
        #expect(DictationPage.privacy.moving(1) == .general)
    }
    @Test func sidebarHoverClearsAndSelectionChangesTheActualNativeSymbolWeight() throws {
        var state = SidebarPresentation(selected:false)
        #expect(state.iconWeight == .regular); #expect(state.foreground == .muted); #expect(state.backgroundOpacity == 0)
        state.hovered = true
        #expect(state.iconWeight == .regular); #expect(state.foreground == .emphasized); #expect(state.backgroundOpacity > 0)
        state.hovered = false
        #expect(state.foreground == .muted); #expect(state.backgroundOpacity == 0)
        state.selected = true
        #expect(state.iconWeight == .semibold); #expect(state.foreground == .accent); #expect(state.backgroundOpacity == 1)
        state.hovered = true; state.hovered = false
        #expect(state.iconWeight == .semibold); #expect(state.foreground == .accent)
        for page in DictationPage.sidebar {
            let image = try #require(NSImage(systemSymbolName:page.symbol,accessibilityDescription:nil))
            let regular = try #require(image.withSymbolConfiguration(.init(pointSize:17,weight:.regular))?.tiffRepresentation)
            let selected = try #require(image.withSymbolConfiguration(.init(pointSize:17,weight:.semibold))?.tiffRepresentation)
            #expect(regular != selected)
        }
    }
    @Test func compactDefaultHomeAndWindowUpdatesPreserveUserGeometryWithoutVoice() async throws {
        #expect(CompactWindowLayout.defaultSize == CGSize(width:960,height:620))
        #expect(CompactWindowLayout.minimumSize == CGSize(width:800,height:520))
        #expect(CompactWindowLayout.sidebarWidth == 230)
        let input = GInput(), coordinator = world(input:input)
        let window = NSWindow(contentRect:NSRect(x:180,y:160,width:960,height:620),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView:GlobalDictationView(coordinator:coordinator,restoredSelection:"Workspace"))
        window.contentView = view; window.orderFront(nil)
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        view.layoutSubtreeIfNeeded()
        #expect(NSHostingController(rootView:GlobalDictationView(coordinator:coordinator)).sizeThatFits(in:.zero) == CGSize(width:800,height:520))
        window.setContentSize(NSSize(width:1120,height:740)); let chosenFrame = window.frame
        view.rootView = GlobalDictationView(coordinator:coordinator,initialPage:.general)
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        view.layoutSubtreeIfNeeded()
        #expect(window.frame == chosenFrame)
        #expect(input.starts == 0); #expect(coordinator.modelInventory.isEmpty)
        window.close(); coordinator.close()
    }
    @Test func nonActivatingPillCannotBecomeKeyOrMainAndHasExactSize() {
        let panel = NonActivatingDictationPanel(contentRect:NSRect(x:0,y:0,width:84,height:32),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        #expect(!panel.canBecomeKey); #expect(!panel.canBecomeMain); #expect(panel.contentRect(forFrameRect:panel.frame).size == NSSize(width:84,height:32)); panel.close()
    }
    @Test func sidebarAndAppearanceSettingsPersistWithoutAIActivation() {
        #expect(DictationPage.sidebar.map(\.rawValue) == ["Dictation","Insights","Dictionary","Command Mode","Smart Formatting","Privacy","General"])
        #expect(DictationPage.allCases.contains(.history)); #expect(!DictationPage.sidebar.contains(.history))
        let name = "WesleyFlow-Prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let store = DictationPreferenceStore(defaults:defaults), coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:store)
        coordinator.preferences.appearance = .dark; coordinator.preferences.showPill = false; coordinator.preferences.spacingCleanup = false
        let loaded = DictationPreferenceStore(defaults:defaults).load()
        #expect(loaded.appearance == .dark); #expect(!loaded.showPill); #expect(!loaded.spacingCleanup)
        #expect(loaded.appearance.colorScheme == .dark); #expect(DictationAppearance.light.colorScheme == .light); #expect(DictationAppearance.system.colorScheme == nil)
        #expect(coordinator.modelInventory.isEmpty); #expect(coordinator.modelStatus.contains("disabled")); coordinator.close()
    }
    @Test func unknownSettingsVersionIsPreserved() {
        let name = "WesleyFlow-Prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let raw = Data("{\"version\":2}".utf8); defaults.set(raw,forKey:"dictation.preferences.v1")
        let store = DictationPreferenceStore(defaults:defaults); _ = store.load(); store.save(.init())
        #expect(store.error != nil); #expect(defaults.data(forKey:"dictation.preferences.v1") == raw)
    }
}
@Suite("Local dictation history",.serialized,.timeLimit(.minutes(1)))
struct GlobalHistoryTests {
    private func entry(_ text: String = "hello", date: Date = Date()) -> DictationHistoryEntry {
        .init(id:UUID().uuidString,timestamp:date,raw:"  "+text,cleaned:text,sourceApplication:"Fixture",durationMilliseconds:1000,insertion:.init(.uncertain,.verificationUnavailable,attempted:true))
    }
    @Test func saveReopenDeleteAndClearPreserveOutcomes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WF-History-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("history.store"), first = entry(), second = entry("second",date:Date().addingTimeInterval(1))
        let store = try await SwiftDataDictationHistoryStore.open(url:url)
        try await store.append(first); try await store.append(second); await store.close()
        let reopened = try await SwiftDataDictationHistoryStore.open(url:url)
        #expect(try await reopened.load() == [second,first]); #expect(try await reopened.load().last?.insertion.outcome == .uncertain)
        try await reopened.delete(id:first.id); #expect(try await reopened.load() == [second])
        try await reopened.clear(); #expect(try await reopened.load().isEmpty); await reopened.close()
    }
    @Test func schemaMismatchAndCorruptionNeverResetFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WF-History-\(UUID().uuidString)"); try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("history.store"), marker = url.appendingPathExtension("schema")
        try Data("2\n".utf8).write(to:marker)
        await #expect(throws:DictationHistoryFailure.self) { _ = try await SwiftDataDictationHistoryStore.open(url:url) }
        #expect(try Data(contentsOf:marker) == Data("2\n".utf8))
        try FileManager.default.removeItem(at:marker); let data = Data("not a database".utf8); try data.write(to:url)
        await #expect(throws:DictationHistoryFailure.self) { _ = try await SwiftDataDictationHistoryStore.open(url:url) }
        #expect(try Data(contentsOf:url) == data)
    }
    @Test func quotaAndDuplicateIDsFailWithoutChangingSavedRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WF-History-\(UUID().uuidString)"); defer { try? FileManager.default.removeItem(at:root) }
        let store = try await SwiftDataDictationHistoryStore.open(url:root.appendingPathComponent("history.store"),entryLimit:2), a = entry(), b = entry("two")
        try await store.append(a)
        await #expect(throws:DictationHistoryFailure.self) { try await store.append(a) }
        try await store.append(b)
        await #expect(throws:DictationHistoryFailure.self) { try await store.append(entry("three")) }
        #expect(try await store.load().count == 2); await store.close()
    }
    @Test func searchAndDateGroupingUseSavedDataOnly() {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
        let a = entry("SwiftUI",date:Date(timeIntervalSince1970:100)), b = entry("other",date:Date(timeIntervalSince1970:90_000))
        #expect(DictationHistoryQuery.filter([a,b],search:"swift").map(\.id) == [a.id])
        #expect(DictationHistoryQuery.filter([a,b],search:"fixture").count == 2)
        let grouped = DictationHistoryQuery.groups([a,b],calendar:calendar)
        #expect(grouped.count == 2); #expect(grouped[0].entries == [b])
        #expect(a.wordCount == 1); #expect(a.characterCount == 7)
    }
}

@Suite("Independent local formatting",.serialized)
@MainActor struct VoiceParityFormattingTests {
    @Test(arguments:["MY_case()", "file.swift", "/Users/test/MyFile.swift", "https://example.com/a?q=1", "fooBar", "HTTP", "12.50", "`um comma`", "git status --short", "\"/a path/file\""])
    func technicalSpansAreNeverRewritten(_ raw: String) {
        var options = DictationFormattingOptions(); options.spokenPunctuation = true; options.sentenceCapitalization = true; options.correctSpelling = true; options.removeFillers = true
        let result = DictationFormatting.format(raw,options:options,whitespace:true,correction:{ _ in Issue.record("Protected content reached spelling"); return "changed" })
        #expect(result == raw)
    }
    @Test func literalCleanupAndNoAggressiveRepetitionOrConjunctionRemoval() {
        var options = DictationFormattingOptions(); options.spokenPunctuation = true; options.sentenceCapitalization = true; options.removeFillers = true
        #expect(DictationFormatting.format("um hello comma world period new line and and keep this question mark",options:options,whitespace:true) == "Hello, world.\nAnd and keep this?")
        options.removeFillers = false; options.removeRepeatedFillers = true
        #expect(DictationFormatting.format("um um and and but not",options:options,whitespace:true) == "Um and and but not")
    }
    @Test func protectedVocabularyOverridesSpellingAndSpokenPunctuation() {
        var options = DictationFormattingOptions(); options.vocabulary = ["nemotron","comma"]; options.correctSpelling = true; options.spokenPunctuation = true
        #expect(DictationFormatting.format("nemotron comma speling",options:options,whitespace:true,correction:{ _ in "spelling" }) == "nemotron comma spelling")
    }
    @Test func replacementOutputsAreProtectedAndNeverRecursive() {
        var options = DictationFormattingOptions(); options.replacements = [.init(phrase:"project root",replacement:"/a path/My_id"),.init(phrase:"alias",replacement:"um comma"),.init(phrase:"um comma",replacement:"BAD")]; options.spokenPunctuation = true; options.removeFillers = true; options.sentenceCapitalization = true; options.correctSpelling = true
        #expect(DictationFormatting.format("project root alias",options:options,whitespace:true,correction:{ _ in "changed" }) == "/a path/My_id um comma")
    }
    @Test func unicodeRangesLimitsAndSafeSpellResponse() {
        var options = DictationFormattingOptions(); options.correctSpelling = true
        #expect(DictationFormatting.format("नमस्ते speling and café",options:options,whitespace:true,correction:{ $0 == "speling" ? "spelling" : "unsafe\ntext" }) == "नमस्ते spelling and café")
        options.vocabulary = Array(repeating:"term",count:129)
        #expect(!options.isValid); #expect(DictationFormatting.format("  untouched ",options:options,whitespace:true) == "  untouched ")
    }
    @Test func legacyPreferencesDecodeWithoutChangingDefaults() throws {
        let data = Data(#"{"version":1,"keepHistory":true,"spacingCleanup":true,"showPill":true,"appearance":"system","holdFnEnabled":true}"#.utf8)
        let result = try JSONDecoder().decode(DictationPreferences.self,from:data)
        #expect(result.activationKey == .fn); #expect(!result.idlePillEnabled); #expect(result.formatting == DictationFormattingOptions())
        var options = result; options.activationKey = .rightOption; options.formatting.vocabulary = ["myTerm"]
        #expect(try JSONDecoder().decode(DictationPreferences.self,from:JSONEncoder().encode(options)) == options)
    }
    @Test(arguments:[DictationActivationKey.fn,.rightOption,.rightCommand,.rightControl])
    func physicalModifierDownUpAndChords(_ key: DictationActivationKey) {
        let code = Int64(ModifierShortcutDecoder.code(key))
        let flags: CGEventFlags = key == .fn ? .maskSecondaryFn : key == .rightOption ? .maskAlternate : key == .rightControl ? .maskControl : .maskCommand
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:flags).signal == .pressed)
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:[]).signal == .released)
        if key != .fn { #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:flags).signal == .pressed) }
        #expect(ModifierShortcutDecoder.decode(key:key,type:.keyDown,code:53,flags:flags).signal == .cancelled)
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:flags.union(.maskShift)).signal == .cancelled)
    }
}

@Suite("Iteration 3 history and activity",.serialized,.timeLimit(.minutes(1)))
@MainActor struct DictationPresentationTests {
    private func calendar(_ zone:String = "UTC",firstWeekday:Int = 1) -> Calendar {
        var value = Calendar(identifier:.gregorian); value.timeZone = TimeZone(identifier:zone)!; value.locale = Locale(identifier:"en_US_POSIX"); value.firstWeekday = firstWeekday; return value
    }
    private func date(_ value:String) -> Date { ISO8601DateFormatter().date(from:value)! }
    private func entry(_ timestamp:Date,id:String = UUID().uuidString,text:String = "one two",receipt:TextInsertionReceipt = .init(.unsupportedTarget,.manualOnly)) -> DictationHistoryEntry {
        .init(id:id,timestamp:timestamp,raw:text,cleaned:text,sourceApplication:nil,durationMilliseconds:1000,insertion:receipt)
    }
    private func coordinator(history:any DictationHistoryStore,clock:GClock = GClock(),insertion:(any DictationTextInserting)? = nil,copy:@escaping @MainActor (String) -> Bool = { _ in false }) -> SystemWideDictationCoordinator {
        .init(input:GInput(),targets:GCapture(),insertion:insertion ?? TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history,historyCopy:copy)
    }
    @Test func nativeSwitchBindingsPersistAndUnavailablePreferencesPreserveOriginalBytes() {
        let name = "WF-UI3-\(UUID())"
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let store = DictationPreferenceStore(defaults:defaults)
        let c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:store)
        let binding = Binding(get:{ c.preferences.showPill },set:{ c.preferences.showPill = $0 })
        let hosted = NSHostingController(rootView:Toggle("Show dictation pill",isOn:binding).toggleStyle(.switch))
        #expect(hosted.sizeThatFits(in:CGSize(width:400,height:100)).width > 0)
        binding.wrappedValue = false; #expect(!store.load().showPill)
        c.preferences.keepHistory = false; c.preferences.formatting.spokenPunctuation = true
        let reloaded = DictationPreferenceStore(defaults:defaults).load()
        #expect(!reloaded.keepHistory); #expect(reloaded.formatting.spokenPunctuation)
        let raw = Data("{\"version\":99}".utf8); defaults.set(raw,forKey:"dictation.preferences.v1")
        let invalid = DictationPreferenceStore(defaults:defaults); _ = invalid.load(); invalid.save(.init())
        #expect(invalid.error != nil); #expect(defaults.data(forKey:"dictation.preferences.v1") == raw); c.close()
    }
    @Test func historyOrderingDateAndStableIdentityIncludeLongText() {
        let a = entry(date("2024-12-31T23:30:00Z")), b = entry(date("2025-01-01T00:30:00Z"),text:String(repeating:"word ",count:4000))
        let rows = DictationHistoryQuery.filter([a,b],search:"")
        #expect(rows.map(\.id) == [b.id,a.id]); #expect(rows[0].cleaned.count == b.cleaned.count)
        let india = DictationRowPresentation.date(a.timestamp,calendar:calendar("Asia/Kolkata"),locale:Locale(identifier:"en_US_POSIX"))
        let utc = DictationRowPresentation.date(a.timestamp,calendar:calendar(),locale:Locale(identifier:"en_US_POSIX"))
        #expect(india != utc); #expect(india.contains("2025")); #expect(utc.contains("2024"))
        #expect(DictationHistoryQuery.filter(rows,search:"word").first?.id == b.id)
        #expect(DictationHistoryQuery.filter([],search:"").isEmpty)
    }
    @Test func activityUsesDailyCountsAndFiveStableLevelsWithoutFakeData() {
        let day = date("2024-02-29T12:00:00Z"), now = date("2024-03-01T12:00:00Z")
        let rows = (0..<8).map { _ in entry(day) }
        let result = DictationActivity(entries:rows,now:now,calendar:calendar())
        #expect(result.days.count == 371); #expect(result.days.filter { $0.count > 0 }.count == 1)
        #expect(result.days.first(where: { $0.date == calendar().startOfDay(for:day) })?.count == 8)
        #expect([0,1,2,3,4,7,8,100].map(DictationActivity.Day.intensity) == [0,1,2,2,3,3,4,4])
        let empty = DictationActivity(entries:[],now:now,calendar:calendar())
        #expect(empty.days.allSatisfy { $0.count == 0 && $0.level == 0 }); #expect(empty.currentStreak == 0); #expect(empty.longestStreak == 0)
    }
    @Test func monthYearLeapWeekStartAndFutureBoundaries() {
        let c = calendar(firstWeekday:2), now = date("2025-01-01T12:00:00Z")
        let rows = [entry(date("2024-02-29T12:00:00Z")),entry(date("2024-12-31T23:00:00Z")),entry(now),entry(date("2025-01-02T00:00:00Z"))]
        let result = DictationActivity(entries:rows,now:now,calendar:c)
        #expect(c.component(.weekday,from:result.days[0].date) == 2)
        #expect(result.days.contains { c.component(.month,from:$0.date) == 2 && c.component(.day,from:$0.date) == 29 && $0.count == 1 })
        #expect(result.eligibleCount == 3); #expect(result.days.filter(\.future).allSatisfy { $0.count == 0 })
        let months = (0..<53).compactMap { result.monthLabelDate(column:$0) }.map { c.component(.month,from:$0) }
        #expect(months.contains(1)); #expect(months.contains(12))
    }
    @Test func partialOpeningMonthDoesNotOverlapTheFollowingMonthLabel() {
        let model = DictationActivity(entries:[],now:date("2026-10-22T12:00:00Z"),calendar:calendar())
        #expect(model.monthLabelDate(column:0) == nil)
        #expect(model.monthLabelDate(column:1) != nil)
        let indices = (0..<53).filter { model.monthLabelDate(column:$0) != nil }
        #expect(zip(indices,indices.dropFirst()).allSatisfy { $1 - $0 >= 4 })
    }
    @Test func timezoneAndDaylightSavingUseCalendarDays() {
        let instant = date("2024-03-10T04:30:00Z"), now = date("2024-03-11T16:00:00Z")
        let rows = [entry(instant),entry(date("2024-03-10T16:00:00Z")),entry(date("2024-03-11T16:00:00Z"))]
        let ny = DictationActivity(entries:rows,now:now,calendar:calendar("America/New_York"))
        let utc = DictationActivity(entries:rows,now:now,calendar:calendar())
        #expect(ny.longestStreak == 3); #expect(utc.longestStreak == 2)
        #expect(ny.days.filter { $0.count > 0 }.count == 3); #expect(utc.days.filter { $0.count > 0 }.count == 2)
        let spring = calendar("America/New_York").startOfDay(for:date("2024-03-10T16:00:00Z"))
        let next = calendar("America/New_York").date(byAdding:.day,value:1,to:spring)!
        #expect(next.timeIntervalSince(spring) == 23*3600)
        #expect(ny.days.contains { $0.date == spring }); #expect(ny.days.contains { $0.date == next })
    }
    @Test func autumnRepeatedHourIsOneLocalActivityDay() {
        let c = calendar("America/New_York"), now = date("2024-11-04T16:00:00Z")
        let a = entry(date("2024-11-03T05:30:00Z")), b = entry(date("2024-11-03T06:30:00Z"))
        let model = DictationActivity(entries:[a,b],now:now,calendar:c)
        #expect(model.days.filter { $0.count > 0 }.count == 1)
        #expect(model.days.first(where: { $0.count > 0 })?.count == 2)
        let start = c.startOfDay(for:a.timestamp)
        #expect(c.date(byAdding:.day,value:1,to:start)!.timeIntervalSince(start) == 25*3600)
    }
    @Test func interruptedSpeechIsNotInsertionFailureAndFragmentsAreNotActivity() {
        let now = date("2024-06-01T12:00:00Z")
        let normal = entry(now)
        let entries = [normal,normal,entry(now,text:"partial",receipt:.init(.cancelled,.cancelled)),entry(now,text:"partial",receipt:.init(.timedOut,.deadline)),entry(now,text:"partial",receipt:.init(.uncertain,.speechFailed)),entry(now,receipt:.init(.uncertain,.deadline,attempted:true)),entry(now,receipt:.init(.denied,.permission)),entry(now,text:"   ")]
        let result = DictationActivity(entries:entries,now:now,calendar:calendar())
        #expect(result.eligibleCount == 3); #expect(result.days.filter { $0.count > 0 }.count == 1)
    }
    @Test func streaksAndDeletionRecalculateFromCurrentData() {
        let c = calendar(), now = date("2024-03-01T12:00:00Z")
        let rows = [entry(date("2024-02-28T12:00:00Z")),entry(date("2024-02-29T12:00:00Z")),entry(now)]
        #expect(DictationActivity(entries:rows,now:now,calendar:c).currentStreak == 3)
        #expect(DictationActivity(entries:rows,now:now,calendar:c).longestStreak == 3)
        #expect(DictationActivity(entries:[rows[0],rows[2]],now:now,calendar:c).currentStreak == 1)
        #expect(DictationActivity(entries:[rows[0],rows[2]],now:now,calendar:c).longestStreak == 1)
        #expect(DictationActivity(entries:Array(rows.prefix(2)),now:now,calendar:c).currentStreak == 0)
    }
    @Test func largeHistoryIsBoundedTo53WeeksAndDatesRemainUnique() {
        let now = date("2024-06-01T12:00:00Z"), rows = (0..<5000).map { i in entry(now.addingTimeInterval(-Double(i*60))) }
        let result = DictationActivity(entries:rows,now:now,calendar:calendar())
        #expect(result.days.count == 371); #expect(Set(result.days.map(\.date)).count == 371); #expect(result.eligibleCount == 5000)
        #expect(DictationHistoryQuery.filter(rows.reversed(),search:"").map(\.id) == rows.map(\.id))
    }
    @Test func copiedFeedbackExpiresPerIDAndRepeatedClicksCannotExpireNewerGeneration() async {
        let clock = GClock(), feedback = HistoryCopyFeedback(clock:clock)
        feedback.show(id:"a"); await clock.waitForSleep(2400) // GClock starts at1000.
        #expect(feedback.copied == ["a"])
        await clock.advance(1100); feedback.show(id:"a"); await clock.waitForSleep(2500)
        await clock.advance(1200); feedback.show(id:"b"); await clock.waitForSleep(2600)
        await clock.advance(2400); #expect(feedback.copied.contains("a")); #expect(feedback.copied.contains("b"))
        await clock.advance(2500)
        for await ids in feedback.$copied.values { if !ids.contains("a") { break } }
        #expect(feedback.copied == ["b"])
        await clock.advance(2600)
        for await ids in feedback.$copied.values { if ids.isEmpty { break } }
        #expect(feedback.copied.isEmpty)
        feedback.show(id:"removed"); feedback.retain(ids:[]); #expect(feedback.copied.isEmpty)
        feedback.show(id:"closing"); feedback.cancelAll(); #expect(feedback.copied.isEmpty)
    }
    @Test func explicitCopyUsesCorrectIDAndRejectsBusyOrPendingClipboardWithoutTouchingBackup() async throws {
        let history = GHistory(), first = entry(date("2024-01-01T12:00:00Z"),text:"first"), second = entry(date("2024-01-02T12:00:00Z"),text:"second")
        try await history.append(first); try await history.append(second)
        var writes:[String] = []; let c = coordinator(history:history,copy:{ writes.append($0); return true }); await c.loadHistory()
        #expect(c.copyHistory(id:second.id)); #expect(writes == ["second"]); #expect(!c.copyHistory(id:"missing")); #expect(!c.copyReviewedText(String(repeating:"x",count:DictationText.maximumBytes+1))); c.pillClicked()
        #expect(!c.copyHistory(id:first.id)); #expect(writes == ["second"]); c.cancel(); c.close()
        let clock = GClock(), clipboard = GClipboard(), service = TextInsertionService(clipboard:clipboard,clock:clock), target = GTarget()
        target.writable = false; target.acknowledgePaste = false
        let operation = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); await clock.advance(2500); let receipt = await operation.value
        #expect(receipt.clipboardPending); let recovery = service.pendingClipboardRecovery
        let pending = coordinator(history:history,clock:clock,insertion:service,copy:{ writes.append($0); return true }); await pending.loadHistory()
        #expect(!pending.historyCopyAllowed); #expect(!pending.copyHistory(id:first.id)); #expect(service.pendingClipboardRecovery == recovery)
        #expect(clipboard.text == "X"); #expect(clipboard.restores == 0); #expect(writes == ["second"]); pending.close()
    }
    @Test func failedCopyDoesNotPublishSuccessAndDeletionPersistsByIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WF-UI3-\(UUID())",isDirectory:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("history.store"), a = entry(Date(),text:"first"), b = entry(Date(),text:"second")
        let store = try await SwiftDataDictationHistoryStore.open(url:url); try await store.append(a); try await store.append(b)
        let c = coordinator(history:store); await c.loadHistory()
        #expect(!c.copyHistory(id:a.id)); await c.deleteHistory(id:a.id)
        #expect(c.entries.map(\.id) == [b.id]); c.close(); await store.close()
        let reopened = try await SwiftDataDictationHistoryStore.open(url:url)
        #expect(try await reopened.load().map(\.id) == [b.id]); await reopened.close()
    }
}

@Suite("Iteration 4 grouped settings history and metrics",.serialized,.timeLimit(.minutes(1)))
@MainActor struct DictationIteration4Tests {
    private func calendar(_ zone:String = "UTC") -> Calendar { var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(identifier:zone)!; c.locale = Locale(identifier:"en_US_POSIX"); return c }
    private func date(_ text:String) -> Date { ISO8601DateFormatter().date(from:text)! }
    private func entry(_ stamp:String,id:String = UUID().uuidString,text:String = "one two",duration:Int64 = 1000,outcome:TextInsertionReceipt = .init(.unsupportedTarget,.manualOnly)) -> DictationHistoryEntry {
        .init(id:id,timestamp:date(stamp),raw:"raw different words here",cleaned:text,sourceApplication:nil,durationMilliseconds:duration,insertion:outcome)
    }
    @Test(arguments:Array(1...31)) func englishOrdinals(day:Int) {
        let expected = [1:"st",2:"nd",3:"rd",21:"st",22:"nd",23:"rd",31:"st"][day] ?? "th"
        #expect(DictationHistoryPresentation.ordinal(day) == "\(day)\(expected)")
    }
    @Test func localDateHeadersRespectLocaleAndGregorianBoundaries() {
        let d = date("2026-10-22T12:00:00Z")
        #expect(DictationHistoryPresentation.heading(d,calendar:calendar(),locale:Locale(identifier:"en_IN")) == "22nd October 2026")
        let french = DictationHistoryPresentation.heading(d,calendar:calendar(),locale:Locale(identifier:"fr_FR"))
        #expect(french.contains("octobre")); #expect(!french.contains("22nd"))
        let midnight = date("2025-12-31T23:45:00Z")
        #expect(DictationHistoryPresentation.heading(midnight,calendar:calendar("Asia/Kolkata"),locale:Locale(identifier:"en_US")).hasPrefix("1st January 2026"))
    }
    @Test func groupingNewestDatesAndRowsUsesStableIDs() {
        let a = entry("2026-10-21T10:00:00Z",id:"a"), b = entry("2026-10-22T11:00:00Z",id:"b"), c = entry("2026-10-22T12:00:00Z",id:"c")
        let groups = DictationHistoryQuery.groups([a,c,b],calendar:calendar())
        #expect(groups.count == 2); #expect(groups[0].entries.map(\.id) == ["c","b"]); #expect(groups[1].entries.map(\.id) == ["a"])
        let removed = DictationHistoryQuery.groups([a,b],calendar:calendar()); #expect(removed[0].entries[0].id == "b")
        #expect(DictationHistoryQuery.groups([],calendar:calendar()).isEmpty)
    }
    @Test func timezoneAndDSTGroupingIsByLocalDay() {
        let rows = [entry("2024-03-10T06:30:00Z",id:"a"),entry("2024-03-10T07:30:00Z",id:"b"),entry("2024-03-11T03:30:00Z",id:"c")]
        #expect(DictationHistoryQuery.groups(rows,calendar:calendar("America/New_York")).count == 1)
        #expect(DictationHistoryQuery.groups(rows,calendar:calendar()).count == 2)
        let repeated = [entry("2024-11-03T05:30:00Z"),entry("2024-11-03T06:30:00Z")]
        #expect(DictationHistoryQuery.groups(repeated,calendar:calendar("America/New_York")).count == 1)
    }
    @Test func timeRowsUseOnlyLocalizedTimeAndRespectHourCycle() {
        let d = date("2026-10-22T18:42:00Z")
        let us = DictationHistoryPresentation.time(d,calendar:calendar(),locale:Locale(identifier:"en_US"))
        let gb = DictationHistoryPresentation.time(d,calendar:calendar(),locale:Locale(identifier:"en_GB"))
        #expect(us.contains("6:42")); #expect(us.contains("PM")); #expect(gb == "18:42")
        #expect(!us.contains("2026")); #expect(!us.contains("October")); #expect(DictationHistoryPresentation.timeColumnWidth == 78)
    }
    @Test func largeHistoryGroupingPreservesEveryEntryAndFullText() {
        let origin = date("2024-01-01T00:00:00Z")
        let rows = (0..<5000).map { i in DictationHistoryEntry(id:String(i),timestamp:origin.addingTimeInterval(Double(i)*3600),raw:"",cleaned:i == 1 ? String(repeating:"long ",count:5000) : "entry",sourceApplication:nil,durationMilliseconds:1000,insertion:.init(.unsupportedTarget,.manualOnly)) }
        let groups = DictationHistoryQuery.groups(rows,calendar:calendar())
        #expect(groups.flatMap(\.entries).count == 5000); #expect(groups.first?.entries.first?.id == "4999")
        #expect(groups.flatMap(\.entries).first(where:{$0.id == "1"})?.cleaned.count == 25000)
    }
    @Test func sevenMetricsUseCanonicalWordsAndActualOutcomes() {
        let rows = [entry("2026-10-22T10:00:00Z",text:"one\n two\tthree",duration:12_000,outcome:.init(.inserted,.verified,attempted:true)),entry("2026-10-22T11:00:00Z",text:"four",duration:3000,outcome:.init(.uncertain,.verificationUnavailable,attempted:true)),entry("2026-10-21T10:00:00Z",text:"five six",duration:5000,outcome:.init(.targetChanged,.changed)),entry("2026-10-21T11:00:00Z",text:"seven",duration:1000,outcome:.init(.denied,.permission))]
        let activity = DictationActivity(entries:rows,now:date("2026-10-22T12:00:00Z"),calendar:calendar())
        let model = DictationInsightsMetrics(entries:rows,activity:activity)
        #expect(model.values.map(\.title) == ["Saved Dictations","Total Words","Recording Time","Verified Insertions","Uncertain Insertions","Current Streak","Longest Streak"])
        #expect(model.values.map(\.value) == ["4","7","0:21","1","1","2 days","2 days"])
        #expect(!model.durationCoverage.contains("unavailable"))
    }
    @Test func unknownDurationHasExplicitCoverageAndNoInventedTime() {
        let rows = [entry("2026-10-22T10:00:00Z",duration:4000),entry("2026-10-22T11:00:00Z",duration:0)]
        func model(_ rows:[DictationHistoryEntry]) -> DictationInsightsMetrics { .init(entries:rows,activity:DictationActivity(entries:rows,now:date("2026-10-22T12:00:00Z"),calendar:calendar())) }
        #expect(model(rows).values[2].value == "0:04"); #expect(model(rows).durationCoverage.contains("1 of 2")); #expect(model(rows).durationCoverage.contains("unavailable"))
        #expect(model([rows[1]]).values[2].value == "Unavailable"); #expect(model([]).values[2].value == "0:00")
        let invalid = entry("2026-10-22T10:00:00Z",duration:-1); #expect(model([invalid]).values[2].value == "Unavailable")
    }
    @Test func unverifiedInsertedPayloadCannotBecomeVerifiedMetric() {
        let rows = [entry("2026-10-22T10:00:00Z",outcome:.init(.inserted,.verificationUnavailable,attempted:false))]
        let model = DictationInsightsMetrics(entries:rows,activity:DictationActivity(entries:rows,now:date("2026-10-22T12:00:00Z"),calendar:calendar()))
        #expect(model.values[3].value == "0"); #expect(model.values[4].value == "0")
    }
    @Test func deletionUpdatesAllHistoryDerivedMetricsAndActivity() {
        let rows = [entry("2026-10-21T10:00:00Z"),entry("2026-10-22T10:00:00Z")], now = date("2026-10-22T12:00:00Z")
        let before = DictationActivity(entries:rows,now:now,calendar:calendar()), remaining = Array(rows.prefix(1))
        let after = DictationActivity(entries:remaining,now:now,calendar:calendar())
        #expect(before.currentStreak == 2); #expect(after.currentStreak == 0); #expect(after.longestStreak == 1); #expect(after.eligibleCount == 1)
        #expect(DictationInsightsMetrics(entries:remaining,activity:after).values[0].value == "1")
    }
    @Test func adaptiveMetricsAreCappedAtFourColumnsAndHaveRoomForSeven() {
        #expect(DictationInsightsMetrics.columns(width:480) == 3); #expect(DictationInsightsMetrics.columns(width:685) == 4)
        #expect(DictationInsightsMetrics.columns(width:1500) == 4); #expect(DictationInsightsMetrics.columns(width:100) == 1)
        #expect(DictationInsightsMetrics.gridHeight(width:480) == 252); #expect(DictationInsightsMetrics.gridHeight(width:685) == 164)
    }
    @Test func separatorPolicyHasNoTrailingOrSingleRowDivider() {
        #expect((0..<3).map { FlowSettingsGroup<Text>.hasSeparator(index:$0,count:3) } == [true,true,false])
        #expect(!FlowSettingsGroup<Text>.hasSeparator(index:0,count:1)); #expect(!FlowSettingsGroup<Text>.hasSeparator(index:0,count:0))
    }
    @Test func nativeControlsAndPickerBindingPersistWithoutChangingDefaults() {
        let name = "WF-UI4-\(UUID())", defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let store = DictationPreferenceStore(defaults:defaults); var prefs = store.load()
        #expect(prefs.appearance == .system && prefs.showPill && !prefs.idlePillEnabled)
        let appearance = Binding(get:{prefs.appearance},set:{prefs.appearance = $0;store.save(prefs)})
        let host = NSHostingController(rootView:FlowSettingsGroup("General") {
            FlowSettingsRow("Appearance") { Picker("Appearance",selection:appearance) { Text("System").tag(DictationAppearance.system);Text("Light").tag(DictationAppearance.light);Text("Dark").tag(DictationAppearance.dark) }.pickerStyle(.menu) }
            FlowSettingsRow("Show dictation pill") { Toggle("Show dictation pill",isOn:Binding(get:{prefs.showPill},set:{prefs.showPill = $0;store.save(prefs)})).toggleStyle(.switch) }
        })
        #expect(host.sizeThatFits(in:CGSize(width:540,height:500)).height >= 96)
        appearance.wrappedValue = .light; #expect(store.load().appearance == .light)
        prefs.showPill = false; store.save(prefs); #expect(!store.load().showPill); #expect(!store.load().idlePillEnabled)
    }
}

@MainActor private final class UI4Geometry {
    var toggle: CGRect = .zero
    var picker: CGRect = .zero
}
@Suite("Iteration 4 native row layout",.serialized)
@MainActor struct SettingsRowLayoutTests {
    @Test func actualNativeControlFramesShareTrailingEdge() async {
        let frames = UI4Geometry()
        let view = FlowSettingsGroup("General") {
            FlowSettingsRow("A short label") {
                Toggle("A short label",isOn:.constant(true)).toggleStyle(.switch)
                    .onGeometryChange(for:CGRect.self) { $0.frame(in:.named("rows")) } action: { frames.toggle = $0 }
            }
            FlowSettingsRow("A longer label",description:"A concise description wraps without moving the trailing control.") {
                Picker("A longer label",selection:.constant(0)) { Text("One").tag(0);Text("Two").tag(1) }.pickerStyle(.menu)
                    .onGeometryChange(for:CGRect.self) { $0.frame(in:.named("rows")) } action: { frames.picker = $0 }
            }
        }.frame(width:540).coordinateSpace(name:"rows")
        let host = NSHostingView(rootView:view)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:240),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        host.layoutSubtreeIfNeeded()
        #expect(frames.toggle.width > 0 && frames.picker.width > 0)
        #expect(abs(frames.toggle.maxX - frames.picker.maxX) < 1)
        #expect(frames.picker.minY > frames.toggle.maxY)
        window.close()
    }
}

private actor GOfflineRewrite: OfflineTranscriptRewriting {
    var calls = 0, hold = false
    var requests:[OfflineRewriteRequest] = []
    var waiter:CheckedContinuation<OfflineRewriteOutcome,Never>?
    var observer:CheckedContinuation<Void,Never>?
    var started = false
    func setHold() { hold = true }
    func rewrite(_ request:OfflineRewriteRequest) async -> OfflineRewriteOutcome {
        calls += 1; requests.append(request)
        if hold { return await withCheckedContinuation { c in waiter = c; started = true; observer?.resume(); observer = nil } }
        return .init(.rewritten,text:request.text + ".")
    }
    func cancel(requestID:String) {}
    func waitForStart() async { if !started { await withCheckedContinuation { observer = $0 } } }
    func release() { waiter?.resume(returning:.init(.rewritten,text:"stale result")); waiter = nil }
}
@Suite("Offline rewrite app preview",.serialized,.timeLimit(.minutes(1))) @MainActor struct OfflineRewriteAppTests {
    private func terminal(_ coordinator:SystemWideDictationCoordinator) async {
        await coordinator.waitForInsertionCompletion()
    }
    @Test func preferenceDefaultMigrationAndPersistence() throws {
        let store = preferences(); #expect(!store.load().offlineAIRewriting)
        var prefs = store.load(); prefs.offlineAIRewriting = true; store.save(prefs); #expect(store.load().offlineAIRewriting)
        let data = try JSONEncoder().encode(prefs); var old = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any]); old.removeValue(forKey:"offlineAIRewriting")
        let migrated = try JSONDecoder().decode(DictationPreferences.self,from:JSONSerialization.data(withJSONObject:old)); #expect(!migrated.offlineAIRewriting)
    }
    @Test func previewIsExplicitFinalOnlyAndNeverInsertsOrDuplicatesHistory() async throws {
        let driver = GOfflineRewrite(), input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history,offlineRewriter:driver)
        #expect(!coordinator.preferences.offlineAIRewriting); #expect(coordinator.startRewritePreview() == nil)
        coordinator.preferences.offlineAIRewriting = true; #expect(coordinator.startRewritePreview() == nil)
        coordinator.pillClicked(); await coordinator.waitUntilRecording(); input.receive?(.transcript("partial"))
        #expect(coordinator.startRewritePreview() == nil); #expect(await driver.calls == 0)
        input.receive?(.transcript("check the button")); coordinator.stop(); input.receive?(.finished); await terminal(coordinator)
        let id = try #require(coordinator.latest?.id), target = try #require(capture.target)
        #expect(await driver.calls == 0); #expect(target.replacements == 1)
        let task = try #require(coordinator.startRewritePreview()); await task.value
        #expect(coordinator.rewritePreview?.text == "check the button."); #expect(target.replacements == 1); #expect(capture.count == 1)
        let rows = try await history.load(); #expect(rows.count == 1); #expect(rows[0].id == id); #expect(rows[0].raw == "check the button"); #expect(rows[0].cleaned == "check the button")
        coordinator.close()
    }
    @Test func cancellationAndNewSessionDiscardLatePreview() async throws {
        let driver = GOfflineRewrite(); await driver.setHold()
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history,offlineRewriter:driver)
        coordinator.preferences.offlineAIRewriting = true
        coordinator.startManual(); await coordinator.waitUntilRecording(); input.receive?(.transcript("check the button")); coordinator.stop(); input.receive?(.finished); await terminal(coordinator)
        let task = try #require(coordinator.startRewritePreview()); await driver.waitForStart(); #expect(coordinator.startRewritePreview() == nil)
        coordinator.startManual(); #expect(coordinator.rewritePreview == nil); await driver.release(); await task.value
        #expect(coordinator.rewritePreview == nil); #expect(capture.count == 0); coordinator.close()
    }
    @Test func disablingOptInAndDeletingEntryInvalidatesPreview() async throws {
        let driver = GOfflineRewrite(), input = GInput(), clock = GClock(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history,offlineRewriter:driver)
        coordinator.preferences.offlineAIRewriting = true; coordinator.startManual(); await coordinator.waitUntilRecording()
        input.receive?(.transcript("check the button")); coordinator.stop(); input.receive?(.finished); await terminal(coordinator)
        let task = try #require(coordinator.startRewritePreview()); await task.value; #expect(coordinator.rewritePreview != nil)
        coordinator.preferences.offlineAIRewriting = false; #expect(coordinator.rewritePreview == nil); #expect(coordinator.startRewritePreview() == nil)
        coordinator.preferences.offlineAIRewriting = true; let id = try #require(coordinator.latest?.id); await coordinator.deleteHistory(id:id)
        #expect(!coordinator.canPreviewRewrite); #expect(try await history.load().isEmpty); coordinator.close()
    }
}

@Suite("Hand-drawn Insights and history presentation")
struct HandDrawnInsightsTests {
    private func calendar(_ zone:String = "UTC") -> Calendar { var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(identifier:zone)!; return c }
    private func entry(_ id:String,_ text:String = "one two",duration:Int64 = 1000,app:String? = "Fixture",receipt:TextInsertionReceipt = .init(.inserted,.verified,attempted:true)) -> DictationHistoryEntry {
        .init(id:id,timestamp:Date(timeIntervalSince1970:1_700_000_000),raw:text,cleaned:text,sourceApplication:app,durationMilliseconds:duration,insertion:receipt)
    }
    private func summary(_ entries:[DictationHistoryEntry]) -> SketchInsightsSummary {
        .init(entries:entries,activity:.init(entries:entries,now:Date(timeIntervalSince1970:1_700_000_001),calendar:calendar()))
    }
    @Test func exactlyFourMetricsAndWeightedWPM() {
        let s = summary([entry("a",duration:1000),entry("b","three four five",duration:2000)])
        #expect(s.values.map(\.title) == ["Total Words","Average WPM","Current Streak","Longest Streak"])
        #expect(s.values[0].value == 5.formatted())
        #expect(s.values[1].value == 100.formatted(.number.precision(.fractionLength(0))))
        #expect(s.values[2].value == "1 day"); #expect(s.values[3].value == "1 day")
    }
    @Test(arguments:[Int64(0),-1,DictationText.maximumDurationMilliseconds + 1]) func missingOrInvalidTimingMakesRateUnavailable(_ duration:Int64) {
        let s = summary([entry("a"),entry("b",duration:duration)])
        #expect(s.values[1].value == "Unavailable"); #expect(s.timingNote.contains("1 of 2"))
    }
    @Test func emptyAndDuplicateHistory() {
        #expect(summary([]).values[1].value == "Unavailable")
        #expect(summary([]).appUsage.isEmpty)
        let e = entry("a"); let s = summary([e,e])
        #expect(s.values[0].value == 2.formatted()); #expect(s.appUsage == [.init(name:"Fixture",words:2)])
    }
    @Test func verifiedApplicationWordsOnlyAndStableTies() {
        let s = summary([
            entry("a","one two three",app:"B"), entry("b",app:"A"),entry("c","one",app:"A"),
            entry("d",app:"Failed",receipt:.init(.unsupportedTarget,.unsupported)),
            entry("e",app:"Uncertain",receipt:.init(.uncertain,.verificationUnavailable,attempted:true)),
            entry("f",app:"Unattempted",receipt:.init(.inserted,.verified,attempted:false)),
            entry("g",app:nil),entry("h",app:"  ")])
        #expect(s.appUsage == [.init(name:"A",words:3),.init(name:"B",words:3)])
        #expect(s.usageNote.contains("2 verified entries lack"))
    }
    @Test func deletionUpdatesNewMetricsAndUsage() {
        let e = entry("a"); #expect(summary([e]).appUsage.count == 1)
        #expect(summary([]).appUsage.isEmpty); #expect(summary([]).values[0].value == 0.formatted())
    }
    @Test func todayUsesActiveTimezoneAndOlderDateRules() {
        let now = Date(timeIntervalSince1970:1_700_006_400)
        let c = calendar("Asia/Kolkata"), yesterday = c.date(byAdding:.day,value:-1,to:now)!
        #expect(DictationHistoryPresentation.sectionHeading(now,now:now,calendar:c,locale:Locale(identifier:"en_IN")) == "TODAY")
        #expect(DictationHistoryPresentation.sectionHeading(yesterday,now:now,calendar:c,locale:Locale(identifier:"en_IN")) == DictationHistoryPresentation.heading(yesterday,calendar:c,locale:Locale(identifier:"en_IN")))
        let earlier = now.addingTimeInterval(-7200)
        for zone in ["UTC","Asia/Kolkata","America/New_York"] {
            let cal = calendar(zone)
            let label = DictationHistoryPresentation.sectionHeading(earlier,now:now,calendar:cal,locale:Locale(identifier:"en_US"))
            #expect((label == "TODAY") == cal.isDate(earlier,inSameDayAs:now))
        }
    }
}

@Suite("Functional settings persistence and command inventory")
@MainActor struct FunctionalSettingsTests {
    @Test func newChoicesPersistWithoutChangingOldDefaults() throws {
        let name = "WF-Settings-\(UUID())", defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let store = DictationPreferenceStore(defaults:defaults)
        var prefs = store.load()
        #expect(!prefs.blockNetworkRequests && !prefs.offlineAIRewriting && prefs.polishTone == .natural)
        prefs.blockNetworkRequests = true; prefs.polishTone = .direct
        prefs.formatting.smartTypography = true; prefs.formatting.handleSelfCorrections = true
        store.save(prefs)
        #expect(store.load() == prefs)
        #expect(!store.load().offlineAIRewriting)
    }
    @Test func earlierPreferencePayloadKeepsNewFeaturesOff() throws {
        let old = Data("{\"version\":1,\"keepHistory\":true,\"spacingCleanup\":true,\"showPill\":true,\"appearance\":\"system\"}".utf8)
        let p = try JSONDecoder().decode(DictationPreferences.self,from:old)
        #expect(!p.blockNetworkRequests && p.polishTone == .natural && !p.offlineAIRewriting)
        #expect(!p.formatting.smartTypography && !p.formatting.handleSelfCorrections)
    }
    @Test func everyReferenceCommandMapsToExistingParser() {
        #expect(AppOpeningCommand.allCases.count == 7)
        for command in AppOpeningCommand.allCases { #expect(AppOpeningCommand.parse("Open \(command.rawValue)") == command) }
        #expect(AppOpeningCommand.parse("open arbitrary app") == nil)
        #expect(AppOpeningCommand.parse("delete history") == nil)
    }
    @Test func loginStatusIsObservedWithoutRegistration() {
        let control = LoginItemControl(); control.refresh()
        #expect(!control.summary.isEmpty); #expect(control.message.isEmpty); #expect(!control.updating)
    }
}


@MainActor private final class GPreviewRegistrar: PreviewShortcutRegistering {
    var kinds = Set<OfflinePreviewKind>(), registrations = 0, disabled = 0
    var failure:PreviewShortcutFailure?
    var receive:(@MainActor @Sendable (PreviewShortcutNotification)->Void)?
    func enable(kinds:Set<OfflinePreviewKind>,receive:@escaping @MainActor @Sendable (PreviewShortcutNotification)->Void) throws {
        if let failure { throw failure }; self.kinds = kinds; self.receive = receive; registrations += 1
    }
    func disable() { disabled += 1; receive = nil; kinds = [] }
}
@Suite("Explicit preview application boundaries",.serialized) @MainActor struct ExplicitPreviewAppTests {
    @Test func independentOptInsAndPreferencePersistence() throws {
        let store = preferences(); var value = store.load()
        #expect(!value.promptEngineeringEnabled); #expect(!value.previewShortcutsEnabled)
        value.promptEngineeringEnabled = true; value.previewShortcutsEnabled = true; store.save(value)
        #expect(store.load().promptEngineeringEnabled); #expect(store.load().previewShortcutsEnabled)
        var old = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
        old.removeValue(forKey:"promptEngineeringEnabled"); old.removeValue(forKey:"previewShortcutsEnabled")
        let migrated = try JSONDecoder().decode(DictationPreferences.self,from:JSONSerialization.data(withJSONObject:old))
        #expect(!migrated.promptEngineeringEnabled); #expect(!migrated.previewShortcutsEnabled)
    }
    @Test func explicitInputNeverCapturesInsertsCopiesOrSubmits() async throws {
        let driver = GOfflineRewrite(), capture = GCapture(), registrar = GPreviewRegistrar()
        var copied = false
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,previewRegistrar:registrar,historyCopy:{ _ in copied = true; return true })
        coordinator.preferences.promptEngineeringEnabled = true; coordinator.preferences.previewShortcutsEnabled = true
        #expect(registrar.kinds == [.promptEngineering]); #expect(coordinator.startSuppliedPreview(.promptEngineering) == nil)
        #expect(await driver.calls == 0)
        coordinator.previewInputText = "Improve WidgetID"; #expect(coordinator.startSuppliedPreview(.polish) == nil)
        let task = try #require(coordinator.startSuppliedPreview(.promptEngineering)); await task.value
        #expect(coordinator.promptPreview?.text == "Improve WidgetID."); #expect(coordinator.rewritePreview == nil)
        #expect(await driver.requests.last?.kind == .promptEngineering); #expect(capture.count == 0); #expect(!copied); #expect(coordinator.entries.isEmpty)
        coordinator.previewInputText = "Changed input"; #expect(coordinator.promptPreview == nil)
        coordinator.preferences.promptEngineeringEnabled = false; #expect(registrar.kinds.isEmpty)
        coordinator.close(); #expect(registrar.receive == nil)
    }
    @Test func shortcutConflictAndSecureInputCancelSafely() async throws {
        let driver = GOfflineRewrite(); await driver.setHold()
        let registrar = GPreviewRegistrar(); registrar.failure = .systemConflict
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,previewRegistrar:registrar)
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.previewShortcutsEnabled = true
        #expect(coordinator.previewShortcutStatus.contains("Conflict")); #expect(registrar.registrations == 0)
        registrar.failure = nil; coordinator.configurePreviewShortcuts(); #expect(registrar.kinds == [.polish])
        coordinator.previewInputText = "Check the button"
        coordinator.openExplicitPreview(.polish); coordinator.generateShortcutPreview(); await driver.waitForStart(); #expect(coordinator.isPreviewingRewrite)
        registrar.receive?(.secureInput); #expect(!coordinator.isPreviewingRewrite)
        await driver.release(); #expect(coordinator.rewritePreview == nil)
        coordinator.close()
    }
    @Test func changedInputDiscardsLateResult() async throws {
        let driver = GOfflineRewrite(); await driver.setHold()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver)
        coordinator.preferences.promptEngineeringEnabled = true; coordinator.previewInputText = "Original"
        let task = try #require(coordinator.startSuppliedPreview(.promptEngineering)); await driver.waitForStart()
        coordinator.previewInputText = "Replacement"; await driver.release(); await task.value
        #expect(coordinator.promptPreview == nil); #expect(!coordinator.isPreviewingRewrite); coordinator.close()
    }
}

@Suite("Selected history preview",.serialized) @MainActor struct SelectedHistoryPreviewTests {
    @Test func onlySelectedCompletedEntryAndDeletionInvalidates() async throws {
        let history = GHistory(), driver = GOfflineRewrite()
        try await history.append(.init(id:"good",timestamp:Date(timeIntervalSince1970:0),raw:"Original",cleaned:"Completed text",sourceApplication:nil,durationMilliseconds:1000,insertion:.init(.unsupportedTarget,.manualOnly)))
        try await history.append(.init(id:"bad",timestamp:Date(timeIntervalSince1970:1),raw:"Partial",cleaned:"Partial text",sourceApplication:nil,durationMilliseconds:0,insertion:.init(.cancelled,.speechFailed)))
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),history:history,offlineRewriter:driver)
        await coordinator.loadHistory(); coordinator.preferences.promptEngineeringEnabled = true; coordinator.previewUseSaved = true
        #expect(coordinator.previewHistoryCandidates.map(\.id) == ["good"])
        coordinator.selectedPreviewEntryID = "bad"; #expect(coordinator.startSuppliedPreview(.promptEngineering) == nil)
        coordinator.selectedPreviewEntryID = "good"
        let task = try #require(coordinator.startSuppliedPreview(.promptEngineering)); await task.value
        #expect(await driver.requests.last?.text == "Completed text"); #expect(coordinator.promptPreview != nil)
        await coordinator.deleteHistory(id:"good"); #expect(coordinator.promptPreview == nil); #expect(coordinator.selectedPreviewEntryID == nil)
        #expect(coordinator.startSuppliedPreview(.promptEngineering) == nil); coordinator.close()
    }
    @Test func repeatedPreviewsRemainExplicitAndHoldOptionConflictIsClosed() async throws {
        let registrar = GPreviewRegistrar(), driver = GOfflineRewrite()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,previewRegistrar:registrar)
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.previewShortcutsEnabled = true
        coordinator.preferences.activationKey = .rightOption; coordinator.preferences.holdFnEnabled = true
        #expect(registrar.kinds.isEmpty); #expect(coordinator.previewShortcutStatus.contains("right-Option"))
        coordinator.previewInputText = "Check the button"
        for _ in 0..<3 { let task = try #require(coordinator.startSuppliedPreview(.polish)); await task.value; #expect(!coordinator.isPreviewingRewrite) }
        #expect(await driver.calls == 3); #expect(coordinator.entries.isEmpty)
        coordinator.close(); #expect(registrar.kinds.isEmpty)
    }
}

@Suite("Core voice failure reporting",.serialized,.timeLimit(.minutes(1))) @MainActor struct VoiceFailureReportingTests {
    private func terminal(_ c:SystemWideDictationCoordinator) async { await c.waitForInsertionCompletion() }
    @Test(arguments:[false,true]) func speechFailureIsNotAnUncertainInsertion(_ oversized:Bool) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history)
        c.pillClicked(); await c.waitUntilRecording(); input.receive?(.transcript("synthetic partial"))
        if oversized { input.receive?(.transcript(String(repeating:"x",count:DictationText.maximumBytes+1))) } else { input.receive?(.failed(.recognitionFailed)) }; await terminal(c)
        let entry = try #require(c.latest); #expect(entry.insertion.reason == .speechFailed); #expect(!entry.insertion.attempted)
        #expect(entry.insertion.status == .failed); #expect(entry.insertion.outcome != .uncertain)
        #expect(capture.target?.replacements == 0); #expect(capture.target?.pastes == 0); #expect(c.phase == .error)
        let rows = try await history.load(); #expect(rows.count == 1); #expect(rows.first?.insertion == entry.insertion); c.close()
    }
    @Test func legacySpeechFailureDoesNotInflateUncertainDelivery() throws {
        let old = TextInsertionReceipt(.uncertain,.speechFailed)
        #expect(old.status == .failed)
        let stamp = Date(timeIntervalSince1970:0)
        let entries = [old,TextInsertionReceipt(.uncertain,.deadline,attempted:true),.init(.denied,.permission)].enumerated().map { index,receipt in DictationHistoryEntry(id:"fixture-\(index)",timestamp:stamp,raw:"synthetic",cleaned:"synthetic",sourceApplication:nil,durationMilliseconds:0,insertion:receipt) }
        let metrics = DictationInsightsMetrics(entries:entries,activity:DictationActivity(entries:entries,now:stamp,calendar:Calendar(identifier:.gregorian)))
        #expect(metrics.values[4].value == "1")
        let decoded = try JSONDecoder().decode(TextInsertionReceipt.self,from:JSONEncoder().encode(old)); #expect(decoded == old)
    }
}

/// Disposable editor state only. No AX calls, global events, audio or system pasteboard.
@MainActor private final class EEditor: InsertionTargetCapturing {
    var fields = ["prefix ","other "]
    var focused = 0
    var direct = true, acknowledge = true, readable = true
    let clipboard:GClipboard
    var targets:[ETarget] = []
    init(_ clipboard:GClipboard) { self.clipboard = clipboard }
    func capture(session:String) throws -> any InsertionTarget {
        let target = ETarget(editor:self,session:session); targets.append(target); return target
    }
}
@MainActor private final class ETarget: InsertionTarget {
    let info:InsertionTargetInfo
    let capturedOriginal:TargetTextState
    var original:TargetTextState? { capturedOriginal }
    unowned let editor:EEditor
    let field:Int, direct:Bool
    var writes = 0, pastes = 0
    init(editor:EEditor,session:String) {
        self.editor = editor; field = editor.focused; direct = editor.direct
        let text = editor.fields[field]; capturedOriginal = .init(text:text,selection:.init(location:text.utf16.count,length:0))
        info = .init(session:session,applicationName:"Synthetic editor",processID:Int32(100+field),windowIdentity:"window-\(field)",elementIdentity:"field-\(field)",role:"AXTextArea")
    }
    func validate() throws { guard editor.focused == field, editor.fields[field] == capturedOriginal.text else { throw TextTargetError.changed } }
    func canReplaceSelection() -> Bool { direct }
    func replaceSelection(_ text:String) throws { try validate(); writes += 1; editor.fields[field] = capturedOriginal.selection.replacing(in:capturedOriginal.text,with:text)! }
    func observedText() -> String? { editor.readable ? editor.fields[field] : nil }
    func postPaste(whileClipboardOwned:()->Bool) throws {
        try validate(); guard whileClipboardOwned() else { throw TextTargetError.clipboardChanged }; pastes += 1
        if editor.acknowledge { editor.fields[field] = capturedOriginal.selection.replacing(in:capturedOriginal.text,with:editor.clipboard.text)! }
    }
}
@Suite("Core voice repeated pipeline",.serialized,.timeLimit(.minutes(1))) @MainActor struct VoiceRepeatedPipelineTests {
    private func recording(_ c:SystemWideDictationCoordinator) async { await c.waitUntilRecording() }
    private func terminal(_ c:SystemWideDictationCoordinator) async { await c.waitForInsertionCompletion() }
    @Test(arguments:[(3,false,false),(3,false,true),(3,true,false),(3,true,true),(10,false,false),(10,false,true),(10,true,false),(10,true,true)])
    func consecutiveSessions(_ scenario:(Int,Bool,Bool)) async throws {
        let (count,differentTargets,paste) = scenario
        let clipboard = GClipboard(), clock = GClock(), input = GInput(), shortcut = GShortcut(), history = GHistory()
        let editor = EEditor(clipboard); editor.direct = !paste
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let c = SystemWideDictationCoordinator(input:input,targets:editor,insertion:service,shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        c.preferences.formatting.sentenceCapitalization = false
        c.enableShortcut(); var expected = editor.fields
        var stale:[@MainActor @Sendable (DictationEvent)->Void] = []
        for index in 0..<count {
            editor.focused = differentTargets ? index % 2 : 0; let focus = editor.focused
            shortcut.receive?(.pressed); shortcut.receive?(.pressed); await recording(c)
            #expect(editor.targets.count == index+1); #expect(input.starts == index+1)
            for old in stale { old(.transcript("stale synthetic")); old(.finished); old(.failed(.recognitionFailed)) }
            let callback = try #require(input.receive); let fragment = "fragment-\(index) "
            callback(.transcript("intermediate")); #expect(editor.fields == expected)
            callback(.transcript(fragment)); shortcut.receive?(.released); shortcut.receive?(.released)
            callback(.finished); callback(.finished); await terminal(c)
            expected[focus] += c.latest!.cleaned
            #expect(editor.fields == expected); #expect(editor.focused == focus)
            #expect(c.latest?.insertion.status == .insertedVerified); #expect(c.phase == .success)
            #expect(!service.hasPendingClipboard); #expect(clipboard.text == "original")
            #expect(editor.targets.last?.writes == (paste ? 0 : 1)); #expect(editor.targets.last?.pastes == (paste ? 1 : 0))
            #expect(clipboard.installed == (paste ? index+1 : 0)); #expect(clipboard.restores == (paste ? index+1 : 0))
            let rows = try await history.load(); #expect(rows.count == index+1); #expect(Set(rows.map(\.id)).count == rows.count)
            stale.append(callback)
        }
        #expect(editor.targets.reduce(0) { $0+$1.writes+$1.pastes } == count)
        #expect(editor.fields.allSatisfy { !$0.contains("\n") && !$0.contains("stale") })
        c.close()
    }
    @Test func focusSwitchPreventsEffectsThenFreshTargetSucceeds() async throws {
        let clipboard = GClipboard(), clock = GClock(), input = GInput(), history = GHistory(), shortcut = GShortcut(), editor = EEditor(clipboard)
        let c = SystemWideDictationCoordinator(input:input,targets:editor,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        c.enableShortcut(); shortcut.receive?(.pressed); await recording(c); input.receive?(.transcript("first synthetic"))
        editor.focused = 1; shortcut.receive?(.released); input.receive?(.finished); await terminal(c)
        #expect(c.latest?.insertion.status == .targetChanged); #expect(editor.fields == ["prefix ","other "]); #expect(editor.focused == 1)
        shortcut.receive?(.pressed); await recording(c); input.receive?(.transcript("second synthetic")); shortcut.receive?(.released); input.receive?(.finished); await terminal(c)
        #expect(c.latest?.insertion.status == .insertedVerified); #expect(editor.focused == 1); #expect(editor.fields[0] == "prefix "); #expect(editor.targets[0].writes == 0); #expect(editor.targets[1].writes == 1); c.close()
    }
    @Test func cancellationAndUncertainPasteNeverReplayOnNextSession() async throws {
        let clipboard = GClipboard(), clock = GClock(), input = GInput(), history = GHistory(), shortcut = GShortcut(), editor = EEditor(clipboard)
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let c = SystemWideDictationCoordinator(input:input,targets:editor,insertion:service,shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        c.enableShortcut(); shortcut.receive?(.pressed); await recording(c); let stale = try #require(input.receive)
        stale(.transcript("cancel this synthetic")); c.cancel(); stale(.finished); await terminal(c)
        #expect(c.latest?.insertion.status == .cancelled); #expect(editor.targets[0].writes == 0)
        editor.direct = false; editor.acknowledge = false
        shortcut.receive?(.pressed); await recording(c); input.receive?(.transcript("unverified synthetic")); shortcut.receive?(.released); input.receive?(.finished)
        await clock.waitForSleep(1050); await clock.advance(2500); await terminal(c)
        #expect(c.latest?.insertion.status == .dispatchedUnverified); #expect(service.hasPendingClipboard); #expect(editor.targets[1].pastes == 1); #expect(c.pillContent == .hidden)
        let recovery = try #require(service.pendingClipboardRecovery)
        shortcut.receive?(.pressed); shortcut.receive?(.released); #expect(input.starts == 2); #expect(editor.targets.count == 2)
        clipboard.externalCopy("new synthetic user copy"); editor.direct = true
        shortcut.receive?(.pressed); await recording(c); stale(.transcript("late synthetic")); stale(.finished)
        input.receive?(.transcript("fresh synthetic")); shortcut.receive?(.released); input.receive?(.finished); await terminal(c)
        #expect(input.starts == 3); #expect(editor.targets[2].writes == 1); #expect(editor.targets[1].pastes == 1)
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:recovery.id) == .unavailable)
        #expect(clipboard.text == "new synthetic user copy"); #expect(clipboard.restores == 0); #expect(!service.hasPendingClipboard)
        #expect(c.latest?.insertion.status == .insertedVerified); #expect(try await history.load().count == 3); c.close()
    }
}


@Suite("Quality preview rejection",.serialized) @MainActor struct QualityPreviewRejectionTests {
    @Test func rejectingCompletedPreviewRetainsInputAndNeverCopies() async throws {
        let driver = GOfflineRewrite()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver)
        coordinator.preferences.offlineAIRewriting = true; coordinator.previewInputText = "Check the button"
        let task = try #require(coordinator.startSuppliedPreview(.polish)); await task.value
        #expect(coordinator.rewritePreview != nil)
        coordinator.rejectRewritePreview()
        #expect(coordinator.rewritePreview == nil && coordinator.promptPreview == nil)
        #expect(coordinator.previewInputText == "Check the button" && coordinator.previewOriginalText == "Check the button")
        #expect(coordinator.previewNotice.contains("rejected")); #expect(!coordinator.isPreviewingRewrite)
        coordinator.rejectRewritePreview(); coordinator.close()
    }
}

@Suite("Global AI shortcut workflow",.serialized) @MainActor struct GlobalAIShortcutWorkflowTests {
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering]) func emptyInputShowsOnlyDisabledHUDWithoutEffects(_ kind:OfflinePreviewKind) async {
        let driver = GOfflineRewrite(), registrar = GPreviewRegistrar(), capture = GCapture()
        var copied = false
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,previewRegistrar:registrar,historyCopy:{ _ in copied = true; return true })
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.promptEngineeringEnabled = true; coordinator.preferences.previewShortcutsEnabled = true
        registrar.receive?(.invokeFrom(kind,processIdentifier:42))
        #expect(!coordinator.previewPresented && coordinator.inPlaceHUD == .error)
        #expect(coordinator.previewOriginProcessIdentifier == nil)
        #expect(coordinator.message == "Enable in-place AI rewrite in Settings.")
        #expect(await driver.calls == 0); #expect(capture.count == 0 && !copied)
        coordinator.dismissShortcutPreview(); #expect(!coordinator.previewPresented); coordinator.close()
    }
    @Test func rapidChordsSleepAndLateResultsNeverReplaceSource() async throws {
        let driver = GOfflineRewrite(), registrar = GPreviewRegistrar(); await driver.setHold()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,previewRegistrar:registrar)
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.promptEngineeringEnabled = true; coordinator.preferences.previewShortcutsEnabled = true
        coordinator.previewInputText = "Check the button"
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); coordinator.generateShortcutPreview(); await driver.waitForStart()
        for _ in 0..<10 { registrar.receive?(.invokeFrom(.promptEngineering,processIdentifier:99)) }
        #expect(await driver.calls == 1); #expect(!coordinator.previewPresented && !coordinator.isPreviewingRewrite)
        registrar.receive?(.suspended); #expect(!coordinator.isPreviewingRewrite && coordinator.previewShortcutStatus.contains("sleeping"))
        coordinator.dismissShortcutPreview(); await driver.release()
        #expect(coordinator.rewritePreview == nil && coordinator.promptPreview == nil)
        registrar.receive?(.resumed); #expect(coordinator.previewShortcutStatus.contains("re-registered"))
        coordinator.close()
    }
    @Test func nativePanelNeverBecomesKeyOrMain() {
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences())
        let panel = ShortcutPreviewPanel(coordinator:coordinator)
        #expect(!panel.canBecomeKey && !panel.isVisible && !panel.hasCreatedPanel)
        panel.close(); coordinator.close()
    }
}

@Suite("Shortcut delivery diagnosis",.serialized) @MainActor struct ShortcutDeliveryDiagnosisTests {
    @Test func disabledOptInDoesNotRegisterAndFailureIsInspectable() {
        let registrar = GPreviewRegistrar()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),previewRegistrar:registrar)
        coordinator.configurePreviewShortcuts()
        #expect(registrar.registrations == 0 && coordinator.previewDiagnostics.last == .disabled)
        registrar.failure = .registration(-9878)
        coordinator.preferences.offlineAIRewriting = true
        coordinator.preferences.previewShortcutsEnabled = true
        #expect(coordinator.previewDiagnostics.last == .registrationFailed)
        #expect(coordinator.previewShortcutStatus.contains("-9878"))
        #expect(!coordinator.previewPresented)
        coordinator.close()
    }
    @Test(arguments:[Int32(42),Int32(99)]) func deliveryUsesSameWindowlessPolicyForLocalAndExternalOrigins(_ process:Int32) {
        let registrar = GPreviewRegistrar()
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),previewRegistrar:registrar)
        coordinator.preferences.offlineAIRewriting = true
        coordinator.preferences.promptEngineeringEnabled = true
        coordinator.preferences.previewShortcutsEnabled = true
        for kind in OfflinePreviewKind.allCases {
            registrar.receive?(.invokeFrom(kind,processIdentifier:process))
            #expect(!coordinator.previewPresented && coordinator.inPlaceHUD == .error)
            #expect(coordinator.previewDiagnostics.last == .activated)
            coordinator.dismissShortcutPreview()
        }
        for _ in 0..<100 { coordinator.recordPreviewDiagnostic(.hidden) }
        #expect(coordinator.previewDiagnostics.count == 32)
        coordinator.close()
    }
}

@MainActor private final class GFocusedText: FocusedTextResolving {
    var calls = 0, allow = false, pid: Int32 = 0
    var hold = false
    var result = FocusedTextResolution(text:"Synthetic draft",source:.draft)
    var pending: CheckedContinuation<FocusedTextResolution,Never>?
    var started: CheckedContinuation<Void,Never>?
    func waitForStart() async { if pending != nil { return }; await withCheckedContinuation { started = $0 } }
    func resolve(processID:Int32,allowUnselected:Bool) async -> FocusedTextResolution {
        calls += 1; allow = allowUnselected; pid = processID
        if hold { return await withCheckedContinuation { pending = $0; started?.resume(); started = nil } }
        return result
    }
    func release() { pending?.resume(returning:result); pending = nil }
}
@Suite("Focused preview capture",.serialized) @MainActor struct FocusedPreviewCaptureTests {
    private func make(_ resolver:GFocusedText, driver:GOfflineRewrite = GOfflineRewrite()) -> SystemWideDictationCoordinator {
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,focusedTextResolver:resolver)
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.promptEngineeringEnabled = true; coordinator.preferences.previewShortcutsEnabled = true
        return coordinator
    }
    @Test func preferenceDefaultAndPersistence() throws {
        let store = preferences(); var value = store.load()
        #expect(!value.useFocusedTextWhenUnselected)
        value.useFocusedTextWhenUnselected = true; store.save(value)
        #expect(store.load().useFocusedTextWhenUnselected)
        var old = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any]); old.removeValue(forKey:"useFocusedTextWhenUnselected")
        #expect(!(try JSONDecoder().decode(DictationPreferences.self,from:JSONSerialization.data(withJSONObject:old))).useFocusedTextWhenUnselected)
    }
    @Test(arguments:[FocusedTextSource.selection,.draft,.paragraph]) func capturesArePreviewOnlyUntilGenerate(_ source:FocusedTextSource) async {
        let resolver = GFocusedText(), driver = GOfflineRewrite(); resolver.result = .init(text:"Synthetic draft",source:source)
        let coordinator = make(resolver,driver:driver); coordinator.preferences.useFocusedTextWhenUnselected = true
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); await coordinator.waitForTextCapture()
        #expect(resolver.calls == 1 && resolver.pid == 42 && resolver.allow)
        #expect(coordinator.shortcutSource == source && coordinator.shortcutInputText == "Synthetic draft")
        #expect(coordinator.previewPresented && !coordinator.isPreviewingRewrite)
        #expect(await driver.calls == 0)
        coordinator.shortcutInputText = "Edited synthetic draft"; #expect(coordinator.shortcutSource == .manual)
        coordinator.dismissShortcutPreview(); #expect(coordinator.shortcutInputText.isEmpty && coordinator.previewOriginalText.isEmpty); coordinator.close()
    }
    @Test func unselectedWithoutOptInNeverBecomesInput() async {
        let resolver = GFocusedText(), coordinator = make(resolver)
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); await coordinator.waitForTextCapture()
        #expect(!resolver.allow && coordinator.shortcutInputText.isEmpty)
        #expect(coordinator.shortcutSource == .manual); coordinator.close()
    }
    @Test func selectionWorksWithoutUnselectedOptIn() async {
        let resolver = GFocusedText(); resolver.result = .init(text:"Selected synthetic text",source:.selection)
        let coordinator = make(resolver)
        coordinator.openExplicitPreview(.promptEngineering,originProcessIdentifier:42); await coordinator.waitForTextCapture()
        #expect(coordinator.shortcutSource == .selection && !resolver.allow); coordinator.close()
    }
    @Test(arguments:["denied","unsupported","stale","empty"]) func unavailableCaptureRetainsManualFallback(_ reason:String) async {
        let resolver = GFocusedText(); resolver.result = .init()
        let coordinator = make(resolver); coordinator.previewInputText = "Explicit manual input"
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); await coordinator.waitForTextCapture()
        #expect(coordinator.shortcutSource == .manual && coordinator.shortcutInputText == "Explicit manual input")
        #expect(coordinator.previewPresented); coordinator.close()
    }
    @Test func disabledFeatureDoesNotReadExternalText() async {
        let resolver = GFocusedText(), coordinator = make(resolver)
        coordinator.preferences.offlineAIRewriting = false
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); await coordinator.waitForTextCapture()
        #expect(resolver.calls == 0); coordinator.close()
    }
    @Test func cancelDuringCaptureDropsLateResultAndSuppressesRepeats() async {
        let resolver = GFocusedText(); resolver.hold = true
        let coordinator = make(resolver); coordinator.preferences.useFocusedTextWhenUnselected = true
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42)
        // Await a controlled continuation handshake, never a timing delay.
        await resolver.waitForStart()
        let capture = coordinator.captureTask
        coordinator.openExplicitPreview(.promptEngineering,originProcessIdentifier:99)
        #expect(resolver.calls == 1 && coordinator.previewKind == .polish)
        coordinator.dismissShortcutPreview(); resolver.release(); await capture?.value
        #expect(!coordinator.previewPresented && coordinator.shortcutInputText.isEmpty)
        coordinator.close()
    }
}

extension FocusedPreviewCaptureTests {
    @Test func explicitGenerationNeverCapturesInsertsOrCopies() async throws {
        let resolver = GFocusedText(), driver = GOfflineRewrite(), capture = GCapture(), clipboard = GClipboard()
        var copied = false
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,focusedTextResolver:resolver,historyCopy:{ _ in copied = true; return true })
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.previewShortcutsEnabled = true; coordinator.preferences.useFocusedTextWhenUnselected = true
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); await coordinator.waitForTextCapture()
        #expect(await driver.calls == 0)
        let task = try #require(coordinator.generateShortcutPreview()); await task.value
        #expect(await driver.calls == 1); #expect(capture.count == 0 && !copied)
        #expect(coordinator.previewOriginalText == "Synthetic draft")
        coordinator.close()
    }
}

extension FocusedPreviewCaptureTests {
    @Test(arguments:[FocusedTextStatus.disabled,.permissionRequired,.unsupported,.empty,.sizeLimit,.sourceChanged,.cancelled,.timedOut])
    func accurateOutcomeAlwaysHasManualGenerationFallback(_ status:FocusedTextStatus) async throws {
        let resolver = GFocusedText(), driver = GOfflineRewrite(), clipboard = GClipboard(), target = GCapture()
        resolver.result = .init(status:status,stage:.attributes)
        let coordinator = SystemWideDictationCoordinator(input:GInput(),targets:target,insertion:TextInsertionService(clipboard:clipboard,clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver,focusedTextResolver:resolver)
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.previewShortcutsEnabled = true
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); await coordinator.waitForTextCapture()
        #expect(coordinator.previewPresented && coordinator.shortcutInputText.isEmpty)
        #expect(coordinator.previewNotice == status.explanation)
        #expect(coordinator.previewCaptureDiagnostic == "\(status.rawValue) · attributes")
        #expect(await driver.calls == 0)
        coordinator.shortcutInputText = "Explicit synthetic manual input"
        let task = try #require(coordinator.generateShortcutPreview()); await task.value
        #expect(await driver.calls == 1)
        #expect(clipboard.text == "original" && clipboard.installed == 0 && clipboard.restores == 0 && clipboard.count == 1)
        #expect(target.count == 0); coordinator.close()
    }
    @Test func originalCaptureCompletesBeforePanelPresentationEvenWithRepeatedGesture() async {
        let resolver = GFocusedText(); resolver.hold = true; resolver.result = .init(text:"Selected synthetic draft",source:.selection)
        let coordinator = make(resolver)
        coordinator.openExplicitPreview(.polish,originProcessIdentifier:42); await resolver.waitForStart()
        #expect(!coordinator.previewPresented && coordinator.isResolvingShortcutText)
        coordinator.openExplicitPreview(.promptEngineering,originProcessIdentifier:99)
        #expect(!coordinator.previewPresented && resolver.calls == 1)
        let capture = coordinator.captureTask; resolver.release(); await capture?.value
        #expect(coordinator.previewPresented && coordinator.previewKind == .polish)
        #expect(coordinator.shortcutSource == .selection); coordinator.close()
    }
}

@MainActor private final class GRewriteAnchor: DictationRewriteAnchor {
    let sessionID:String, originalText:String
    var processID:Int32 { 42 }
    private weak var target:GTarget?
    private let expected:String
    var commitRejection:DictationRewriteValidationFailure?
    var lastValidationFailure:DictationRewriteValidationFailure? { commitRejection }
    var typedRejection:DictationRewriteValidationFailure?
    var rejection:TextTargetError?
    var stale = false, used = false, replacements = 0
    init(target:GTarget,text:String) { self.target = target; sessionID = target.info.session; originalText = text; expected = target.value ?? "" }
    func validate() throws { if let typedRejection { throw typedRejection }; if let rejection { throw rejection }; guard !stale, !used, target?.value == expected else { throw TextTargetError.changed } }
    func replaceValidatedSpan(_ text:String) -> TextInsertionReceipt {
        if commitRejection != nil { return .init(.targetChanged,.changed) }
        do { try validate() } catch { return .init(.targetChanged,.changed) }
        guard let target, let value = TextSelection(location:target.capturedOriginal.selection.location,length:originalText.utf16.count).replacing(in:expected,with:text) else { return .init(.unsupportedTarget,.unsupported) }
        used = true; replacements += 1; target.value = value
        return .init(.inserted,.verified,attempted:true)
    }
}
private actor InPlaceFixtureRewriter: OfflineTranscriptRewriting {
    var blocked = false, held = false, invalid = false
    var forcedOutcome:OfflineRewriteStatus?
    var calls = 0
    var requests:[OfflineRewriteRequest] = []
    var pending:CheckedContinuation<OfflineRewriteOutcome,Never>?
    var started:CheckedContinuation<Void,Never>?
    var waiting = false
    func configure(blocked:Bool = false,held:Bool = false,invalid:Bool = false,outcome:OfflineRewriteStatus? = nil) { self.blocked = blocked; self.held = held; self.invalid = invalid; self.forcedOutcome = outcome }
    func rewrite(_ request:OfflineRewriteRequest) async -> OfflineRewriteOutcome {
        calls += 1; requests.append(request)
        if let forcedOutcome { return .init(forcedOutcome,text:request.text) }
        if blocked { return .init(.resourceBlocked,text:request.text) }
        if held { waiting = true; started?.resume(); started = nil; return await withCheckedContinuation { pending = $0 } }
        if invalid { return .init(.rewritten,text:"invented requirements and numbers 123") }
        if request.kind == .promptEngineering { return .init(.rewritten,text:"## Objective\n"+request.text) }
        return .init(.rewritten,text:request.text+".")
    }
    func waitForStart() async { if waiting { return }; await withCheckedContinuation { started = $0 } }
    func release() { pending?.resume(returning:.init(.rewritten,text:"check the button.")); pending = nil }
    func cancel(requestID:String) {}
}
@Suite("In-place dictation rewrite",.serialized) @MainActor struct InPlaceRewriteTests {
    private func prepare(_ driver:InPlaceFixtureRewriter, verified:Bool = true, registrar:GPreviewRegistrar? = nil, presentation:PreviewPresentationSpy? = nil, transcript:String = "check the button", hudClock:GClock = GClock(), clock:GClock = GClock()) async throws -> (SystemWideDictationCoordinator,GTarget,GClipboard) {
        let input = GInput(), capture = GCapture(), clipboard = GClipboard()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:GShortcut(),clock:clock,hudClock:hudClock,preferenceStore:preferences(),offlineRewriter:driver,previewRegistrar:registrar,previewPresentationRequest:{ presentation?.requests.append($0) })
        coordinator.preferences.offlineAIRewriting = true; coordinator.preferences.promptEngineeringEnabled = true; coordinator.preferences.inPlaceAIRewrite = true
        coordinator.pillClicked(); await coordinator.waitUntilRecording()
        let target = try #require(capture.target)
        if !verified { target.failWrite = true }
        input.receive?(.transcript(transcript)); coordinator.stop(); input.receive?(.finished)
        await coordinator.waitForInsertionCompletion()
        return (coordinator,target,clipboard)
    }
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering]) func exactSpanRoutingLeavesSurroundingsAndHistoryUnchanged(_ kind:OfflinePreviewKind) async throws {
        let driver = InPlaceFixtureRewriter(); let (coordinator,target,clipboard) = try await prepare(driver)
        let original = try #require(coordinator.latest)
        #expect(await driver.calls == 0)
        coordinator.invokeAIShortcut(kind,originProcessIdentifier:42); await coordinator.waitForInPlaceRewrite()
        #expect(!coordinator.previewPresented && coordinator.inPlaceHUD == .success)
        #expect(target.value?.hasPrefix("a") == true && target.value?.hasSuffix("bc") == true)
        #expect(target.rewriteFixture?.replacements == 1 && coordinator.latest == original)
        #expect(clipboard.text == "original" && clipboard.installed == 0 && target.pastes == 0 && target.unicodePosts == 0)
        coordinator.invokeAIShortcut(kind,originProcessIdentifier:42); await coordinator.waitForInPlaceRewrite()
        #expect(target.rewriteFixture?.replacements == 1); coordinator.close()
    }
    @Test(arguments:["edited","other-app","uncertain"]) func unsafeTargetsNeverGenerateOrReplace(_ reason:String) async throws {
        let driver = InPlaceFixtureRewriter(); let (coordinator,target,_) = try await prepare(driver,verified:reason != "uncertain")
        if reason == "edited" { target.value = "user changed this field" }
        coordinator.invokeAIShortcut(.polish,originProcessIdentifier:reason == "other-app" ? 99 : 42); await coordinator.waitForInPlaceRewrite()
        #expect(await driver.calls == 0); #expect((target.rewriteFixture?.replacements ?? 0) == 0); #expect(!coordinator.previewPresented)
        coordinator.close()
    }
    @Test(arguments:["memory","invalid"]) func rejectedGenerationKeepsOriginal(_ reason:String) async throws {
        let driver = InPlaceFixtureRewriter(); await driver.configure(blocked:reason == "memory",invalid:reason == "invalid")
        let (coordinator,target,_) = try await prepare(driver); let original = target.value
        coordinator.invokeAIShortcut(.polish,originProcessIdentifier:42); await coordinator.waitForInPlaceRewrite()
        #expect(target.value == original && target.rewriteFixture?.replacements == 0 && coordinator.inPlaceHUD == .error)
        coordinator.close()
    }
    @Test(arguments:[false,true]) func cancellationAndEditDuringGenerationDiscardResult(_ edit:Bool) async throws {
        let driver = InPlaceFixtureRewriter(); await driver.configure(held:true)
        let (coordinator,target,_) = try await prepare(driver)
        coordinator.invokeAIShortcut(.polish,originProcessIdentifier:42); await driver.waitForStart()
        if edit { target.value = "new user text" } else { coordinator.cancelInPlaceRewrite() }
        await driver.release(); await coordinator.waitForInPlaceRewrite()
        #expect(target.rewriteFixture?.replacements == 0); coordinator.close()
    }
    @Test func replacementPreferenceDefaultsOffAndPersists() {
        let store = preferences(); var value = store.load(); #expect(!value.inPlaceAIRewrite)
        value.inPlaceAIRewrite = true; store.save(value); #expect(store.load().inPlaceAIRewrite)
    }
}

@Suite("Continuous dictation HUD") struct ContinuousHUDTests {
    @Test @MainActor func microphoneAndNonMicrophoneStatesAreHonest() {
        #expect(DictationHUDContent.resolve(phase:.recording,ai:.idle,verified:false) == .waveform)
        #expect(DictationHUDContent.resolve(phase:.finalizing,ai:.idle,verified:false) == .label("Transcribing…"))
        #expect(DictationHUDContent.resolve(phase:.inserting,ai:.idle,verified:false) == .label("Transcribing…"))
        #expect(DictationHUDContent.resolve(phase:.success,ai:.idle,verified:false) == .hidden)
        #expect(DictationHUDContent.resolve(phase:.success,ai:.idle,verified:true) == .hidden)
        #expect(DictationHUDContent.resolve(phase:.idle,ai:.polishing,verified:false) == .label("Polishing…"))
        #expect(DictationHUDContent.resolve(phase:.idle,ai:.structuring,verified:false) == .label("Structuring…"))
    }
}

// These enter through the exact callback registered by the app coordinator, not
// by directly calling the private/native delivery layer or injecting OS keys.
extension InPlaceRewriteTests {
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering])
    func registeredShortcutRoutesInPlaceWithoutPanel(_ kind:OfflinePreviewKind) async throws {
        let registrar = GPreviewRegistrar(), driver = InPlaceFixtureRewriter()
        let (c,target,clipboard) = try await prepare(driver,registrar:registrar)
        c.preferences.previewShortcutsEnabled = true
        #expect(registrar.kinds == [.polish,.promptEngineering])
        registrar.receive?(.invokeFrom(kind,processIdentifier:42)); await c.waitForInPlaceRewrite()
        #expect(c.shortcutRouteTrace.suffix(6).map(\.stage) == [.received,.inPlaceSelected,.generationRequested,.generationReturned,.replacementRequested,.replacementVerified])
        #expect(!c.previewPresented && target.rewriteFixture?.replacements == 1)
        let request = try #require(await driver.requests.last)
        #expect(request.kind == kind && request.text == "check the button")
        #expect(clipboard.text == "original" && clipboard.installed == 0 && target.pastes == 0 && target.unicodePosts == 0)
        c.close()
    }
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering])
    func registeredShortcutWithModeOffShowsOnlyHUD(_ kind:OfflinePreviewKind) async {
        let store = preferences(), registrar = GPreviewRegistrar(), driver = InPlaceFixtureRewriter()
        let c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:store,offlineRewriter:driver,previewRegistrar:registrar)
        c.preferences.offlineAIRewriting = true; c.preferences.promptEngineeringEnabled = true; c.preferences.previewShortcutsEnabled = true
        registrar.receive?(.invokeFrom(kind,processIdentifier:42))
        #expect(!c.previewPresented && c.inPlaceHUD == .error && c.shortcutRouteTrace.last?.stage == .featureDisabled)
        #expect(c.message == "Enable in-place AI rewrite in Settings.")
        #expect(await driver.calls == 0); #expect(!store.load().inPlaceAIRewrite); c.close()
    }
    @Test(arguments:[TextTargetError.denied,.unsupported,.secure,.changed])
    func sourceFailuresHaveSpecificCompactOutcome(_ failure:TextTargetError) async throws {
        let driver = InPlaceFixtureRewriter(); let (c,target,_) = try await prepare(driver)
        target.rewriteFixture?.rejection = failure
        c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.inPlaceHUD == .error && !c.previewPresented && target.rewriteFixture?.replacements == 0)
        #expect(await driver.calls == 0)
        let expected = switch failure { case .denied: "Accessibility permission"; case .unsupported:"Destination editor"; case .secure:"Secure input"; default:"changed or expired" }
        #expect(c.message.contains(expected)); #expect(c.shortcutRouteTrace.last?.stage == .sourceRejected); c.close()
    }
    @Test func missingDictationDoesNotOpenOrReadPreview() async {
        let driver = InPlaceFixtureRewriter(), capture = GCapture()
        let c = SystemWideDictationCoordinator(input:GInput(),targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),offlineRewriter:driver)
        c.preferences.inPlaceAIRewrite = true; c.preferences.promptEngineeringEnabled = true
        c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42)
        #expect(!c.previewPresented && c.message.contains("No insertion receipt exists") && capture.count == 0)
        #expect(await driver.calls == 0); c.close()
    }
    @Test(arguments:[false,true]) func conflictingSavedModeNeverFallsBack(_ memoryEnabled:Bool) {
        let store = preferences()
        let real = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:store)
        real.preferences.inPlaceAIRewrite = memoryEnabled
        var external = store.load(); external.inPlaceAIRewrite = !memoryEnabled; store.save(external)
        real.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42)
        #expect(!real.previewPresented && real.shortcutRouteTrace.last?.stage == .settingsDisagree)
        #expect(real.message.contains("another app instance")); #expect(store.load().inPlaceAIRewrite == !memoryEnabled)
        real.close()
    }
}

extension InPlaceRewriteTests {
    @Test(arguments:[OfflineRewriteStatus.modelUnavailable,.resourceBlocked,.timedOut,.cancelled])
    func registeredGenerationFailureRetainsTextAndNeverOpensPanel(_ status:OfflineRewriteStatus) async throws {
        let driver = InPlaceFixtureRewriter(), registrar = GPreviewRegistrar()
        await driver.configure(outcome:status)
        let (c,target,clipboard) = try await prepare(driver,registrar:registrar); let original = target.value
        c.preferences.previewShortcutsEnabled = true
        registrar.receive?(.invokeFrom(.promptEngineering,processIdentifier:42)); await c.waitForInPlaceRewrite()
        #expect(!c.previewPresented && c.inPlaceHUD == .error && target.value == original)
        #expect(target.rewriteFixture?.replacements == 0 && clipboard.installed == 0)
        let expected = switch status { case .modelUnavailable:"Local AI"; case .resourceBlocked:"memory/resource admission"; case .timedOut:"timed out"; default:"cancelled" }
        #expect(c.message.contains(expected) && c.previewShortcutStatus == c.message)
        #expect(await driver.calls == 1); c.close()
    }
}

@MainActor private final class PreviewPresentationSpy {
    var requests:[OfflinePreviewKind] = []
}
extension InPlaceRewriteTests {
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering], ["success","disabled","missing","denied","unsupported","secure","changed","foreign","memory","invalid","unavailable","timeout","feature-off"])
    func everyShortcutBranchMakesZeroPreviewRequests(_ kind:OfflinePreviewKind,_ scenario:String) async throws {
        let spy = PreviewPresentationSpy(), registrar = GPreviewRegistrar(), driver = InPlaceFixtureRewriter()
        await driver.configure(blocked:scenario == "memory",invalid:scenario == "invalid",outcome:scenario == "unavailable" ? .modelUnavailable : scenario == "timeout" ? .timedOut : nil)
        let (c,target,clipboard) = try await prepare(driver,verified:scenario != "missing",registrar:registrar,presentation:spy)
        c.preferences.previewShortcutsEnabled = true
        let before = target.value
        if scenario == "disabled" { c.preferences.inPlaceAIRewrite = false }
        if scenario == "feature-off" { if kind == .polish { c.preferences.offlineAIRewriting = false } else { c.preferences.promptEngineeringEnabled = false } }
        let rejection:TextTargetError? = switch scenario { case "denied": .denied; case "unsupported": .unsupported; case "secure": .secure; case "changed": .changed; default:nil }
        target.rewriteFixture?.rejection = rejection
        registrar.receive?(.invokeFrom(kind,processIdentifier:scenario == "foreign" ? 99 : 42)); await c.waitForInPlaceRewrite()
        #expect(spy.requests.isEmpty && !c.previewPresented && !c.isResolvingShortcutText)
        #expect(clipboard.text == "original" && clipboard.installed == 0 && target.pastes == 0 && target.unicodePosts == 0)
        if scenario == "success" { #expect(target.rewriteFixture?.replacements == 1 && c.inPlaceHUD == .success) }
        else { #expect(target.value == before && (target.rewriteFixture?.replacements ?? 0) == 0 && c.inPlaceHUD == .error) }
        c.close()
    }
    @Test func explicitSettingsPreviewRequestsPresenterAndShortcutFencesLateCapture() async {
        let spy = PreviewPresentationSpy(), resolver = GFocusedText(), registrar = GPreviewRegistrar()
        resolver.hold = true; resolver.result = .init(text:"Synthetic explicitly requested text",source:.selection)
        let c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),previewRegistrar:registrar,previewPresentationRequest:{ spy.requests.append($0) },focusedTextResolver:resolver)
        c.preferences.offlineAIRewriting = true; c.preferences.previewShortcutsEnabled = true
        c.openExplicitPreview(.polish,originProcessIdentifier:42); await resolver.waitForStart()
        let capture = c.captureTask
        registrar.receive?(.invokeFrom(.polish,processIdentifier:42))
        resolver.release(); await capture?.value
        #expect(spy.requests.isEmpty && !c.previewPresented)
        c.openExplicitPreview(.polish)
        #expect(spy.requests == [.polish] && c.previewPresented)
        registrar.receive?(.invokeFrom(.polish,processIdentifier:42))
        #expect(spy.requests == [.polish] && !c.previewPresented)
        c.close()
    }
    @Test(arguments:[false,true]) func cancellationOrUserEditHasZeroPresentationAndNoLateWrite(_ edit:Bool) async throws {
        let spy = PreviewPresentationSpy(), registrar = GPreviewRegistrar(), driver = InPlaceFixtureRewriter()
        await driver.configure(held:true)
        let (c,target,_) = try await prepare(driver,registrar:registrar,presentation:spy)
        c.preferences.previewShortcutsEnabled = true
        registrar.receive?(.invokeFrom(.polish,processIdentifier:42)); await driver.waitForStart()
        registrar.receive?(.invokeFrom(.promptEngineering,processIdentifier:42)); #expect(await driver.calls == 1)
        let task = c.inPlaceRunning
        #expect(task)
        let completion:Task<Void,Never>?
        if edit { target.value = "Synthetic edited source"; completion = nil } else { completion = c.cancelInPlaceRewrite() }
        await driver.release(); await completion?.value; await c.waitForInPlaceRewrite()
        #expect(spy.requests.isEmpty && !c.previewPresented && target.rewriteFixture?.replacements == 0)
        c.close()
    }
}

extension InPlaceRewriteTests {
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering])
    func disabledShortcutShowsConciseHUDAndDismissesDeterministically(_ kind:OfflinePreviewKind) async {
        let spy = PreviewPresentationSpy(), hudClock = GClock(), registrar = GPreviewRegistrar()
        let c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),hudClock:hudClock,preferenceStore:preferences(),previewRegistrar:registrar,previewPresentationRequest:{ spy.requests.append($0) })
        c.preferences.offlineAIRewriting = true; c.preferences.promptEngineeringEnabled = true; c.preferences.previewShortcutsEnabled = true
        let panel = ShortcutPreviewPanel(coordinator:c)
        registrar.receive?(.invokeFrom(kind,processIdentifier:42))
        #expect(c.compactAIStatus == "Enable in-place AI" && c.pillVisible && c.hudFeedbackVisible)
        #expect(spy.requests.isEmpty && !panel.hasCreatedPanel && !c.previewPresented)
        await hudClock.waitForSleep(2200); await hudClock.advance(2200); await c.waitForHUDFeedback()
        #expect(!c.pillVisible && c.inPlaceHUD == .idle && !panel.hasCreatedPanel)
        panel.close(); c.close()
    }
    @Test(arguments:[false,true])
    func staleSavedSettingMakesZeroPresentationRequests(_ enabled:Bool) {
        let spy = PreviewPresentationSpy(), store = preferences(), registrar = GPreviewRegistrar()
        let c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:store,previewRegistrar:registrar,previewPresentationRequest:{ spy.requests.append($0) })
        c.preferences.offlineAIRewriting = true; c.preferences.promptEngineeringEnabled = true; c.preferences.previewShortcutsEnabled = true; c.preferences.inPlaceAIRewrite = enabled
        var external = store.load(); external.inPlaceAIRewrite = !enabled; store.save(external)
        for kind in OfflinePreviewKind.allCases { registrar.receive?(.invokeFrom(kind,processIdentifier:42)) }
        #expect(spy.requests.isEmpty && !c.previewPresented && c.compactAIStatus == "Settings changed")
        c.close()
    }
}

extension InPlaceRewriteTests {
    @Test func formattedInsertedTextIsTheRewriteSourceNotRawSpeech() async throws {
        let driver = InPlaceFixtureRewriter(), spy = PreviewPresentationSpy()
        let (c,target,clipboard) = try await prepare(driver,presentation:spy,transcript:"  check   the button  ")
        #expect(c.latest?.raw == "  check   the button  ")
        #expect(c.latest?.cleaned == "check the button" && target.rewriteFixture?.originalText == "check the button")
        c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(await driver.requests.last?.text == "check the button")
        #expect(target.value == "a## Objective\ncheck the buttonbc")
        #expect(spy.requests.isEmpty && clipboard.installed == 0); c.close()
    }
    @Test(arguments:DictationRewriteValidationFailure.allCases)
    func typedValidationFailuresDoNotMislabelMissingDataAsChangedText(_ failure:DictationRewriteValidationFailure) async throws {
        let driver = InPlaceFixtureRewriter(), spy = PreviewPresentationSpy()
        let (c,target,clipboard) = try await prepare(driver,presentation:spy)
        target.rewriteFixture?.typedRejection = failure
        c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.inPlaceHUD == .error && !c.previewPresented && spy.requests.isEmpty)
        #expect((c.compactAIStatus == "Text changed") == (failure == .textMismatch))
        #expect(target.rewriteFixture?.replacements == 0 && clipboard.installed == 0)
        #expect(await driver.calls == 0); c.close()
    }
}

extension InPlaceRewriteTests {
    @Test func initialVerificationCannotAcceptCanonicalEqualityWithDifferentUTF16() async {
        let target = GTarget(text:"ab",selection:.init(location:1,length:0)), clipboard = GClipboard()
        target.observedOverride = "aéb"
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("e\u{301}",target:target,session:"s")
        #expect(receipt.status != .insertedVerified && receipt.attempted)
        #expect(target.replacements == 1 && target.pastes == 0 && clipboard.installed == 0)
    }
}

extension InPlaceRewriteTests {
    @Test(arguments:[DictationRewriteValidationFailure.textUnavailable,.invalidRange,.caretChanged])
    func finalPreflightFailureKeepsItsSourceReasonAndDoesNotBecomeAIUnavailable(_ reason:DictationRewriteValidationFailure) async throws {
        let driver = InPlaceFixtureRewriter(), spy = PreviewPresentationSpy()
        let (c,target,clipboard) = try await prepare(driver,presentation:spy)
        target.rewriteFixture?.commitRejection = reason
        c.invokeAIShortcut(.polish,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.inPlaceHUD == .error && c.compactAIStatus != "AI unavailable" && c.compactAIStatus != "Text changed")
        #expect(target.rewriteFixture?.replacements == 0 && clipboard.installed == 0 && spy.requests.isEmpty)
        #expect(await driver.calls == 1); c.close()
    }
}

// 36D: receipt existence is independent of transient UI and model outcomes.
extension InPlaceRewriteTests {
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering])
    func provenanceSurvivesTeardownHUDAndUnrelatedPreferences(_ kind:OfflinePreviewKind) async throws {
        let driver = InPlaceFixtureRewriter(), hud = GClock()
        await driver.configure(blocked:true)
        let (c,target,clipboard) = try await prepare(driver,hudClock:hud)
        #expect(c.eligibleReceiptPresent && c.provenanceReason == .none && !c.busy)
        c.preferences.spacingCleanup.toggle()
        // Exercise a genuine HUD lifecycle without replacing/consuming the record.
        c.invokeAIShortcut(kind,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.eligibleReceiptPresent && c.message.contains("memory/resource"))
        await hud.waitForSleep(2200); await hud.advance(2200); await c.waitForHUDFeedback()
        #expect(!c.hudFeedbackVisible && c.eligibleReceiptPresent)
        c.invokeAIShortcut(kind,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(await driver.calls == 2)
        #expect(target.rewriteFixture?.replacements == 0 && !c.previewPresented)
        #expect(clipboard.text == "original" && clipboard.installed == 0)
        #expect(c.verificationDiagnosticSummary.contains("eligibleReceipt=true"))
        c.close(); #expect(!c.eligibleReceiptPresent && c.provenanceReason == .invalidated)
    }
    @Test(arguments:[DictationRewriteValidationFailure.expired,.editorUnavailable,.targetChanged,.invalidRange,.textMismatch])
    func repeatedFailureKeepsSpecificProvenanceReason(_ failure:DictationRewriteValidationFailure) async throws {
        let driver = InPlaceFixtureRewriter(), (c,target,_) = try await prepare(driver)
        target.rewriteFixture?.typedRejection = failure
        c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        let reason = c.provenanceReason, message = c.message
        #expect(reason != .noReceipt && reason != .none && !c.eligibleReceiptPresent)
        c.invokeAIShortcut(.polish,originProcessIdentifier:42)
        #expect(c.provenanceReason == reason && c.message == message)
        #expect(await driver.calls == 0); #expect(!c.previewPresented)
        c.close()
    }
    @Test func uncertainReceiptNeverBecomesAuthorityAndRestartCannotRestoreIt() async throws {
        let driver = InPlaceFixtureRewriter(), (c,_,_) = try await prepare(driver,verified:false)
        #expect(!c.eligibleReceiptPresent && c.provenanceReason == .uncertain)
        c.invokeAIShortcut(.polish,originProcessIdentifier:42)
        #expect(!c.message.contains("No eligible recent dictation")); #expect(await driver.calls == 0)
        let fresh = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences())
        #expect(!fresh.eligibleReceiptPresent && fresh.provenanceReason == .noReceipt)
        c.close(); fresh.close()
    }
    @Test func anchorCreationFailureHasVerifiedReceiptButNoRangeAuthority() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), driver = InPlaceFixtureRewriter()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),offlineRewriter:driver)
        c.preferences.inPlaceAIRewrite = true; c.preferences.promptEngineeringEnabled = true
        c.pillClicked(); await c.waitUntilRecording()
        capture.target?.rewriteCreationFailure = .compositionUnavailable
        input.receive?(.transcript("Synthetic draft")); c.stop(); input.receive?(.finished)
        await c.waitForInsertionCompletion()
        #expect(c.latest?.insertion.status == .insertedVerified)
        #expect(c.provenanceReason == .rangeUnavailable && !c.eligibleReceiptPresent)
        #expect(c.verificationDiagnosticSummary.contains("verifiedReceipt=true"))
        c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42)
        #expect(c.message.contains("composition") && !c.previewPresented)
        #expect(await driver.calls == 0); c.close()
    }
}

extension InPlaceRewriteTests {
    @Test(arguments:[119_999,120_000,120_001])
    func monotonicReceiptLifetime(_ elapsed:Int64) async throws {
        let clock = GClock(), driver = InPlaceFixtureRewriter()
        await driver.configure(blocked:true)
        let (c,target,_) = try await prepare(driver,clock:clock)
        let start = await clock.now(); await clock.advance(start + elapsed)
        c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(await driver.calls == (elapsed < 120_000 ? 1 : 0))
        #expect(c.eligibleReceiptPresent == (elapsed < 120_000))
        if elapsed >= 120_000 { #expect(c.provenanceReason == .expired && c.compactAIStatus == "Dictation expired") }
        #expect(target.rewriteFixture?.replacements == 0 && !c.previewPresented)
        c.close()
    }
}

@MainActor private final class ProvenanceReceiptFixture: DictationTextInserting {
    var hasPendingClipboard:Bool { false }
    var pendingClipboardRecovery:ClipboardRecovery? { nil }
    var pending:CheckedContinuation<Void,Never>?
    var observer:CheckedContinuation<Void,Never>?
    func waitForStart() async { if pending != nil { return }; await withCheckedContinuation { observer = $0 } }
    func insert(_ text:String,target:any InsertionTarget,session:String) async -> TextInsertionReceipt {
        // Deliberately noncooperative adapter: cancellation must not grant authority.
        await withCheckedContinuation { pending = $0; observer?.resume(); observer = nil }
        try? target.replaceSelection(text)
        return .init(.inserted,.verified,attempted:true)
    }
    func release() { pending?.resume(); pending = nil }
    func reconcileClipboardState() -> ClipboardRestoration? { nil }
    func restoreAfterUserConfirmation(expectedRecoveryID:String) -> ClipboardRestoration { .unavailable }
}
extension InPlaceRewriteTests {
    @Test func cancelledInsertionCannotPublishLateVerifiedAuthority() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), insertion = ProvenanceReceiptFixture()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:insertion,shortcut:GShortcut(),clock:clock,preferenceStore:preferences())
        c.preferences.inPlaceAIRewrite = true
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("Synthetic late receipt")); c.stop(); input.receive?(.finished)
        await insertion.waitForStart(); c.cancel(); insertion.release()
        await c.waitForInsertionCompletion()
        #expect(c.latest?.insertion.status == .insertedVerified) // Actual delivery is retained honestly.
        #expect(!c.eligibleReceiptPresent && c.provenanceReason == .invalidated)
        #expect(capture.target?.rewriteFixture == nil && !c.previewPresented)
        c.close()
    }
    @Test(arguments:["disabled","cancelled","speechFailed"])
    func missingEligibilityHasActualCreationReason(_ mode:String) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences())
        c.preferences.inPlaceAIRewrite = mode != "disabled"
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("Synthetic draft"))
        if mode == "cancelled" { c.cancel() }
        else if mode == "speechFailed" { input.receive?(.failed(.recognitionFailed)) }
        else { c.stop(); input.receive?(.finished) }
        await c.waitForInsertionCompletion()
        #expect(!c.eligibleReceiptPresent)
        #expect(c.provenanceReason == (mode == "disabled" ? .disabled : .failed))
        #expect(c.latest?.insertion.status == (mode == "disabled" ? .insertedVerified : mode == "cancelled" ? .cancelled : .failed))
        c.close()
    }
}

extension InPlaceRewriteTests {
    @Test func expiryReleasesRecordWithoutShortcutAndCannotDeliverLateAI() async throws {
        let clock = GClock(), driver = InPlaceFixtureRewriter()
        await driver.configure(held:true)
        let (c,target,_) = try await prepare(driver,clock:clock)
        await clock.waitForSleep(121000)
        c.invokeAIShortcut(.polish,originProcessIdentifier:42); await driver.waitForStart()
        await clock.advance(121000); await c.waitForReceiptExpiration()
        #expect(!c.eligibleReceiptPresent && c.provenanceReason == .expired)
        await driver.release(); await c.waitForInPlaceRewrite()
        #expect(target.rewriteFixture?.replacements == 0 && c.compactAIStatus == "Dictation expired")
        #expect(!c.previewPresented); c.close()
    }
}
extension InPlaceRewriteTests {
    @Test func successiveDictationsReplaceOnlyAuthoritativeLatestRecord() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), driver = InPlaceFixtureRewriter()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),offlineRewriter:driver)
        c.preferences.inPlaceAIRewrite = true; c.preferences.promptEngineeringEnabled = true
        await driver.configure(blocked:true)
        var previous:GRewriteAnchor?
        for index in 1...3 {
            c.pillClicked()
            #expect(!c.eligibleReceiptPresent && c.provenanceReason == .invalidated)
            await c.waitUntilRecording()
            input.receive?(.transcript("Synthetic request \(index)")); c.stop(); input.receive?(.finished)
            await c.waitForInsertionCompletion()
            let current = try #require(capture.target?.rewriteFixture)
            #expect(c.eligibleReceiptPresent && c.provenanceReason == .none)
            #expect(current.sessionID == c.latest?.id && current !== previous)
            c.invokeAIShortcut(.promptEngineering,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
            #expect(await driver.requests.last?.text == "Synthetic request \(index)")
            #expect(current.replacements == 0 && (previous?.replacements ?? 0) == 0)
            previous = current
        }
        #expect(await driver.calls == 3 && !c.previewPresented)
        c.close()
    }
}


@Suite("36E insertion readback",.serialized,.timeLimit(.minutes(1))) @MainActor struct InsertionReadbackRepairTests {
    @Test(arguments:[true,false])
    func delayedTextEditLikeReadbackVerifiesWithoutSecondEffect(_ direct:Bool) async throws {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.writable = direct; target.deferDirectReadback = true; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("Hello 😀",target:target,session:"s") }
        await clock.waitForSleep(1050)
        #expect(target.readbacks == 1)
        #expect(target.replacements + target.pastes == 1)
        target.value = target.capturedOriginal.selection.replacing(in:target.capturedOriginal.text,with:"Hello 😀")
        await clock.advance(1050)
        let receipt = await task.value
        #expect(receipt.status == .insertedVerified && !service.hasPendingClipboard)
        #expect(target.replacements + target.pastes == 1 && target.unicodePosts == 0)
        #expect(clipboard.text == "original")
        #expect(service.verificationDiagnostics.contains { $0.code == .verified && $0.timing == .settling })
    }
    @Test(arguments:[InsertionReadbackFailure.unsupported,.denied,.rangeUnavailable,.rangeInvalid,.targetChanged,.secure])
    func typedReadbackRejectionDoesNotGrantReceipt(_ failure:InsertionReadbackFailure) async {
        let target = GTarget(), clipboard = GClipboard(), service = TextInsertionService(clipboard:clipboard,clock:GClock())
        target.readbackFailure = failure
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(receipt.status != .insertedVerified && receipt.attempted)
        #expect(target.value == "aXbc" && target.replacements == 1 && target.pastes == 0)
        let code:InsertionVerificationDiagnostic.Code = switch failure {
        case .unsupported: .readbackUnsupported
        case .denied,.secure: .readbackDenied
        case .rangeUnavailable: .rangeUnavailable
        case .rangeInvalid: .rangeInvalid
        default: .targetChanged
        }
        #expect(service.verificationDiagnostics.contains { $0.code == code })
        #expect(clipboard.installed == 0)
    }
    @Test(arguments:[true,false])
    func temporaryReadbackCanSettleOrCancel(_ cancel:Bool) async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock(), service = TextInsertionService(clipboard:clipboard,clock:clock)
        target.readbackFailure = .temporarilyUnavailable
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050)
        if cancel { task.cancel() } else { target.readbackFailure = nil; await clock.advance(1050) }
        let receipt = await task.value
        #expect(receipt.status == (cancel ? .uncertain : .insertedVerified))
        #expect(target.replacements == 1 && target.pastes == 0 && clipboard.installed == 0)
    }
    @Test(arguments:[true,false])
    func deadlineNeverConvertsLateReadbackToSuccess(_ direct:Bool) async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.writable = direct; target.deferDirectReadback = true; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); target.value = "aXbc"; await clock.advance(2500)
        let receipt = await task.value
        #expect(receipt.status != .insertedVerified)
        #expect(service.verificationDiagnostics.contains { $0.code == .readbackTimeout })
        #expect(service.hasPendingClipboard == !direct && clipboard.restores == 0)
    }
    @Test(arguments:[true,false])
    func focusLossDuringSettlingRemainsUncertain(_ direct:Bool) async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.writable = direct; target.deferDirectReadback = true; target.acknowledgePaste = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForSleep(1050); target.readbackFailure = .targetChanged; await clock.advance(1050)
        let receipt = await task.value
        #expect(receipt.status != .insertedVerified && target.replacements + target.pastes == 1)
        #expect(service.hasPendingClipboard == !direct && clipboard.restores == 0)
        #expect(service.verificationDiagnostics.contains { $0.code == .targetChanged })
    }
    @Test(arguments:["prefix 😀 ","curly ‘quotes’ ","line1\nline2 ","e\u{301} "])
    func exactUTF16SpanAndSurroundings(_ prefix:String) async throws {
        let text = "Dictation 😀\nnext line", target = GTarget(text:prefix+"suffix",selection:.init(location:prefix.utf16.count,length:0))
        let service = TextInsertionService(clipboard:GClipboard(),clock:GClock())
        let receipt = await service.insert(text,target:target,session:"s")
        #expect(receipt.status == .insertedVerified)
        #expect(target.value == prefix+text+"suffix")
        #expect(service.verificationDiagnostics.contains { $0.code == .verified && $0.rangeLocation == prefix.utf16.count && $0.rangeLength == text.utf16.count })
    }
    @Test(arguments:["X ","x","é"])
    func formattingOrContentMismatchNeverBecomesSuccess(_ observed:String) async {
        let target = GTarget(text:"",selection:.init(location:0,length:0)); target.observedOverride = observed
        let service = TextInsertionService(clipboard:GClipboard(),clock:GClock())
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(receipt.status != .insertedVerified && target.replacements == 1)
        #expect(service.verificationDiagnostics.contains { $0.code == .textMismatch || $0.code == .contextMismatch })
    }
    @Test func realAXErrorCategoriesAndAttributedValueHandling() {
        #expect(NativeReadbackFailureClassifier.classify([-25211,-25205]) == .denied)
        #expect(NativeReadbackFailureClassifier.classify([-25202]) == .targetChanged)
        #expect(NativeReadbackFailureClassifier.classify([-25204]) == .temporarilyUnavailable)
        #expect(NativeReadbackFailureClassifier.classify([-25212]) == .temporarilyUnavailable)
        #expect(NativeReadbackFailureClassifier.classify([-25205]) == .unsupported)
        #expect(NativeReadbackFailureClassifier.classify([-25213]) == .rangeUnavailable)
        #expect(NativeReadbackFailureClassifier.classify([]) == .rangeInvalid)
        let attributed = CFAttributedStringCreate(nil,"Hello 😀" as CFString,nil)
        #expect(NativeFieldTextReader.plainTextValue(attributed) == "Hello 😀")
        #expect(NativeFieldTextReader.plainTextValue("Hello" as CFString) == "Hello")
        #expect(NativeFieldTextReader.plainTextValue(NSNumber(value:7)) == nil)
    }
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering])
    func receiptBecomesEligibleOnlyAfterSettledReadback(_ kind:OfflinePreviewKind) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), clipboard = GClipboard(), driver = InPlaceFixtureRewriter()
        await driver.configure(blocked:true)
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),offlineRewriter:driver)
        c.preferences.inPlaceAIRewrite = true; c.preferences.offlineAIRewriting = true; c.preferences.promptEngineeringEnabled = true
        c.pillClicked(); await c.waitUntilRecording()
        let target = try #require(capture.target); target.deferDirectReadback = true
        input.receive?(.transcript("Synthetic request")); c.stop(); input.receive?(.finished)
        await clock.waitForSleep(1050)
        #expect(!c.eligibleReceiptPresent && target.rewriteFixture == nil)
        target.value = "aSynthetic requestbc"; await clock.advance(1050)
        await c.waitForInsertionCompletion()
        #expect(c.eligibleReceiptPresent && c.latest?.insertion.status == .insertedVerified)
        #expect(c.verificationDiagnosticSummary.contains("INSERTION_VERIFIED") && c.verificationDiagnosticSummary.contains("INSERTION_RECEIPT_CREATED"))
        c.invokeAIShortcut(kind,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(await driver.requests.last?.text == "Synthetic request")
        #expect(c.eligibleReceiptPresent && !c.previewPresented && clipboard.text == "original")
        #expect(!c.verificationDiagnosticSummary.contains("Synthetic request"))
        c.close()
    }
}

extension InsertionReadbackRepairTests {
    @Test(arguments:[true,false])
    func unconfirmedAXWriteNeedsActualReadbackNotAcknowledgement(_ readable:Bool) async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock(), service = TextInsertionService(clipboard:clipboard,clock:clock)
        target.unconfirmedDirectWrite = true; target.deferDirectReadback = !readable
        let task = Task { await service.insert("X",target:target,session:"s") }
        if !readable { await clock.waitForSleep(1050); await clock.advance(2500) }
        let receipt = await task.value
        #expect(receipt.status == (readable ? .insertedVerified : .dispatchedUnverified))
        #expect(target.replacements == 1 && target.pastes == 0 && target.unicodePosts == 0 && clipboard.installed == 0)
        #expect(service.verificationDiagnostics.contains { $0.code == .directDispatched && $0.status == .pending })
        #expect(service.verificationDiagnostics.contains { $0.code == (readable ? .verified : .readbackTimeout) })
    }
}


@Suite("36F cross-app capability isolation",.serialized,.timeLimit(.minutes(1))) @MainActor struct CrossAppReliabilityTests {
    @Test(arguments:[0,1,2])
    func containerFocusUsesOnlyOwnedEditorFallbacks(_ system:Int) throws {
        var visited:[String] = []
        let element = try NativeFocusedElementResolver.resolve(processID:42,application:{ visited.append("application"); return 1 },system:{ visited.append("system"); return system == 0 ? nil : (system == 1 ? 2 : 3) },window:{ visited.append("window"); return 3 },owner:{ _ in 42 },isEditor:{ $0 == 3 })
        #expect(element == 3 && visited.first == "application")
        #expect(visited.contains("window") == (system != 2))
    }
    @Test func foreignOrSecureContainerNeverFallsBackToAnotherTarget() {
        #expect(throws:TextTargetError.changed) {
            try NativeFocusedElementResolver.resolve(processID:42,application:{ 1 },system:{ Issue.record("Foreign owner must stop resolution"); return 2 },owner:{ _ in 99 },isEditor:{ _ in false })
        }
        #expect(throws:TextTargetError.secure) {
            try NativeFocusedElementResolver.resolve(processID:42,application:{ 1 },system:{ Issue.record("Secure target must stop resolution"); return 2 },owner:{ _ in 42 },isEditor:{ _ in throw TextTargetError.secure })
        }
        #expect(throws:TextTargetError.unsupported) {
            try NativeFocusedElementResolver.resolve(processID:42,application:{ 1 },system:{ 2 },window:{ 3 },owner:{ _ in 42 },isEditor:{ _ in false })
        }
    }
    @Test(arguments:[EditorReplacementCapability.available,.unavailable,.unknown],[true,false])
    func ordinaryDeliveryDoesNotRequirePreciseReplacementSupport(_ capability:EditorReplacementCapability,_ direct:Bool) async {
        let target = GTarget(), clipboard = GClipboard()
        target.replacementCapability = capability
        target.writable = direct; target.pasted = "X"
        let service = TextInsertionService(clipboard:clipboard,clock:GClock())
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(receipt.status == .insertedVerified && target.value == "aXbc")
        #expect(target.pastes == (direct ? 0 : 1) && target.replacements == (direct ? 1 : 0) && target.unicodePosts == 0)
        #expect(clipboard.text == "original" && clipboard.restores == (direct ? 0 : 1))
        #expect(service.verificationDiagnostics.contains { $0.code == (direct ? .directDispatched : .pasteDispatched) })
    }
    private func finish(_ c:SystemWideDictationCoordinator) async {
        await c.waitForInsertionCompletion()
    }
    @Test(arguments:[false,true])
    func targetIsCapturedBeforeRecordingAndHUDStateThenRevalidated(_ focusChanged:Bool) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), clipboard = GClipboard(), shortcut = GShortcut()
        capture.configure = { target in target.writable = false; target.pasted = "Synthetic draft" }
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences())
        var capturedBeforePreparing = false
        let observation = c.$phase.sink { phase in if phase == .preparing { capturedBeforePreparing = capture.target != nil && input.starts == 0 } }
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        let target = try #require(capture.target)
        #expect(capturedBeforePreparing && capture.count == 1)
        if focusChanged { target.validationError = .changed }
        input.receive?(.transcript("Synthetic draft")); shortcut.receive?(.released); input.receive?(.finished); await finish(c)
        #expect(target.pastes == (focusChanged ? 0 : 1) && target.replacements == 0)
        #expect(c.deliveryStatus == (focusChanged ? .notDelivered : .verifiedInsertion))
        #expect(clipboard.text == "original" && !c.previewPresented)
        if focusChanged { #expect(c.crossAppFailure == .targetChanged && target.value == "abc") }
        observation.cancel(); c.close()
    }
    @Test(arguments:[OfflinePreviewKind.polish,.promptEngineering])
    func customEditorMayReceivePasteWithoutReadbackOrReplacement(_ kind:OfflinePreviewKind) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), clipboard = GClipboard(), driver = InPlaceFixtureRewriter()
        capture.configure = { t in t.writable = false; t.pasted = "Synthetic draft"; t.readbackFailure = .unsupported; t.replacementCapability = .unavailable }
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:service,shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),offlineRewriter:driver)
        c.preferences.offlineAIRewriting = true; c.preferences.promptEngineeringEnabled = true; c.preferences.inPlaceAIRewrite = true
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("Synthetic draft")); c.stop(); input.receive?(.finished); await finish(c)
        let target = try #require(capture.target)
        #expect(target.value == "aSynthetic draftbc" && target.pastes == 1 && target.replacements == 0)
        #expect(c.deliveryStatus == .insertedUnverified && c.readbackStatus == .readbackUnavailable)
        #expect(c.replacementCapabilityStatus == .replacementUnsupported && !c.eligibleReceiptPresent)
        c.invokeAIShortcut(kind,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.crossAppFailure == .replacementUnsupported && c.compactAIStatus == "Editor unsupported")
        #expect(!c.previewPresented && target.rewriteFixture == nil); #expect(await driver.calls == 0)
        #expect(service.hasPendingClipboard && clipboard.restores == 0 && clipboard.text == "Synthetic draft")
        let diagnostics = c.verificationDiagnosticSummary
        #expect(diagnostics.contains("DICTATION_DELIVERY=DICTATION_INSERTED_UNVERIFIED"))
        #expect(diagnostics.contains("REPLACEMENT_CAPABILITY=EDITOR_REPLACEMENT_UNSUPPORTED"))
        #expect(!diagnostics.contains("Synthetic draft")); c.close()
    }
    @Test func verifiedPasteDoesNotGrantUnsupportedReplacementAuthority() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), clipboard = GClipboard()
        capture.configure = { t in t.writable = false; t.pasted = "Synthetic draft"; t.replacementCapability = .unavailable }
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences())
        c.preferences.inPlaceAIRewrite = true
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("Synthetic draft")); c.stop(); input.receive?(.finished); await finish(c)
        #expect(c.latest?.insertion.status == .insertedVerified && c.readbackStatus == .verifiedInsertion)
        #expect(c.provenanceReason == .replacementUnsupported && !c.eligibleReceiptPresent)
        #expect(capture.target?.rewriteFixture == nil && clipboard.text == "original")
        c.close()
    }
    @Test func missingReceiptNeverClaimsEditorUnsupported() {
        let c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences())
        c.preferences.inPlaceAIRewrite = true; c.preferences.offlineAIRewriting = true
        c.invokeAIShortcut(.polish,originProcessIdentifier:42)
        #expect(c.crossAppFailure == .noReceipt && c.replacementCapabilityStatus == .unknown)
        #expect(c.compactAIStatus != "Editor unsupported" && !c.previewPresented)
        c.close()
    }
}
extension InPlaceRewriteTests {
    @Test(arguments:[true,false])
    func generationFailureIsSeparateFromVerifiedInsertion(_ memory:Bool) async throws {
        let driver = InPlaceFixtureRewriter(); await driver.configure(blocked:memory,invalid:!memory)
        let (c,target,_) = try await prepare(driver)
        let original = target.value
        c.invokeAIShortcut(.polish,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.deliveryStatus == .verifiedInsertion && c.readbackStatus == .verifiedInsertion)
        #expect(c.generationStatus == (memory ? .memoryBlocked : .generationFailed))
        #expect(c.crossAppFailure == (memory ? .memoryBlocked : .generationFailed))
        #expect(target.value == original && target.rewriteFixture?.replacements == 0 && !c.previewPresented)
        c.close()
    }
    @Test func actualSourceMismatchHasItsOwnCategory() async throws {
        let driver = InPlaceFixtureRewriter(), (c,target,_) = try await prepare(driver)
        target.value = "Synthetic user edit"; target.rewriteFixture?.typedRejection = .textMismatch
        c.invokeAIShortcut(.polish,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.crossAppFailure == .sourceChanged && c.compactAIStatus == "Text changed")
        #expect(c.deliveryStatus == .verifiedInsertion && !c.previewPresented); #expect(await driver.calls == 0)
        c.close()
    }
}

extension CrossAppReliabilityTests {
    @Test func failedCaptureCannotReusePreviousAppsVerificationTrace() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), clipboard = GClipboard()
        capture.configure = { t in t.writable = false; t.pasted = "First synthetic" }
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:service,shortcut:GShortcut(),clock:clock,preferenceStore:preferences())
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("First synthetic")); c.stop(); input.receive?(.finished); await finish(c)
        let firstSession = try #require(c.latest?.id)
        #expect(service.verificationSession == firstSession && c.verificationDiagnosticSummary.contains("PASTE_DISPATCHED"))
        capture.failure = .unsupported; c.pillClicked()
        await c.waitUntilRecording()
        input.receive?(.transcript("Second synthetic")); c.stop(); input.receive?(.finished); await finish(c)
        #expect(c.latest?.id != firstSession && service.verificationSession == firstSession)
        #expect(c.deliveryStatus == .notDelivered && c.readbackStatus == .notRequested)
        let diagnostic = c.verificationDiagnosticSummary
        #expect(!diagnostic.contains("PASTE_DISPATCHED") && !diagnostic.contains("INSERTION_VERIFIED"))
        #expect(!c.eligibleReceiptPresent && clipboard.text == "original")
        c.close()
    }
}

extension InPlaceRewriteTests {
    @Test func disabledFeatureDoesNotReusePreviousMemoryFailureCode() async throws {
        let driver = InPlaceFixtureRewriter(); await driver.configure(blocked:true)
        let (c,target,_) = try await prepare(driver)
        c.invokeAIShortcut(.polish,originProcessIdentifier:42); await c.waitForInPlaceRewrite()
        #expect(c.crossAppFailure == .memoryBlocked)
        c.preferences.offlineAIRewriting = false
        c.invokeAIShortcut(.polish,originProcessIdentifier:42)
        #expect(c.generationStatus == .notRequested && c.crossAppFailure == .featureDisabled)
        #expect(await driver.calls == 1); #expect(target.rewriteFixture?.replacements == 0 && !c.previewPresented)
        c.close()
    }
    @Test func cancellationHasCurrentStageCodeAndCannotPublishLateResult() async throws {
        let driver = InPlaceFixtureRewriter(); await driver.configure(held:true)
        let (c,target,_) = try await prepare(driver)
        c.invokeAIShortcut(.polish,originProcessIdentifier:42); await driver.waitForStart()
        let completion = c.cancelInPlaceRewrite()
        #expect(c.generationStatus == .generationCancelled && c.crossAppFailure == .generationCancelled)
        await driver.release(); await completion?.value
        #expect(c.generationStatus == .generationCancelled && target.rewriteFixture?.replacements == 0 && !c.previewPresented)
        c.close()
    }
}


@Suite("Milestone37 core delivery",.serialized,.timeLimit(.minutes(1))) @MainActor struct CoreDelivery37Tests {
    @Test(arguments:[true,false])
    func identityBoundPasteDoesNotRequireAnExactOriginal(_ accepts:Bool) async {
        let target = GTarget(), clipboard = GClipboard(), clock = GClock()
        target.hasOriginalContext = false; target.writable = true; target.acknowledgePaste = accepts; target.pasted = "Synthetic 😀 draft"
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let receipt = await service.insert("Synthetic 😀 draft",target:target,session:"s")
        #expect(target.replacements == 0 && target.pastes == 1 && target.unicodePosts == 0)
        #expect(target.value == (accepts ? "aSynthetic 😀 draftbc" : "abc"))
        // Physical-looking fixture acceptance is not exact API verification.
        #expect(receipt.status == .dispatchedUnverified && service.hasPendingClipboard)
        #expect(clipboard.restores == 0 && clipboard.text == "Synthetic 😀 draft")
        #expect(service.verificationDiagnostics.contains { $0.code == .readbackUnsupported })
        let rejected = await service.insert("Another",target:target,session:"s")
        #expect(!rejected.attempted && target.pastes == 1) // No reuse of unacknowledged payload.
        let recovery = service.pendingClipboardRecovery
        #expect(service.restoreAfterUserConfirmation(expectedRecoveryID:recovery?.id ?? "") == .restored)
        #expect(clipboard.text == "original" && target.pastes == 1 && !service.hasPendingClipboard)
    }
    @Test func userCopySupersedesOpaquePasteWithoutRestorationOrRetry() async {
        let target = GTarget(), clipboard = GClipboard(), service = TextInsertionService(clipboard:clipboard,clock:GClock())
        target.hasOriginalContext = false; target.pasted = "X"
        _ = await service.insert("X",target:target,session:"s")
        clipboard.externalCopy("New synthetic copy")
        #expect(service.reconcileClipboardState() == .preservedNewer)
        #expect(!service.hasPendingClipboard && clipboard.text == "New synthetic copy" && clipboard.restores == 0 && target.pastes == 1)
    }
    @Test(arguments:[TextTargetError.changed,.secure,.denied])
    func unsafeOpaqueTargetCannotReceiveAnyEvent(_ failure:TextTargetError) async {
        let target = GTarget(), clipboard = GClipboard(), service = TextInsertionService(clipboard:clipboard,clock:GClock())
        target.hasOriginalContext = false; target.validationError = failure
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(!receipt.attempted && target.pastes == 0 && target.replacements == 0 && clipboard.installed == 0)
    }
    @Test func opaqueTargetCannotUseUnverifiableTypingWhenClipboardIsUnsupported() async {
        let target = GTarget(), clipboard = GClipboard(); target.hasOriginalContext = false; target.unicodeSupported = true; clipboard.unsupported = true
        let receipt = await TextInsertionService(clipboard:clipboard,clock:GClock()).insert("X",target:target,session:"s")
        #expect(!receipt.attempted && target.pastes == 0 && target.unicodePosts == 0 && clipboard.text == "original")
    }
    @Test func readOnlySelectionOrSecureContextDoesNotAuthorizeOpaquePaste() {
        #expect(!NativeEditorCapability.allowsIdentityOnlyPaste(enabled:true,editable:nil,writableText:false,console:false))
        #expect(!NativeEditorCapability.allowsIdentityOnlyPaste(enabled:true,editable:false,writableText:true,console:false))
        #expect(!NativeEditorCapability.allowsIdentityOnlyPaste(enabled:false,editable:true,writableText:true,console:false))
        #expect(!NativeEditorCapability.allowsIdentityOnlyPaste(enabled:true,editable:true,writableText:true,console:true))
        #expect(!NativeEditorCapability.allowsIdentityOnlyPaste(enabled:true,editable:true,writableText:true,console:false,secure:true))
        #expect(NativeEditorCapability.allowsIdentityOnlyPaste(enabled:true,editable:true,writableText:false,console:false))
    }
    @Test func sameOwnershipRevisionCannotHideAChangedClipboardPayload() throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Original synthetic copy",forType:.string)
        let native = NativeDictationPasteboard(pasteboard:board), snapshot = try native.snapshot()
        let ownership = try native.install("Synthetic payload",replacing:snapshot)
        let count = board.changeCount
        #expect(native.owns(ownership))
        board.setString("New synthetic copy",forType:.string)
        #expect(board.changeCount == count) // Real NSPasteboard, not the user's clipboard.
        #expect(!native.owns(ownership) && native.isSuperseded(ownership))
        #expect(native.restore(snapshot,ifOwned:ownership) == .preservedNewer)
        #expect(board.string(forType:.string) == "New synthetic copy")
    }
    private func terminal(_ c:SystemWideDictationCoordinator) async {
        await c.waitForInsertionCompletion()
    }
    @Test func noExactContextCreatesNoAIReceiptAndPreservesHistoryAndPipelineState() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), clipboard = GClipboard(), history = GHistory(), driver = InPlaceFixtureRewriter()
        capture.configure = { t in t.hasOriginalContext = false; t.pasted = "Synthetic draft" }
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history,offlineRewriter:driver)
        c.preferences.offlineAIRewriting = true; c.preferences.promptEngineeringEnabled = true; c.preferences.inPlaceAIRewrite = true
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("Synthetic draft")); c.stop(); input.receive?(.finished); await terminal(c)
        #expect(c.audioCaptureResult == .success && c.transcriptionResult == .success && c.targetCaptureResult == .success)
        #expect(c.targetValidationResult == .success && c.insertionDispatchResult == .dispatched && c.pasteboardLeaseResult == .recoveryPending)
        #expect(c.latest?.cleaned == "Synthetic draft" && c.latest?.insertion.status == .dispatchedUnverified)
        #expect(c.entries.count == 1 && !c.eligibleReceiptPresent)
        for kind in OfflinePreviewKind.allCases { c.invokeAIShortcut(kind,originProcessIdentifier:42); await c.waitForInPlaceRewrite() }
        #expect(await driver.calls == 0); #expect(!c.previewPresented && capture.target?.rewriteFixture == nil)
        #expect(!c.historyCopyAllowed)
        c.restoreClipboardAfterConfirmation(expectedRecoveryID:c.clipboardRecoveryID)
        #expect(c.pasteboardLeaseResult == .restored && c.historyCopyAllowed && clipboard.text == "original")
        let metadata = c.verificationDiagnosticSummary
        for code in ["CAPTURE_RESULT=SUCCESS","TRANSCRIPTION_RESULT=SUCCESS","TARGET_CAPTURE_RESULT=SUCCESS","TARGET_VALIDATION_RESULT=SUCCESS","PASTEBOARD_LEASE_RESULT=RESTORED","INSERTION_DISPATCH_RESULT=DISPATCHED_UNVERIFIED","DESTINATION_READBACK_RESULT=ACCESSIBILITY_READBACK_UNAVAILABLE"] { #expect(metadata.contains(code)) }
        #expect(!metadata.contains("Synthetic draft")); c.close()
    }
    @Test func cancelledOpaqueDictationDoesNotDispatchOrLoseItsCompletedText() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), clipboard = GClipboard()
        capture.configure = { $0.hasOriginalContext = false }
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences())
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("Synthetic cancelled draft")); c.cancel(); await terminal(c)
        #expect(c.audioCaptureResult == .cancelled && c.transcriptionResult == .cancelled)
        #expect(c.latest?.cleaned == "Synthetic cancelled draft" && c.latest?.insertion.status == .cancelled)
        #expect(capture.target?.pastes == 0 && clipboard.installed == 0 && !c.eligibleReceiptPresent)
        c.close()
    }
}

private actor PreDispatchClock37:TaskClock {
    var calls = 0
    var held:CheckedContinuation<Int64,Never>?
    var observer:CheckedContinuation<Void,Never>?
    func now() async -> Int64 {
        calls += 1
        if calls == 3 { return await withCheckedContinuation { held = $0; observer?.resume(); observer = nil } }
        return 1000
    }
    func sleep(until:Int64) async throws { throw CancellationError() }
    func waitForHeldNow() async { if held != nil { return }; await withCheckedContinuation { observer = $0 } }
    func release() { held?.resume(returning:1000); held = nil }
}
extension CoreDelivery37Tests {
    @Test func cancelWhilePreDispatchClockIsSuspendedCannotPaste() async {
        let target = GTarget(), clipboard = GClipboard(), clock = PreDispatchClock37()
        target.hasOriginalContext = false
        let service = TextInsertionService(clipboard:clipboard,clock:clock)
        let task = Task { await service.insert("X",target:target,session:"s") }
        await clock.waitForHeldNow(); task.cancel(); await clock.release()
        let receipt = await task.value
        #expect(receipt.status == .cancelled && !receipt.attempted && target.pastes == 0)
        #expect(clipboard.text == "original" && clipboard.restores == 1 && !service.hasPendingClipboard)
    }
    @Test func postPublicationMismatchPreservesNewDataWithoutDispatch() async throws {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("Original synthetic",forType:.string)
        let native = NativeDictationPasteboard(pasteboard:board,publication:{ items in
            let result = board.writeObjects(items)
            board.setString("New synthetic data",forType:.string)
            return result
        })
        let target = GTarget(); target.writable = false
        let service = TextInsertionService(clipboard:native,clock:GClock())
        let receipt = await service.insert("X",target:target,session:"s")
        #expect(!receipt.attempted && target.pastes == 0)
        #expect(board.string(forType:.string) == "New synthetic data" && !service.hasPendingClipboard)
    }
}

// 37R1: explicit AX failures must not be hidden by another focus route.
extension CoreDelivery37Tests {
    @Test(arguments:[TextTargetError.denied,.changed])
    func failedApplicationFocusReadDoesNotFallBack(_ error:TextTargetError) {
        #expect(throws:error) {
            try NativeFocusedElementResolver.resolve(processID:42,application:{ () throws -> Int? in throw error },system:{ Issue.record("Explicit failure must stop resolution"); return 2 },window:{ Issue.record("No window search after explicit failure"); return 3 },owner:{ _ in 42 })
        }
    }
    @Test func failedSystemFocusReadDoesNotSearchAnotherTarget() {
        #expect(throws:TextTargetError.denied) {
            try NativeFocusedElementResolver.resolve(processID:42,application:{ nil as Int? },system:{ () throws -> Int? in throw TextTargetError.denied },window:{ Issue.record("Denied system read must stop"); return 3 },owner:{ _ in 42 })
        }
    }
    @Test func ordinaryMissingFocusStillAllowsTheExistingBoundedWindowRoute() throws {
        var visited:[String] = []
        let result = try NativeFocusedElementResolver.resolve(processID:42,application:{ visited.append("application"); return nil as Int? },system:{ visited.append("system"); return nil as Int? },window:{ visited.append("window"); return 3 },owner:{ _ in 42 },isEditor:{ $0 == 3 })
        #expect(result == 3 && visited == ["application","system","window"])
    }
}

extension ContinuousHUDTests {
    @Test @MainActor func startupAndOrdinaryErrorsHaveNoVisiblePillContent() {
        #expect(DictationHUDContent.resolve(phase:.preparing,ai:.idle,verified:false) == .hidden)
        #expect(DictationHUDContent.resolve(phase:.error,ai:.idle,verified:false) == .label("Check dictation"))
        #expect(DictationHUDContent.resolve(phase:.recording,ai:.idle,verified:false) == .waveform)
    }
    @Test @MainActor func bothPostSpeechStagesKeepTheRequestedTranscriptionLabel() {
        for phase in [SystemWideDictationCoordinator.Phase.finalizing,.inserting] {
            #expect(DictationHUDContent.resolve(phase:phase,ai:.idle,verified:false) == .label("Transcribing…"))
        }
    }
}

@MainActor private extension SystemWideDictationCoordinator {
    func waitUntilRecording() async {
        await waitForCaptureStartup()
        #expect(phase == .recording)
    }
}

@Suite("Milestone38 held dictation",.serialized) @MainActor struct HeldSpeech38Tests {
    @Test(arguments:[15_000,60_000,180_000,300_000])
    func heldSessionNeverStopsOrInsertsBeforeRelease(_ milliseconds:Int64) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), history = GHistory()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript("first తెలుగు English"))
        await clock.advance(1000 + milliseconds)
        #expect(c.phase == .recording && input.stops == 0)
        #expect(capture.target?.replacements == 0 && capture.target?.pastes == 0)
        input.receive?(.transcript("first తెలుగు English last words"))
        shortcut.receive?(.released); #expect(input.stops == 1 && c.phase == .finalizing)
        input.receive?(.finished); await history.waitForEntry()
        #expect(c.latest?.raw == "first తెలుగు English last words")
        #expect(c.latest?.durationMilliseconds == milliseconds)
        #expect(capture.target?.replacements == 1)
        c.close()
    }
    @Test func providerEndWhileHeldRetainsTextWithoutAnyInsertion() async {
        let input = GInput(), capture = GCapture(), history = GHistory()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),history:history)
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("available earlier speech")); input.receive?(.finished)
        await history.waitForEntry()
        #expect(capture.target?.replacements == 0 && capture.target?.pastes == 0)
        #expect(c.latest?.raw == "available earlier speech" && c.verificationDiagnosticSummary.contains("providerEnded"))
        c.close()
    }
}

extension GlobalHistoryTests {
    @Test func maximumLongDictationReopensWithoutCorruptingHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WF-LongHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("history.store")
        let text = String(repeating:"\\",count:DictationText.maximumBytes)
        let value = DictationHistoryEntry(id:UUID().uuidString,timestamp:Date(),raw:text,cleaned:text,sourceApplication:nil,durationMilliseconds:300_000,insertion:.init(.unsupportedTarget,.manualOnly))
        let first = try await SwiftDataDictationHistoryStore.open(url:url)
        try await first.append(value); await first.close()
        let reopened = try await SwiftDataDictationHistoryStore.open(url:url)
        #expect(try await reopened.load() == [value]); await reopened.close()
    }
}
extension VoiceParityFormattingTests {
    @Test func commonTyposWorkWithoutAnAppleSuggestionAndKeepProtectedTerms() {
        var options = DictationFormattingOptions(); options.correctSpelling = true
        options.vocabulary = ["teh"]
        #expect(DictationFormatting.format("teh adn recieve seperate `adn` /tmp/adn Teh తెలుగు",options:options,whitespace:true) == "teh and receive separate `adn` /tmp/adn Teh తెలుగు")
        options.correctSpelling = false
        #expect(DictationFormatting.format("adn recieve",options:options,whitespace:true) == "adn recieve")
    }
    @Test func spellingNeverChangesAnAsciiSuffixInsideUnicodeWord() {
        var options = DictationFormattingOptions(); options.correctSpelling = true
        #expect(DictationFormatting.format("తెలుగుadn caféadn",options:options,whitespace:true,correction:{ _ in "BAD" }) == "తెలుగుadn caféadn")
    }
}

extension GlobalCoordinatorTests {
    @Test func resourceInstallationIsExplicitAndPreparesWithoutRecordingOrInsertion() async {
        let input = GInput(), capture = GCapture(), backend = SpeechBackendFixture38L2()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),localeIdentifier:"en-US",speechResources:AppleSpeechResourceService(backend:backend))
        c.installSpeechResources(); #expect(backend.installationCalls == 0)
        await c.inspectSpeech(); #expect(backend.installationCalls == 0 && c.canInstallSpeechResources)
        backend.request.held = true
        c.installSpeechResources(); c.installSpeechResources(); await backend.request.waitForStart()
        #expect(!c.canTerminateSafely())
        c.startManual(); c.pillClicked()
        #expect(input.starts == 0 && capture.count == 0)
        backend.request.release(); await c.waitForSpeechResourceSetup()
        #expect(backend.installationCalls == 1 && backend.preparationCalls == 1)
        #expect(c.speechPreparation?.engine == .speechTranscriber && c.speechConfiguration?.readyModernEngine == .speechTranscriber)
        #expect(c.localeIdentifier == "en-US" && c.speechResourceStatus.contains("Preparation verified"))
        #expect(input.starts == 0 && capture.count == 0 && !c.speechResourceWorking)
        c.close()
    }
    @Test func downloadFailureShowsActualCodeAndNeverRecords() async {
        let backend = SpeechBackendFixture38L2(), input = GInput()
        backend.request.failure = NSError(domain:"NSURLErrorDomain",code:-1009)
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),localeIdentifier:"en-US",speechResources:AppleSpeechResourceService(backend:backend))
        await c.inspectSpeech(); c.installSpeechResources(); await c.waitForSpeechResourceSetup()
        #expect(c.speechPreparation == nil && c.speechResourceStatus.contains("NSURLErrorDomain") && c.speechResourceStatus.contains("-1009"))
        #expect(input.starts == 0 && backend.preparationCalls == 0)
        c.close()
    }
    @Test func stoppedResourceWaitCannotPublishLateSuccessOrStartCapture() async {
        let backend = SpeechBackendFixture38L2(), input = GInput(); backend.request.held = true
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),localeIdentifier:"en-US",speechResources:AppleSpeechResourceService(backend:backend))
        await c.inspectSpeech(); c.installSpeechResources(); await backend.request.waitForStart()
        let stopped = c.stopWaitingForSpeechResources(); backend.request.release(); await stopped?.value
        #expect(c.speechPreparation == nil && !c.speechResourceWorking && c.speechResourceStatus.hasPrefix("Stopped waiting"))
        #expect(input.starts == 0 && backend.preparationCalls == 0)
        c.close()
    }
    @Test func activeRecordingCannotInitiateAssetInstallation() async {
        let backend = SpeechBackendFixture38L2(), input = GInput()
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),localeIdentifier:"en-US",speechResources:AppleSpeechResourceService(backend:backend))
        await c.inspectSpeech(); c.startManual(); await c.waitUntilRecording(); c.installSpeechResources()
        #expect(backend.installationCalls == 0 && !c.speechResourceWorking)
        c.cancel(); c.close()
    }
}
extension HeldSpeech38Tests {
    @Test(arguments:[60_000,180_000,300_000])
    func longCancellationAndMidRecordingPausesNeverInsert(_ duration:Int64) async {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), shortcut = GShortcut()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript("first తెలుగు")); await clock.advance(1000+duration/2)
        #expect(c.phase == .recording && input.stops == 0 && capture.target?.replacements == 0)
        // No result during a long silence pause; the prefix remains available.
        #expect(c.raw == "first తెలుగు")
        input.receive?(.transcript("first తెలుగు last English")); await clock.advance(1000+duration)
        c.cancel(); await c.waitForInsertionCompletion(); shortcut.receive?(.released)
        #expect(c.latest?.raw == "first తెలుగు last English" && c.latest?.insertion.outcome == .cancelled)
        #expect(input.cancels > 0 && capture.target?.replacements == 0 && capture.target?.pastes == 0)
        c.close()
    }
}

extension GlobalCoordinatorTests {
    @Test func networkBlockingCannotBeBypassedBySpeechInstallAction() async {
        let backend = SpeechBackendFixture38L2()
        let c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),localeIdentifier:"en-US",speechResources:AppleSpeechResourceService(backend:backend))
        await c.inspectSpeech(); c.preferences.blockNetworkRequests = true
        #expect(!c.canInstallSpeechResources); c.installSpeechResources()
        #expect(backend.installationCalls == 0 && c.preferences.blockNetworkRequests)
        c.close()
    }
}

@Suite("38L3 complete transcript failure recovery",.serialized) @MainActor struct SpeechRecovery38L3Tests {
    @Test(arguments:[20_000,40_000,75_000,180_000,300_000],[1101,1107])
    func failureWhileHeldRetainsFullAvailableSnapshotWithoutInsertion(_ duration:Int64,_ code:Int) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), shortcut = GShortcut()
        var copies: [String] = []
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history,historyCopy:{ copies.append($0); return true })
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript("SYNTHETIC_PRIVATE_START")); await clock.advance(1000+duration/2)
        #expect(c.phase == .recording && input.stops == 0)
        let full = "SYNTHETIC_PRIVATE_START middle last words"
        input.receive?(.transcript(full)); await clock.advance(1000+duration)
        var diagnostic = DictationSpeechDiagnostics(); diagnostic.provider = .legacyOnDevice; diagnostic.stage = .legacyRecognition
        diagnostic.captureMilliseconds = duration; diagnostic.recognitionMilliseconds = duration
        diagnostic.captureActiveAtSnapshot = true; diagnostic.stoppedBeforeRelease = true; diagnostic.preservedBytes = full.utf8.count
        diagnostic.partialResults = 3; diagnostic.preservedSegments = 3
        diagnostic.nativeError = .init(primary:.init(domain:"kAFAssistantErrorDomain",code:code))
        input.injectedSpeechDiagnostics = diagnostic
        input.receive?(.failed(.recognitionFailed)); await c.waitForInsertionCompletion()
        #expect(c.latest?.raw == full && c.latest?.insertion.reason == .speechFailed)
        #expect(capture.target?.replacements == 0 && capture.target?.pastes == 0 && copies.isEmpty)
        #expect(c.message.contains(String(code)) && c.speechFailureDiagnostics?.captureMilliseconds == duration)
        #expect(c.speechDiagnosticSummary.contains("hotkeyHeldObserved=true"))
        #expect(!c.speechDiagnosticSummary.contains("SYNTHETIC_PRIVATE_START"))
        #expect(c.speechFailureDiagnostics?.failure != "timedOut")
        shortcut.receive?(.released); #expect(capture.target?.replacements == 0)
        #expect(c.copyReviewedText(try #require(c.latest).raw)); #expect(copies == [full])
        c.close()
    }
    @Test(arguments:[10_000,20_000,40_000,45_000,75_000,180_000,300_000])
    func releaseWaitsForLateTranscriptAndOneCompletion(_ duration:Int64) async {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences())
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript("start")); await clock.advance(1000+duration)
        #expect(c.phase == .recording && input.stops == 0 && capture.target?.replacements == 0)
        shortcut.receive?(.released); #expect(c.phase == .finalizing && input.stops == 1)
        // Queued recognition completes AFTER release; never insert an earlier hypothesis.
        input.receive?(.transcript("start middle end")); input.receive?(.finished); await c.waitForInsertionCompletion()
        #expect(c.latest?.raw == "start middle end" && capture.target?.replacements == 1)
        input.receive?(.finished); #expect(capture.target?.replacements == 1)
        c.close()
    }
    @Test func terminalMetadataIsBoundedAcrossManySessions() async {
        let input = GInput()
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences())
        for _ in 0..<12 {
            c.startManual(); await c.waitUntilRecording(); input.receive?(.transcript("synthetic draft")); c.stop(); input.receive?(.finished); await c.waitForInsertionCompletion()
        }
        #expect(c.speechRunDiagnostics.count == 8)
        #expect(!c.speechDiagnosticSummary.contains("synthetic draft"))
        c.close()
    }
}

extension SpeechRecovery38L3Tests {
    @Test func ambiguousCandidateIsExplicitRecoveryNeverJoinedOrLogged() async {
        let input = GInput(), capture = GCapture()
        var copied: [String] = []
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences(),historyCopy:{ copied.append($0); return true })
        c.pillClicked(); await c.waitUntilRecording()
        input.receive?(.transcript("ACCEPTED_PRIVATE_PREFIX"))
        input.unmergedRecognitionText = "UNMERGED_PRIVATE_CANDIDATE"
        var diagnostics = DictationSpeechDiagnostics(); diagnostics.stage = .transcriptMerge; diagnostics.mergeRejection = "legacyTimestampReset"
        diagnostics.preservedBytes = 23; diagnostics.unmergedCandidateBytes = 26
        input.injectedSpeechDiagnostics = diagnostics
        input.receive?(.failed(.recognitionFailed)); await c.waitForInsertionCompletion()
        #expect(c.latest?.raw == "ACCEPTED_PRIVATE_PREFIX")
        #expect(c.unmergedSpeechRecoveryEntry?.raw == "UNMERGED_PRIVATE_CANDIDATE")
        #expect(capture.target?.replacements == 0 && capture.target?.pastes == 0 && copied.isEmpty)
        #expect(!c.speechDiagnosticSummary.contains("ACCEPTED_PRIVATE_PREFIX") && !c.speechDiagnosticSummary.contains("UNMERGED_PRIVATE_CANDIDATE"))
        c.close()
    }
}

@MainActor private final class ActivationCapture38L3R3:InsertionTargetCapturing {
    var observedApplicationIdentity:DictationApplicationIdentity? = .init(processID:42,launchTime:1,bundleIdentifier:"fixture.Editor")
    var expected:[DictationActivationContext]=[]
    var unboundCalls=0
    var target:GTarget?
    func capture(session:String) throws -> any InsertionTarget { unboundCalls += 1;throw TextTargetError.unsupported }
    func capture(session:String,activation:DictationActivationContext) throws -> any InsertionTarget {
        expected.append(activation)
        guard activation.permits(observedApplicationIdentity) else { throw TextTargetError.changed }
        let target=GTarget(session:session);self.target=target;return target
    }
}
@Suite("38L3R3 dictation activation identity",.serialized) @MainActor struct ActivationIdentity38L3R3Tests {
    func origin(_ process:Int32=42,_ launch:Double=1,_ bundle:String="fixture.Editor",unchanged:Bool=true)->DictationActivationContext {
        .init(application:.init(processID:process,launchTime:launch,bundleIdentifier:bundle),pressUptime:10,source:"fixture",activationUnchanged:unchanged)
    }
    @Test func immutableOriginRejectsOtherAppsRelaunchesAndActivationChanges() {
        let context=origin()
        #expect(context.permits(context.application))
        #expect(!context.permits(origin(43).application))
        #expect(!context.permits(origin(42,2).application))
        #expect(!context.permits(origin(42,1,"fixture.Other").application))
        #expect(!origin(unchanged:false).permits(context.application))
        #expect(!context.permits(nil))
        #expect(!DictationActivationContext(application:nil,pressUptime:10,source:"fixture").permits(context.application))
    }
    @Test func mailboxGenerationInvalidatesQueuedPressEvenAfterAppReturns() {
        let app=origin().application,mailbox=DictationActivationIdentityMailbox(origin().application)
        let first=mailbox.snapshot()
        mailbox.update(origin(43).application);mailbox.update(app)
        #expect(first.application==mailbox.snapshot().application && first.epoch != mailbox.snapshot().epoch)
    }
    @Test func nativeCaptureRejectsMissingOriginBeforeAnyEditorAXRead() {
        let capture=NativeInsertionTargetCapture()
        #expect(throws:TextTargetError.changed) { try capture.capture(session:"fixture",activation:.init(application:nil,pressUptime:10,source:"fixture")) }
        #expect(capture.captureDiagnostics.allSatisfy { $0.code == .targetChanged })
        #expect(capture.failureExplanation?.contains("Nothing was redirected") == true)
    }
    @Test func boundCaptureCannotSilentlyUseAnUnboundConformer() {
        let capture=GCapture()
        #expect(throws:TextTargetError.changed) { try capture.capture(session:"fixture",activation:origin()) }
        #expect(capture.count==0)
    }
    @Test func matchingPressOriginIsCapturedOnceBeforeRecording() async {
        let input=GInput(),capture=ActivationCapture38L3R3(),shortcut=GShortcut(),clipboard=GClipboard()
        shortcut.activationContext=origin()
        let c=SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        c.enableShortcut();shortcut.receive?(.pressed);await c.waitUntilRecording()
        #expect(capture.expected==[origin()] && capture.unboundCalls==0)
        shortcut.activationContext=origin(99);shortcut.receive?(.pressed)
        input.receive?(.transcript("fixture speech"));shortcut.receive?(.released);input.receive?(.finished);await c.waitForInsertionCompletion()
        #expect(capture.expected.count==1 && capture.target?.replacements==1)
        #expect(capture.target?.value=="afixture speechbc")
        #expect(c.speechDiagnosticSummary.contains("pid=42") && !c.speechDiagnosticSummary.contains("fixture speech"))
        c.close()
    }
    @Test func focusSwitchBeforeCapturePreservesTranscriptWithoutAnyDispatch() async {
        let input=GInput(),capture=ActivationCapture38L3R3(),shortcut=GShortcut(),clipboard=GClipboard()
        shortcut.activationContext=origin(99,1,"fixture.Chat")
        let c=SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        c.enableShortcut();shortcut.receive?(.pressed);await c.waitUntilRecording()
        input.receive?(.transcript("all fixture speech"));shortcut.receive?(.released);input.receive?(.finished);await c.waitForInsertionCompletion()
        #expect(capture.expected.count==1 && capture.unboundCalls==0 && capture.target==nil)
        #expect(c.latest?.raw=="all fixture speech" && c.latest?.insertion.status == .targetChanged)
        #expect(c.compactDictationStatus == "Target changed")
        #expect(clipboard.installed==0 && clipboard.restores==0)
        #expect(c.speechDiagnosticSummary.contains("fixture.Chat") && c.speechDiagnosticSummary.contains("fixture.Editor"))
        c.close()
    }
}

extension ActivationIdentity38L3R3Tests {
    @Test func eventPredatingActivationCannotBindToTheNewForegroundApp() {
        #expect(DictationActivationTiming.accepts(event:21,observed:22,activation:20))
        #expect(!DictationActivationTiming.accepts(event:19,observed:22,activation:20))
        #expect(!DictationActivationTiming.accepts(event:0,observed:22,activation:20))
        #expect(!DictationActivationTiming.accepts(event:23,observed:22,activation:20))
        #expect(!DictationActivationTiming.accepts(event:.nan,observed:22,activation:20))
        #expect(DictationActivationTiming.accepts(event:20,observed:20,activation:20))
    }
}

@Suite("39A-R1 independent Agent voice") @MainActor struct AgentHotkeyR1Tests {
    private func prefs() -> DictationPreferenceStore { DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!) }
    @Test(arguments:[5000,20000,45000]) func agentReleasePlansOnceWithoutInsertionThenDictation(_ duration:Int64) async throws {
        let input = GInput(), target = GCapture(), board = GClipboard(), clock = GClock(), dictation = GShortcut(), agent = GShortcut(), history = GHistory()
        let c = SystemWideDictationCoordinator(input:input,targets:target,insertion:TextInsertionService(clipboard:board,clock:clock),shortcut:dictation,agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },clock:clock,preferenceStore:prefs(),history:history)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        c.personalAgentQueueURL = root.appendingPathComponent("queue.json"); defer { c.close(); try? FileManager.default.removeItem(at:root) }
        c.enableShortcut(); c.enableAgentShortcut()
        #expect(agent.configuredKey == .rightControl); #expect(dictation.configuredKey == .fn)
        agent.receive?(.pressed); await c.waitUntilRecording(); let old = input.receive
        #expect(c.pillContent == .label("Agent listening"))
        agent.receive?(.pressed); dictation.receive?(.pressed); dictation.receive?(.released)
        #expect(input.starts == 1); #expect(c.phase == .recording)
        input.receive?(.transcript("Open Safari")); await clock.advance(1000+duration)
        agent.receive?(.released); #expect(c.pillContent == .label("Processing command"))
        input.receive?(.finished); agent.receive?(.released); old?(.finished)
        #expect(c.agentRecords.count == 1); #expect(c.agentPlan?.steps.first?.text == "Safari")
        #expect(c.agentRecords.first?.state == .awaitingApproval); #expect(c.pillContent == .label("Approval required"))
        #expect(target.count == 0); #expect(board.installed == 0); #expect(board.restores == 0); #expect(board.text == "original")
        #expect(try await history.load().isEmpty)
        if let id = c.agentPlan?.id { c.cancelAgentTask(id) }
        dictation.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript("Open Safari")); dictation.receive?(.released); input.receive?(.finished)
        await history.waitForEntry()
        #expect(target.count == 1); #expect(target.target?.value == "aOpen Safaribc"); #expect(c.agentRecords.count == 1)
    }
    @Test(arguments:["cancel","failure","unexpected","empty","unknown","secure","overflow"])
    func incompleteSpeechNeverPlansOrInserts(_ scenario:String) async throws {
        let input = GInput(), target = GCapture(), board = GClipboard(), agent = GShortcut()
        let blocked = GSecureGate()
        let c = SystemWideDictationCoordinator(input:input,targets:target,insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{ if blocked.value { throw TextTargetError.secure } },agentConflict:{ _ in false },preferenceStore:prefs())
        defer { c.close() }; c.enableAgentShortcut(); agent.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript("Open Safari"))
        switch scenario {
        case "cancel": agent.receive?(.cancelled)
        case "failure": input.receive?(.failed(.recognitionFailed))
        case "unexpected": input.receive?(.finished)
        case "secure": blocked.value = true; input.receive?(.transcript("Open Safari"))
        default:
            input.receive?(.transcript(scenario == "empty" ? "" : scenario == "overflow" ? String(repeating:"x",count:DictationText.maximumBytes+1) : "send a message"))
            agent.receive?(.released); input.receive?(.finished)
        }
        #expect(c.agentPlan == nil); #expect(c.agentRecords.isEmpty); #expect(target.count == 0); #expect(board.installed == 0)
    }
    @Test func collisionRebindAndDeniedCapture() async {
        let input = GInput(), agent = GShortcut()
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{ throw TextTargetError.secure },agentConflict:{ $0 == .rightCommand },preferenceStore:prefs())
        defer { c.close() }; c.enableShortcut(); c.enableAgentShortcut()
        c.changeAgentKey(.fn); #expect(c.preferences.agentKey == .rightControl)
        c.changeAgentKey(.rightCommand); #expect(c.preferences.agentKey == .rightControl)
        c.changeAgentKey(.rightOption); #expect(c.preferences.agentKey == .rightOption)
        c.changeActivationKey(.rightOption); #expect(c.preferences.activationKey == .fn)
        agent.receive?(.pressed); #expect(input.starts == 0); #expect(c.agentHUD == "Agent unavailable")
        c.disableAgentShortcut(); agent.authorizationReady = false; c.enableAgentShortcut(); #expect(!c.agentShortcutEnabled)
    }
    @Test func releaseDuringStartupAndStaleCallbacksAreFenced() async {
        let input = GInput(), agent = GShortcut(); input.hold = true
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },preferenceStore:prefs())
        defer { c.close() }; c.enableAgentShortcut(); agent.receive?(.pressed); await input.waitForStart()
        let stale = input.receive; agent.receive?(.released); input.resolve(); await c.waitForCaptureStartup()
        stale?(.transcript("Open Safari")); stale?(.finished)
        #expect(!c.busy); #expect(c.agentPlan == nil); #expect(c.agentRecords.isEmpty)
    }
    @Test(arguments:[DictationFailure.microphoneDenied,.speechDenied,.unavailable,.assetsMissing,.audioUnavailable,.busy,.recognitionFailed,.overflow,.timedOut,.providerEnded,.anotherInstance], [false,true])
    func allSpeechFailuresKeepPartialSpeechOutOfPlanner(_ failure:DictationFailure, atStart:Bool) async {
        let input = GInput(), agent = GShortcut(), board = GClipboard()
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },preferenceStore:prefs())
        input.startFailure = atStart ? failure : nil
        defer { c.close() }; c.enableAgentShortcut(); agent.receive?(.pressed); await c.waitForCaptureStartup()
        if !atStart { input.receive?(.transcript("Create a note partial")); input.receive?(.failed(failure)) }
        agent.receive?(.released); input.receive?(.finished)
        #expect(!c.busy); #expect(c.agentPlan == nil); #expect(c.agentRecords.isEmpty); #expect(board.installed == 0)
    }
    @Test func rapidRepeatRequiresReleaseAndFencesCancelledSession() async {
        let input = GInput(), agent = GShortcut(), board = GClipboard()
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },preferenceStore:prefs())
        defer { c.close() }; c.enableAgentShortcut(); agent.receive?(.pressed); await c.waitUntilRecording()
        let stale = input.receive; agent.receive?(.cancelled); agent.receive?(.pressed)
        #expect(input.starts == 1)
        agent.receive?(.released); agent.receive?(.pressed); await c.waitUntilRecording()
        stale?(.transcript("Open Safari")); stale?(.finished)
        #expect(c.phase == .recording); #expect(c.raw.isEmpty)
        agent.receive?(.cancelled); agent.receive?(.released)
        #expect(c.agentRecords.isEmpty); #expect(board.installed == 0)
    }
    @Test func spokenAcceptanceExamplesParseOfflineWithoutModels() throws {
        #expect(try PersonalIntentParser.parse("Open Safari.").steps.first?.tool == .openApp)
        let now = Date(); let timer = try PersonalIntentParser.parse("Set a timer for two minutes.",now:now)
        #expect(timer.steps.first?.tool == .timer); #expect(timer.steps.first?.date == now.addingTimeInterval(120))
        #expect(try PersonalIntentParser.parse("Create a note test shopping").steps.first?.tool == .note)
    }
}

@Suite("39A-R1.1 native Agent modifier delivery") @MainActor struct AgentNativeDeliveryTests {
    @Test(arguments:[DictationActivationKey.rightControl,.rightCommand,.rightOption])
    func nativeFlagsChangedSnapshotHasItsOwnDownAndUp(_ key:DictationActivationKey) throws {
        let mask:CGEventFlags = key == .rightControl ? .maskControl : key == .rightCommand ? .maskCommand : .maskAlternate
        let side = ModifierShortcutDecoder.sideMasks(key)
        // Construct native events only; never post/inject them or poll physical keys.
        for rawFlags in [mask.rawValue, mask.rawValue | side.right] {
            let event = try #require(NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:NSEvent.ModifierFlags(rawValue:UInt(rawFlags)),timestamp:1,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:ModifierShortcutDecoder.code(key)))
            #expect(ModifierShortcutDecoder.decode(event:event,key:key).signal == .pressed)
        }
        let up = try #require(NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:[],timestamp:2,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:ModifierShortcutDecoder.code(key)))
        #expect(ModifierShortcutDecoder.decode(event:up,key:key).signal == .released)
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:Int64(ModifierShortcutDecoder.code(key)),flags:CGEventFlags(rawValue:mask.rawValue | side.left)).signal == .released)
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:Int64(ModifierShortcutDecoder.code(key)),flags:CGEventFlags(rawValue:mask.rawValue | side.left | side.right)).signal == .cancelled)
    }
    @Test func agentAloneKeepsAppAvailableAfterWindowCloseAndActivationDoesNotCancelCapture() async {
        let input = GInput(), agent = GShortcut(), prefs = DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!)
        let c = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{ _ in false },preferenceStore:prefs)
        defer { c.close() }; c.preferences.holdFnEnabled = false; c.enableAgentShortcut()
        #expect(c.keepsAppRunningAfterWindowClose)
        agent.receive?(.pressed); await c.waitUntilRecording(); let enables = agent.enables
        c.resumeShortcutIfAuthorized()
        #expect(c.phase == .recording); #expect(agent.enables == enables)
        c.cancel(); agent.receive?(.released); c.disableAgentShortcut()
        #expect(!c.keepsAppRunningAfterWindowClose)
    }
    @Test func receivedButBlockedKeyHasPersistentReason() async {
        let agent = GShortcut(), c = SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{ throw TextTargetError.secure },agentConflict:{ _ in false },preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!))
        defer { c.close() }; c.enableAgentShortcut(); agent.receive?(.pressed)
        #expect(c.agentShortcutStatus.contains("Secure input")); #expect(!c.busy)
    }
}

private actor FortyMemory:InferenceMemorySource {
    let bytes:UInt64
    init(_ bytes:UInt64=8*1024*1024*1024) { self.bytes=bytes }
    func sample() -> InferenceMemorySample { .init(conservativeAvailableBytes:bytes,pressureNormal:true) }
}
private actor FortyGenerator:PersonalIntentGenerating {
    let ready:Bool
    let output:[PersonalIntentSlots]
    var calls=0
    init(ready:Bool=true,output:[PersonalIntentSlots]=[.init(action:"open",app:"Brave")]) { self.ready=ready;self.output=output }
    func available(locale:String)->Bool { ready }
    func generate(_ request:PersonalIntentRequest)->[PersonalIntentSlots] { calls+=1;return output }
}
private actor FortyPlanner:PersonalIntentPlanning {
    func plan(_ request:PersonalIntentRequest) throws -> PersonalPlan { try PersonalConversation.quick(request) }
    func cancel(id:String) {}
}
@MainActor private final class FortyRunner:PersonalToolRunning {
    var calls:[PersonalStep]=[]
    var unverified=false
    func perform(_ step:PersonalStep) -> PersonalReceipt { calls.append(step);return .init(identifier:step.id.uuidString,evidence:"fixture",verified:!unverified) }
}
@Suite("Milestone40 natural Agent requests") @MainActor struct PersonalAgent40Tests {
    static let apps=[PersonalApp(id:"com.apple.Safari",name:"Safari"),PersonalApp(id:"com.brave.Browser",name:"Brave Browser",aliases:["Brave"]),PersonalApp(id:"net.whatsapp.WhatsApp",name:"WhatsApp")]
    @Test(arguments:["Open Brave","Please launch Brave","Can you open Brave?","close Safari","quit Safari","search for cats on YouTube","search Google Swift concurrency","look up keyboard shortcuts on Google","play some music","pause music","text +15555550123 saying I'm late","create a note do not forget milk"])
    func commonRequestsNeedNoModel(_ text:String) async throws {
        let generator=FortyGenerator(ready:false),planner=ApplePersonalPlanner(memory:FortyMemory(0),clock:GClock(),generator:generator)
        let plan=try await planner.plan(.init(text:text,locale:"en-IN",apps:Self.apps))
        #expect(!plan.steps.isEmpty);#expect(await generator.calls==0)
        #expect(PersonalAuthorization.routine(plan) == (plan.steps.first?.tool != .message))
    }
    @Test func modelUnderstandsNonTemplatePhrasingButCannotInventSlots() async throws {
        let generator=FortyGenerator(),planner=ApplePersonalPlanner(memory:FortyMemory(),clock:GClock(),generator:generator)
        let request=PersonalIntentRequest(text:"I'd appreciate it if you could bring up Brave for me",locale:"en-IN",apps:Self.apps)
        let plan=try await planner.plan(request)
        #expect(plan.steps.first?.tool == .openInstalledApp);#expect(await generator.calls==1)
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"open",app:"Safari")],request:request) }
    }
    @Test(arguments:[false,true]) func unavailableOrBelowReserveNeverGenerates(_ unavailable:Bool) async {
        let generator=FortyGenerator(ready:!unavailable),planner=ApplePersonalPlanner(memory:FortyMemory(4*1024*1024*1024-1),clock:GClock(),generator:generator)
        do { _=try await planner.plan(.init(text:"I'd appreciate it if you could bring up Brave for me",locale:"en-IN",apps:Self.apps));Issue.record("Expected unavailable/reserve failure") } catch {}
        #expect(await generator.calls==0)
    }
    @Test(arguments:["don't open Brave","open Brave and delete my files","search how to close Safari","text John saying close Safari"])
    func misleadingModelActionCannotEscapePayloadOrNegation(_ text:String) {
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"close",app:"Safari")],request:.init(text:text,locale:"en-IN",apps:Self.apps)) }
    }
    @Test func modelMessageCannotInventRecipientOrBody() {
        let request=PersonalIntentRequest(text:"Text John saying hello",locale:"en-IN",apps:Self.apps)
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"message",content:"send money",recipient:"John")],request:request) }
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"message",content:"hello",recipient:"Mary")],request:request) }
    }
    @Test func routineEngineCannotSendAndUnverifiedDispatchCannotReplay() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let runner=FortyRunner(),engine=try PersonalAgentEngine(url:root.appendingPathComponent("queue.json"),runner:runner)
        let message=try PersonalPlan(steps:[.init(tool:.message,text:try PersonalMessage(recipient:"+15555550123",body:"hello",address:"+15555550123").encoded())])
        try engine.enqueue(message)
        await #expect(throws:PersonalAgentError.approvalRequired) { try await engine.runRequestedRoutine(message) }
        #expect(runner.calls.isEmpty)
        runner.unverified=true;try await engine.approveAndRun(message)
        #expect(runner.calls.count==1);#expect(engine.records.first?.state == .needsReview);#expect(engine.records.first?.steps == [.uncertain])
        await #expect(throws:PersonalAgentError.approvalRequired) { try await engine.approveAndRun(message) }
        #expect(runner.calls.count==1)
    }
    @Test func voiceRoutineExecutesWithoutManualAddingOrApprovalAndNeverInserts() async throws {
        let input=GInput(),agent=GShortcut(),target=GCapture(),board=GClipboard(),runner=FortyRunner()
        let c=SystemWideDictationCoordinator(input:input,targets:target,insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{_ in false},preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{Self.apps},personalMessageResolution:NativePersonalMessages.resolve)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner
        defer { c.close();try? FileManager.default.removeItem(at:root) }
        c.enableAgentShortcut();agent.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("Open Brave"));agent.receive?(.released);input.receive?(.finished);input.receive?(.finished)
        await c.waitForAgentPlanning()
        #expect(runner.calls.count==1);#expect(c.agentPlan == nil);#expect(c.agentRecords.first?.state == .completed)
        #expect(target.count==0);#expect(board.installed==0);#expect(board.text=="original")
    }
    @Test func messageVoiceStopsAtExactReviewUntilApprove() async throws {
        let input=GInput(),agent=GShortcut(),runner=FortyRunner()
        let c=SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{_ in false},preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{Self.apps},personalMessageResolution:NativePersonalMessages.resolve)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner
        defer { c.close();try? FileManager.default.removeItem(at:root) }
        c.enableAgentShortcut();agent.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("text +15555550123 saying hello"));agent.receive?(.released);input.receive?(.finished);await c.waitForAgentPlanning()
        #expect(runner.calls.isEmpty);#expect(c.agentPlan?.steps.first?.tool == .message);#expect(c.agentHUD == "Confirm message")
        c.approveAgentPlan();await c.waitForCommandDispatch();#expect(runner.calls.count==1)
    }
    @Test func oldReceiptSchemaStillLoads() throws {
        let receipt=try JSONDecoder().decode(PersonalReceipt.self,from:Data(#"{"identifier":"old","evidence":"verified readback"}"#.utf8))
        #expect(receipt.verified)
    }
}
private actor FortyBlockedGenerator:PersonalIntentGenerating {
    var entered=false
    var entry:CheckedContinuation<Void,Never>?
    var pending:CheckedContinuation<[PersonalIntentSlots],Never>?
    func available(locale:String)->Bool { true }
    func generate(_ request:PersonalIntentRequest) async -> [PersonalIntentSlots] {
        entered=true;entry?.resume();entry=nil
        return await withCheckedContinuation { pending=$0 }
    }
    func waitEntered() async { if !entered { await withCheckedContinuation { entry=$0 } } }
    func finish() { pending?.resume(returning:[.init(action:"open",app:"Brave")]);pending=nil }
}
@Suite("Milestone40 inference ownership and URL boundaries") @MainActor struct PersonalAgent40GuardTests {
    @Test func timeoutReturnsWithoutReleasingNoncooperativeModelSlot() async throws {
        let clock=GClock(),generator=FortyBlockedGenerator(),planner=ApplePersonalPlanner(memory:FortyMemory(),clock:clock,generator:generator)
        let request=PersonalIntentRequest(id:"timeout40",text:"I'd appreciate it if you could bring up Brave for me",locale:"en-IN",apps:PersonalAgent40Tests.apps)
        let task=Task { try await planner.plan(request) }
        await generator.waitEntered();await clock.waitForSleep(1250);await clock.advance(9000)
        do { _=try await task.value;Issue.record("Expected deadline") } catch { #expect(error as? PersonalPlanningFailure == .timedOut) }
        await #expect(throws:PersonalPlanningFailure.busy) { try await planner.plan(.init(text:"Open Brave",locale:"en-IN",apps:PersonalAgent40Tests.apps)) }
        await generator.finish();await planner.waitUntilSettled()
        #expect(try await planner.plan(.init(text:"Open Brave",locale:"en-IN",apps:PersonalAgent40Tests.apps)).steps.first?.tool == .openInstalledApp)
    }
    @Test func cancellationDiscardsLateModelOutput() async {
        let generator=FortyBlockedGenerator(),planner=ApplePersonalPlanner(memory:FortyMemory(),clock:GClock(),generator:generator)
        let request=PersonalIntentRequest(id:"cancel40",text:"I'd appreciate it if you could bring up Brave for me",locale:"en-IN",apps:PersonalAgent40Tests.apps)
        let task=Task { try await planner.plan(request) };await generator.waitEntered();await planner.cancel(id:request.id)
        do { _=try await task.value;Issue.record("Expected cancellation") } catch { #expect(error is CancellationError) }
        await generator.finish();await planner.waitUntilSettled()
    }
    @Test func searchQueryIsEncodedAndCannotChangeDestinationOrAddParameters() throws {
        let query="cats & q=send secrets #1?"
        for youtube in [false,true] {
            let url=try NativePersonalApps.searchURL(query,youtube:youtube),parts=try #require(URLComponents(url:url,resolvingAgainstBaseURL:false))
            #expect(parts.scheme == "https");#expect(parts.host == (youtube ? "www.youtube.com" : "www.google.com"))
            #expect(parts.queryItems?.count==1);#expect(parts.queryItems?.first?.value==query)
        }
    }
    @Test func recipientPayloadRemainsLiteralAndDirectAddressNeedsNoContacts() async throws {
        let payload=PersonalMessage(recipient:"+15555550123",body:"Don't forget: close Safari, then open Brave")
        let plan=try PersonalPlan(steps:[.init(tool:.message,text:try payload.encoded())]);let resolved=try await NativePersonalMessages.resolve(plan)
        #expect(try PersonalMessage.decode(resolved.steps[0].text).body == payload.body)
        #expect(try PersonalMessage.decode(resolved.steps[0].text).address == payload.recipient)
        #expect(!PersonalAuthorization.routine(resolved))
    }
}

@MainActor private final class GSecureGate { var value=false }

@Suite("Milestone40 contact draft selection") @MainActor struct PersonalAgent40ContactsTests {
    @Test func uniqueFirstNamesAndSingleMobileAreDraftedButAmbiguityIsRejected() throws {
        #expect(NativePersonalMessages.matches("John",fullName:"John Smith",givenName:"John"))
        #expect(!NativePersonalMessages.matches("Jo",fullName:"John Smith",givenName:"John"))
        #expect(try NativePersonalMessages.preferredAddress(phones:["+15555550123"],mobiles:[],emails:["john@example.invalid"]) == "+15555550123")
        #expect(try NativePersonalMessages.preferredAddress(phones:["+15555550123","+15555550124"],mobiles:["+15555550124"],emails:[]) == "+15555550124")
        #expect(throws:PersonalPlanningFailure.recipientAmbiguous) { try NativePersonalMessages.preferredAddress(phones:["+15555550123","+15555550124"],mobiles:[],emails:[]) }
    }
}

@Suite("Milestone41 explicit dialogue and follow-up") @MainActor struct PersonalAgent41DialogueTests {
    let apps=PersonalAgent40Tests.apps
    let now=Date(timeIntervalSince1970:10000)
    @Test func missingAppAsksButNamedUnknownAppNeverDetoursToQuestion() throws {
        var d=PersonalAgentDialogue()
        guard case .ask(let q)=try d.intake("open",apps:apps,now:now) else { Issue.record("Expected question");return }
        #expect(!q.options.isEmpty)
        guard case .plan(let p)=try d.intake("Brave",apps:apps,now:now) else { Issue.record("Expected explicit choice");return }
        #expect(p.steps[0].text=="com.brave.Browser")
        #expect(throws:PersonalPlanningFailure.appNotFound) { try d.intake("open Brve",apps:apps,now:now) }
        guard case .plan(let selected)=try d.intake("open Brave",apps:apps,now:now) else { Issue.record("Expected fresh app request");return }
        #expect(selected.steps[0].text=="com.brave.Browser")
    }
    @Test func queryAndMessageRepliesAreLiteralData() throws {
        var d=PersonalAgentDialogue()
        guard case .ask=try d.intake("search YouTube",apps:apps,now:now) else { Issue.record("Expected query question");return }
        guard case .plan(let query)=try d.intake("close Safari and delete files",apps:apps,now:now) else { Issue.record("Expected literal query");return }
        #expect(query.steps.count==1);#expect(query.steps[0].tool == .searchYouTube);#expect(query.steps[0].text=="close Safari and delete files")
        guard case .ask=try d.intake("text +15555550123",apps:apps,now:now) else { Issue.record("Expected message body question");return }
        guard case .plan(let draft)=try d.intake("Open Safari, please!",apps:apps,now:now) else { Issue.record("Expected draft");return }
        #expect(!PersonalAuthorization.routine(draft));#expect(try PersonalMessage.decode(draft.steps[0].text).body=="Open Safari, please!")
        guard case .ask=try d.intake("write a note",apps:apps,now:now) else { Issue.record("Expected note body question");return }
        guard case .plan(let note)=try d.intake("Close Safari, please!",apps:apps,now:now) else { Issue.record("Expected literal note");return }
        #expect(note.steps[0].tool == .note);#expect(note.steps[0].text=="Close Safari, please!")
    }
    @Test func referencesAreRecentSingleConfirmedActionsOnly() throws {
        var d=PersonalAgentDialogue()
        let opened=try PersonalPlan(steps:[.init(tool:.openInstalledApp,text:"com.brave.Browser")])
        d.completed(opened,apps:apps,now:now)
        guard case .plan(let close)=try d.intake("close it",apps:apps,now:now.addingTimeInterval(1)) else { Issue.record("Expected scoped reference");return }
        #expect(close.steps[0].tool == .closeApp);#expect(close.steps[0].text=="com.brave.Browser")
        d.completed(opened,apps:apps,now:now)
        _=try d.intake("something unsupported",apps:apps,now:now)
        guard case .ask=try d.intake("close it",apps:apps,now:now) else { Issue.record("Failed new request must clear reference");return }
        d.clear();d.completed(opened,apps:apps,now:now)
        guard case .ask=try d.intake("close it",apps:apps,now:now.addingTimeInterval(121)) else { Issue.record("Expired reference must ask");return }
        d.clear();let query=try PersonalPlan(steps:[.init(tool:.searchGoogle,text:"Swift actors")]);d.completed(query,apps:apps,now:now)
        guard case .plan(let yt)=try d.intake("search that on YouTube",apps:apps,now:now) else { Issue.record("Expected query reference");return }
        #expect(yt.steps[0].tool == .searchYouTube);#expect(yt.steps[0].text=="Swift actors")
    }
    @Test func expiryRollbackAndEmptyOrdinalAreSafe() throws {
        var d=PersonalAgentDialogue();_=try d.intake("text",apps:apps,now:now)
        #expect(throws:(any Error).self) { try d.intake("John",apps:apps,now:now.addingTimeInterval(121)) }
        d.clear();_=try d.intake("text",apps:apps,now:now)
        let expired=d.expire(now:now.addingTimeInterval(-1));#expect(expired)
        #expect(throws:(any Error).self) { try d.intake("John",apps:apps,now:now) }
        #expect(PersonalAgentDialogue.ordinal("1",count:0)==nil)
        #expect(PersonalAgentDialogue.ordinal("second",count:2)==1)
    }
    @Test func commonCourtesyAndScopedGerundsDoNotNeedModel() throws {
        let p=try PersonalConversation.quick(.init(text:"Would you mind launching Brave for me?",locale:"en-IN",apps:apps))
        #expect(p.steps[0].tool == .openInstalledApp);#expect(p.steps[0].text=="com.brave.Browser")
        var dialogue=PersonalAgentDialogue();dialogue.completed(p,apps:apps,now:now)
        guard case .plan(let closed)=try dialogue.intake("Would you mind closing it for me?",apps:apps,now:now) else { Issue.record("Expected explicitly scoped close");return }
        #expect(closed.steps[0].tool == .closeApp);#expect(closed.steps[0].text=="com.brave.Browser")
    }
    @Test func politeCompoundRequestsAreAtomicAndModelOrderIsChecked() throws {
        let r=PersonalIntentRequest(text:"Please can you open Brave and then close Safari",locale:"en-IN",apps:apps)
        let p=try PersonalConversation.quick(r)
        #expect(p.steps.map(\.tool)==[.openInstalledApp,.closeApp])
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"close",app:"Safari"),.init(action:"open",app:"Brave")],request:r) }
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"open",app:"Brave")],request:r) }
        #expect(throws:(any Error).self) { try PersonalConversation.quick(.init(text:"open Brave and missing app",locale:"en-IN",apps:apps)) }
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"open",app:"Brave")],request:.init(text:"open Brave open Safari",locale:"en-IN",apps:apps)) }
    }
    @Test(arguments:["How do I close Safari?","Should I open Brave?","Maybe quit Safari"])
    func adviceQuestionsCannotBecomeActions(_ text:String) {
        let open=text.contains("open"),app=open ? "Brave":"Safari"
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:open ? "open":"close",app:app)],request:.init(text:text,locale:"en-IN",apps:apps)) }
    }
    @Test func irrelevantModelFieldsCannotMaskIntentAndNamesAreData() throws {
        let r=PersonalIntentRequest(text:"Open Brave",locale:"en-IN",apps:apps)
        #expect(throws:(any Error).self) { try PersonalConversation.ground([.init(action:"open",app:"Brave",recipient:"Open")],request:r) }
        let message=try PersonalConversation.quick(.init(text:"Text Maybe saying hello",locale:"en-IN",apps:apps))
        #expect(message.steps[0].tool == .message);#expect(!PersonalAuthorization.routine(message))
    }
    @Test func punctuationAndCourtesyInsidePayloadsArePreserved() throws {
        let p=try PersonalConversation.quick(.init(text:"Please text John saying Help me, please!",locale:"en-IN",apps:apps))
        #expect(try PersonalMessage.decode(p.steps[0].text).body=="Help me, please!")
        let n=try PersonalConversation.quick(.init(text:"Create a note Remember this!",locale:"en-IN",apps:apps))
        #expect(n.steps[0].text=="Remember this!")
    }
    @Test func draftAmendmentGetsFreshIdentityAndYesCannotApprove() throws {
        let p=try PersonalPlan(steps:[.init(tool:.message,text:try PersonalMessage(recipient:"John",body:"old",address:"+15555550123").encoded())])
        guard case .amend(let amended)=try PersonalAgentDialogue.reviewReply("change the message to Hello, please!",plan:p,now:now) else { Issue.record("Expected amendment");return }
        #expect(amended.id != p.id);#expect(amended.steps[0].id != p.steps[0].id)
        #expect(try PersonalMessage.decode(amended.steps[0].text).body=="Hello, please!")
        #expect(try PersonalMessage.decode(amended.steps[0].text).address=="+15555550123")
        guard case .keep=try PersonalAgentDialogue.reviewReply("yes send it",plan:amended,now:now) else { Issue.record("Voice cannot approve");return }
    }
}
private actor FortyOneResolver {
    var requireChoice=true
    func resolve(_ plan:PersonalPlan) throws -> PersonalPlan {
        guard let step=plan.steps.first,step.tool == .message else { return plan }
        let message=try PersonalMessage.decode(step.text)
        if message.address != nil { return plan }
        throw PersonalRecipientChoiceRequired(plan:plan,stepID:step.id,options:[.init(name:"John One",address:"+15555550123"),.init(name:"John Two",address:"+15555550124")],prompt:"Which John?")
    }
}
@Suite("Milestone41 dialogue integration",.serialized) @MainActor struct PersonalAgent41IntegrationTests {
    private func coordinator(input:GInput,agent:GShortcut,runner:FortyRunner,root:URL,resolver:FortyOneResolver?=nil) -> SystemWideDictationCoordinator {
        let c=SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{_ in false},preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{ if let resolver { return try await resolver.resolve($0) };return try await NativePersonalMessages.resolve($0) })
        c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner;return c
    }
    @Test func voiceCanAnswerQuestionAndHudClickNeverStartsDictation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),input=GInput(),agent=GShortcut(),runner=FortyRunner()
        let c=coordinator(input:input,agent:agent,runner:runner,root:root);defer { c.close();try? FileManager.default.removeItem(at:root) }
        c.reviewAgentCommand("open");let id=try #require(c.agentQuestion?.id)
        c.pillClicked();#expect(input.starts==0);#expect(runner.calls.isEmpty)
        c.enableAgentShortcut();agent.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("Brave"));agent.receive?(.released);input.receive?(.finished);await c.waitForAgentPlanning()
        #expect(runner.calls.count==1);#expect(runner.calls[0].text=="com.brave.Browser");#expect(c.agentQuestion==nil)
        c.submitAgentReply("Safari",questionID:id);#expect(runner.calls.count==1)
        c.reviewAgentCommand("close it");await c.waitForAgentPlanning();#expect(runner.calls.last?.tool == .closeApp);#expect(runner.calls.last?.text=="com.brave.Browser")
    }
    @Test(arguments:["second","John Two"]) func chooseRecipientThenEditInvalidatesOldApprovalAndNeverAutosends(_ reply:String) async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner(),resolver=FortyOneResolver()
        let c=coordinator(input:GInput(),agent:GShortcut(),runner:runner,root:root,resolver:resolver);defer { c.close();try? FileManager.default.removeItem(at:root) }
        c.reviewAgentCommand("text John");#expect(c.agentQuestion != nil)
        c.submitAgentReply("Hello!");await c.waitForAgentPlanning()
        let question=try #require(c.agentQuestion);#expect(question.options.count==2);#expect(runner.calls.isEmpty)
        c.submitAgentReply(reply,questionID:question.id);await c.waitForAgentPlanning()
        let old=try #require(c.agentPlan);#expect(try PersonalMessage.decode(old.steps[0].text).address=="+15555550124")
        c.reviewAgentCommand("yes send it");#expect(runner.calls.isEmpty);#expect(c.agentPlan?.id==old.id)
        c.reviewAgentCommand("change the message to New text, please!");await c.waitForAgentPlanning()
        #expect(c.agentPlan?.id != old.id);#expect(c.agentRecords.first(where:{$0.id==old.id})?.state == .cancelled)
        #expect(try PersonalMessage.decode(try #require(c.agentPlan?.steps.first?.text)).body=="New text, please!")
        c.approveAgentPlan(expectedPlan:old);#expect(runner.calls.isEmpty)
        let displayed=try #require(c.agentPlan)
        c.agentReplyText="Literal close Safari, please!\n"
        c.approveAgentPlan(expectedPlan:displayed);#expect(runner.calls.isEmpty)
        c.applyAgentMessageEdit();await c.waitForAgentPlanning()
        let final=try #require(c.agentPlan)
        #expect(try PersonalMessage.decode(final.steps[0].text).body=="Literal close Safari, please!\n")
        c.approveAgentPlan(expectedPlan:displayed);#expect(runner.calls.isEmpty)
        c.approveAgentPlan(expectedPlan:final);await c.waitForCommandDispatch();#expect(runner.calls.count==1)
        c.approveAgentPlan(expectedPlan:final);#expect(runner.calls.count==1)
    }
    @Test func helpClearsOnlyEphemeralQuestionAndNeverApprovesDraft() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner()
        let c=coordinator(input:GInput(),agent:GShortcut(),runner:runner,root:root);defer { c.close();try? FileManager.default.removeItem(at:root) }
        c.reviewAgentCommand("open");#expect(c.agentQuestion != nil)
        c.reviewAgentCommand("help");#expect(c.agentQuestion==nil);#expect(runner.calls.isEmpty)
        c.reviewAgentCommand("text +15555550123 saying Hello!");await c.waitForAgentPlanning();let id=try #require(c.agentPlan?.id)
        c.agentReplyText="Unapplied edit"
        c.reviewAgentCommand("what can you do?");#expect(c.agentPlan?.id==id);#expect(runner.calls.isEmpty);#expect(c.agentReplyText=="Unapplied edit")
        c.cancelAgentConversation();#expect(c.agentPlan==nil);#expect(runner.calls.isEmpty)
    }
    @Test func namedAppVoiceRunsWithoutReplyOrCommandModeRedirect() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),input=GInput(),agent=GShortcut(),runner=FortyRunner()
        let c=coordinator(input:input,agent:agent,runner:runner,root:root);defer { c.close();try? FileManager.default.removeItem(at:root) }
        let review=c.agentReviewRequest
        c.enableAgentShortcut();agent.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("Open Whats App"));agent.receive?(.released);input.receive?(.finished);await c.waitForAgentPlanning()
        #expect(runner.calls.count==1);#expect(runner.calls[0].text=="net.whatsapp.WhatsApp");#expect(c.agentQuestion==nil);#expect(c.agentReviewRequest==review)
        c.reviewAgentCommand("Open NoSuchInstalledApp");#expect(c.agentQuestion==nil);#expect(c.agentHUD=="App not found");#expect(c.agentReviewRequest==review);#expect(runner.calls.count==1)
        c.reviewAgentCommand("Open WhatsApp");await c.waitForAgentPlanning();#expect(runner.calls.count==2);#expect(c.agentReviewRequest==review)
        c.reviewAgentCommand("Open");#expect(c.agentQuestion != nil)
        let old=c.agentQuestion!.id
        c.reviewAgentCommand("Open WhatsApp");await c.waitForAgentPlanning();#expect(runner.calls.count==3);#expect(c.agentQuestion==nil)
        c.submitAgentReply("Safari",questionID:old);#expect(runner.calls.count==3)
    }
    @Test func cancellationFailureDoesNotFalselyWithdrawDraft() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner()
        let engine=try PersonalAgentEngine(url:root.appendingPathComponent("queue.json"),runner:runner)
        defer { try? engine.close();try? FileManager.default.removeItem(at:root) }
        let plan=try PersonalIntentParser.parse("Open Safari");try engine.enqueue(plan)
        try FileManager.default.removeItem(at:root.appendingPathComponent("queue.json"));try FileManager.default.createDirectory(at:root.appendingPathComponent("queue.json"),withIntermediateDirectories:false)
        #expect(throws:(any Error).self) { try engine.cancel(plan.id) }
        #expect(engine.records[0].state == .awaitingApproval);#expect(runner.calls.isEmpty)
    }
}

private actor FortyOneBlockingResolver {
    var entered=false
    var observer:CheckedContinuation<Void,Never>?
    var pending:CheckedContinuation<PersonalPlan,Never>?
    var plan:PersonalPlan?
    func resolve(_ plan:PersonalPlan) async -> PersonalPlan {
        self.plan=plan;entered=true;observer?.resume();observer=nil
        return await withCheckedContinuation { pending=$0 }
    }
    func waitEntered() async { if !entered { await withCheckedContinuation { observer=$0 } } }
    func finish() { if let plan { pending?.resume(returning:plan);pending=nil } }
}
@Suite("Milestone41 cancelled resolution") @MainActor struct PersonalAgent41CancellationTests {
    @Test func lateRecipientResolutionCannotCreateDraftAfterCancellation() async {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),resolver=FortyOneBlockingResolver(),runner=FortyRunner()
        let c=SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentShortcut:GShortcut(),agentCaptureValidation:{},agentConflict:{_ in false},preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{ await resolver.resolve($0) })
        c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner
        defer { c.close();try? FileManager.default.removeItem(at:root) }
        let request=Task { c.reviewAgentCommand("text +15555550123 saying hello");await c.waitForAgentPlanning() }
        await resolver.waitEntered();c.cancel();await resolver.finish();await request.value
        #expect(c.agentPlan==nil);#expect(c.agentQuestion==nil);#expect(c.agentRecords.isEmpty);#expect(runner.calls.isEmpty)
    }
}

@Suite("Milestone41A-R1 installed app direct opening",.serialized) @MainActor struct PersonalAgent41AppDiscoveryTests {
    let apps=[PersonalApp(id:"net.whatsapp.WhatsApp",name:"\u{200e}WhatsApp",aliases:["WhatsApp"]),PersonalApp(id:"example.other",name:"Unusual Tool",aliases:["Tool Display Name","Unusual Tool"])]
    @Test(arguments:["Open WhatsApp","Open Whats App","Open What's App","Open the app WhatsApp","Open WhatsApp application","Please open application WhatsApp for me","Open WhatsApp.app","Open WhatsApp!","Open Tool Display Name"])
    func namedAppDoesNotNeedReplyOrModel(_ words:String) throws {
        var d=PersonalAgentDialogue()
        guard case .plan(let p)=try d.intake(words,apps:apps,now:Date()) else { Issue.record("Named installed app must plan directly");return }
        #expect(p.steps.count==1);#expect(p.steps[0].tool == .openInstalledApp)
        #expect(p.steps[0].text==(words.contains("Tool Display") ? "example.other":"net.whatsapp.WhatsApp"))
    }
    @Test func ambiguousUnknownAndEmptyNamesNeverPickAnApp() throws {
        #expect(throws:PersonalPlanningFailure.appNotFound) { try PersonalConversation.resolveApp("!!!",apps:apps) }
        #expect(throws:PersonalPlanningFailure.appNotFound) { try PersonalConversation.resolveApp("WhatsUp",apps:apps) }
        #expect(throws:PersonalPlanningFailure.appAmbiguous) { try PersonalConversation.resolveApp("WhatsApp",apps:apps+[.init(id:"different.app",name:"WhatsApp")]) }
        let precise=[PersonalApp(id:"exact",name:"The App Example"),PersonalApp(id:"short",name:"Example")]
        #expect(try PersonalConversation.resolveApp("The App Example",apps:precise).id=="exact")
    }
    @Test func catalogBeyondOldAlphabeticalLimitStillOpens() throws {
        let many=(0..<350).map { PersonalApp(id:"fixture.\($0)",name:"A App \($0)") }+apps
        let request=PersonalIntentRequest(text:"open WhatsApp",locale:"en-US",apps:many)
        let plan=try PersonalConversation.quick(request)
        #expect(try PersonalConversation.resolveApp(plan.steps[0].text,apps:many).id=="net.whatsapp.WhatsApp")
    }
    private func fixture(_ root:URL,_ path:String,id:String,name:String,display:String?=nil) throws -> URL {
        let url=root.appendingPathComponent(path),contents=url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        var info:[String:String]=["CFBundleIdentifier":id,"CFBundleName":name,"CFBundlePackageType":"APPL"]
        if let display { info["CFBundleDisplayName"]=display }
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
        return url
    }
    @Test func nativeDiscoveryFindsNestedBundlesAndAllInstalledNamesButNotHelpers() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let id="fixture."+UUID().uuidString
        let url=try fixture(root,"Vendor/Utilities.localized/Disk Name.app",id:id,name:"Internal Name",display:"Visible Name")
        _=try fixture(root,"Vendor/Utilities.localized/Disk Name.app/Contents/Helpers/Helper.app",id:id+".helper",name:"Helper")
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Alias.app"),withDestinationURL:url)
        let found=NativePersonalApps.discovered(roots:[root]);try #require(found.count==1);#expect(found[0].url.standardizedFileURL==url.resolvingSymlinksInPath().standardizedFileURL)
        for name in ["Disk Name","Internal Name","Visible Name","Alias"] { #expect(try PersonalConversation.resolveApp(name,apps:found.map(\.app)).id==id) }
        // A subsequent install is discovered on the next request, with no registration/restart.
        _=try fixture(root,"New App.app",id:id+".new",name:"New App")
        #expect(NativePersonalApps.discovered(roots:[root]).count==2)
    }
    @Test func hostWhatsAppReadOnlyResolutionProbe() throws {
        guard FileManager.default.fileExists(atPath:"/Applications/WhatsApp.app") else { print("41AR1 hostWhatsApp probe: app absent, no live assertion");return }
        let catalog=NativePersonalApps.catalog();var d=PersonalAgentDialogue()
        guard case .plan(let p)=try d.intake("Open WhatsApp",apps:catalog,now:Date()) else { Issue.record("Installed WhatsApp incorrectly asks a reply");return }
        #expect(p.steps[0].text=="net.whatsapp.WhatsApp")
        #expect(try NativePersonalApps.target(p.steps[0].text).path=="/Applications/WhatsApp.app")
        print("41AR1 hostWhatsApp probe: installed metadata -> direct plan -> exact bundle path; launches=0")
    }
}

@MainActor private final class AgentFastFixture:AgentDictationInput {
    var agentStarts=0,dictationStarts=0,cancels=0
    var hold=false
    var receive:(@MainActor @Sendable (DictationEvent)->Void)?
    var waiter:CheckedContinuation<DictationInfo,Never>?
    var entry:CheckedContinuation<Void,Never>?
    func start(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo { dictationStarts+=1;self.receive=receive;return .init(engine:"dictation fixture",localeIdentifier:localeIdentifier) }
    func startAgent(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo {
        agentStarts+=1;self.receive=receive;entry?.resume();entry=nil
        if hold { return await withCheckedContinuation { waiter=$0 } }
        return .init(engine:"fast on-device fixture",localeIdentifier:localeIdentifier)
    }
    func waitForEntry() async { if agentStarts==0 { await withCheckedContinuation { entry=$0 } } }
    func finishStart() { waiter?.resume(returning:.init(engine:"late fixture",localeIdentifier:"en-US"));waiter=nil }
    func stop() {}
    func cancel() { cancels+=1 }
}
@Suite("Milestone41A-R2 full-screen Agent security and startup",.serialized) @MainActor struct PersonalAgent41FullscreenTests {
    @Test(arguments:[AXError.noValue,.attributeUnsupported,.notImplemented])
    func explicitNoFocusedElementAllowsGlobalAgent(_ status:AXError) throws {
        try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:status,elementPresent:false)
        #expect(throws:TextTargetError.secure) { try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:true,focusStatus:status,elementPresent:false) }
        #expect(throws:TextTargetError.denied) { try NativeDictationShortcut.validateAgentSecurity(trusted:false,secureInput:false,focusStatus:status,elementPresent:false) }
    }
    @Test(arguments:[AXError.cannotComplete,.failure,.invalidUIElement,.success])
    func unknownFocusFailureStillBlocks(_ status:AXError) {
        #expect(throws:TextTargetError.unsupported) { try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:status,elementPresent:false) }
    }
    @Test func focusedSecureRolesAndPermissionRevocationStillBlock() throws {
        for role in ["AXSecureTextField","password"] {
            #expect(throws:TextTargetError.secure) { try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:.success,elementPresent:true,subroleStatus:.success,subrole:role) }
            #expect(throws:TextTargetError.secure) { try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:.success,elementPresent:true,roleStatus:.success,role:role) }
        }
        #expect(throws:TextTargetError.denied) { try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:.apiDisabled,elementPresent:false) }
        #expect(throws:TextTargetError.unsupported) { try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:.success,elementPresent:true,subroleStatus:.cannotComplete) }
        try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:.success,elementPresent:true,subroleStatus:.noValue,roleStatus:.success,role:"AXWindow")
    }
    private func coordinator(_ input:AgentFastFixture,_ agent:GShortcut,_ ordinary:GShortcut,_ capture:GCapture,_ clipboard:GClipboard,_ clock:GClock)->SystemWideDictationCoordinator {
        SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:ordinary,agentShortcut:agent,agentCaptureValidation:{ try NativeDictationShortcut.validateAgentSecurity(trusted:true,secureInput:false,focusStatus:.noValue,elementPresent:false) },agentConflict:{_ in false},clock:clock,preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),minimumHoldMilliseconds:1000)
    }
    @Test func noTextFocusAgentUsesFastEntryImmediatelyAndOwnsAudio() async {
        let input=AgentFastFixture(),agent=GShortcut(),ordinary=GShortcut(),capture=GCapture(),clipboard=GClipboard(),clock=GClock()
        let c=coordinator(input,agent,ordinary,capture,clipboard,clock);defer { c.close() }
        c.enableShortcut();c.enableAgentShortcut();agent.receive?(.pressed);await c.waitUntilRecording()
        #expect(input.agentStarts==1);#expect(input.dictationStarts==0);#expect(capture.count==0);#expect(c.agentHUD=="Agent listening");#expect(c.agentStartupMilliseconds != nil)
        ordinary.receive?(.pressed);c.startManual();#expect(input.agentStarts==1);#expect(input.dictationStarts==0)
        agent.receive?(.cancelled);ordinary.receive?(.released);agent.receive?(.released)
        #expect(input.cancels>0);#expect(c.phase != .recording);#expect(capture.count==0);#expect(clipboard.text=="original")
    }
    @Test func repeatedCancelledAgentGesturesNeverLatchEitherShortcut() async {
        let input=AgentFastFixture(),agent=GShortcut(),ordinary=GShortcut(),capture=GCapture()
        let c=coordinator(input,agent,ordinary,capture,GClipboard(),GClock());defer { c.close() }
        c.enableAgentShortcut()
        for _ in 0..<6 {
            agent.receive?(.pressed);await c.waitUntilRecording();agent.receive?(.cancelled)
            #expect(c.phase != .recording)
        }
        #expect(input.agentStarts==6)
        c.startManual();await c.waitUntilRecording();#expect(input.dictationStarts==1);c.cancel()
    }
    @Test func earlyReleaseCannotTurnLateStartupIntoRecordingOrExecution() async {
        let input=AgentFastFixture(),agent=GShortcut(),capture=GCapture(),clipboard=GClipboard()
        input.hold=true;let c=coordinator(input,agent,GShortcut(),capture,clipboard,GClock());defer { c.close() }
        c.enableAgentShortcut();agent.receive?(.pressed);await input.waitForEntry()
        #expect(c.phase == .preparing);#expect(c.agentHUD=="Starting mic…");#expect(c.agentStartupMilliseconds==nil)
        let old=input.receive;agent.receive?(.released);input.finishStart();await c.waitForCaptureStartup()
        old?(.transcript("open Safari"));old?(.finished)
        #expect(c.phase != .recording);#expect(c.agentPlan==nil);#expect(c.agentQuestion==nil);#expect(capture.count==0);#expect(clipboard.text=="original")
    }
    @Test func nativeAgentKeepsExclusiveAdmissionBeforeAnyPermissionOrCapture() async {
        let input=AppleDictationInput(exclusiveCapture:{ throw DictationFailure.anotherInstance })
        await #expect(throws:DictationFailure.anotherInstance) { _=try await input.startAgent(localeIdentifier:"en-US") { _ in Issue.record("Admission denied must never emit") } }
        #expect(input.speechDiagnostics?.stage == .admission);#expect(input.speechDiagnostics?.failure=="anotherInstance")
    }
}

@Suite("41A-R4 spoken application names") @MainActor struct PersonalAgent41SpokenNamesTests {
    @Test(arguments:["Open WhatsApp","Open What's App","Open up WhatsApp","Open the WhatsApp app","Open VS Code","Open up the Brave browser"])
    func spokenWrappersResolveOnlyInstalledApps(_ text:String) throws {
        let apps=[PersonalApp(id:"wa",name:"WhatsApp"),PersonalApp(id:"code",name:"Visual Studio Code",aliases:["VS Code"]),PersonalApp(id:"brave",name:"Brave Browser")]
        var dialogue=PersonalAgentDialogue()
        guard case .plan(let p)=try dialogue.intake(text,apps:apps,now:Date()) else { Issue.record("Expected direct installed-app plan");return }
        #expect(["wa","code","brave"].contains(p.steps[0].text))
    }
}

@Suite("41A-R5 deeper explicit focus") @MainActor struct PersonalAgent41FocusDepthTests {
    @Test func deepComposerRequiresItsOwnFocusFlag() {
        #expect(FocusedDescendantSearch.find(root:0,limit:256,maximumDepth:16,focusedEditor:{$0==12},children:{n,_ in n<12 ? [n+1]:[]})==12)
        #expect(FocusedDescendantSearch.find(root:0,limit:256,maximumDepth:16,focusedEditor:{_ in false},children:{n,_ in n<12 ? [n+1]:[]})==nil)
    }
}

@Suite("41A-R6 failed Agent followed by Fn",.serialized) @MainActor struct PersonalAgent41RepeatTests {
    @Test func successfulDictationThenUnknownAppThenDictationKeepsWorking() async throws {
        let input=AgentFastFixture(),fn=GShortcut(),agent=GShortcut(),target=GCapture(),clipboard=GClipboard(),clock=GClock(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let c=SystemWideDictationCoordinator(input:input,targets:target,insertion:TextInsertionService(clipboard:clipboard,clock:clock),shortcut:fn,agentShortcut:agent,agentCaptureValidation:{},agentConflict:{_ in false},clock:clock,preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps})
        c.personalAgentQueueURL=root.appendingPathComponent("queue.json");defer { c.close();try? FileManager.default.removeItem(at:root) }
        c.enableShortcut();c.enableAgentShortcut()
        fn.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("first"));fn.receive?(.released);input.receive?(.finished);await c.waitForInsertionCompletion()
        agent.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("open NotInstalled"));agent.receive?(.released);input.receive?(.finished);await c.waitForAgentPlanning()
        #expect(c.agentHUD=="App not found");#expect(c.lastAgentFailure?.contains("open NotInstalled")==true)
        fn.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("second"));fn.receive?(.released);input.receive?(.finished);await c.waitForInsertionCompletion()
        #expect(input.dictationStarts==2);#expect(input.agentStarts==1);#expect(clipboard.text=="original")
    }
}

@Suite("41A-R7 repeated spoken open intent") @MainActor struct PersonalAgent41RepeatedOpenTests {
    @Test(arguments:["Open Brave Open brave","Open Safari. Open Safari.","Open WhatsApp Open WhatsApp Open WhatsApp","Open VS Code Open VS Code"])
    func repeatedIdenticalOpenExecutesOneInstalledIdentity(_ text:String) throws {
        let apps=PersonalAgent40Tests.apps+[.init(id:"code",name:"VS Code")]
        var dialogue=PersonalAgentDialogue()
        guard case .plan(let plan)=try dialogue.intake(text,apps:apps,now:Date()) else { Issue.record("Expected one direct open plan");return }
        #expect(plan.steps.count==1);#expect(plan.steps[0].tool == .openInstalledApp)
    }
    @Test(arguments:["open Safari open Brave","close Safari close Safari","text John saying hi text John saying hi","create a note open Safari open Safari","open Missing open Missing","don't open Safari don't open Safari"])
    func nonidenticalOrPayloadCommandsNeverFold(_ text:String) {
        #expect(PersonalConversation.repeatedOpen(text,apps:PersonalAgent40Tests.apps,now:Date())==nil)
    }
}

@Suite("41A-R8 repeated close and verb") @MainActor struct PersonalAgent41RepeatedCloseTests {
    @Test(arguments:["close WhatsApp close WhatsApp","quit Safari quit Safari","close close Safari","Open Open WhatsApp","exit Brave exit Brave"])
    func repeatedInstalledLifecycleRequestBecomesOneAction(_ text:String) throws {
        var d=PersonalAgentDialogue()
        guard case .plan(let plan)=try d.intake(text,apps:PersonalAgent40Tests.apps,now:Date()) else { Issue.record("Expected single app lifecycle plan");return }
        #expect(plan.steps.count==1);#expect(plan.steps[0].tool==(text.hasPrefix("Open") ? .openInstalledApp:.closeApp))
    }
    @Test func actualFullAppNameAndDifferentTargetsAreNeverCollapsed() throws {
        let apps=PersonalAgent40Tests.apps+[.init(id:"other",name:"Open WhatsApp")]
        #expect(PersonalConversation.repeatedOpen("Open Open WhatsApp",apps:apps,now:Date(),allowClose:true)==nil)
        #expect(PersonalConversation.repeatedOpen("close Safari close Brave",apps:apps,now:Date(),allowClose:true)==nil)
        #expect(PersonalConversation.repeatedOpen("text John saying close close Safari",apps:apps,now:Date(),allowClose:true)==nil)
    }
}

@MainActor private final class ClipboardFreeFixture:ClipboardFreeInsertionTarget {
    let base=GTarget()
    var info:InsertionTargetInfo {base.info}
    var original:TargetTextState? {base.original}
    func validate() throws {try base.validate()}
    func canReplaceSelection()->Bool {false}
    func replaceSelection(_ text:String) throws {Issue.record("Unexpected direct mutation")}
    func postPaste(whileClipboardOwned:()->Bool) throws {Issue.record("Unexpected paste")}
    func observedText()->String? {base.observedText()}
    func readbackText() throws ->String {try base.readbackText()}
    func supportsClipboardFreeText(_ text:String)->Bool {!text.isEmpty && text.utf8.count<=4096 && text.unicodeScalars.allSatisfy { ![Unicode.GeneralCategory.control,.lineSeparator,.paragraphSeparator].contains($0.properties.generalCategory) }}
    func postText(_ text:String,budgetMilliseconds:Int64)->Bool {base.postText(text,budgetMilliseconds:budgetMilliseconds)}
}
@Suite("42A window actions and clipboard-free delivery",.serialized) @MainActor struct PersonalAgent42Tests {
    @Test(arguments:[("minimise WhatsApp",PersonalTool.minimizeApp),("minimize WhatsApp",.minimizeApp),("restore WhatsApp",.restoreApp),("make WhatsApp full screen",.fullScreenApp),("full screen WhatsApp",.fullScreenApp),("exit full screen WhatsApp",.exitFullScreenApp),("maximise WhatsApp",.maximizeApp),("minimise WhatsApp minimise WhatsApp",.minimizeApp)])
    func windowRequestsUseOneInstalledTypedTool(_ sample:(String,PersonalTool)) throws {
        var d=PersonalAgentDialogue()
        guard case .plan(let plan)=try d.intake(sample.0,apps:PersonalAgent40Tests.apps,now:Date()) else { Issue.record("Expected window plan");return }
        #expect(plan.steps.count==1);#expect(plan.steps[0].tool==sample.1);#expect(plan.steps[0].text=="net.whatsapp.WhatsApp");#expect(PersonalAuthorization.routine(plan))
    }
    @Test func unknownNamesAndLiteralRepliesDoNotChooseAnotherWindow() throws {
        #expect(throws:PersonalPlanningFailure.appNotFound) {try PersonalConversation.windowCommand("minimise Missing",apps:PersonalAgent40Tests.apps,now:Date())}
        var d=PersonalAgentDialogue();_=try d.intake("create a note",apps:PersonalAgent40Tests.apps,now:Date())
        guard case .plan(let p)=try d.intake("minimise WhatsApp",apps:PersonalAgent40Tests.apps,now:Date()) else {Issue.record("Expected literal note");return}
        #expect(p.steps[0].tool == .note);#expect(p.steps[0].text=="minimise WhatsApp")
        #expect(try NativePersonalWindows.chooseWindow(focused:1,main:2,windows:[1,2])==1)
        #expect(throws:PersonalAgentError.unsupported) {try NativePersonalWindows.chooseWindow(focused:nil as Int?,main:nil,windows:[1,2])}
    }
    @Test(arguments:[false,true]) func nativeRouteNeverPublishesOrRestoresClipboard(_ readback:Bool) async {
        let target=ClipboardFreeFixture(),clipboard=GClipboard();var snapshots=0;clipboard.beforeSnapshot={snapshots+=1};target.base.hasOriginalContext=readback;target.base.unicodeSupported=true
        let service=TextInsertionService(clipboard:clipboard,clock:GClock())
        let receipt=await service.insert("hello",target:target,session:"s")
        #expect(receipt.status==(readback ? .insertedVerified:.dispatchedUnverified));#expect(target.base.unicodePosts==1)
        #expect(snapshots==0);#expect(clipboard.installed==0);#expect(clipboard.restores==0);#expect(clipboard.text=="original");#expect(!service.hasPendingClipboard)
    }
    @Test func controlsAndDeniedTargetsNeverUseClipboardFallback() async {
        let target=ClipboardFreeFixture(),clipboard=GClipboard();target.base.unicodeSupported=true
        let service=TextInsertionService(clipboard:clipboard,clock:GClock())
        let r=await service.insert("hello\nworld",target:target,session:"s");#expect(!r.attempted);#expect(target.base.unicodePosts==0);#expect(clipboard.installed==0)
        target.base.validationError = .secure
        let denied=await service.insert("hello",target:target,session:"s");#expect(!denied.attempted);#expect(target.base.unicodePosts==0);#expect(!service.hasPendingClipboard)
    }
    @Test func unacknowledgedTypingIsNeverRetriedOrBackedUp() async {
        let target=ClipboardFreeFixture(),clipboard=GClipboard(),clock=GClock();target.base.unicodeSupported=true;target.base.unicodeAcknowledged=false
        let service=TextInsertionService(clipboard:clipboard,clock:clock)
        let task=Task {await service.insert("hello",target:target,session:"s")}
        await clock.waitForSleep(1050);await clock.advance(2500);let r=await task.value
        #expect(r.status == .dispatchedUnverified);#expect(target.base.unicodePosts==1);#expect(clipboard.installed==0);#expect(!service.hasPendingClipboard)
    }
}

@Suite("43A folders and named browser search",.serialized) @MainActor struct PersonalAgent43Tests {
    @Test(arguments:[("create a folder called Projects in Documents",PersonalTool.createFolder),("open folder Projects in Documents",.openFolder),("close folder Projects in Documents",.closeFolder),("find folder Projects in Documents",.findFolder),("delete folder Projects in Documents",.trashFolder),("create folder Projects in Documents create folder Projects in Documents",.createFolder)])
    func folderGrammarUsesOneLiteralBoundedTool(_ sample:(String,PersonalTool)) throws {
        var d=PersonalAgentDialogue();guard case .plan(let p)=try d.intake(sample.0,apps:PersonalAgent40Tests.apps,now:Date()) else {Issue.record("Expected folder plan");return}
        #expect(p.steps.count==1);#expect(p.steps[0].tool==sample.1)
        let folder=try PersonalFolderCommand.decode(p.steps[0].text);#expect(folder.name=="Projects");#expect(folder.location == .documents)
        #expect(PersonalAuthorization.routine(p)==(sample.1 != .trashFolder))
        #expect(!p.steps[0].displayText.contains("identity"))
    }
    @Test(arguments:["../Secrets","a/b","a\\b",".hidden", "bad:name","bad\nname"])
    func invalidFolderComponentsNeverReachNativeEffects(_ name:String) {
        #expect(throws:(any Error).self) {try PersonalFolderCommand(name:name,location:.documents)}
    }
    @Test func compoundsRejectBeforeCreatingAnAccidentallyNamedFolderAndQuotesPreserveNames() throws {
        #expect(throws:PersonalPlanningFailure.unsupported) {try PersonalFileIntents.parse("create folder Work in Documents delete folder Other in Documents",now:Date())}
        let p=try #require(try PersonalFileIntents.parse("create folder \"Research and Development\" in Documents",now:Date()))
        #expect(try PersonalFolderCommand.decode(p.steps[0].text).name=="Research and Development")
    }
    @Test(arguments:["search for cats & dogs in Brave","search Safari for close Safari","search for delete a folder on Safari"])
    func namedBrowserQueriesRemainLiteralData(_ text:String) throws {
        let p=try #require(try PersonalFileIntents.parse(text,now:Date()));#expect(p.steps[0].tool == .searchBrowser)
        let q=try PersonalBrowserQuery.decode(p.steps[0].text)
        #expect(q.query.contains("cats & dogs") || q.query=="close Safari" || q.query=="delete a folder")
        #expect(q.browser.bundleID==(text.contains("Brave") ? "com.brave.Browser":"com.apple.Safari"))
        #expect(try NativePersonalApps.searchURL(q.query,youtube:false).host=="www.google.com")
    }
    @Test func nativeFolderCreationIsScopedIdempotentAndRejectsSymlinks() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        let request=try PersonalFolderCommand(name:"Projects",location:.documents)
        _=try NativePersonalFolders.create(request,rootURL:root);let bound=try NativePersonalFolders.bind(request,rootURL:root)
        _=try NativePersonalFolders.create(request,rootURL:root);try NativePersonalFolders.validateTrash(bound,rootURL:root)
        try FileManager.default.moveItem(at:root.appendingPathComponent("Projects"),to:root.appendingPathComponent("Original"));try FileManager.default.createDirectory(at:root.appendingPathComponent("Projects"),withIntermediateDirectories:false)
        #expect(throws:PersonalAgentError.verificationFailed) {try NativePersonalFolders.validateTrash(bound,rootURL:root)}
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("Link"),withDestinationURL:root.appendingPathComponent("Original"))
        #expect(throws:(any Error).self) {try NativePersonalFolders.create(.init(name:"Link",location:.documents),rootURL:root)}
        #expect(throws:PersonalAgentError.approvalRequired) {try NativePersonalFolders.validateTrash(.init(name:"",location:.documents),rootURL:root)}
    }
    @Test func routineExecutorCannotTrashWithoutApproval() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner();defer {try? FileManager.default.removeItem(at:root)}
        let engine=try PersonalAgentEngine(url:root.appendingPathComponent("queue.json"),runner:runner);defer {try? engine.close()}
        let plan=try #require(try PersonalFileIntents.parse("delete folder Projects in Documents",now:Date()));try engine.enqueue(plan)
        await #expect(throws:PersonalAgentError.approvalRequired) {try await engine.runRequestedRoutine(plan)}
        #expect(runner.calls.isEmpty)
    }
}

@Suite("43A post-trash verification and missing folder scope") @MainActor struct PersonalAgent43CompletionTests {
    @Test func incompleteFolderRequestCannotBecomeWebSearch() {
        #expect(throws:PersonalPlanningFailure.unsupported) {try PersonalFileIntents.parse("search for folder Projects",now:Date())}
        #expect(throws:PersonalPlanningFailure.unsupported) {try PersonalFileIntents.parse("create a folder",now:Date())}
    }
    @Test func verifiedMoveRequiresSourceAbsenceAndSameDirectoryIdentity() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        let request=try PersonalFolderCommand(name:"Projects",location:.documents)
        _=try NativePersonalFolders.create(request,rootURL:root)
        let bound=try NativePersonalFolders.bind(request,rootURL:root),moved=root.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at:root.appendingPathComponent("Projects"),to:moved)
        #expect(try NativePersonalFolders.verifyTrashCompletion(bound,rootURL:root,moved:moved))
        let other=root.appendingPathComponent("Other");try FileManager.default.createDirectory(at:other,withIntermediateDirectories:false)
        #expect(throws:PersonalAgentError.verificationFailed) {try NativePersonalFolders.verifyTrashCompletion(bound,rootURL:root,moved:other)}
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Projects"),withIntermediateDirectories:false)
        #expect(throws:PersonalAgentError.verificationFailed) {try NativePersonalFolders.verifyTrashCompletion(bound,rootURL:root,moved:moved)}
    }
}

@Suite("43A folder-result HUD navigation",.serialized) @MainActor struct PersonalAgent43ResultTests {
    @Test func clickingSearchResultsNeverStartsDictation() async throws {
        let input=GInput(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner()
        let c=SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),agentCaptureValidation:{},agentConflict:{_ in false},preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{$0})
        c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner;defer {c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand("find folder Projects in Documents");await c.waitForAgentPlanning()
        #expect(c.agentHUD=="Folder results");let before=c.agentReviewRequest
        c.pillClicked();#expect(c.agentReviewRequest != before);#expect(input.starts==0);#expect(runner.calls.count==1)
    }
}


@Suite("44A Mac audio and browser/player actions",.serialized) @MainActor struct PersonalAgent44Tests {
    @Test(arguments:[("set volume to forty five percent",45),("set the volume to 0%",0),("set volume to one hundred",100),("change volume to 72 percent",72)])
    func numericSpeechAndBoundaries(_ sample:(String,Int)) throws {
        let p=try #require(try PersonalControlIntents.parse(sample.0,now:Date()))
        #expect(p.steps.count==1);#expect(p.steps[0].tool == .systemAudio)
        let c=try PersonalAudioCommand.decode(p.steps[0].text);#expect(c.action == .set);#expect(c.percent==sample.1)
    }
    @Test(arguments:["set volume to -1","set volume to 101 percent","set volume to lots","next tab","open a new tab in Firefox","volume up then delete folder Projects in Documents","mute and open Safari"])
    func unsupportedControlsCannotFallIntoOtherTools(_ text:String) {
        #expect(throws:(any Error).self) {try PersonalConversation.quick(.init(text:text,locale:"en",apps:PersonalAgent40Tests.apps))}
    }
    @Test(arguments:[("volume up",PersonalAudioCommand.Action.up),("turn down the volume",.down),("mute",.mute),("unmute audio",.unmute),("what is the volume",.status)])
    func routineAudioPhrases(_ sample:(String,PersonalAudioCommand.Action)) throws {
        var d=PersonalAgentDialogue();guard case .plan(let p)=try d.intake(sample.0,apps:[],now:Date()) else {Issue.record("Expected native audio plan");return}
        #expect(try PersonalAudioCommand.decode(p.steps[0].text).action==sample.1);#expect(PersonalAuthorization.routine(p));#expect(!p.steps[0].displayText.contains("{"))
    }
    @Test(arguments:["new tab in Safari","open a new window in Brave","switch to the next tab in Safari","previous tab in Brave"])
    func browserUsesExplicitFixedIdentity(_ text:String) throws {
        let p=try #require(try PersonalControlIntents.parse(text,now:Date()));let c=try PersonalBrowserControl.decode(p.steps[0].text)
        #expect(p.steps[0].tool == .browserControl);#expect(c.browser.bundleID==(text.contains("Brave") ? "com.brave.Browser":"com.apple.Safari"))
    }
    @Test(arguments:["next track in Spotify","play the previous song in Music","skip to next track","next track in Apple Music"])
    func playerCommandsStayClosed(_ text:String) throws {
        let p=try #require(try PersonalControlIntents.parse(text,now:Date()));#expect(p.steps[0].tool==(text.contains("Spotify") ? .spotify:.music));#expect(["next","previous"].contains(p.steps[0].text))
    }
    @Test func repeatAndPayloadAreHandledSeparately() throws {
        let p=try #require(try PersonalControlIntents.parse("volume up volume up",now:Date()));#expect(p.steps.count==1)
        let note=try PersonalConversation.quick(.init(text:"create a note next tab in Safari",locale:"en",apps:[]));#expect(note.steps[0].tool == .note);#expect(note.steps[0].text=="next tab in Safari")
        #expect(throws:(any Error).self) {try PersonalAudioCommand.decode("{\"action\":\"set\",\"percent\":200}")}
        #expect(throws:(any Error).self) {try PersonalAudioCommand(action:.mute,percent:5)}
    }
    @Test func nativeAudioReadbackMustBeValid() throws {
        #expect(try NativePersonalControls.audioEvidence("45:true").contains("muted"))
        for bad in ["200:true","40:maybe","unverified", "-1:false"] {#expect(throws:PersonalAgentError.verificationFailed) {try NativePersonalControls.audioEvidence(bad)}}
    }
    @Test func fixedAudioAndBrowserScriptsCompileWithoutExecuting() throws {
        var sources:[String]=[]
        for action in [PersonalAudioCommand.Action.status,.set,.up,.down,.mute,.unmute] {sources.append(NativePersonalControls.audioSource(try .init(action:action,percent:action == .set ? 40:nil)))}
        for browser in [PersonalBrowserQuery.Browser.safari] {for action in [PersonalBrowserControl.Action.newTab,.newWindow,.nextTab,.previousTab] {sources.append(NativePersonalControls.browserSource(.init(browser:browser,action:action)))}}
        for source in sources {var failure:NSDictionary?;let script=try #require(NSAppleScript(source:source));let ok=script.compileAndReturnError(&failure);#expect(ok,"Fixed native template failed compile: \(String(describing:failure))")}
    }
}

@Suite("44A delayed player verification") @MainActor struct PersonalAgent44TrackTests {
    @Test func slowReadbackIsObservedWithoutSendingAnotherCommand() async throws {
        var reads=0,pauses=0
        try await NativePersonalControls.observeChangedTrack("original",read:{reads+=1;return reads>=3 ? "changed":"original"},pause:{pauses+=1})
        #expect(reads==3);#expect(pauses==2)
    }
    @Test func unchangedOrMissingTrackNeverVerifies() async {
        var reads=0
        await #expect(throws:PersonalAgentError.verificationFailed) {try await NativePersonalControls.observeChangedTrack("original",read:{reads+=1;return "original"},pause:{})}
        #expect(reads==12)
        await #expect(throws:PersonalAgentError.verificationFailed) {try await NativePersonalControls.observeChangedTrack("original",read:{""},pause:{})}
    }
}

@Suite("45A roadmap native layout and Mac controls",.serialized) @MainActor struct PersonalAgent45LayoutTests {
    @Test(arguments:["left half","right half","top half","bottom half","top-left quarter","top-right quarter","bottom-left quarter","bottom-right quarter","next display"])
    func nativeLayoutGrammar(_ kind:String) throws {
        let plan=try #require(try PersonalWindowLayout.parse("Move Safari to the "+kind,apps:PersonalAgent40Tests.apps,now:Date()))
        #expect(plan.steps.count==1);#expect(plan.steps[0].tool == .layoutApp)
        #expect(try PersonalWindowLayout.decode(plan.steps[0].text).appID=="com.apple.Safari")
    }
    @Test func centerAndRepeatedRequestBindOneInstalledApp() throws {
        let c=try #require(try PersonalWindowLayout.parse("Centre the Safari window",apps:PersonalAgent40Tests.apps,now:Date()))
        #expect(try PersonalWindowLayout.decode(c.steps[0].text).layout == .center)
        let p=try #require(try PersonalWindowLayout.parse("Move Safari to the left half Move Safari to the left half",apps:PersonalAgent40Tests.apps,now:Date()));#expect(p.steps.count==1)
    }
    @Test func layoutGeometryUsesVisibleFrameAndPreservesCenterSize() {
        let visible=CGRect(x:-1200,y:100,width:1200,height:800)
        #expect(NativePersonalWindows.layoutFrame(.left,visible:visible,currentSize:.zero)==CGRect(x:-1200,y:100,width:600,height:800))
        #expect(NativePersonalWindows.layoutFrame(.topRight,visible:visible,currentSize:.zero)==CGRect(x:-600,y:500,width:600,height:400))
        #expect(NativePersonalWindows.layoutFrame(.center,visible:visible,currentSize:CGSize(width:1400,height:900)).size==CGSize(width:1400,height:900))
    }
    @Test func deviceSelectionRejectsAmbiguityAndHonorsExactMatch() throws {
        let devices:[(id:UInt32,name:String,builtIn:Bool)]=[(1,"Studio Headphones",false),(2,"Travel Headphones",false),(3,"MacBook Microphone",true)]
        #expect(throws:PersonalAgentError.unsupported) {try NativeMacControl.uniqueDevice("headphones",devices:devices)}
        #expect(try NativeMacControl.uniqueDevice("Studio Headphones",devices:devices)==1)
        #expect(try NativeMacControl.uniqueDevice("built-in",devices:devices)==3)
    }
    @Test(arguments:["Increase the brightness","Set brightness to fifty percent","Dim the screen","What is my battery level","Switch sound output to my headphones","Use the built-in microphone"])
    func macControlGrammar(_ text:String) throws {
        let p=try #require(try PersonalMacControl.parse(text,now:Date()));#expect(p.steps[0].tool == .macControl)
        #expect(throws:PersonalAgentError.invalidCommand) {try PersonalMacControl(action:.brightnessSet,value:"101")}
    }
}

@Suite("45A expanded roadmap contracts",.serialized) @MainActor struct PersonalAgent45ExpandedTests {
    @Test(arguments:["show reminders due today","show overdue reminders","create a reminder list called Work","mark Buy milk as complete","move Call Sam to tomorrow at ten am","rename reminder Buy milk to Buy oat milk","move Buy milk to my Shopping list","flag Call Sam as important","delete the reminder Buy milk","find reminders mentioning passport","what is on my calendar tomorrow","find a free hour tomorrow afternoon","find my dentist appointment","open my next meeting","rename Lunch with Sam event to Lunch with team","move my dentist appointment to Friday at three pm","extend my focus block by thirty minutes","cancel my personal focus block","remind me fifteen minutes before my appointment","show my next event location"])
    func recordsAreTypedAndRequireReview(_ text:String) throws {
        let now=Date();var dialogue=PersonalAgentDialogue()
        guard case .plan(let p)=try dialogue.intake(text,apps:PersonalAgent40Tests.apps,now:now) else {Issue.record("Expected complete record plan");return}
        #expect(p.steps.count==1);#expect(p.steps[0].tool == .recordAction);#expect(PersonalAuthorization.routine(p) == !(try PersonalRecordCommand.decode(p.steps[0].text).isMutation))
        _=try PersonalRecordCommand.decode(p.steps[0].text)
    }
    @Test func ambiguousTimeAndRecordTypeAskBeforeAnyEffect() throws {
        var d=PersonalAgentDialogue();let now=Date()
        guard case .ask=try d.intake("Move Call Sam to tomorrow at ten",apps:[],now:now) else {Issue.record("Expected AM/PM question");return}
        guard case .plan(let p)=try d.intake("tomorrow at ten am",apps:[],now:now) else {Issue.record("Expected completed date");return}
        #expect(try PersonalRecordCommand.decode(p.steps[0].text).date != nil)
        guard case .ask=try d.intake("Rename Lunch with Sam to Lunch with team",apps:[],now:now) else {Issue.record("Expected entity question");return}
        guard case .plan(let renamed)=try d.intake("calendar event",apps:[],now:now) else {Issue.record("Expected calendar plan");return}
        #expect(try PersonalRecordCommand.decode(renamed.steps[0].text).action == .calendarRename)
    }
    @Test(arguments:["Show my Notes folders","Create a Notes folder called Ideas","Find notes titled Project Plan","Open the note titled Project Plan","Append Buy batteries to my Shopping note","Rename my note Project Plan to Launch Plan","Move my Project Plan note to Work","Duplicate my Project Plan note","Export my Project Plan note as PDF","Play the song named Imagine in Music","Play my Focus playlist in Music","Turn shuffle on in Spotify","Turn shuffle off in Music","Repeat this track in Music","Turn repeat off in Music","Skip forward thirty seconds in Music","What song is playing in Spotify","Find Sam in Contacts","Show the phone numbers for Sam","Open my chat with Sam in Messages","Open my chat with Sam in WhatsApp"])
    func objectCommandsDoNotBecomeAppLaunches(_ text:String) throws {
        let p=try #require(try PersonalObjectCommand.parse(text,now:Date()))
        #expect([PersonalTool.notesAction,.mediaAction,.contactAction].contains(p.steps[0].tool));#expect(p.steps.count==1)
    }
    @Test(arguments:["Rename folder Drafts to Archive in Documents","Move folder Projects from Desktop to Documents","Duplicate folder Projects in Documents","Rename file draft.txt to final.txt in Documents","Copy file agenda.pdf from Desktop to Documents","Show information for folder Projects in Documents","Compress folder Projects in Documents"])
    func fileCommandsRequireBoundReview(_ text:String) throws {
        let p=try #require(try PersonalFileAction.parse(text,now:Date()));#expect(p.steps[0].tool == .fileAction);#expect(PersonalAuthorization.routine(p) == ((try PersonalFileAction.decode(p.steps[0].text).action) == .info))
        let c=try PersonalFileAction.decode(p.steps[0].text);#expect(c.sourceIdentity==nil)
    }
    @Test func missingSourceLocationIsNeverGuessed() throws {
        var d=PersonalAgentDialogue();let now=Date()
        guard case .ask=try d.intake("Move file agenda.pdf to Downloads",apps:[],now:now) else {Issue.record("Expected location");return}
        guard case .plan(let p)=try d.intake("Desktop",apps:[],now:now) else {Issue.record("Expected scoped plan");return}
        #expect(try PersonalFileAction.decode(p.steps[0].text).location == .desktop)
        #expect(throws:(any Error).self) {try PersonalFileAction(action:.move,folder:false,name:"../secret",location:.documents)}
    }
    @Test(arguments:["Close the current tab in Brave","Duplicate this tab in Safari","Find the tab named Documentation in Brave","Find my example.com tab in Safari"])
    func browserExtrasStayClosed(_ text:String) throws {
        let p=try #require(try PersonalBrowserExtra.parse(text,now:Date()));#expect(PersonalAuthorization.routine(p) == ((try PersonalBrowserExtra.decode(p.steps[0].text).action) != .close));#expect(p.steps[0].tool == .browserExtra)
    }
    @Test func fileCopyMoveAndConflictAreRealTemporaryFixtureEffects() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
        try Data("original".utf8).write(to:root.appendingPathComponent("source.txt"))
        let copy=try PersonalFileAction(action:.copy,folder:false,name:"source.txt",location:.documents,destinationName:"copy.txt")
        _=try await NativeFileActions.fixtureOperation(copy,sourceRoot:root,destinationRoot:root)
        #expect(try Data(contentsOf:root.appendingPathComponent("copy.txt"))==Data("original".utf8))
        await #expect(throws:(any Error).self) {try await NativeFileActions.fixtureOperation(copy,sourceRoot:root,destinationRoot:root)}
        let rename=try PersonalFileAction(action:.rename,folder:false,name:"copy.txt",location:.documents,destinationName:"renamed.txt")
        _=try await NativeFileActions.fixtureOperation(rename,sourceRoot:root,destinationRoot:root);#expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("copy.txt").path))
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("link.txt"),withDestinationURL:root.appendingPathComponent("source.txt"))
        let link=try PersonalFileAction(action:.copy,folder:false,name:"link.txt",location:.documents,destinationName:"bad.txt")
        await #expect(throws:(any Error).self) {try await NativeFileActions.fixtureOperation(link,sourceRoot:root,destinationRoot:root)}
    }
    @Test func boundedFolderCopyAndCompressionPreserveOriginal() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root.appendingPathComponent("Source"),withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        try Data("hidden data".utf8).write(to:root.appendingPathComponent("Source/.hidden"))
        _=try await NativeFileActions.fixtureOperation(.init(action:.copy,folder:true,name:"Source",location:.documents,destinationName:"Copy"),sourceRoot:root,destinationRoot:root)
        #expect(try Data(contentsOf:root.appendingPathComponent("Copy/.hidden"))==Data("hidden data".utf8))
        _=try await NativeFileActions.fixtureOperation(.init(action:.compress,folder:true,name:"Source",location:.documents,destinationName:"Source.aar"),sourceRoot:root,destinationRoot:root)
        #expect(try Data(contentsOf:root.appendingPathComponent("Source.aar")).count>0)
        #expect(FileManager.default.fileExists(atPath:root.appendingPathComponent("Source/.hidden").path))
    }
    @Test func outputWriterNeverOverwritesOrFollowsSymlinks() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let bytes=Data("sentinel".utf8);_ = try NativeFileActions.writeExclusive(bytes,name:"new.txt",rootURL:root)
        #expect(throws:(any Error).self) {try NativeFileActions.writeExclusive(Data(),name:"new.txt",rootURL:root)}
        #expect(try Data(contentsOf:root.appendingPathComponent("new.txt"))==bytes)
    }
    @Test func notePDFRendersMultiplePagesWithoutNativeNotesAccess() throws {
        let pdf=try #require(NativeNotesActions.pdf(String(repeating:"A paragraph of synthetic text.\n",count:2000)))
        let provider=try #require(CGDataProvider(data:pdf as CFData));let doc=try #require(CGPDFDocument(provider));#expect(doc.numberOfPages>1)
    }
    @Test func ownedTimersStayIsolatedAndNamed() throws {
        let now=Date();let plan=try #require(try PersonalTimerControl.parse("Set a tea timer for four minutes",now:now));#expect(plan.steps[0].text=="tea");#expect(plan.steps[0].date==now.addingTimeInterval(240))
        let content=UNMutableNotificationContent();content.title="Unrelated";content.body="tea"
        let unrelated=UNNotificationRequest(identifier:"unrelated",content:content,trigger:nil)
        #expect(!NativeOwnedTimers.isOwned(unrelated));#expect(throws:PersonalAgentError.unsupported) {try NativeOwnedTimers.matchingName("tea",requests:[unrelated])}
    }
    @Test func reviewedScreenshotPlansDoNotCaptureDuringParsing() throws {
        let p=try #require(try PersonalScreenCapture.parse("Take a screenshot of an area",now:Date()));#expect(!PersonalAuthorization.routine(p));#expect(try PersonalScreenCapture.decode(p.steps[0].text).region)
    }
    @Test func nativeMediaAndBrowserTemplatesCompileWithoutExecuting() throws {
        for action in [PersonalObjectCommand.Action.mediaTrack,.mediaPlaylist,.mediaShuffleOff,.mediaRepeatOne,.mediaRepeatOff,.mediaSeek] {
            let c=try PersonalObjectCommand(action:action,name:action == .mediaTrack ? "Imagine":action == .mediaPlaylist ? "Focus":"music",value:action == .mediaSeek ? "30":"")
            var error:NSDictionary?;let script=try #require(NSAppleScript(source:NativeMediaActions.source(c)));let ok=script.compileAndReturnError(&error);#expect(ok,"\(String(describing:error))")
        }
        var c=try PersonalBrowserExtra(action:.duplicate,browser:.safari);c.windowID=1;c.tabIndex=1;c.url="https://example.com"
        let commands=[c,try PersonalBrowserExtra(action:.findDomain,browser:.safari,query:"example.com")]
        for c in commands {var error:NSDictionary?;let source=NativeBrowserExtra.source(c.browser,try NativeBrowserExtra.body(c));let script=try #require(NSAppleScript(source:source));let ok=script.compileAndReturnError(&error);#expect(ok,"\(String(describing:error))")}

    }
}

@MainActor private final class RoadmapPausingRunner:PersonalToolRunning {
    var engine:PersonalAgentEngine?
    var calls:[UUID]=[]
    var pauseFirst=true
    func perform(_ step:PersonalStep) throws ->PersonalReceipt {
        calls.append(step.id)
        if pauseFirst,calls.count==1,let engine {try engine.pause(engine.records.last!.id)}
        return .init(identifier:step.id.uuidString,evidence:"synthetic verified result")
    }
}
@Suite("45A exact review, durable workflows and actual template rendering",.serialized) @MainActor struct PersonalAgent45SafetyTests {
    private func temporaryRoot() throws ->URL {let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);return root}
    @Test func legacyPlanAndJournalDecodeKeepsNewReviewRulesConservative() throws {
        let plan=try PersonalPlan(steps:[.init(tool:.openInstalledApp,text:"com.apple.Safari")])
        var data=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(plan)) as? [String:Any]);data.removeValue(forKey:"requiresReview")
        let old=try JSONDecoder().decode(PersonalPlan.self,from:JSONSerialization.data(withJSONObject:data));#expect(!old.requiresReview);#expect(old.steps==plan.steps)
        let forced=try PersonalPlan(steps:plan.steps,requiresReview:true);#expect(!PersonalAuthorization.routine(forced))
    }
    @Test func routineEditIsCompareAndSwapAndRunsNeedFreshReview() async throws {
        let root=try temporaryRoot();defer{try? FileManager.default.removeItem(at:root)}
        let store=PersonalRoutineStore(url:root.appendingPathComponent("routines.json")),now=Date()
        let first=try PersonalRoutineDefinition(name:"Morning setup",steps:[.init(tool:.openInstalledApp,text:"com.apple.Safari"),.init(tool:.timer,text:"tea",date:now.addingTimeInterval(240))],createdAt:now)
        _=try store.save(.init(definition:first));let loaded=try store.named("Morning setup");#expect(loaded==first)
        let plan=try loaded.freshPlan(now:now.addingTimeInterval(60));#expect(plan.requiresReview);#expect(plan.steps[0].id != first.steps[0].id);#expect(plan.steps[1].date==now.addingTimeInterval(300))
        let resolved=try await NativeAgentResolution.resolve(try .init(steps:[.init(tool:.openInstalledApp,text:"synthetic.app")],requiresReview:true));#expect(resolved.requiresReview)
        let replacement=try PersonalRoutineDefinition(name:"Morning setup",steps:[.init(tool:.openInstalledApp,text:"com.brave.Browser")])
        #expect(throws:PersonalAgentError.approvalRequired) {try store.save(.init(definition:replacement))}
        _=try store.save(.init(definition:replacement,replacing:first.id));#expect(try store.named("Morning setup")==replacement)
        #expect(throws:(any Error).self) {try PersonalRoutineDefinition(name:"Nested",steps:[.init(tool:.routineSave,text:"{}")])}
    }
    @Test func pauseAndContinueNeverReplayVerifiedOrCreateTwoContinuations() async throws {
        let root=try temporaryRoot(),runner=RoadmapPausingRunner();defer{try? FileManager.default.removeItem(at:root)}
        let engine=try PersonalAgentEngine(url:root.appendingPathComponent("queue.json"),runner:runner);runner.engine=engine;defer{try? engine.close()}
        let original=try PersonalPlan(steps:[.init(tool:.openInstalledApp,text:"one"),.init(tool:.openInstalledApp,text:"two")]);try engine.enqueue(original);try await engine.approveAndRun(original)
        #expect(engine.records[0].state == .paused);#expect(runner.calls==[original.steps[0].id])
        let next=try engine.continuationPlan(original.id,now:Date());#expect(next.requiresReview);#expect(next.steps.count==1);#expect(next.steps[0].text=="two")
        try engine.enqueueContinuation(next,from:original.id)
        #expect(throws:PersonalAgentError.approvalRequired) {try engine.enqueueContinuation(next,from:original.id)}
        #expect(throws:PersonalAgentError.approvalRequired) {try engine.continuationPlan(original.id,now:Date())}
        try await engine.approveAndRun(next);#expect(runner.calls.count==2);#expect(engine.records.last?.state == .completed)
    }
    @Test func uncertainEffectsRequireHumanEvidenceAndAreNeverReplayed() async throws {
        let root=try temporaryRoot(),runner=FortyRunner();runner.unverified=true;defer{try? FileManager.default.removeItem(at:root)}
        let engine=try PersonalAgentEngine(url:root.appendingPathComponent("queue.json"),runner:runner);defer{try? engine.close()}
        let original=try PersonalPlan(steps:[.init(tool:.openInstalledApp,text:"one"),.init(tool:.openInstalledApp,text:"two")]);try engine.enqueue(original);try await engine.approveAndRun(original)
        #expect(runner.calls.count==1);#expect(throws:PersonalAgentError.approvalRequired) {try engine.continuationPlan(original.id,now:Date())}
        #expect(throws:PersonalAgentError.approvalRequired) {try engine.confirmObservedOutcome(original.id,expectedStep:original.steps[1])}
        try engine.confirmObservedOutcome(original.id,expectedStep:original.steps[0]);#expect(runner.calls.count==1);#expect(engine.records[0].receipts[0]?.evidence.contains("Human observation")==true)
        let next=try engine.continuationPlan(original.id,now:Date());#expect(next.steps.count==1);#expect(next.steps[0].text=="two")
    }
    @Test func dueDraftClaimIsDurableAndNeverDispatchesAnything() throws {
        let root=try temporaryRoot();defer{try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("scheduled.json"),store=PersonalScheduledMessageStore(url:url),now=Date(),id=UUID()
        let message=PersonalMessage(recipient:"Sam",body:"Synthetic draft",address:"+15555550123"),record=try PersonalScheduledMessage(id:id,message:message,date:now.addingTimeInterval(60))
        try store.add(record)
        #expect(throws:PersonalAgentError.approvalRequired) {try store.claim(id,now:now)}
        _=try store.claim(id,now:now.addingTimeInterval(61))
        #expect(try PersonalScheduledMessageStore(url:url).records()[0].state == .claimed)
        #expect(throws:PersonalAgentError.approvalRequired) {try store.claim(id,now:now.addingTimeInterval(62))}
        #expect(throws:PersonalAgentError.approvalRequired) {try store.cancel(id)}
        let second=try PersonalScheduledMessage(id:UUID(),message:message,date:now.addingTimeInterval(120));try store.add(second);try store.cancel(second.id);#expect(try store.records().last?.state == .cancelled)
    }
    @Test func restoreBindsExactTrashIdentityAndRefusesConflicts() throws {
        let root=try temporaryRoot(),trash=root.appendingPathComponent("Trash"),destination=root.appendingPathComponent("Documents");defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:trash.appendingPathComponent("old-name"),withIntermediateDirectories:true);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
        let request=try PersonalFileAction(action:.restore,folder:true,name:"old-name",location:.documents,destinationName:"Restored",destinationLocation:.documents)
        let bound=try NativeFileActions.bindRestore(request,trashRoot:trash,destinationRoot:destination,requireExpected:false)
        _=try NativeFileActions.restore(bound,trashRoot:trash,destinationRoot:destination);#expect(FileManager.default.fileExists(atPath:destination.appendingPathComponent("Restored").path))
        #expect(throws:(any Error).self) {try NativeFileActions.restore(bound,trashRoot:trash,destinationRoot:destination)}
        try FileManager.default.createDirectory(at:trash.appendingPathComponent("old-name"),withIntermediateDirectories:false)
        #expect(throws:(any Error).self) {try NativeFileActions.bindRestore(request,trashRoot:trash,destinationRoot:destination,requireExpected:false)}
    }
    @Test func addressChoicesPreserveRoutineReviewAndCannotChangeToolFamily() throws {
        let contact=try PersonalObjectCommand(action:.contactMessages,name:"Sam"),step=PersonalStep(tool:.contactAction,text:try contact.encoded()),plan=try PersonalPlan(steps:[step],requiresReview:true)
        let choice=PersonalRecipientChoiceRequired(plan:plan,stepID:step.id,options:[],prompt:"Choose")
        let selected=try choice.choosing(.init(name:"Sam Smith",address:"+15555550123",sourceID:"synthetic-contact"),now:Date());#expect(selected.requiresReview);#expect(!PersonalAuthorization.routine(selected))
        #expect(try PersonalObjectCommand.decode(selected.steps[0].text).targetID=="synthetic-contact")
    }
    @Test func mailMetadataAndAttachmentIdentityAreCheckedBeforeDataRead() throws {
        let before=try PersonalMailSnapshot(id:1,sender:"owner@example.invalid",subject:"Subject",body:"Body",to:["sam@example.invalid"],cc:[],bcc:[],attachments:[])
        let changed=try PersonalMailSnapshot(id:1,sender:before.sender,subject:before.subject,body:before.body,to:["other@example.invalid"],cc:[],bcc:[],attachments:[])
        #expect(!NativeMailActions.sameEnvelope(before,changed))
        let root=try temporaryRoot(),file=root.appendingPathComponent("attachment.txt");defer{try? FileManager.default.removeItem(at:root)}
        try Data("first".utf8).write(to:file);let bound=try NativeMailActions.file(file)
        try FileManager.default.moveItem(at:file,to:root.appendingPathComponent("original.txt"));try Data("replacement".utf8).write(to:file)
        #expect(throws:PersonalAgentError.verificationFailed) {try NativeMailActions.file(file,expectedIdentity:bound.identity)}
    }
    @Test func actualNotesScriptsCompileWithoutReadingOrChangingNotes() throws {
        let root=try temporaryRoot();defer{try? FileManager.default.removeItem(at:root)}
        for action in [PersonalObjectCommand.Action.noteFolders,.noteCreateFolder,.noteFind,.noteOpen,.noteAppend,.noteRename,.noteMove,.noteDuplicate,.notePDF,.noteTrash] {
            var c=try PersonalObjectCommand(action:action,name:"Synthetic",value:"Synthetic value");c.containerID="synthetic-account";c.targetID="synthetic-note";c.version="synthetic-date"
            _=try NativeNotesActions.perform(.init(tool:.notesAction,text:try c.encoded()),execute:{body in
                var failure:NSDictionary?;let script=try #require(NSAppleScript(source:NativeNotesActions.source(body)));let ok=script.compileAndReturnError(&failure);#expect(ok,"\(String(describing:failure))");guard ok else {throw PersonalAgentError.invalidCommand};return body.contains("return plaintext of n") ? "Synthetic note text":"synthetic-result"
            },writePDF:{data,name in try NativeFileActions.writeExclusive(data,name:name,rootURL:root)})
        }
    }
    @Test func actualMailScriptsCompileWithoutSendingOrAccessingMail() throws {
        let before=try PersonalMailSnapshot(id:1,sender:"owner@example.invalid",subject:"Subject",body:"Body",to:["sam@example.invalid"],cc:[],bcc:[],attachments:[])
        for action in [PersonalMailCommand.Action.draft,.reply,.attach,.send] {
            var c=try PersonalMailCommand(action:action,recipient:"sam@example.invalid",subject:"Subject",body:"Body",fileName:action == .attach ? "synthetic.txt":nil,fileLocation:.documents)
            c.sourceMessageID=10;c.snapshot=before;c.fileIdentity="synthetic-identity";c.fileDigest=String(repeating:"a",count:64)
            let result=try NativeMailActions.perform(.init(tool:.mailAction,text:try c.encoded()),execute:{body in
                var failure:NSDictionary?;let script=try #require(NSAppleScript(source:NativeMailActions.source(body)));let ok=script.compileAndReturnError(&failure);#expect(ok,"\(String(describing:failure))");guard ok else {throw PersonalAgentError.invalidCommand};return body.contains("send d") ? "send-accepted":"1"
            },readSnapshot:{_,_,adding in
                if let adding {return try .init(id:1,sender:before.sender,subject:before.subject,body:before.body,to:before.to,cc:[],bcc:[],attachments:[adding.url.path],attachmentDigests:[adding.digest],attachmentIdentities:[adding.identity])};return before
            },inspectFile:{_,_ in ("synthetic-identity",String(repeating:"a",count:64))})
            #expect(result.verified == (action != .send))
        }
    }
    @Test func changedMailDraftNeverReachesSendTemplate() throws {
        let before=try PersonalMailSnapshot(id:1,sender:"owner@example.invalid",subject:"Subject",body:"Body",to:["sam@example.invalid"],cc:[],bcc:[],attachments:[])
        let changed=try PersonalMailSnapshot(id:1,sender:before.sender,subject:before.subject,body:"Changed",to:before.to,cc:[],bcc:[],attachments:[])
        var c=try PersonalMailCommand(action:.send);c.snapshot=before;var calls=0
        #expect(throws:PersonalAgentError.verificationFailed) {try NativeMailActions.perform(.init(tool:.mailAction,text:try c.encoded()),execute:{_ in calls+=1;return "send-accepted"},readSnapshot:{_,_,_ in changed},inspectFile:{_,_ in ("","")})}
        #expect(calls==0)
    }
    @Test(arguments:["tomorrow at 3PM","tomorrow at 3:30PM","tomorrow at three pm","tomorrow at 10 a.m."])
    func commonSpokenTimesStayExplicit(_ text:String) {#expect(PersonalRecordCommand.date(text,now:Date()) != nil)}
    @Test func selectedContactAsksInsteadOfGuessingAndMetadataScopesAreExplicit() throws {
        var d=PersonalAgentDialogue();let now=Date()
        guard case .ask=try d.intake("Show the phone numbers for my selected contact",apps:[],now:now) else {Issue.record("Expected exact-name question");return}
        guard case .plan(let p)=try d.intake("Sam Smith",apps:[],now:now) else {Issue.record("Expected named lookup");return}
        #expect(try PersonalObjectCommand.decode(p.steps[0].text).name=="Sam Smith")
        let scoped=try #require(try PersonalRecordCommand.plan("Show reminders due today in Shopping list",now:now));#expect(try PersonalRecordCommand.decode(scoped.steps[0].text).scopeName=="Shopping")
    }
    @Test func controlDataNeverBecomesScriptAndMenusNeedSemanticMatch() throws {
        #expect(throws:(any Error).self) {try PersonalObjectCommand(action:.noteAppend,name:"Synthetic",value:"bad\u{0}data")}
        #expect(throws:(any Error).self) {try PersonalMenuAction(action:.lock,appID:"com.brave.Browser")}
        #expect(NativeMenuActions.bookmarkURL("https://example.invalid/travel") != nil)
        #expect(NativeMenuActions.bookmarkURL("javascript:alert(1)")==nil)
        #expect(NativeMenuActions.bookmarkURL("https://user:password@example.invalid")==nil)
        #expect(NativeMenuActions.matchesCommand(.lock,character:"q",modifiers:2,title:"Lock Screen",path:["Apple"]))
        #expect(!NativeMenuActions.matchesCommand(.lock,character:"q",modifiers:2,title:"Quit",path:["File"]))
        #expect(NativeMenuActions.matchesCommand(.zoomIn,character:"+",modifiers:0,title:"Zoom In",path:["View"]))
        #expect(!NativeMenuActions.matchesCommand(.zoomIn,character:"+",modifiers:0,title:"Delete All Data",path:["View"]))
    }
}

@Suite("45A frozen 100-command roadmap admission",.serialized) @MainActor struct PersonalAgent45CatalogTests {
    static let apps=PersonalAgent40Tests.apps+[PersonalApp(id:"com.apple.Notes",name:"Notes"),PersonalApp(id:"com.apple.reminders",name:"Reminders"),PersonalApp(id:"com.apple.iCal",name:"Calendar"),PersonalApp(id:"com.microsoft.VSCode",name:"Visual Studio Code",aliases:["VS Code"])]
    @Test func catalogIsExactlyTheFrozen100UniqueIDs() {#expect(PersonalRoadmapCatalog.commands.map(\.id)==Array(1...100));#expect(Set(PersonalRoadmapCatalog.commands.map(\.example)).count==100)}
    @Test(arguments:PersonalRoadmapCatalog.commands.filter{!$0.contextual}.map(\.example))
    func everyNoncontextualRoadmapExampleHasATypedPathOrExplicitQuestion(_ text:String) throws {
        var dialogue=PersonalAgentDialogue();let outcome=try dialogue.intake(text,apps:Self.apps,now:Date())
        switch outcome {case .plan(let p):#expect(!p.steps.isEmpty);case .ask(let q):#expect(!q.prompt.isEmpty);default:Issue.record("No typed command/question for frozen example: \(text)")}
    }
}

@Suite("45A context-only commands never guess targets",.serialized) @MainActor struct PersonalAgent45ContextTests {
    @Test(arguments:["Restore the folder I just trashed","Schedule a reviewed message for tomorrow","Save these reviewed steps as Morning setup","Edit my Morning setup routine","Run my Morning setup routine","Open my development apps together","Arrange my work windows","Pause this routine after the current step","Continue this interrupted routine"])
    func absentContextNeverExecutesOrTouchesClipboard(_ request:String) async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner(),board=GClipboard(),target=GCapture()
        let c=SystemWideDictationCoordinator(input:GInput(),targets:target,insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent45CatalogTests.apps},personalMessageResolution:{$0})
        c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner
        defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand(request);await c.waitForAgentPlanning()
        #expect(runner.calls.isEmpty);#expect(target.count==0);#expect(board.installed==0);#expect(board.text=="original")
        if request.hasPrefix("Open my development") || request=="Arrange my work windows" {#expect(c.agentEditingRoutine != nil)}
    }
    @Test func qualifiedMusicTrackRetainsArtistAlbumAndCompiles() throws {
        let p=try #require(try PersonalObjectCommand.parse("Play the song named Imagine by John Lennon from album Imagine in Music",now:Date())),c=try PersonalObjectCommand.decode(p.steps[0].text)
        #expect(c.name=="Imagine");#expect(c.value=="John Lennon");#expect(c.scopeName=="Imagine")
        var error:NSDictionary?;#expect(NSAppleScript(source:NativeMediaActions.source(c))?.compileAndReturnError(&error)==true);#expect(error==nil)
    }
}

extension PersonalAgent45ContextTests {
    @Test func savedRoutineRunAndEditUseRealContextWithoutAutoexecution() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner(),board=GClipboard()
        let store=PersonalRoutineStore(url:root.appendingPathComponent("routines.json")),definition=try PersonalRoutineDefinition(name:"Morning setup",steps:[.init(tool:.openInstalledApp,text:"com.apple.Safari")])
        _=try store.save(.init(definition:definition))
        let c=SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent45CatalogTests.apps},personalMessageResolution:{$0})
        c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner
        defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand("Run my Morning setup routine");await c.waitForAgentPlanning()
        let plan=try #require(c.agentPlan);#expect(plan.requiresReview);#expect(plan.steps[0].text=="com.apple.Safari");#expect(runner.calls.isEmpty)
        c.cancelAgentConversation();c.reviewAgentCommand("Edit my Morning setup routine");await c.waitForAgentPlanning()
        #expect(c.agentEditingRoutine=="Morning setup");#expect(c.agentRoutineExistingSteps.count==1)
        c.agentRoutineEditText="Open Brave";c.saveAgentRoutineEdits();await c.waitForAgentPlanning()
        let saved=try #require(c.agentPlan);#expect(saved.steps[0].tool == .routineSave);#expect(runner.calls.isEmpty)
        #expect(try store.named("Morning setup")==definition);#expect(board.installed==0)
    }
    @Test func schedulingBindsExactPendingMessageAndRequestsSpecificTime() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),runner=FortyRunner()
        let c=SystemWideDictationCoordinator(input:GInput(),targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent45CatalogTests.apps},personalMessageResolution:NativePersonalMessages.resolve)
        c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner
        defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand("Text +15555550123 saying Open Safari");await c.waitForAgentPlanning();#expect(c.agentPlan?.steps[0].tool == .message)
        c.reviewAgentCommand("Schedule a reviewed message for tomorrow");await c.waitForAgentPlanning()
        #expect(c.agentQuestion != nil);#expect(runner.calls.isEmpty)
        c.submitAgentReply("tomorrow at 10 am");await c.waitForAgentPlanning()
        let step=try #require(c.agentPlan?.steps[0]);#expect(step.tool == .messageSchedule);#expect(runner.calls.isEmpty)
    }
}


@Suite("45A-R1 website intent and duplicate snapshot guards",.serialized) @MainActor struct PersonalWebsiteR1Tests {
    @Test(arguments:["Search for YouTube.com","youtube.com Search for youtube.com","Search for YouTube.com Search for youtube.com","Open youtube.com open YouTube.com","Visit https://youtube.com","youtube.com"])
    func reportedFormsProduceOneDirectWebsite(_ text:String) throws {
        let plan=try PersonalConversation.quick(.init(text:text,locale:"en-IN",apps:PersonalAgent40Tests.apps));#expect(plan.steps.count==1);#expect(plan.steps[0].tool == .website)
        #expect(try PersonalWebsiteRequest.decode(plan.steps[0].text).address=="https://youtube.com/")
        var dialogue=PersonalAgentDialogue();guard case .plan(let direct)=try dialogue.intake(text,apps:PersonalAgent40Tests.apps,now:Date()) else {Issue.record("Website must have a direct deterministic path");return};#expect(direct.steps.count==1);#expect(direct.steps[0].tool == .website)
    }
    @Test(arguments:["Search Google for youtube.com","Search Google youtube.com","Search on Google for youtube.com"])
    func explicitEngineRemainsSearch(_ text:String) throws {
        let plan=try PersonalConversation.quick(.init(text:text,locale:"en-IN",apps:PersonalAgent40Tests.apps));#expect(plan.steps[0].tool == .searchGoogle);#expect(plan.steps[0].text=="youtube.com")
    }
    @Test func searchesAndLiteralRepliesRetainRepeatedWords() throws {
        let punctuation=try PersonalConversation.quick(.init(text:"Search Google for why? why?",locale:"en-IN",apps:[]));#expect(punctuation.steps[0].text=="why? why?")
        let plan=try PersonalConversation.quick(.init(text:"Search YouTube for very very good music",locale:"en-IN",apps:[]));#expect(plan.steps[0].tool == .searchYouTube);#expect(plan.steps[0].text=="very very good music")
        #expect(try PersonalWebsiteRequest.plan("search for ha ha",apps:[],now:Date())==nil)
        var d=PersonalAgentDialogue();_ = try d.intake("create a note",apps:[],now:Date());guard case .plan(let note)=try d.intake("youtube.com Search for youtube.com",apps:[],now:Date()) else {Issue.record("Expected literal note");return};#expect(note.steps[0].tool == .note);#expect(note.steps[0].text=="youtube.com Search for youtube.com")
    }
    @Test func targetBrowserAndAppIdentityArePreserved() throws {
        let encoded=try PersonalWebsiteRequest(address:"https://example.com/caf%C3%A9?q=one%20two");#expect(try PersonalWebsiteRequest.decode(encoded.encoded())==encoded)
        let p=try #require(try PersonalWebsiteRequest.plan("Search for youtube.com in Safari",apps:[],now:Date()));#expect(try PersonalWebsiteRequest.decode(p.steps[0].text).browser == .safari)
        #expect(try PersonalWebsiteRequest.plan("Open com.apple.Safari",apps:PersonalAgent40Tests.apps,now:Date())==nil)
        #expect(throws:PersonalPlanningFailure.unsupported) {try PersonalWebsiteRequest.plan("youtube.com Search for example.com",apps:[],now:Date())}
    }
    @Test(arguments:["javascript:alert(1)","https://user:password@example.com","file:///tmp/data","http://example.com","example.com:8080","example.com%2f.evil.test","example.com\\evil","https://example.com\nopen"])
    func unsafeAddressesCannotReachNativeOpening(_ text:String) {#expect(PersonalWebsiteRequest.url(text)==nil)}
    @Test func agentSnapshotsExecuteOnceWithoutInsertion() async throws {
        let input=GInput(),agent=GShortcut(),board=GClipboard(),target=GCapture(),runner=FortyRunner()
        runner.unverified=true
        let c=SystemWideDictationCoordinator(input:input,targets:target,insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),agentShortcut:agent,agentCaptureValidation:{},agentConflict:{_ in false},preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{$0})
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner;defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.enableAgentShortcut();agent.receive?(.pressed);await c.waitUntilRecording();input.receive?(.transcript("youtube.com"));input.receive?(.transcript("youtube.com Search for youtube.com"));agent.receive?(.released);input.receive?(.finished);input.receive?(.finished);await c.waitForAgentPlanning()
        #expect(runner.calls.count==1);#expect(runner.calls.first?.tool == .website);#expect(!c.busy);#expect(c.agentHUD=="Website opened");#expect(c.agentRecords.first?.state == .needsReview);#expect(target.count==0);#expect(board.installed==0);#expect(board.text=="original")
    }
}


@Suite("45A-R2 local website names and natural command introductions",.serialized) @MainActor struct PersonalNaturalR2Tests {
    @Test(arguments:PersonalWebsiteNames.sites.map(\.name))
    func everyKnownNameHasAnOfflineTypedWebsite(_ name:String) throws {
        let plan=try PersonalConversation.quick(.init(text:"Hey, could you please open "+name,locale:"en-IN",apps:[]));#expect(plan.steps.count==1);#expect(plan.steps[0].tool == .website)
        #expect(try PersonalWebsiteRequest.decode(plan.steps[0].text).address==PersonalWebsiteNames.address(name))
        var d=PersonalAgentDialogue();guard case .plan(let p)=try d.intake("Go open "+name,apps:[],now:Date()) else {Issue.record("Named website must resolve locally");return};#expect(p.steps[0].tool == .website)
    }
    @Test(arguments:["Hey, open WhatsApp","hey Wesley, please open WhatsApp","Could you just open WhatsApp","Go open WhatsApp","Please go and open WhatsApp","Bring up WhatsApp","Pull up WhatsApp","Okay, can you open WhatsApp"])
    func naturalOpeningsRetainInstalledAppTarget(_ text:String) throws {
        var d=PersonalAgentDialogue();guard case .plan(let p)=try d.intake(text,apps:PersonalAgent40Tests.apps,now:Date()) else {Issue.record("Expected installed app");return};#expect(p.steps.count==1);#expect(p.steps[0].tool == .openInstalledApp);#expect(p.steps[0].text=="net.whatsapp.WhatsApp")
        let q=try PersonalConversation.quick(.init(text:text,locale:"en-IN",apps:PersonalAgent40Tests.apps));#expect((q.steps[0].tool == .openInstalledApp && q.steps[0].text=="net.whatsapp.WhatsApp") || (q.steps[0].tool == .openApp && q.steps[0].text==AppOpeningCommand.whatsapp.rawValue))
    }
    @Test(arguments:PersonalWebsiteRequest.Browser.allCases)
    func browserSelectionIsTypedAndRoundTrips(_ browser:PersonalWebsiteRequest.Browser) throws {
        let p=try #require(try PersonalWebsiteRequest.plan("Open the Gmail website in "+browser.rawValue,apps:[],now:Date()));let c=try PersonalWebsiteRequest.decode(p.steps[0].text);#expect(c.browser==browser);#expect(c.address=="https://mail.google.com/");#expect(!browser.bundleID.isEmpty)
    }
    @Test func nativeAppPriorityAndExplicitWebsiteDisambiguation() throws {
        let apps=[PersonalApp(id:"local.gmail",name:"Gmail")]
        let native=try PersonalConversation.quick(.init(text:"Open Gmail",locale:"en-IN",apps:apps));#expect(native.steps[0].tool == .openInstalledApp)
        let web=try #require(try PersonalWebsiteRequest.plan("Open Gmail website",apps:apps,now:Date()));#expect(web.steps[0].tool == .website)
        let old=try PersonalWebsiteRequest.decode(#"{"address":"https://youtube.com/","browser":"safari"}"#);#expect(old.browser == .safari)
    }
    @Test func explicitSearchAndCombinedSearchPreserveLiteralQuery() throws {
        let a=try PersonalConversation.quick(.init(text:"Hey, search Google for Gmail",locale:"en-IN",apps:[]));#expect(a.steps[0].tool == .searchGoogle);#expect(a.steps[0].text=="Gmail")
        let b=try PersonalConversation.quick(.init(text:"Go open YouTube and search for very very good piano?",locale:"en-IN",apps:[]));#expect(b.steps.count==1);#expect(b.steps[0].tool == .searchYouTube);#expect(b.steps[0].text=="very very good piano?")
    }
    @Test func unknownWebsiteNeedsExactAddressWithoutGuessing() throws {
        var d=PersonalAgentDialogue();guard case .ask = try d.intake("Open my unknown bank website in Firefox",apps:[],now:Date()) else {Issue.record("Do not invent domains");return}
        guard case .plan(let p)=try d.intake("https://example.invalid/",apps:[],now:Date()) else {Issue.record("Exact address reply");return};#expect(try PersonalWebsiteRequest.decode(p.steps[0].text).browser == .firefox)
        #expect(try PersonalWebsiteRequest.plan("Open madeupsite",apps:[],now:Date())==nil)
        var replacement=PersonalAgentDialogue();_ = try replacement.intake("Open unknown website",apps:[],now:Date());guard case .plan(let newRequest)=try replacement.intake("Hey, open Gmail",apps:[],now:Date()) else {Issue.record("A complete navigation request replaces an old navigation question");return};#expect(newRequest.steps[0].tool == .website)
    }
    @Test func literalNoteAndMessageRepliesDoNotBecomeOpenCommands() throws {
        let full=try PersonalConversation.quick(.init(text:"Create a note Google website",locale:"en-IN",apps:[]));#expect(full.steps[0].tool == .note);#expect(full.steps[0].text=="Google website")
        var d=PersonalAgentDialogue();_ = try d.intake("create a note",apps:[],now:Date());guard case .plan(let note)=try d.intake("Hey, open Google",apps:[],now:Date()) else {Issue.record("Expected literal note");return};#expect(note.steps[0].tool == .note);#expect(note.steps[0].text=="Hey, open Google")
        var m=PersonalAgentDialogue();_ = try m.intake("text +15555550123",apps:[],now:Date());guard case .plan(let message)=try m.intake("Hey, open WhatsApp",apps:[],now:Date()) else {Issue.record("Expected literal message");return};#expect(try PersonalMessage.decode(message.steps[0].text).body=="Hey, open WhatsApp")
    }
    @Test func websiteNamesAsOpenRepliesAndSpokenDomains() throws {
        var d=PersonalAgentDialogue();_ = try d.intake("open",apps:[],now:Date());guard case .plan(let p)=try d.intake("Gmail",apps:[],now:Date()) else {Issue.record("Navigation reply");return};#expect(p.steps[0].tool == .website)
        var unknown=PersonalAgentDialogue();_ = try unknown.intake("open",apps:[],now:Date());guard case .ask = try unknown.intake("unknown website",apps:[],now:Date()) else {Issue.record("Unknown navigation reply asks for address");return}
        let spoken=try #require(try PersonalWebsiteRequest.plan("Take me to youtube dot com",apps:[],now:Date()));#expect(try PersonalWebsiteRequest.decode(spoken.steps[0].text).address=="https://youtube.com/")
        let repeated=try #require(try PersonalWebsiteRequest.plan("Open Gmail Open Gmail",apps:[],now:Date()));#expect(repeated.steps.count==1)
    }
    @Test func allCatalogOriginsAreValidatedAndNamesAreUnique() throws {
        #expect(Set(PersonalWebsiteNames.sites.map(\.name)).count==PersonalWebsiteNames.sites.count)
        for site in PersonalWebsiteNames.sites {#expect(PersonalWebsiteRequest.url(site.address) != nil);#expect(!site.address.contains("?"));for alias in site.aliases {#expect(PersonalWebsiteNames.address(alias)==site.address)}}
    }
}

extension PersonalNaturalR2Tests {
    @Test func naturalRequestsWorkWithUnavailableModelAndZeroInferenceBudget() async throws {
        let generator=FortyGenerator(ready:false),planner=ApplePersonalPlanner(memory:FortyMemory(0),clock:GClock(),generator:generator)
        for text in ["Hey, open WhatsApp","Go open Google","Open Gmail","Take me to YouTube in Safari","Open Google and search for Swift tutorials"] {
            let plan=try await planner.plan(.init(text:text,locale:"en-IN",apps:PersonalAgent40Tests.apps));#expect(plan.steps.count==1)
        }
        #expect(await generator.calls==0)
    }
}


@MainActor private final class CloseR3Environment:AppCloseEnvironment {
    let process=PersonalCloseProcess(pid:987654,seconds:100,microseconds:1)
    var available=true,accept=true,alive=true,replacement=false
    var calls:[PersonalCloseProcess]=[]
    var sleeps=0,exitAfter:Int?
    func instances(_ id:String)->[PersonalCloseProcess]? {
        if !available {return nil}
        if replacement {return [.init(pid:process.pid,seconds:200)]}
        return alive ? [process]:[]
    }
    func state(_ p:PersonalCloseProcess)->CloseProcessState {alive && !replacement ? .running:.exited}
    func request(_ p:PersonalCloseProcess,bundleID:String)->Bool {calls.append(p);return accept}
    func sleep(milliseconds:Int) async throws {try Task.checkCancellation();sleeps+=1;if let exitAfter,sleeps>=exitAfter {alive=false};await Task.yield()}
}
@MainActor private final class CloseR3Runner:PersonalToolRunning {
    var receipt:PersonalReceipt
    var calls:[PersonalStep]=[]
    var fail=false
    var firstReceipt:PersonalReceipt?
    init(_ receipt:PersonalReceipt) {self.receipt=receipt}
    func perform(_ step:PersonalStep) throws ->PersonalReceipt {calls.append(step);if fail {throw PersonalAgentError.verificationFailed};return calls.count==1 ? (firstReceipt ?? receipt):receipt}
}
private actor CloseR3Gate {
    var waiting:CheckedContinuation<PersonalReceipt?,Never>?
    var entered=false
    var entry:CheckedContinuation<Void,Never>?
    func observe(_ receipt:PersonalReceipt) async ->PersonalReceipt? {entered=true;entry?.resume();entry=nil;return await withCheckedContinuation{waiting=$0}}
    func waitForEntry() async {if entered {return};await withCheckedContinuation{entry=$0}}
    func finish(_ receipt:PersonalReceipt?) {waiting?.resume(returning:receipt);waiting=nil}
}
@Suite("45A-R3 normal quit verification and Agent result clicks",.serialized) @MainActor struct PersonalCloseR3Tests {
    static func token(_ outcome:PersonalAppCloseObservation.Outcome = .pending)throws ->PersonalAppCloseObservation {try .init(bundleID:"net.whatsapp.WhatsApp",processes:[.init(pid:987654,seconds:100,microseconds:1)],outcome:outcome)}
    static func root()->URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    @Test func processProofHandlesExitZombieReuseAndDeniedMetadata() {
        let p=PersonalCloseProcess(pid:9,seconds:100),new=PersonalCloseProcess(pid:9,seconds:200)
        #expect(NativeAppClosing.classify(p,observed:p,zombie:false,failure:0) == .running)
        #expect(NativeAppClosing.classify(p,observed:p,zombie:true,failure:0) == .exited)
        #expect(NativeAppClosing.classify(p,observed:new,zombie:false,failure:0) == .exited)
        #expect(NativeAppClosing.classify(p,observed:nil,zombie:false,failure:ESRCH) == .exited)
        #expect(NativeAppClosing.classify(p,observed:nil,zombie:false,failure:EPERM) == .unknown)
        #expect(NativeAppClosing.classify(p,observed:nil,zombie:false,failure:0) == .unknown)
    }
    @Test func fastQuitVerifiesWithoutExtraRequests() async throws {
        let env=CloseR3Environment();env.exitAfter=1
        let receipt=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:env)
        #expect(receipt.verified);#expect(receipt.appClose?.outcome == .closed);#expect(env.calls.count==1);#expect(env.sleeps==1)
    }
    @Test func slowQuitReleasesForegroundThenReadOnlyObserverConfirms() async throws {
        let env=CloseR3Environment();env.exitAfter=12
        let pending=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:env)
        #expect(!pending.verified);#expect(pending.appClose?.outcome == .pending);#expect(env.sleeps==8);#expect(env.calls.count==1)
        let completed=try #require(await NativeAppClosing.followup(pending,environment:env));#expect(completed.verified);#expect(completed.appClose?.token==pending.appClose?.token);#expect(env.calls.count==1)
    }
    @Test func savePromptOrCanceledQuitStaysUnverifiedAndObservationStops() async throws {
        let env=CloseR3Environment(),pending=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:env)
        let final=try #require(await NativeAppClosing.followup(pending,environment:env));#expect(!final.verified);#expect(final.appClose?.outcome == .unconfirmed);#expect(env.calls.count==1);#expect(env.sleeps==158)
    }
    @Test func refusedUnavailableAndAlreadyClosedNeverPretendAQuitSucceeded() async throws {
        let denied=CloseR3Environment();denied.accept=false
        let refusal=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:denied);#expect(!refusal.verified);#expect(refusal.appClose?.outcome == .refused);#expect(denied.calls.count==1)
        let unknown=CloseR3Environment();unknown.available=false
        let missing=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:unknown);#expect(!missing.verified);#expect(missing.appClose?.outcome == .unavailable);#expect(unknown.calls.isEmpty)
        let gone=CloseR3Environment();gone.alive=false
        let closed=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:gone);#expect(closed.verified);#expect(gone.calls.isEmpty)
    }
    @Test func relaunchedInstanceIsNeverQuitByObservation() async throws {
        let env=CloseR3Environment(),pending=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:env);env.replacement=true
        let result=try #require(await NativeAppClosing.followup(pending,environment:env));#expect(!result.verified);#expect(result.appClose?.outcome == .reopened);#expect(env.calls.count==1)
    }
    @Test func canceledObserverNeverRequestsAnotherQuit() async throws {
        let env=CloseR3Environment(),pending=try await NativeAppClosing.perform("net.whatsapp.WhatsApp",environment:env)
        let task=Task {await NativeAppClosing.followup(pending,environment:env)};task.cancel();#expect(await task.value==nil);#expect(env.calls.count==1)
    }
    @Test func scopedLateProofCompletesOriginalOnlyAndNeverRunsRemainingSteps() async throws {
        let root=Self.root(),token=try Self.token(),runner=CloseR3Runner(token.receipt),engine=try PersonalAgentEngine(url:root.appendingPathComponent("queue.json"),runner:runner);defer{try? engine.close();try? FileManager.default.removeItem(at:root)}
        let first=PersonalStep(tool:.closeApp,text:token.bundleID),plan=try PersonalPlan(steps:[first,.init(tool:.openInstalledApp,text:"second")]);try engine.enqueue(plan);try await engine.runRequestedRoutine(plan);#expect(runner.calls.count==1)
        let wrong=try PersonalAppCloseObservation(bundleID:token.bundleID,processes:token.processes,outcome:.closed)
        #expect(throws:PersonalAgentError.verificationFailed) {try engine.reconcileAppClose(plan.id,expectedStep:first,receipt:wrong.receipt)}
        try engine.reconcileAppClose(plan.id,expectedStep:first,receipt:token.changing(.closed).receipt);#expect(engine.records[0].steps == [.verified,.pending]);#expect(engine.records[0].state == .needsReview);#expect(runner.calls.count==1)
        let continuation=try engine.continuationPlan(plan.id,now:Date());#expect(continuation.steps.count==1);#expect(continuation.requiresReview)
        #expect(throws:PersonalAgentError.approvalRequired) {try engine.reconcileAppClose(plan.id,expectedStep:first,receipt:token.changing(.closed).receipt)}
    }
    @Test(arguments:[PersonalAppCloseObservation.Outcome.pending,.refused])
    func pendingThenVerifiedCloseUpdatesPillWithoutExecutingTwice(_ outcome:PersonalAppCloseObservation.Outcome) async throws {
        let root=Self.root(),token=try Self.token(outcome),runner=CloseR3Runner(token.receipt),gate=CloseR3Gate(),input=GInput(),board=GClipboard()
        let c=SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:GShortcut(),preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{$0});c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner;c.personalCloseObservation={await gate.observe($0)}
        defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand("Now I want you to close the WhatsApp");await c.waitForAgentPlanning();await gate.waitForEntry()
        #expect(c.agentHUD==(outcome == .pending ? "Quit pending":"Quit refused"));#expect(!c.busy);let id=try #require(c.agentRecords.last?.id),before=c.agentReviewRequest
        c.pillClicked();#expect(c.agentReviewRequest != before);#expect(input.starts==0)
        await gate.finish(try token.changing(.closed).receipt);await c.waitForCloseObservation(id)
        #expect(c.agentHUD=="App closed");#expect(c.agentRecords.last?.state == .completed);#expect(runner.calls.count==1);#expect(board.text=="original")
    }
    @Test func lateProofDoesNotReplaceNewFnRecordingOrInsertAgentText() async throws {
        let root=Self.root(),token=try Self.token(),runner=CloseR3Runner(token.receipt),gate=CloseR3Gate(),input=GInput(),fn=GShortcut(),board=GClipboard()
        let c=SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:board,clock:GClock()),shortcut:fn,preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{$0});c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner;c.personalCloseObservation={await gate.observe($0)}
        defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand("Close WhatsApp");await c.waitForAgentPlanning();await gate.waitForEntry();let id=try #require(c.agentRecords.last?.id)
        c.enableShortcut();fn.receive?(.pressed);await c.waitUntilRecording()
        await gate.finish(try token.changing(.closed).receipt);await c.waitForCloseObservation(id)
        #expect(c.phase == .recording);#expect(c.agentHUD==nil);#expect(runner.calls.count==1);#expect(board.installed==0);#expect(board.text=="original");c.pillClicked();#expect(input.stops==1);c.cancel()
    }
    @Test func genericAgentFailurePillNeverStartsDictation() async throws {
        let root=Self.root(),runner=CloseR3Runner(.init(identifier:"fixture",evidence:"fixture")),input=GInput();runner.fail=true
        let c=SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{$0});c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner;defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand("Close WhatsApp");await c.waitForAgentPlanning();#expect(c.agentHUD=="Agent needs review");let before=c.agentReviewRequest;c.pillClicked();#expect(c.agentReviewRequest != before);#expect(input.starts==0);#expect(runner.calls.count==1)
    }
    @Test func oldReceiptsAndExactNamedAppArticlesRemainCompatible() throws {
        let old=try JSONDecoder().decode(PersonalReceipt.self,from:Data(#"{"identifier":"old","evidence":"native result"}"#.utf8));#expect(old.verified);#expect(old.appClose==nil)
        let full=try Self.token().receipt;#expect(try JSONDecoder().decode(PersonalReceipt.self,from:JSONEncoder().encode(full))==full)
        let exact=PersonalApp(id:"exact",name:"The WhatsApp"),plain=PersonalApp(id:"plain",name:"WhatsApp")
        #expect(try PersonalConversation.resolveApp("the WhatsApp",apps:[exact,plain]).id=="exact");#expect(try PersonalConversation.resolveApp("the WhatsApp",apps:[plain]).id=="plain")
    }
}

extension PersonalCloseR3Tests {
    @Test func earlierSuccessfulQuitCannotHideALaterPendingQuit() async throws {
        let root=Self.root(),token=try Self.token(),runner=CloseR3Runner(token.receipt),gate=CloseR3Gate(),input=GInput()
        runner.firstReceipt=try PersonalAppCloseObservation(bundleID:"com.apple.Safari",processes:[.init(pid:987653,seconds:99)],outcome:.closed).receipt
        let store=PersonalRoutineStore(url:root.appendingPathComponent("routines.json"));_ = try store.save(.init(definition:.init(name:"Close apps",steps:[.init(tool:.closeApp,text:"com.apple.Safari"),.init(tool:.closeApp,text:token.bundleID)])))
        let c=SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:DictationPreferenceStore(defaults:UserDefaults(suiteName:UUID().uuidString)!),personalPlanner:FortyPlanner(),personalApps:{PersonalAgent40Tests.apps},personalMessageResolution:{$0});c.personalAgentQueueURL=root.appendingPathComponent("queue.json");c.personalToolRunner=runner;c.personalCloseObservation={await gate.observe($0)};defer{c.close();try? FileManager.default.removeItem(at:root)}
        c.reviewAgentCommand("Run my Close apps routine");await c.waitForAgentPlanning();c.approveAgentPlan();await c.waitForAgentPlanning();await gate.waitForEntry()
        let record=try #require(c.agentRecords.last);#expect(agentTaskStatusLabel(record)=="Quit pending");#expect(c.agentHUD=="Quit pending");#expect(runner.calls.count==2)
        await gate.finish(try token.changing(.closed).receipt);await c.waitForCloseObservation(record.id)
        #expect(c.agentRecords.last?.state == .completed);#expect(c.agentHUD=="App closed");#expect(runner.calls.count==2);#expect(input.starts==0)
    }
}


@MainActor private func braveScriptingDictionaryAvailable()->Bool {
    guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.brave.Browser"),let bundle=Bundle(url:url),bundle.bundleIdentifier=="com.brave.Browser",let dictionary=bundle.object(forInfoDictionaryKey:"OSAScriptingDefinition") as? String else {return false}
    return FileManager.default.isReadableFile(atPath:url.appendingPathComponent("Contents/Resources").appendingPathComponent(dictionary).path)
}
@Suite("Optional installed Brave dictionary conformance",.serialized) @MainActor struct BraveDictionaryIntegrationTests {
    @Test(.enabled("Requires the optional installed Brave scripting dictionary; deterministic command contracts always run") {await MainActor.run{braveScriptingDictionaryAvailable()}})
    func fixedBrowserControlTemplatesCompileWithoutExecuting() throws {
        for action in [PersonalBrowserControl.Action.newTab,.newWindow,.nextTab,.previousTab] {
            let source=NativePersonalControls.browserSource(.init(browser:.brave,action:action));var failure:NSDictionary?;let script=try #require(NSAppleScript(source:source));let ok=script.compileAndReturnError(&failure);#expect(ok,"\(String(describing:failure))")
        }
    }
    @Test(.enabled("Requires the optional installed Brave scripting dictionary; deterministic command contracts always run") {await MainActor.run{braveScriptingDictionaryAvailable()}})
    func reviewedTabTemplatesCompileWithoutExecuting() throws {
        var close=try PersonalBrowserExtra(action:.close,browser:.brave);close.windowID=1;close.tabID="1";close.url="https://example.com";close.title="Example"
        for command in [close,try PersonalBrowserExtra(action:.findTitle,browser:.brave,query:"Documentation")] {
            var failure:NSDictionary?;let script=try #require(NSAppleScript(source:NativeBrowserExtra.source(.brave,try NativeBrowserExtra.body(command))));let ok=script.compileAndReturnError(&failure);#expect(ok,"\(String(describing:failure))")
        }
    }
}
@Suite("Brave script data binding without an installed browser",.serialized) @MainActor struct BravePortableContractTests {
    @Test func reviewedIdentityAndUntrustedTitleStayLiteralInProductionTemplate() throws {
        let literal="Quoted \"tab\"\nopen Safari"
        var command=try PersonalBrowserExtra(action:.close,browser:.brave);command.windowID=17;command.tabID="reviewed-tab";command.url="https://example.invalid/";command.title=literal
        let source=NativeBrowserExtra.source(.brave,try NativeBrowserExtra.body(command))
        #expect(source.contains("tell application id \"com.brave.Browser\""));#expect(source.contains(NativeAgentScript.literal(literal)))
        #expect(source.contains("set w to window id 17"));#expect(source.contains(NativeAgentScript.literal("reviewed-tab")));#expect(!source.contains("\nopen Safari\n"))
    }
}

@MainActor private final class TeluguRoutingFixture: TeluguLanguageConfiguring {
    var language: TeluguRecognitionLanguage = .automatic
    var starts = 0, stops = 0, cancels = 0
    var receive: (@MainActor @Sendable (DictationEvent)->Void)?
    func start(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo {
        starts += 1; self.receive = receive
        return .init(engine:"Fixture Small",localeIdentifier:language.whisperLanguage)
    }
    func stop() { stops += 1 }
    func cancel() { cancels += 1 }
}
@Suite("Telugu coordinator vertical slice",.serialized) @MainActor struct TeluguCoordinatorTests {
    @Test func oldPreferencesDefaultToExistingEnglishAndRoundTripNewMode() throws {
        var old = try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(DictationPreferences())) as? [String:Any])
        old.removeValue(forKey:"languageMode"); old.removeValue(forKey:"teluguRecognitionLanguage")
        var value = try JSONDecoder().decode(DictationPreferences.self,from:JSONSerialization.data(withJSONObject:old))
        #expect(value.languageMode == .english); #expect(value.teluguRecognitionLanguage == .automatic)
        value.languageMode = .teluguRomanised; value.teluguRecognitionLanguage = .teluguOnly
        #expect(try JSONDecoder().decode(DictationPreferences.self,from:JSONEncoder().encode(value)) == value)
    }
    @Test func routerDefaultsToEnglishAndAgentIgnoresTeluguSelection() async throws {
        let english = GInput(), telugu = TeluguRoutingFixture()
        let router = LanguageDictationInput(english:english,telugu:telugu)
        _ = try await router.start(localeIdentifier:"en-IN") { _ in }
        #expect(english.starts == 1); #expect(telugu.starts == 0); router.cancel()
        router.mode = .teluguRomanised
        _ = try await router.start(localeIdentifier:"en-IN") { _ in }
        #expect(telugu.starts == 1); #expect(telugu.language == .automatic)
        router.mode = .english; router.stop(); #expect(telugu.stops == 1); router.cancel()
        router.mode = .teluguRomanised; router.recognitionLanguage = .teluguOnly
        _ = try await router.start(localeIdentifier:"en-IN") { _ in }
        #expect(telugu.language == .teluguOnly); router.cancel()
        _ = try await router.startAgent(localeIdentifier:"en-IN") { _ in }
        #expect(english.starts == 2); #expect(telugu.starts == 2); router.cancel()
    }
    @Test func realInsertionServiceReceivesRomanisedTextOnceAfterRelease() async {
        let input = GInput(), capture = GCapture(), shortcut = GShortcut(), clipboard = GClipboard()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        c.preferences.keepHistory = false; c.preferences.languageMode = .teluguRomanised
        c.preferences.formatting.correctSpelling = true
        c.preferences.formatting.replacements = [.init(phrase:"మీటింగ్",replacement:"standup")]
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript("రేపు మీటింగ్ API"))
        #expect(capture.target?.replacements == 0)
        // A settings edit cannot change the backend or dictionary of an active gesture.
        c.preferences.languageMode = .english; c.preferences.formatting.replacements = []
        shortcut.receive?(.released); input.receive?(.finished); input.receive?(.finished)
        await c.waitForInsertionCompletion()
        #expect(c.cleaned == "repu standup API")
        #expect(capture.target?.value == "arepu standup APIbc")
        #expect(capture.target?.replacements == 1); #expect(clipboard.installed == 0)
        c.close()
    }
    @Test func cancelledTeluguCannotInsertThroughLateCompletionOrNextSession() async {
        let input = GInput(), capture = GCapture(), shortcut = GShortcut()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        c.preferences.keepHistory = false; c.preferences.languageMode = .teluguRomanised
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        let old = input.receive; input.receive?(.transcript("మీటింగ్")); shortcut.receive?(.cancelled)
        await c.waitForInsertionCompletion(); #expect(capture.target?.replacements == 0)
        shortcut.receive?(.pressed); await c.waitUntilRecording()
        old?(.transcript("old")); old?(.finished)
        input.receive?(.transcript("కాల్")); shortcut.receive?(.released); input.receive?(.finished)
        await c.waitForInsertionCompletion()
        #expect(c.cleaned == "call"); #expect(capture.target?.replacements == 1)
        c.close()
    }
    @Test func missingModelHasActionableMessageAndNoInsertion() async {
        let input = GInput(), capture = GCapture()
        input.startFailure = .assetsMissing
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),shortcut:GShortcut(),preferenceStore:preferences())
        c.preferences.languageMode = .teluguRomanised
        c.startManual(); await c.waitForCaptureStartup()
        #expect(c.phase == .error); #expect(c.message.contains("Small model")); #expect(capture.count == 0)
        c.close()
    }
}


extension TeluguCoordinatorTests {
    @Test func teluguStartupShowsPreparationUntilAudioIsReadyAndEnglishStaysQuiet() async {
        for mode in DictationLanguageMode.allCases {
            let input = GInput(), capture = GCapture(), shortcut = GShortcut()
            input.hold = true
            let c = SystemWideDictationCoordinator(input:input,targets:capture,
                insertion:TextInsertionService(clipboard:GClipboard(),clock:GClock()),
                shortcut:shortcut,preferenceStore:preferences())
            c.preferences.keepHistory = false; c.preferences.languageMode = mode
            c.enableShortcut(); shortcut.receive?(.pressed); await input.waitForStart()
            #expect(c.phase == .preparing)
            #expect(c.pillContent == (mode == .teluguRomanised ? .label("Preparing Telugu…") : .hidden))
            #expect(c.pillVisible)
            input.resolve(); await c.waitForCaptureStartup()
            #expect(c.phase == .recording); #expect(c.pillContent == .waveform)
            shortcut.receive?(.cancelled); await c.waitForInsertionCompletion()
            #expect(capture.target?.replacements == 0); c.close()
        }
    }
}


extension TeluguCoordinatorTests {
    @Test(arguments:["ಸಿಲಿ" + String(repeating:"ಲಿ",count:52),"సి" + String(repeating:"లి",count:52)])
    func rejectedRecognitionNeverReachesTheInsertionService(_ rejected:String) async {
        let input = GInput(), capture = GCapture(), shortcut = GShortcut(), clipboard = GClipboard()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:clipboard,clock:GClock()),shortcut:shortcut,preferenceStore:preferences())
        c.preferences.keepHistory = false; c.preferences.languageMode = .teluguRomanised
        c.enableShortcut(); shortcut.receive?(.pressed); await c.waitUntilRecording()
        input.receive?(.transcript(rejected)); shortcut.receive?(.released); input.receive?(.finished)
        await c.waitForInsertionCompletion()
        #expect(c.phase == .error); #expect(capture.target?.replacements == 0); #expect(clipboard.installed == 0)
        #expect(c.raw.isEmpty && c.cleaned.isEmpty); #expect(c.transcriptionResult == .failed)
        c.close()
    }
}
