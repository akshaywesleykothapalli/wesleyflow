import AppKit
import Domain
import Foundation
import AVFoundation
import Speech
import Testing
@testable import SystemOperations
@testable import ModelProviders
@testable import VoiceInput
@testable import WesleyFlow

private actor VoiceClock: TaskClock {
    private var value: Int64 = 1000
    private var waits: [UUID: (Int64, CheckedContinuation<Void, any Error>)] = [:]
    private var observers: [(Int64, CheckedContinuation<Void, Never>)] = []
    func now() -> Int64 { value }
    func sleep(until deadline: Int64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                if deadline <= value { continuation.resume(); return }
                waits[id] = (deadline, continuation)
                let ready = observers.filter { $0.0 == deadline }; observers.removeAll { $0.0 == deadline }
                ready.forEach { $0.1.resume() }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) { waits.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
    func waitForSleep(_ deadline: Int64) async {
        if waits.values.contains(where: { $0.0 == deadline }) { return }
        await withCheckedContinuation { observers.append((deadline, $0)) }
    }
    func advance(_ value: Int64) {
        self.value = value
        for id in waits.keys.filter({ waits[$0]!.0 <= value }) { waits.removeValue(forKey: id)?.1.resume() }
    }
}
@MainActor private final class VoiceFixture: DictationInput {
    var receive: (@MainActor @Sendable (DictationEvent) -> Void)?
    var starts = 0, stops = 0, cancels = 0
    var failure: DictationFailure?
    var hold = false
    var finishDuringStart = false
    var finishDuringStop = false
    var pending: CheckedContinuation<DictationInfo, any Error>?
    var entered: CheckedContinuation<Void, Never>?
    var cancellation: CheckedContinuation<Void, Never>?
    var stopping: CheckedContinuation<Void, Never>?
    func start(localeIdentifier: String, receive: @escaping @MainActor @Sendable (DictationEvent) -> Void) async throws -> DictationInfo {
        starts += 1; self.receive = receive; entered?.resume(); entered = nil
        if finishDuringStart { receive(.transcript("early result")); receive(.finished) }
        if let failure { throw failure }
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        return .init(engine: "Fixture", localeIdentifier: localeIdentifier)
    }
    func stop() { stops += 1; stopping?.resume(); stopping = nil; if finishDuringStop { receive?(.finished) } }
    func cancel() { cancels += 1; cancellation?.resume(); cancellation = nil }
    func waitForStart() async { if starts == 0 { await withCheckedContinuation { entered = $0 } } }
    func waitForCancel() async { if cancels == 0 { await withCheckedContinuation { cancellation = $0 } } }
    func waitForStop() async { if stops == 0 { await withCheckedContinuation { stopping = $0 } } }
    func resolve() { pending?.resume(returning: .init(engine: "Fixture",localeIdentifier: "en-IN")); pending = nil }
}
@Suite("Dictation data and lifecycle", .serialized, .timeLimit(.minutes(1)))
@MainActor struct DictationTests {
    @Test(arguments:[("  hello   world  ","hello world"),("line\r\n\tline","line line"),("",""),("  नमस्ते  दुनिया ","नमस्ते दुनिया"),("Um, keep  MY_case()!","Um, keep MY_case()!")])
    func deterministicCleanup(_ example: (String,String)) { #expect(DictationText.cleaned(example.0) == example.1) }
    @Test func constructionRequestsNothingAndUsesMacLanguage() {
        let input = VoiceFixture(), model = DictationModel(input: input)
        #expect(input.starts == 0); #expect(model.phase == .idle)
        #expect(model.localeIdentifier == (Locale.preferredLanguages.first ?? Locale.current.identifier))
        #expect(!model.canUseText); #expect(model.prompt.isEmpty)
    }
    @Test func partialSnapshotsReplaceAndFinalTextNeedsExplicitPromptAction() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock,localeIdentifier: "en-IN",rewriter: RewriteFixture())
        model.start(); await clock.waitForSleep(61000)
        #expect(model.phase == .recording); #expect(model.info?.localeIdentifier == "en-IN")
        input.receive?(.transcript("hello")); input.receive?(.transcript("hello   world"))
        #expect(model.raw == "hello   world"); #expect(model.prompt.isEmpty); #expect(!model.canUseText)
        model.stop(); #expect(input.stops == 1)
        input.receive?(.finished)
        #expect(model.phase == .complete); #expect(model.edited == "hello world"); #expect(model.prompt.isEmpty)
        model.edit("Reviewed text"); await model.useAsPrompt()?.value; #expect(model.prompt == "AI rewrite: Reviewed text")
        #expect(model.raw == "hello   world"); model.close()
    }
    @Test func terminalResultDuringStartupCannotRestartRecording() async {
        let input = VoiceFixture(), model = DictationModel(input: input)
        input.finishDuringStart = true; model.start(); await input.waitForStart()
        #expect(model.phase == .complete); #expect(model.edited == "early result")
        #expect(!model.busy); model.close()
    }
    @Test func synchronousStopCompletionRemainsTerminal() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input, clock: clock)
        input.finishDuringStop = true; model.start(); await clock.waitForSleep(61000)
        input.receive?(.transcript("complete")); model.stop()
        #expect(model.phase == .complete); #expect(model.edited == "complete")
        await clock.advance(100000)
        #expect(model.phase == .complete); model.close()
    }
    @Test func cancelDiscardsNewTextAndRejectsLateCallbacks() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock)
        model.edit("previous edit"); model.start(); await clock.waitForSleep(61000)
        let old = input.receive; old?(.transcript("private draft")); model.cancel()
        old?(.transcript("late")); old?(.finished)
        #expect(model.raw.isEmpty); #expect(model.edited == "previous edit"); #expect(model.prompt.isEmpty)
        #expect(model.phase == .idle); model.close()
    }
    @Test func cancelDuringPermissionWaitCannotStartRecording() async {
        let input = VoiceFixture(), model = DictationModel(input: input)
        input.hold = true; model.start(); await input.waitForStart(); model.cancel(); input.resolve()
        #expect(model.phase == .idle); #expect(model.raw.isEmpty)
        input.receive?(.finished); #expect(model.phase == .idle); model.close()
    }
    @Test(arguments:[DictationFailure.microphoneDenied,.speechDenied,.assetsMissing,.audioUnavailable])
    func failureKeepsTypedInputAvailable(_ reason: DictationFailure) async {
        let input = VoiceFixture(), model = DictationModel(input: input,rewriter: RewriteFixture())
        input.failure = reason; model.start(); await input.waitForCancel()
        #expect(model.phase == .failed); #expect(!model.busy)
        model.edit("Type instead"); await model.useAsPrompt()?.value; #expect(model.prompt == "AI rewrite: Type instead"); model.close()
    }
    @Test func finishingTimeoutClosesInputAndFencesLateResults() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock)
        model.start(); await clock.waitForSleep(61000); input.receive?(.transcript("partial")); model.stop()
        await clock.waitForSleep(9000); await clock.advance(9000); await input.waitForCancel()
        #expect(model.phase == .failed); #expect(model.edited == "partial")
        input.receive?(.finished); #expect(model.phase == .failed); model.close()
    }
    @Test func recordingLimitStopsCapture() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock)
        model.start(); await clock.waitForSleep(61000); await clock.advance(61000); await input.waitForStop()
        #expect(model.phase == .finalizing); #expect(input.stops == 1); model.cancel(); model.close()
    }
    @Test func oversizeTranscriptFailsWithoutAcceptingPayload() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock)
        model.start(); await clock.waitForSleep(61000); input.receive?(.transcript(String(repeating: "x",count: 16385)))
        #expect(model.phase == .failed); #expect(model.raw.isEmpty); model.close()
    }
    @Test func oversizedEditsDoNotReplacePriorDraft() {
        let model = DictationModel(input: VoiceFixture()); model.edit("retained"); model.editPrompt("draft")
        model.edit(String(repeating: "🙂",count: 5000)); model.editPrompt(String(repeating: "x",count: 16385))
        #expect(model.edited == "retained"); #expect(model.prompt == "draft"); model.close()
    }
    @Test func segmentRevisionsDoNotDuplicate() throws {
        var buffer = TranscriptBuffer()
        #expect(try buffer.replace("hello",start: 0,end: 1) == "hello")
        #expect(try buffer.replace("hello world",start: 0,end: 2) == "hello world")
        #expect(try buffer.replace("again",start: 2,end: 3) == "hello world again")
        #expect(try buffer.replace("again!",start: 2,end: 3) == "hello world again!")
        #expect(throws: DictationFailure.recognitionFailed) { try buffer.replace("invalid",start: .nan,end: 4) }
        #expect(throws: DictationFailure.overflow) { try buffer.replace(String(repeating: "x",count: 16385),start: 3,end: 4) }
    }
    @Test func nativeAudioBridgeConvertsAndFinishesWithoutMicrophone() async throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1))
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16,sampleRate: 16000,channels: 1,interleaved: false))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: source,frameCapacity: 1024)); input.frameLength = 1024
        for i in 0..<1024 { input.floatChannelData![0][i] = 0 }
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        let bridge = try AudioIngress(source: source,target: target,modern: pair.continuation)
        bridge.append(input); bridge.close()
        var count = 0
        for try await _ in pair.stream { count += 1 }
        #expect(count == 1)
    }
    @Test func analyzerRejectsFloatPCMBeforeFrameworkPrecondition() throws {
        let float = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000,channels: 1))
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        #expect(throws: DictationFailure.audioUnavailable) { try AudioIngress(source: float,target: float,modern: pair.continuation) }
        pair.continuation.finish()
    }
    @Test func boundedNativeAudioQueueFailsInsteadOfDroppingSilently() async throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16,sampleRate: 16000,channels: 1,interleaved: false))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 1024)); input.frameLength = 1024
        for i in 0..<1024 { input.int16ChannelData![0][i] = 0 }
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        let bridge = try AudioIngress(source: format,target: format,modern: pair.continuation)
        for _ in 0..<40 { bridge.append(input) }; bridge.close()
        var count = 0
        do { for try await _ in pair.stream { count += 1 }; Issue.record("Overflow silently succeeded") }
        catch { #expect(error as? DictationFailure == .overflow) }
        #expect(count == 32)
    }

    @Test func changedAudioFormatFailsBeforeConversion() async throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1))
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16,sampleRate: 16000,channels: 1,interleaved: false))
        let changed = try #require(AVAudioPCMBuffer(pcmFormat: target,frameCapacity: 32)); changed.frameLength = 32
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        let bridge = try AudioIngress(source: source,target: target,modern: pair.continuation)
        bridge.append(changed); bridge.close()
        do { for try await _ in pair.stream { Issue.record("Changed format accepted") }; Issue.record("No format failure") }
        catch { #expect(error as? DictationFailure == .audioUnavailable) }
    }

    @Test(arguments:[SFSpeechRecognizerAuthorizationStatus.authorized,.denied,.restricted,.notDetermined])
    func nativeAuthorizationCallbackMayRunOnBackgroundQueue(_ status: SFSpeechRecognizerAuthorizationStatus) async {
        let received = await NativeSpeechCallbacks.authorization { callback in
            DispatchQueue.global().async { callback(status) }
        }
        MainActor.assertIsolated()
        #expect(received == status)
    }
    @Test func nativeRecognitionCallbackHopsToMainActor() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let callback = NativeSpeechCallbacks.recognition { text, final, failed in
                MainActor.assertIsolated()
                #expect(text == nil); #expect(!final); #expect(failed)
                continuation.resume()
            }
            DispatchQueue.global().async { callback(nil, DictationFailure.recognitionFailed) }
        }
    }
    @Test func nativeTapCallbackMayRunOnBackgroundQueue() async throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16,sampleRate: 16000,channels: 1,interleaved: false))
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        let bridge = try AudioIngress(source: format,target: format,modern: pair.continuation)
        let callback = NativeSpeechCallbacks.tap(bridge)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                let localFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,sampleRate: 16000,channels: 1,interleaved: false)!
                let input = AVAudioPCMBuffer(pcmFormat: localFormat,frameCapacity: 1024)!
                input.frameLength = 1024
                for i in 0..<1024 { input.int16ChannelData![0][i] = 0 }
                callback(input,AVAudioTime(sampleTime:0,atRate:16000)); continuation.resume()
            }
        }
        bridge.close()
        var count = 0; for try await _ in pair.stream { count += 1 }
        #expect(count == 1)
    }

}

