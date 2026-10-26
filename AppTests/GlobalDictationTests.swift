import AppKit
import Combine
import SwiftUI
import Foundation
import Domain
import Testing
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
@MainActor private final class GTarget: InsertionTarget {
    let info: InsertionTargetInfo
    let original: TargetTextState
    var value: String?
    var validationError: TextTargetError?
    var writable = true, failWrite = false, acknowledgePaste = true
    var replacements = 0, pastes = 0
    var unicodeSupported = false, unicodeAcknowledged = true
    var unicodePosts = 0
    var pasted = "X"
    var beforePaste: (() -> Void)?
    init(session: String = "s", text: String = "abc", selection: Domain.TextSelection = .init(location:1,length:0)) {
        info = .init(session:session,applicationName:"Fixture Editor",processID:42,windowIdentity:"w",elementIdentity:"e",role:"AXTextArea")
        original = .init(text:text,selection:selection); value = text
    }
    func validate() throws { if let validationError { throw validationError } }
    func canReplaceSelection() -> Bool { writable }
    func replaceSelection(_ text: String) throws { replacements += 1; if failWrite { throw TextTargetError.unsupported }; value = original.selection.replacing(in:original.text,with:text) }
    func postPaste(whileClipboardOwned: () -> Bool) throws {
        beforePaste?(); try validate(); guard whileClipboardOwned() else { throw TextTargetError.clipboardChanged }
        pastes += 1
        if acknowledgePaste { value = original.selection.replacing(in:original.text,with:pasted) }
    }
    func observedText() -> String? { value }
    func postText(_ text: String, budgetMilliseconds: Int64) -> Bool {
        guard unicodeSupported else { return false }
        unicodePosts += 1
        if unicodeAcknowledged { value = original.selection.replacing(in:original.text,with:text) }
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
    var target: GTarget?
    func capture(session: String) throws -> any InsertionTarget { count += 1; if let failure { throw failure }; let t = GTarget(session:session); target = t; return t }
}
@MainActor private final class GInput: DictationInput {
    var starts = 0, stops = 0, cancels = 0
    var hold = false
    var receive: (@MainActor @Sendable (DictationEvent) -> Void)?
    var waiter: CheckedContinuation<DictationInfo,any Error>?
    var entered: CheckedContinuation<Void,Never>?
    func start(localeIdentifier: String, receive: @escaping @MainActor @Sendable (DictationEvent) -> Void) async throws -> DictationInfo {
        starts += 1; self.receive = receive; entered?.resume(); entered = nil
        if hold { return try await withCheckedThrowingContinuation { waiter = $0 } }
        return .init(engine:"Fixture Apple Speech",localeIdentifier:localeIdentifier)
    }
    func stop() { stops += 1 }
    func cancel() { cancels += 1 }
    func waitForStart() async { if starts == 0 { await withCheckedContinuation { entered = $0 } } }
    func resolve() { waiter?.resume(returning:.init(engine:"Fixture",localeIdentifier:"en-IN")); waiter = nil }
}
@MainActor private final class GShortcut: DictationShortcutMonitoring {
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
        #expect(FocusedDescendantSearch.find(root:0,limit:65,focusedEditor:{ _ in true },children:{ _,_ in [] }) == nil)
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
        for await phase in coordinator.$phase.values {
            if ![.preparing,.recording,.finalizing,.inserting].contains(phase) { return }
        }
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
        #expect(coordinator.phase == .error); #expect(!coordinator.busy); #expect(!coordinator.pillVisible)
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
        await clock.advance(2250); await clock.waitForSleep(62250)
        #expect(input.starts == 1); #expect(capture.count == 2)
        input.receive?(.transcript("hello")); shortcut.receive?(.released); input.receive?(.finished); await waitForTerminal(coordinator)
        #expect(capture.target?.replacements == 1); coordinator.close()
    }
    @Test func optionalPillCapturesBeforeStartupWithoutActivatingAWindow() async {
        let input = GInput(), capture = GCapture(), clock = GClock()
        let coordinator = world(input:input,capture:capture,clock:clock)
        #expect(!coordinator.pillVisible); coordinator.preferences.idlePillEnabled = true
        #expect(coordinator.pillVisible); coordinator.pillClicked(); #expect(capture.count == 1)
        await clock.waitForSleep(61000); coordinator.pillClicked(); input.receive?(.transcript("hello")); input.receive?(.finished)
        await waitForTerminal(coordinator); #expect(capture.target?.value == "ahellobc")
        #expect(coordinator.pillVisible); coordinator.close(); #expect(!coordinator.pillVisible)
    }
    @Test func finalFormattingKeepsRawAndNeverInsertsHypotheses() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory()
        let coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.preferences.formatting.spokenPunctuation = true; coordinator.preferences.formatting.sentenceCapitalization = true
        coordinator.pillClicked(); await clock.waitForSleep(61000)
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
            for await phase in coordinator.$phase.values { if phase == .recording { break } }
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
        coordinator.pillClicked(); await clock.waitForSleep(61000)
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
        shortcut.receive?(.pressed); await clock.waitForSleep(62500)
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
    @Test func commandsRequireOneShotArmingAndNeverInsertCommandText() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), history = GHistory()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history,appOpener:{ requests.append($0) })
        coordinator.enableShortcut(); coordinator.armCommand()
        shortcut.receive?(.pressed); await clock.waitForSleep(61000)
        #expect(!coordinator.commandArmed); #expect(capture.count == 0); #expect(coordinator.message.contains("app-opening command"))
        input.receive?(.transcript("open WhatsApp")); shortcut.receive?(.released); input.receive?(.finished)
        await waitForTerminal(coordinator)
        #expect(requests == [.whatsapp]); #expect(coordinator.phase == .success); #expect(try await history.load().isEmpty)
        #expect(!coordinator.commandArmed); coordinator.close()
    }
    @Test func unarmedCommandWordsRemainDictation() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), history = GHistory()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history,appOpener:{ requests.append($0) })
        coordinator.enableShortcut(); shortcut.receive?(.pressed); await clock.waitForSleep(61000)
        input.receive?(.transcript("open browser")); shortcut.receive?(.released); input.receive?(.finished)
        await waitForTerminal(coordinator)
        #expect(requests.isEmpty); #expect(capture.count == 1)
        #expect(capture.target?.value == "aopen browserbc"); coordinator.close()
    }
    @Test func closingBeforeQueuedVoiceDispatchPreventsOpening() async {
        let input = GInput(), clock = GClock(), shortcut = GShortcut()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),appOpener:{ requests.append($0) })
        coordinator.enableShortcut(); coordinator.armCommand(); shortcut.receive?(.pressed); await clock.waitForSleep(61000)
        input.receive?(.transcript("open settings")); shortcut.receive?(.released); input.receive?(.finished); coordinator.close()
        // Join the cancelled dispatch task explicitly; no sleeps or scheduler guesses.
        await coordinator.waitForCommandDispatch()
        #expect(requests.isEmpty)
    }
    @Test(arguments:[false,true])
    func unknownOrCancelledVoiceCommandsHaveNoEffects(_ cancelled: Bool) async {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut()
        var requests: [AppOpeningCommand] = []
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),appOpener:{ requests.append($0) })
        coordinator.enableShortcut(); coordinator.armCommand(); shortcut.receive?(.pressed); await clock.waitForSleep(61000)
        input.receive?(.transcript(cancelled ? "open settings" : "open settings and delete everything"))
        if cancelled { coordinator.cancel() } else { shortcut.receive?(.released); input.receive?(.finished) }
        await coordinator.waitForCommandDispatch()
        #expect(requests.isEmpty); #expect(capture.count == 0); #expect(!coordinator.commandArmed); coordinator.close()
    }
    @Test func disablingShortcutDisarmsVoiceCommands() {
        let coordinator = world(); coordinator.armCommand(); #expect(coordinator.commandArmed)
        coordinator.disableShortcut(); #expect(!coordinator.commandArmed); coordinator.close()
    }
    @Test func holdFnCapturesOnceStopsOnReleaseAndHidesPillAtTerminal() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), shortcut = GShortcut(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        #expect(!coordinator.pillVisible)
        let pill = ClickableDictationPill(coordinator:coordinator); #expect(!pill.panel.isVisible)
        coordinator.resumeShortcutIfAuthorized(); #expect(shortcut.enables == 1); #expect(input.starts == 0)
        shortcut.receive?(.pressed); #expect(capture.count == 1); #expect(coordinator.pillVisible)
        shortcut.receive?(.pressed); await clock.waitForSleep(61000); #expect(input.starts == 1)
        input.receive?(.transcript("Fn words")); shortcut.receive?(.released); shortcut.receive?(.released)
        #expect(input.stops == 1); #expect(coordinator.phase == .finalizing); #expect(coordinator.pillVisible)
        input.receive?(.finished); await waitForTerminal(coordinator)
        #expect(coordinator.phase == .success); #expect(!coordinator.pillVisible)
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
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), shortcut = GShortcut()
        capture.failure = .unsupported; capture.failureExplanation = "The field does not expose a readable caret or selection. Copy from History."
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        coordinator.resumeShortcutIfAuthorized(); shortcut.receive?(.pressed); await clock.waitForSleep(61000)
        input.receive?(.transcript("retained words")); shortcut.receive?(.released); input.receive?(.finished); await waitForTerminal(coordinator)
        #expect(coordinator.phase == .error); #expect(!coordinator.pillVisible); #expect(coordinator.message == capture.failureExplanation)
        #expect(coordinator.latest?.cleaned == "retained words"); #expect(coordinator.latest?.insertion.attempted == false); coordinator.close()
    }
    @Test func speechFailureTakesPrecedenceOverEarlierTargetDiagnostic() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), shortcut = GShortcut()
        capture.failure = .unsupported; capture.failureExplanation = "Target diagnostic"
        let coordinator = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:shortcut,clock:clock,preferenceStore:preferences(),history:history)
        coordinator.resumeShortcutIfAuthorized(); shortcut.receive?(.pressed); await clock.waitForSleep(61000)
        input.receive?(.transcript("partial")); input.receive?(.failed(.recognitionFailed)); await waitForTerminal(coordinator)
        #expect(coordinator.latest?.insertion.reason == .speechFailed); #expect(coordinator.message.contains("Speech")); #expect(!coordinator.pillVisible); coordinator.close()
    }
    @Test func nonFnManualCaptureNeverShowsPill() async {
        let input = GInput(), clock = GClock(), coordinator = world(input:input,clock:clock)
        coordinator.startManual(); await clock.waitForSleep(61000); #expect(!coordinator.pillVisible)
        coordinator.cancel(); #expect(!coordinator.pillVisible); coordinator.close()
    }
    @Test func pillCapturesTargetBeforeSpeechAndDoubleClicksCannotStartAnotherSession() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), coordinator = world(input:input,capture:capture,clock:clock)
        coordinator.pillClicked(); #expect(capture.count == 1)
        coordinator.pillClicked(clickCount:2); #expect(capture.count == 1)
        await clock.waitForSleep(61000); #expect(input.starts == 1)
        coordinator.pillClicked(); #expect(input.stops == 1); coordinator.pillClicked(); #expect(input.starts == 1)
        coordinator.cancel()
    }
    @Test func finalTextIsCleanedInsertedOnceAndSavedWithVerifiedOutcome() async {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await clock.waitForSleep(61000)
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
        coordinator.pillClicked(); await clock.waitForSleep(61000)
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
        coordinator.pillClicked(); await clock.waitForSleep(61000); capture.target?.validationError = .changed
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
        coordinator.pillClicked(); await clock.waitForSleep(61000); input.receive?(.transcript("partial")); coordinator.stop()
        await clock.waitForSleep(9000); await clock.advance(9000); await history.waitForEntry()
        #expect(try await history.load().first?.insertion.outcome == .timedOut); #expect(capture.target?.replacements == 0); coordinator.close()
    }
    @Test func historyOptOutAndSpacingControlAreConnected() async throws {
        let input = GInput(), clock = GClock(), history = GHistory(), coordinator = world(input:input,clock:clock,history:history)
        coordinator.preferences.keepHistory = false; coordinator.preferences.spacingCleanup = false
        coordinator.startManual(); await clock.waitForSleep(61000); input.receive?(.transcript("x   y")); coordinator.stop(); input.receive?(.finished)
        // The manual path finishes without a persistence await; wait for its owned work through the clock actor.
        await coordinator.loadHistory()
        #expect(try await history.load().isEmpty); #expect(coordinator.cleaned == "x   y"); coordinator.close()
    }
    @Test(arguments:[false,true])
    func cancellationDuringRecordingAndFinalizationNeverInserts(_ finalizing: Bool) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await clock.waitForSleep(61000); input.receive?(.transcript("cancelled draft"))
        if finalizing { coordinator.stop() }
        coordinator.cancel(); input.receive?(.transcript("late")); input.receive?(.finished); await history.waitForEntry()
        let row = try await history.load().first
        #expect(row?.insertion.outcome == .cancelled); #expect(row?.raw == "cancelled draft"); #expect(capture.target?.replacements == 0)
        coordinator.close()
    }
    @Test func cancellationDuringInsertionRetainsActualUncertainOutcome() async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory(), coordinator = world(input:input,capture:capture,clock:clock,history:history)
        coordinator.pillClicked(); await clock.waitForSleep(61000)
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
    @Test(arguments:[DictationActivationKey.fn,.rightOption,.rightCommand])
    func physicalModifierDownUpAndChords(_ key: DictationActivationKey) {
        let code = Int64(ModifierShortcutDecoder.code(key))
        let flags: CGEventFlags = key == .fn ? .maskSecondaryFn : key == .rightOption ? .maskAlternate : .maskCommand
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:flags,selectedDown:true).signal == .pressed)
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:[],selectedDown:false).signal == .released)
        if key != .fn { #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:flags,selectedDown:false).signal == .released) }
        #expect(ModifierShortcutDecoder.decode(key:key,type:.keyDown,code:53,flags:flags,selectedDown:true).signal == .cancelled)
        #expect(ModifierShortcutDecoder.decode(key:key,type:.flagsChanged,code:code,flags:flags.union(.maskShift),selectedDown:true).signal == .cancelled)
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
        for await phase in coordinator.$phase.values { if ![.preparing,.recording,.finalizing,.inserting].contains(phase) { return } }
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
        coordinator.pillClicked(); await clock.waitForSleep(61000); input.receive?(.transcript("partial"))
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
        coordinator.startManual(); await clock.waitForSleep(61000); input.receive?(.transcript("check the button")); coordinator.stop(); input.receive?(.finished); await terminal(coordinator)
        let task = try #require(coordinator.startRewritePreview()); await driver.waitForStart(); #expect(coordinator.startRewritePreview() == nil)
        coordinator.startManual(); #expect(coordinator.rewritePreview == nil); await driver.release(); await task.value
        #expect(coordinator.rewritePreview == nil); #expect(capture.count == 0); coordinator.close()
    }
    @Test func disablingOptInAndDeletingEntryInvalidatesPreview() async throws {
        let driver = GOfflineRewrite(), input = GInput(), clock = GClock(), history = GHistory()
        let coordinator = SystemWideDictationCoordinator(input:input,targets:GCapture(),insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history,offlineRewriter:driver)
        coordinator.preferences.offlineAIRewriting = true; coordinator.startManual(); await clock.waitForSleep(61000)
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
    @Test(arguments:[Int64(0),-1,120001]) func missingOrInvalidTimingMakesRateUnavailable(_ duration:Int64) {
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
        #expect(AppOpeningCommand.allCases.count == 6)
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
        registrar.receive?(.invoke(.polish)); await driver.waitForStart(); #expect(coordinator.isPreviewingRewrite)
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
    private func terminal(_ c:SystemWideDictationCoordinator) async { for await phase in c.$phase.values { if ![.preparing,.recording,.finalizing,.inserting].contains(phase) { return } } }
    @Test(arguments:[false,true]) func speechFailureIsNotAnUncertainInsertion(_ oversized:Bool) async throws {
        let input = GInput(), capture = GCapture(), clock = GClock(), history = GHistory()
        let c = SystemWideDictationCoordinator(input:input,targets:capture,insertion:TextInsertionService(clipboard:GClipboard(),clock:clock),shortcut:GShortcut(),clock:clock,preferenceStore:preferences(),history:history)
        c.pillClicked(); await clock.waitForSleep(61000); input.receive?(.transcript("synthetic partial"))
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
    let info:InsertionTargetInfo, original:TargetTextState
    unowned let editor:EEditor
    let field:Int, direct:Bool
    var writes = 0, pastes = 0
    init(editor:EEditor,session:String) {
        self.editor = editor; field = editor.focused; direct = editor.direct
        let text = editor.fields[field]; original = .init(text:text,selection:.init(location:text.utf16.count,length:0))
        info = .init(session:session,applicationName:"Synthetic editor",processID:Int32(100+field),windowIdentity:"window-\(field)",elementIdentity:"field-\(field)",role:"AXTextArea")
    }
    func validate() throws { guard editor.focused == field, editor.fields[field] == original.text else { throw TextTargetError.changed } }
    func canReplaceSelection() -> Bool { direct }
    func replaceSelection(_ text:String) throws { try validate(); writes += 1; editor.fields[field] = original.selection.replacing(in:original.text,with:text)! }
    func observedText() -> String? { editor.readable ? editor.fields[field] : nil }
    func postPaste(whileClipboardOwned:()->Bool) throws {
        try validate(); guard whileClipboardOwned() else { throw TextTargetError.clipboardChanged }; pastes += 1
        if editor.acknowledge { editor.fields[field] = original.selection.replacing(in:original.text,with:editor.clipboard.text)! }
    }
}
@Suite("Core voice repeated pipeline",.serialized,.timeLimit(.minutes(1))) @MainActor struct VoiceRepeatedPipelineTests {
    private func recording(_ c:SystemWideDictationCoordinator) async { for await phase in c.$phase.values { if phase == .recording { return } } }
    private func terminal(_ c:SystemWideDictationCoordinator) async { for await phase in c.$phase.values { if ![.preparing,.recording,.finalizing,.inserting].contains(phase) { return } } }
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
        #expect(c.latest?.insertion.status == .dispatchedUnverified); #expect(service.hasPendingClipboard); #expect(editor.targets[1].pastes == 1)
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