@MainActor private final class ShortcutFixture: DictationShortcutMonitoring {
    var receive: (@MainActor @Sendable (DictationShortcutEvent) -> Void)?
    var denies = false
    var authorizationReady = true
    var enables = 0, disables = 0
    func enable(receive: @escaping @MainActor @Sendable (DictationShortcutEvent) -> Void) throws {
        enables += 1
        if denies { throw DictationShortcutFailure.permissionRequired }
        self.receive = receive
    }
    func disable() { disables += 1 }
}
@MainActor private final class DestinationFixture: DictationTextDestination, DictationDestinationCapturing {
    var captures = 0
    var inserted: [String] = []
    var captureFails = false, insertionFails = false
    func capture() throws -> any DictationTextDestination {
        captures += 1
        if captureFails { throw DictationShortcutFailure.unsupportedField }
        return self
    }
    func insert(_ text: String) throws {
        if insertionFails { throw DictationShortcutFailure.destinationChanged }
        inserted.append(text)
    }
}
extension DictationTests {
    @Test func shortcutNeedsExplicitEnableAndOneGestureInsertsOnce() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target)
        #expect(key.enables == 0); #expect(target.captures == 0)
        model.enableShortcut(); #expect(model.shortcutEnabled); #expect(input.starts == 0)
        key.receive?(.pressed); await clock.waitForSleep(61000)
        key.receive?(.pressed); #expect(input.starts == 1); #expect(target.captures == 1)
        input.receive?(.transcript("hello   outside app")); #expect(target.inserted.isEmpty)
        key.receive?(.released); #expect(model.phase == .finalizing); #expect(target.inserted.isEmpty)
        input.receive?(.finished); input.receive?(.finished); key.receive?(.released)
        #expect(target.inserted == ["hello outside app"]); #expect(model.prompt.isEmpty)
        model.disableShortcut(); model.close()
    }
    @Test func shortcutReleaseDuringPreparationCancelsWithoutLateInsertion() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture()
        let model = DictationModel(input: input,shortcut: key,destinations: target)
        input.hold = true; model.enableShortcut(); key.receive?(.pressed); await input.waitForStart()
        key.receive?(.released); input.resolve(); input.receive?(.transcript("late")); input.receive?(.finished)
        #expect(model.phase == .idle); #expect(target.inserted.isEmpty)
        model.disableShortcut(); model.close()
    }
    @Test func shortcutCancellationAndDisabledCallbacksCannotInsert() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target)
        model.enableShortcut(); let old = key.receive
        key.receive?(.pressed); await clock.waitForSleep(61000)
        input.receive?(.transcript("discard")); key.receive?(.cancelled); input.receive?(.finished)
        #expect(target.inserted.isEmpty); #expect(model.phase == .idle)
        model.disableShortcut(); old?(.pressed); #expect(input.starts == 1)
        model.close()
    }
    @Test func shortcutPermissionAndUnsupportedFieldFailBeforeCapture() {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture()
        let model = DictationModel(input: input,shortcut: key,destinations: target)
        key.denies = true; model.enableShortcut(); #expect(!model.shortcutEnabled)
        #expect(input.starts == 0); #expect(target.captures == 0)
        key.denies = false; target.captureFails = true; model.enableShortcut(); key.receive?(.pressed)
        #expect(input.starts == 0); #expect(target.inserted.isEmpty)
        model.disableShortcut(); model.close()
    }
    @Test func changedDestinationKeepsTranscriptWithoutRetry() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target)
        target.insertionFails = true; model.enableShortcut(); key.receive?(.pressed); await clock.waitForSleep(61000)
        input.receive?(.transcript("retained")); key.receive?(.released); input.receive?(.finished)
        #expect(target.inserted.isEmpty); #expect(model.edited == "retained")
        #expect(model.shortcutMessage.contains("field changed"))
        target.insertionFails = false; input.receive?(.finished); #expect(target.inserted.isEmpty)
        model.disableShortcut(); model.close()
    }
    @Test func monitorLossStopsDictationAndDisablesShortcut() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target)
        model.enableShortcut(); key.receive?(.pressed); await clock.waitForSleep(61000)
        key.receive?(.unavailable); input.receive?(.finished)
        #expect(!model.shortcutEnabled); #expect(!model.busy); #expect(target.inserted.isEmpty)
        model.close()
    }
    @Test func inAppMicrophoneNeverInsertsIntoOtherApps() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target,rewriter: RewriteFixture())
        model.enableShortcut(); model.start(); await clock.waitForSleep(61000)
        input.receive?(.transcript("local")); model.stop(); input.receive?(.finished)
        #expect(target.captures == 0); #expect(target.inserted.isEmpty); #expect(model.edited == "local")
        await model.useAsPrompt()?.value; #expect(model.prompt == "AI rewrite: local")
        model.disableShortcut(); model.close()
    }
    @Test func earlyTerminalShortcutResultWaitsForRelease() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture()
        let model = DictationModel(input: input,shortcut: key,destinations: target)
        input.finishDuringStart = true; model.enableShortcut(); key.receive?(.pressed); await input.waitForStart()
        #expect(model.phase == .complete); #expect(target.inserted.isEmpty)
        key.receive?(.released); #expect(target.inserted == ["early result"])
        model.disableShortcut(); model.close()
    }
}

extension DictationTests {
    @Test func fnDecoderConsumesOnlyStandaloneFnAndCancelsChords() {
        let down = FnShortcutDecoder.decode(type: .flagsChanged,code: 63,flags: .maskSecondaryFn)
        #expect(down.signal == .pressed); #expect(!down.consume)
        let up = FnShortcutDecoder.decode(type: .flagsChanged,code: 63,flags: [])
        #expect(up.signal == .released); #expect(!up.consume)
        for flag: CGEventFlags in [.maskCommand,.maskControl,.maskAlternate,.maskShift] {
            let chord = FnShortcutDecoder.decode(type: .flagsChanged,code: 63,flags: [.maskSecondaryFn,flag])
            #expect(chord.signal == .cancelled); #expect(!chord.consume)
        }
        let other = FnShortcutDecoder.decode(type: .keyDown,code: 0,flags: [])
        #expect(other.signal == nil); #expect(!other.consume)
        let chord = FnShortcutDecoder.decode(type: .keyDown,code: 0,flags: .maskSecondaryFn)
        #expect(chord.signal == .cancelled); #expect(!chord.consume)
        let escape = FnShortcutDecoder.decode(type: .keyDown,code: 53,flags: [])
        #expect(escape.signal == .cancelled); #expect(!escape.consume)
    }
}

extension DictationTests {
    @Test func appDelegateKeepsEnabledShortcutAliveAndCleansUpAtQuit() {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture()
        let model = DictationModel(input: input,shortcut: key,destinations: target)
        let delegate = AppDelegate(); delegate.dictation = model
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        model.enableShortcut()
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(!model.shortcutEnabled); #expect(key.disables > 0)
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}

extension DictationTests {
    @Test func missingAIServiceNeverSubstitutesBoilerplate() {
        let model = DictationModel(input:VoiceFixture()); model.edit("Improve the animated UI button")
        model.editPrompt("previous draft")
        #expect(model.useAsPrompt() == nil); #expect(model.prompt == "previous draft")
        #expect(model.message.contains("unavailable")); model.close()
    }
    @Test func invalidRewritePreservesExistingDraft() async {
        let rewrite = RewriteFixture(failure:.invalidRequest)
        let model = DictationModel(input:VoiceFixture(),rewriter:rewrite)
        model.editPrompt("existing draft"); model.edit(String(repeating:"x",count:16384))
        await model.useAsPrompt()?.value
        #expect(model.prompt == "existing draft"); #expect(model.message.contains("Shorten")); model.close()
    }
}

extension DictationTests {
    @Test func grantingPermissionRearmsOnlyAnExplicitlyRequestedShortcut() {
        let key = ShortcutFixture(), model = DictationModel(input: VoiceFixture(),shortcut: key,destinations: DestinationFixture())
        model.refreshShortcutPermission(); #expect(key.enables == 0)
        key.denies = true; key.authorizationReady = false; model.enableShortcut(); #expect(!model.shortcutEnabled)
        key.denies = false; key.authorizationReady = true; model.refreshShortcutPermission()
        #expect(model.shortcutEnabled); #expect(key.enables == 2)
        model.disableShortcut(); model.refreshShortcutPermission(); #expect(key.enables == 2); model.close()
    }
    @Test func revokedAccessibilityDisarmsAnActiveGesture() async {
        let key = ShortcutFixture(), target = DestinationFixture(), input = VoiceFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target)
        model.enableShortcut(); key.receive?(.pressed); await clock.waitForSleep(61000)
        key.authorizationReady = false; model.refreshShortcutPermission(); input.receive?(.finished)
        #expect(!model.shortcutEnabled); #expect(!model.busy); #expect(target.inserted.isEmpty); model.close()
    }
}

private actor RewriteFixture: PromptRewriting {
    var failure: InferenceFailure?
    var hold = false
    var settlement: InferenceCancellation = .completed
    var waiter: CheckedContinuation<Void,Never>?
    var observer: CheckedContinuation<Void,Never>?
    var calls = 0
    var ids: [String] = []
    init(failure: InferenceFailure? = nil) { self.failure = failure }
    func configure(hold: Bool = false, settlement: InferenceCancellation = .completed) { self.hold = hold; self.settlement = settlement }
    func rewrite(_ text: String, modelName: String, requestID: String) async throws -> String {
        calls += 1; ids.append(requestID)
        if hold { await withCheckedContinuation { waiter = $0; observer?.resume(); observer = nil } }
        if let failure { throw failure }
        return "AI rewrite: " + text
    }
    func waitForCall() async { if waiter == nil { await withCheckedContinuation { observer = $0 } } }
    func resolve() { waiter?.resume(); waiter = nil }
    func cancel(requestID: String) -> InferenceCancellation { .httpCancelledProviderUncertain }
    func settle() -> InferenceCancellation { settlement }
}
private actor RewriteProviderFixture: LocalModelProvider {
    var requests: [InferenceRequest] = []
    var cancelled: [String] = []
    var response = #""Review the button states and refine animation transitions.""#
    var invalidIdentity = false
    var hold = false
    var waiter: CheckedContinuation<Void,Never>?
    var observer: CheckedContinuation<Void,Never>?
    func model() throws -> ModelDescriptor { try .init(name:"qwen2.5-coder:7b",digest:String(repeating:"a",count:64),storedBytes:4_683_087_561,capabilities:.init(structuredOutput:true,maximumContext:4096)) }
    func discover() throws -> [ModelDescriptor] { [try model()] }
    func generate(_ request: InferenceRequest) async throws -> InferenceResponse {
        requests.append(request)
        if hold { await withCheckedContinuation { waiter = $0; observer?.resume(); observer = nil } }
        return .init(requestID:invalidIdentity ? "foreign" : request.id,modelDigest:request.model.digest,content:response,metrics:.init())
    }
    func configure(response: String? = nil, invalidIdentity: Bool = false, hold: Bool = false) {
        if let response { self.response = response }; self.invalidIdentity = invalidIdentity; self.hold = hold
    }
    func waitForCall() async { if waiter == nil { await withCheckedContinuation { observer = $0 } } }
    func resolve() { waiter?.resume(); waiter = nil }
    func cancel(requestID: String) -> InferenceCancellation { cancelled.append(requestID); return .httpCancelledProviderUncertain }
    func reconcile() -> InferenceCancellation { .completed }
    func shutdown() -> InferenceCancellation { .completed }
}
extension DictationTests {
    @Test func memoryDenialNeverCreatesAnAIOrTemplatePrompt() async {
        let model = DictationModel(input:VoiceFixture(),rewriter:RewriteFixture(failure:.memoryAdmissionDenied))
        model.edit("Check if it works"); model.editPrompt("keep")
        await model.useAsPrompt()?.value
        #expect(model.prompt == "keep"); #expect(model.edited == "Check if it works")
        #expect(model.message.contains("safe memory budget")); #expect(!model.isRewriting); model.close()
    }
    @Test func cancelledRewriteCannotOverwriteManualPromptOrStartSpeechDuringCleanup() async {
        let rewrite = RewriteFixture(), input = VoiceFixture(), key = ShortcutFixture()
        await rewrite.configure(hold:true,settlement:.httpCancelledProviderUncertain)
        let model = DictationModel(input:input,shortcut:key,destinations:DestinationFixture(),rewriter:rewrite)
        model.enableShortcut(); model.edit("Improve animations")
        let task = model.useAsPrompt(); await rewrite.waitForCall()
        #expect(model.useAsPrompt() == nil); key.receive?(.pressed); #expect(input.starts == 0)
        model.editPrompt("manual draft"); #expect(model.isRewriting); #expect(model.isCancellingRewrite)
        await rewrite.resolve(); await task?.value
        #expect(model.prompt == "manual draft"); #expect(model.localProviderUncertain)
        key.receive?(.pressed); #expect(input.starts == 0)
        await rewrite.configure(settlement:.completed); await model.checkRewriteProvider()?.value
        #expect(!model.localProviderUncertain); model.disableShortcut(); model.close()
    }
    @Test func rewriteServiceBindsInputModelDeadlineAndJSONSchema() async throws {
        let provider = RewriteProviderFixture(), clock = VoiceClock()
        let service = LocalPromptRewriter(provider:provider,clock:clock)
        let result = try await service.rewrite("Improve the animated UI button",modelName:"qwen2.5-coder:7b",requestID:"rewrite_1")
        #expect(result == "Review the button states and refine animation transitions.")
        let request = try #require(await provider.requests.first)
        #expect(request.syntheticUserContent == "Improve the animated UI button")
        #expect(request.deadline == 61000); #expect(request.systemInstruction.contains("check-only"))
        #expect(request.outputSchema.contains("string")); #expect(request.model.name == "qwen2.5-coder:7b")
        #expect(await service.settle() == .completed)
    }
    @Test(arguments:["{}","null","42",#""   ""#,String(repeating:"x",count:16385)])
    func rewriteServiceRejectsInvalidOutput(_ payload: String) async throws {
        let provider = RewriteProviderFixture(); await provider.configure(response:payload)
        let service = LocalPromptRewriter(provider:provider,clock:VoiceClock())
        await #expect(throws:InferenceFailure.invalidResponse) { try await service.rewrite("Check it",modelName:"qwen2.5-coder:7b",requestID:"bad_output") }
    }
    @Test func rewriteServiceRejectsForeignIdentityAndOversizeInput() async throws {
        let provider = RewriteProviderFixture(), service = LocalPromptRewriter(provider:provider,clock:VoiceClock())
        await provider.configure(invalidIdentity:true)
        await #expect(throws:InferenceFailure.invalidResponse) { try await service.rewrite("Check it",modelName:"qwen2.5-coder:7b",requestID:"expected_request") }
        await #expect(throws:InferenceFailure.invalidRequest) { try await service.rewrite(String(repeating:"x",count:1801),modelName:"qwen2.5-coder:7b",requestID:"oversize") }
        #expect(await provider.requests.count == 1)
    }
    @Test func staleRewriteCancellationCannotCancelAnotherRequest() async throws {
        let provider = RewriteProviderFixture(), service = LocalPromptRewriter(provider:provider,clock:VoiceClock())
        _ = try await service.rewrite("First",modelName:"qwen2.5-coder:7b",requestID:"old")
        await provider.configure(hold:true)
        let second = Task { try await service.rewrite("Second",modelName:"qwen2.5-coder:7b",requestID:"new") }
        await provider.waitForCall()
        #expect(await service.cancel(requestID:"old") == .notSent)
        #expect(await provider.cancelled.isEmpty)
        await provider.resolve(); _ = try await second.value
    }
}

@Suite("Live audio energy visualization") struct LiveAudioEnergyTests {
    @Test func silenceAndLevelsAreMonotonicAndBounded() {
        var silence = DictationAudioEnvelope(), quiet = DictationAudioEnvelope(), loud = DictationAudioEnvelope()
        for n:UInt32 in 1...30 {
            silence.update(.init(sequence:n,rms:0)); quiet.update(.init(sequence:n,rms:0.003)); loud.update(.init(sequence:n,rms:0.2))
        }
        #expect(silence.bars.allSatisfy { $0 == 0 })
        #expect(quiet.bars.last! > 0 && quiet.bars.last! < loud.bars.last!)
        #expect(loud.bars.allSatisfy { $0 >= 0 && $0 <= 1 })
        let high = loud.bars.last!
        for n:UInt32 in 31...100 { loud.update(.init(sequence:n,rms:0)) }
        #expect(high > 0.5 && loud.bars.allSatisfy { $0 == 0 })
        loud.reset(); #expect(loud.bars.allSatisfy { $0 == 0 })
    }
    @Test func staleInvalidAndNoiseNeverInventSpeech() {
        var envelope = DictationAudioEnvelope()
        envelope.update(.init(sequence:1,rms:0.8)); #expect(envelope.bars.last! > 0.5)
        for _ in 0..<100 { envelope.update(.init(sequence:1,rms:0.8)) }
        #expect(envelope.bars.allSatisfy { $0 == 0 })
        for n:UInt32 in 2...30 { envelope.update(.init(sequence:n,rms:.nan)) }
        #expect(envelope.bars.allSatisfy { $0 == 0 })
        for n:UInt32 in 31...60 { envelope.update(.init(sequence:n,rms:0.0001)) }
        #expect(envelope.bars.allSatisfy { $0 == 0 })
    }
    @Test func realPCMFeedsOneScalarMailboxWithoutAudioRetention() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate:48000,channels:1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)); buffer.frameLength = 1024
        let samples = try #require(buffer.floatChannelData)
        let meter = AudioLevelMailbox()
        for i in 0..<1024 { samples[0][i] = 0.02 }
        meter.append(buffer); #expect(abs(meter.snapshot().rms-0.02) < 0.0001)
        #expect(meter.snapshot().sequence == 1)
        for i in 0..<1024 { samples[0][i] = 0 }
        meter.append(buffer); #expect(meter.snapshot().rms == 0 && meter.snapshot().sequence == 2)
        #expect(AudioLevelMailbox().snapshot().rms == 0)
    }
}

extension LiveAudioEnergyTests {
    @Test func interleavedStereoUsesTheActualChannelStride() throws {
        let format = try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:2,interleaved:true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:128)); buffer.frameLength = 128
        let samples = try #require(buffer.floatChannelData)
        for i in 0..<128 { samples[0][2*i] = 0.25; samples[0][2*i+1] = -0.25 }
        let meter = AudioLevelMailbox(); meter.append(buffer)
        #expect(abs(meter.snapshot().rms-0.25) < 0.0001)
    }
}
