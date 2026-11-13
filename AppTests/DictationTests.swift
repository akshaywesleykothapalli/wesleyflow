import AppKit
import Domain
import Foundation
import AVFoundation
import CoreMedia
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
        model.start(); await model.waitUntilRecording()
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
        #expect(model.phase == .failed); #expect(model.edited == "early result")
        #expect(!model.busy); model.close()
    }
    @Test func synchronousStopCompletionRemainsTerminal() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input, clock: clock)
        input.finishDuringStop = true; model.start(); await model.waitUntilRecording()
        input.receive?(.transcript("complete")); model.stop()
        #expect(model.phase == .complete); #expect(model.edited == "complete")
        await clock.advance(100000)
        #expect(model.phase == .complete); model.close()
    }
    @Test func cancelDiscardsNewTextAndRejectsLateCallbacks() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock)
        model.edit("previous edit"); model.start(); await model.waitUntilRecording()
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
        model.start(); await model.waitUntilRecording(); input.receive?(.transcript("partial")); model.stop()
        await clock.waitForSleep(9000); await clock.advance(9000); await input.waitForCancel()
        #expect(model.phase == .failed); #expect(model.edited == "partial")
        input.receive?(.finished); #expect(model.phase == .failed); model.close()
    }
    @Test func recordingContinuesUntilExplicitRelease() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock)
        model.start(); await model.waitUntilRecording(); await clock.advance(301000)
        #expect(model.phase == .recording); #expect(input.stops == 0)
        model.stop(); #expect(input.stops == 1); model.cancel(); model.close()
    }
    @Test func oversizeTranscriptFailsWithoutAcceptingPayload() async {
        let input = VoiceFixture(), clock = VoiceClock(), model = DictationModel(input: input,clock: clock)
        model.start(); await model.waitUntilRecording(); input.receive?(.transcript(String(repeating: "x",count: DictationText.maximumBytes + 1)))
        #expect(model.phase == .failed); #expect(model.raw.isEmpty); model.close()
    }
    @Test func oversizedEditsDoNotReplacePriorDraft() {
        let model = DictationModel(input: VoiceFixture()); model.edit("retained"); model.editPrompt("draft")
        model.edit(String(repeating: "🙂",count: 17000)); model.editPrompt(String(repeating: "x",count: DictationText.maximumBytes + 1))
        #expect(model.edited == "retained"); #expect(model.prompt == "draft"); model.close()
    }
    @Test func segmentRevisionsDoNotDuplicate() throws {
        var buffer = TranscriptBuffer()
        #expect(try buffer.replace("hello",start: 0,end: 1) == "hello")
        #expect(try buffer.replace("hello world",start: 0,end: 2) == "hello world")
        #expect(try buffer.replace("again",start: 2,end: 3) == "hello world again")
        #expect(try buffer.replace("again!",start: 2,end: 3) == "hello world again!")
        #expect(throws: DictationFailure.recognitionFailed) { try buffer.replace("invalid",start: .nan,end: 4) }
        #expect(throws: DictationFailure.overflow) { try buffer.replace(String(repeating: "x",count: DictationText.maximumBytes + 1),start: 3,end: 4) }
    }
    @available(macOS 26.0, *)
    @Test func nativeAudioBridgeConvertsAndFinishesWithoutMicrophone() async throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1))
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16,sampleRate: 16000,channels: 1,interleaved: false))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: source,frameCapacity: 1024)); input.frameLength = 1024
        for i in 0..<1024 { input.floatChannelData![0][i] = 0 }
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        let bridge = try AudioIngress(source: source,target: target,modern: pair.continuation)
        bridge.append(input); bridge.close()
        var frames = 0
        for try await value in pair.stream { frames += Int(value.buffer.frameLength) }
        #expect(abs(Double(frames)-1024.0/3.0) <= 1)
        #expect(bridge.diagnostics.converterDrained && bridge.diagnostics.closeReason == "endOfInput")
    }
    @available(macOS 26.0, *)
    @Test func analyzerRejectsFloatPCMBeforeFrameworkPrecondition() throws {
        let float = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000,channels: 1))
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        #expect(throws: DictationFailure.audioUnavailable) { try AudioIngress(source: float,target: float,modern: pair.continuation) }
        pair.continuation.finish()
    }
    @available(macOS 26.0, *)
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

    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
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
        key.receive?(.pressed); await model.waitUntilRecording()
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
        key.receive?(.pressed); await model.waitUntilRecording()
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
        target.insertionFails = true; model.enableShortcut(); key.receive?(.pressed); await model.waitUntilRecording()
        input.receive?(.transcript("retained")); key.receive?(.released); input.receive?(.finished)
        #expect(target.inserted.isEmpty); #expect(model.edited == "retained")
        #expect(model.shortcutMessage.contains("field changed"))
        target.insertionFails = false; input.receive?(.finished); #expect(target.inserted.isEmpty)
        model.disableShortcut(); model.close()
    }
    @Test func monitorLossStopsDictationAndDisablesShortcut() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target)
        model.enableShortcut(); key.receive?(.pressed); await model.waitUntilRecording()
        key.receive?(.unavailable); input.receive?(.finished)
        #expect(!model.shortcutEnabled); #expect(!model.busy); #expect(target.inserted.isEmpty)
        model.close()
    }
    @Test func inAppMicrophoneNeverInsertsIntoOtherApps() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture(), clock = VoiceClock()
        let model = DictationModel(input: input,clock: clock,shortcut: key,destinations: target,rewriter: RewriteFixture())
        model.enableShortcut(); model.start(); await model.waitUntilRecording()
        input.receive?(.transcript("local")); model.stop(); input.receive?(.finished)
        #expect(target.captures == 0); #expect(target.inserted.isEmpty); #expect(model.edited == "local")
        await model.useAsPrompt()?.value; #expect(model.prompt == "AI rewrite: local")
        model.disableShortcut(); model.close()
    }
    @Test func earlyProviderEndNeverGrantsReleaseInsertion() async {
        let input = VoiceFixture(), key = ShortcutFixture(), target = DestinationFixture()
        let model = DictationModel(input: input,shortcut: key,destinations: target)
        input.finishDuringStart = true; model.enableShortcut(); key.receive?(.pressed); await input.waitForStart()
        #expect(model.phase == .failed); #expect(model.edited == "early result"); #expect(target.inserted.isEmpty)
        key.receive?(.released); #expect(target.inserted.isEmpty)
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
        model.enableShortcut(); key.receive?(.pressed); await model.waitUntilRecording()
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

@MainActor private extension DictationModel {
    func waitUntilRecording() async {
        await waitForCaptureStartup()
        #expect(phase == .recording)
    }
}

@Suite("Milestone38 long speech") struct LongSpeech38Tests {
    @Test(arguments: [15, 60, 180, 300])
    func orderedFinalPhrasesSurviveVolatileRevisions(_ seconds: Int) throws {
        var buffer = TranscriptBuffer(), expected: [String] = []
        // One phrase/second exceeds the former 256-segment cap at five minutes.
        for index in 0..<seconds {
            let start = Double(index), end = start + 0.8
            let phrase = index % 2 == 0 ? "తెలుగు \(index)" : "English \(index)"
            _ = try buffer.replace("tentative",start:start,end:end)
            expected.append(phrase)
            let snapshot = try buffer.replace(phrase,start:start,end:end,isFinal:true)
            #expect(snapshot == expected.joined(separator:" "))
            #expect(try buffer.replace("stale",start:start,end:end) == snapshot)
        }
        #expect(try buffer.replace("last words",start:Double(seconds),end:Double(seconds)+1,isFinal:true) == (expected + ["last words"]).joined(separator:" "))
    }
    @Test func finalBoundaryCannotBeReplacedByLatestPartial() throws {
        var buffer = TranscriptBuffer()
        _ = try buffer.replace("first full sentence",start:0,end:10,isFinal:true)
        #expect(throws: DictationFailure.recognitionFailed) { try buffer.replace("last words",start:0,end:11) }
        #expect(try buffer.replace("second sentence",start:10,end:20,isFinal:true) == "first full sentence second sentence")
        #expect(throws: DictationFailure.overflow) { try buffer.replace(String(repeating:"x",count:DictationText.maximumBytes),start:20,end:21,isFinal:true) }
        #expect(try buffer.replace("third",start:20,end:21,isFinal:true) == "first full sentence second sentence third")
    }
    @Test func cumulativeVolatileRangeCommitsOnce() throws {
        var buffer = TranscriptBuffer()
        _ = try buffer.replace("one",start:0,end:1)
        _ = try buffer.replace("two",start:1,end:2)
        #expect(try buffer.replace("one two",start:0,end:2,isFinal:true) == "one two")
        #expect(try buffer.replace("one two",start:0,end:2,isFinal:true) == "one two")
        #expect(try buffer.replace("three",start:2,end:3) == "one two three")
    }
    @available(macOS 26.0, *)
    @Test(arguments: [15, 60, 180, 300])
    func syntheticPCMStreamsWithBoundedConsumerWithoutMicrophone(_ seconds: Int) async throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate:16000,channels:1))
        let target = try #require(AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat:source,frameCapacity:1600)); pcm.frameLength = 1600
        let pair = AsyncThrowingStream<AnalyzerInput,any Error>.makeStream(bufferingPolicy:.bufferingOldest(32))
        let ingress = try AudioIngress(source:source,target:target,modern:pair.continuation)
        var iterator = pair.stream.makeAsyncIterator()
        for tick in 0..<(seconds*10) {
            // Silence, soft and loud PCM; simulated sample duration, no recognition claim.
            for n in 0..<1600 { pcm.floatChannelData![0][n] = tick % 30 < 10 ? 0 : tick % 30 < 20 ? 0.003 : 0.2 }
            ingress.append(pcm)
            #expect(try await iterator.next() != nil)
        }
        ingress.close(); #expect(try await iterator.next() == nil)
    }
}

extension LongSpeech38Tests {
    @Test func legacyPassageAfterSilenceRetainsEarlierSpeechAndDefersUnverifiedReset() throws {
        var buffer = LegacyTranscriptBuffer()
        #expect(try buffer.replace("first sentence",start:0,end:10) == "first sentence")
        #expect(try buffer.replace("last",start:12,end:13) == "first sentence last")
        #expect(try buffer.replace("last words",start:12,end:14) == "first sentence last words")
        #expect(try buffer.replace("reset",start:0,end:1) == "first sentence last words")
        #expect(buffer.boundaryPending && buffer.unmergedText == "reset")
        #expect(try buffer.replace("reset complete",start:0,end:3) == "first sentence last words")
        #expect(throws:DictationFailure.recognitionFailed) { try buffer.replace("reset complete",start:0,end:3,isFinal:true) }
    }
    @Test func legacyCumulativeRevisionsAreNotAppendedTwice() throws {
        var buffer = LegacyTranscriptBuffer()
        _ = try buffer.replace("first",start:0,end:1)
        #expect(try buffer.replace("first second",start:0,end:2) == "first second")
        #expect(try buffer.replace("first second",start:0,end:2) == "first second")
    }
}

extension LongSpeech38Tests {
    @Test func narrowOverlappingPassageCannotEraseEarlierPrefix() throws {
        var buffer = TranscriptBuffer()
        _ = try buffer.replace("all the earlier words",start:0,end:10)
        #expect(throws:DictationFailure.recognitionFailed) { try buffer.replace("last words",start:9,end:11) }
        #expect(try buffer.replace("next",start:10,end:11) == "all the earlier words next")
    }
}

// No Apple asset requests, model loads or microphone access in these fixtures.
@MainActor func speechResources38L2(_ speechStatus: String = "supported", dictationStatus: String = "supported", speechInstalled: Bool = false, dictationInstalled: Bool = false, supported: Bool = true, available: Bool = true, legacy: Bool = true) -> AppleSpeechConfiguration {
    let locale = supported ? "en_US" : nil
    return .init(locale:"en-US",
                 speech:.init(engine:.speechTranscriber,deviceAvailable:available,resolvedLocale:locale,supportedLocales:supported ? ["en-US"] : [],installedLocales:speechInstalled ? ["en_US"] : [],inventoryStatus:speechStatus),
                 dictation:.init(engine:.dictationTranscriber,deviceAvailable:true,resolvedLocale:locale,supportedLocales:supported ? ["en-US"] : [],installedLocales:dictationInstalled ? ["en-US"] : [],inventoryStatus:dictationStatus),
                 legacyOnDeviceAvailable:legacy,microphone:"Not requested",speechPermission:"Not requested")
}
@MainActor final class SpeechInstallFixture38L2: SpeechResourceInstallation {
    var progress = SpeechDownloadProgress(completedUnits:3,totalUnits:8)
    var calls = 0, held = false
    var failure: (any Error)?
    var finish: (() -> Void)?
    var entered: CheckedContinuation<Void,Never>?
    var pending: CheckedContinuation<Void,Never>?
    func downloadAndInstall() async throws {
        calls += 1
        if held { await withCheckedContinuation { pending = $0; entered?.resume(); entered = nil } }
        try Task.checkCancellation()
        if let failure { throw failure }
        progress = .init(completedUnits:8,totalUnits:8); finish?()
    }
    func waitForStart() async { if pending != nil || calls > 0 { return }; await withCheckedContinuation { entered = $0 } }
    func release() { pending?.resume(); pending = nil }
}
@MainActor final class SpeechBackendFixture38L2: SpeechResourceBackend {
    var configuration = speechResources38L2()
    let request = SpeechInstallFixture38L2()
    var inspectCalls = 0, installationCalls = 0, preparationCalls = 0
    var nilRequest = false, completeInstallation = true, removeDuringPreparation = false, wrongPreparation = false
    var installationFailure: (any Error)?, preparationFailure: (any Error)?
    var requestedEngines: [ModernSpeechEngine] = [], requestedLocales: [String] = []
    func inspect(localeIdentifier: String) async -> AppleSpeechConfiguration { inspectCalls += 1; return configuration }
    func installation(engine: ModernSpeechEngine, locale: String) async throws -> (any SpeechResourceInstallation)? {
        installationCalls += 1; requestedEngines.append(engine); requestedLocales.append(locale)
        if let installationFailure { throw installationFailure }
        if nilRequest { return nil }
        request.finish = { [weak self] in
            guard let self, self.completeInstallation else { return }
            self.configuration = speechResources38L2("installed",dictationStatus:"installed",speechInstalled:true,dictationInstalled:true)
        }
        return request
    }
    func prepare(engine: ModernSpeechEngine, requestedLocale: String, resolvedLocale: String) async throws -> SpeechEnginePreparation {
        preparationCalls += 1
        if let preparationFailure { throw preparationFailure }
        if removeDuringPreparation { configuration = speechResources38L2() }
        return .init(engine:engine,requestedLocale:requestedLocale,resolvedLocale:wrongPreparation ? "fr-FR" : resolvedLocale,sampleRate:16000,channels:1)
    }
}
@Suite("38L2 speech resource readiness",.serialized) @MainActor struct SpeechResources38L2Tests {
    @Test(arguments:["supported","downloading","installed","unsupported"])
    func statusRequiresBothInventoryAndInstalledLocale(_ status:String) {
        let missing = speechResources38L2(status)
        let expected:SpeechAssetState = status == "supported" ? .missing : status == "downloading" ? .downloading : status == "installed" ? .unconfirmed : .unsupported
        #expect(missing.speech.state == expected)
        #expect(missing.readyModernEngine == nil)
        if status == "installed" {
            #expect(speechResources38L2(status,speechInstalled:true).readyModernEngine == .speechTranscriber)
        }
    }
    @Test func unsupportedLocaleAndUnavailableDeviceNeverBecomeMissingDownloads() {
        let language = speechResources38L2(supported:false), device = speechResources38L2(available:false)
        #expect(language.speech.state == .unsupported && language.installCandidate == nil)
        #expect(device.speech.state == .deviceUnavailable && device.installCandidate == .dictationTranscriber)
        #expect(SpeechEngineResources.sameLocale("en_US","en-US"))
        #expect(!SpeechEngineResources.sameLocale("en-US","en-IN"))
    }
    @Test func preferenceAndCompatibilityFallbackAreExplicit() {
        #expect(speechResources38L2("installed",dictationStatus:"installed",speechInstalled:true,dictationInstalled:true).readyModernEngine == .speechTranscriber)
        #expect(speechResources38L2(dictationStatus:"installed",dictationInstalled:true).readyModernEngine == .dictationTranscriber)
        #expect(speechResources38L2().recommendedEngineLabel.contains("one-minute"))
        #expect(speechResources38L2(legacy:false).recommendedEngineLabel == "No on-device speech engine ready")
    }
    @Test func inspectionNeverInstallsOrPrepares() async {
        let backend = SpeechBackendFixture38L2()
        let subject = AppleSpeechResourceService(backend:backend)
        _ = await subject.inspect(localeIdentifier:"en-US")
        #expect(backend.inspectCalls == 1 && backend.installationCalls == 0 && backend.preparationCalls == 0 && backend.request.calls == 0)
    }
    @Test func explicitInstallReportsProviderProgressAndThenPrepares() async throws {
        let backend = SpeechBackendFixture38L2()
        let subject = AppleSpeechResourceService(backend:backend)
        var samples: [SpeechDownloadProgress] = []
        let result = try await subject.install(localeIdentifier:"en-US",engine:.speechTranscriber) { samples.append($0) }
        #expect(result.speech.state == .installed && result.locale == "en-US")
        #expect(backend.installationCalls == 1 && backend.request.calls == 1 && backend.preparationCalls == 0)
        #expect(samples.first?.fraction == 0.375 && samples.last?.fraction == 1)
        #expect(backend.requestedLocales == ["en_US"])
        let prepared = try await subject.prepare(localeIdentifier:"en-US",engine:.speechTranscriber)
        #expect(prepared.requestedLocale == "en-US" && prepared.resolvedLocale == "en_US" && backend.preparationCalls == 1)
    }
    @Test(arguments:["unsupported","nil-request","download-error","incomplete"])
    func failedInstallationCannotAdvertiseReadiness(_ scenario:String) async {
        let backend = SpeechBackendFixture38L2()
        if scenario == "unsupported" { backend.configuration = speechResources38L2(supported:false) }
        if scenario == "nil-request" { backend.nilRequest = true }
        if scenario == "download-error" { backend.request.failure = NSError(domain:"NSURLErrorDomain",code:-1009) }
        if scenario == "incomplete" { backend.completeInstallation = false }
        let subject = AppleSpeechResourceService(backend:backend)
        await #expect(throws:(any Error).self) { _ = try await subject.install(localeIdentifier:"en-US",engine:.speechTranscriber) { _ in } }
        #expect(backend.preparationCalls == 0 && backend.configuration.readyModernEngine == nil)
        if scenario == "unsupported" { #expect(backend.installationCalls == 0) }
    }
    @Test func alreadyInstalledNeverCreatesDownloadRequest() async throws {
        let backend = SpeechBackendFixture38L2(); backend.configuration = speechResources38L2("installed",speechInstalled:true)
        _ = try await AppleSpeechResourceService(backend:backend).install(localeIdentifier:"en-US",engine:.speechTranscriber) { _ in Issue.record("Installed assets should not download") }
        #expect(backend.installationCalls == 0 && backend.request.calls == 0)
    }
    @Test(arguments:["missing","provider-error","removed","wrong-locale"])
    func preparationFailuresNeverClaimReady(_ scenario:String) async {
        let backend = SpeechBackendFixture38L2(); backend.configuration = speechResources38L2("installed",speechInstalled:true)
        if scenario == "missing" { backend.configuration = speechResources38L2() }
        if scenario == "provider-error" { backend.preparationFailure = DictationFailure.assetsMissing }
        backend.removeDuringPreparation = scenario == "removed"; backend.wrongPreparation = scenario == "wrong-locale"
        await #expect(throws:(any Error).self) { _ = try await AppleSpeechResourceService(backend:backend).prepare(localeIdentifier:"en-US",engine:.speechTranscriber) }
        #expect(backend.installationCalls == 0)
    }
    @Test func cancelledInstallationCannotPrepareOrOverrideNewState() async {
        let backend = SpeechBackendFixture38L2(); backend.request.held = true
        let subject = AppleSpeechResourceService(backend:backend)
        let task = Task { try await subject.install(localeIdentifier:"en-US",engine:.speechTranscriber) { _ in } }
        await backend.request.waitForStart(); task.cancel(); backend.request.release()
        await #expect(throws:CancellationError.self) { _ = try await task.value }
        #expect(backend.configuration.readyModernEngine == nil && backend.preparationCalls == 0)
    }
    @Test func unknownSizeDoesNotInventDownloadPercentage() {
        #expect(SpeechDownloadProgress(completedUnits:4,totalUnits:0).fraction == nil)
        #expect(SpeechDownloadProgress(completedUnits:200,totalUnits:100).fraction == 1)
    }
}

extension SpeechResources38L2Tests {
    @Test func installedLocaleAloneDoesNotProveModuleReadiness() {
        let resources = speechResources38L2("supported",speechInstalled:true)
        #expect(resources.speech.state == .missing && resources.readyModernEngine == nil)
        #expect(resources.speech.summary.contains("Locale present; required module resources not ready"))
        #expect(resources.installCandidate == .speechTranscriber)
    }
}

@Suite("38L3 speech failure diagnostics",.serialized) @MainActor struct SpeechFailure38L3Tests {
    @Test(arguments:[("kLSRErrorDomain",102,"Speech assets missing"),("kAFAssistantErrorDomain",203,"Recognition failed"),("kAFAssistantErrorDomain",1100,"Speech already active"),("kAFAssistantErrorDomain",1101,"Speech service reset"),("kAFAssistantErrorDomain",1107,"Speech interrupted"),("kAFAssistantErrorDomain",1110,"No speech recognized"),("kAFAssistantErrorDomain",1700,"Speech access denied"),("kLSRErrorDomain",301,"Speech request cancelled")])
    func legacyCodesRetainTheirProviderSpecificMeaning(_ row:(String,Int,String)) {
        var value = DictationSpeechDiagnostics(); value.provider = .legacyOnDevice; value.stage = .legacyRecognition
        value.nativeError = .init(primary:.init(domain:row.0,code:row.1))
        #expect(value.compactFailure == row.2)
        value.provider = .speechTranscriber
        #expect(value.compactFailure == "Speech error \(row.1)")
        #expect(!value.compactFailure.contains("timed out"))
    }
    @Test func metadataNeverIncludesDescriptionsOrPrivateUserInfo() throws {
        let secret = "SYNTHETIC_PRIVATE_TRANSCRIPT_AND_CLIPBOARD"
        let underlying = NSError(domain:"kLSRErrorDomain",code:102,userInfo:[NSLocalizedDescriptionKey:secret,"transcript":secret])
        let error = NSError(domain:"kAFAssistantErrorDomain",code:203,userInfo:[NSUnderlyingErrorKey:underlying,NSLocalizedDescriptionKey:secret,"audio":Data(secret.utf8)])
        let metadata = try #require(NativeSpeechCallbacks.errorMetadata(error))
        #expect(metadata.primary == .init(domain:"kAFAssistantErrorDomain",code:203))
        #expect(metadata.underlying == [.init(domain:"kLSRErrorDomain",code:102)])
        var value = DictationSpeechDiagnostics(); value.nativeError = metadata; value.provider = .legacyOnDevice
        #expect(value.compactFailure == "Speech assets missing")
        #expect(!value.summary.contains(secret))
        #expect(!String(decoding:try JSONEncoder().encode(value),as:UTF8.self).contains(secret))
    }
    @Test func underlyingErrorChainIsBounded() throws {
        var error = NSError(domain:"NSOSStatusErrorDomain",code:-50)
        for n in 0..<10 { error = NSError(domain:"NSCocoaErrorDomain",code:n,userInfo:[NSUnderlyingErrorKey:error]) }
        #expect(NativeSpeechCallbacks.errorMetadata(error)?.underlying.count == 4)
        #expect(SpeechErrorCode(domain:"untrusted private sentence",code:1).domain == "InvalidErrorDomain")
    }
    @Test func callbackPreservesNativeErrorAcrossActorHop() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void,Never>) in
            let callback = NativeSpeechCallbacks.recognitionPassages { observation in
                let text = observation.text, start = observation.start, end = observation.end, final = observation.isFinal, failure = observation.failure, observedAt = observation.observedAt
                MainActor.assertIsolated()
                #expect(text == nil && start == nil && end == nil && !final && observedAt.isFinite)
                #expect(failure?.primary == .init(domain:"kAFAssistantErrorDomain",code:1107))
                done.resume()
            }
            DispatchQueue.global().async { callback(nil,NSError(domain:"kAFAssistantErrorDomain",code:1107)) }
        }
    }
    @Test func sourceStagesDistinguishPreparationAudioMergeAndTimeout() {
        var value = DictationSpeechDiagnostics(); value.provider = .speechTranscriber
        value.stage = .modernPreparation; #expect(value.compactFailure == "Speech preparation failed")
        value.stage = .audioConfiguration; #expect(value.compactFailure == "Microphone interrupted")
        value.stage = .transcriptMerge; value.mergeRejection = "finalizedPrefixOverlap"; #expect(value.compactFailure == "Final speech conflict")
        value.mergeRejection = "none"; value.stage = .finalizationWatchdog; #expect(value.compactFailure == "Finalization timed out")
    }
    @Test func pureAdmissionPermitsOnlyOneDeterministicOwner() {
        let copies = [DictationInstance(processID:42,launchedAt:10),.init(processID:43,launchedAt:11)]
        #expect(DictationInstanceAdmission.permits(processID:42,instances:copies))
        #expect(!DictationInstanceAdmission.permits(processID:43,instances:copies))
        #expect(!DictationInstanceAdmission.permits(processID:99,instances:copies))
        #expect(!DictationInstanceAdmission.permits(processID:42,instances:[]))
        #expect(!DictationInstanceAdmission.permits(processID:42,instances:[.init(processID:42,launchedAt:.nan)]))
    }
    @Test func secondaryNativeInputFailsBeforeMicrophoneOrPermissions() async {
        let input = AppleDictationInput(exclusiveCapture:{ throw DictationFailure.anotherInstance })
        await #expect(throws:DictationFailure.anotherInstance) { _ = try await input.start(localeIdentifier:"en-IN") { _ in Issue.record("Admission failure must not start a speech callback") } }
        #expect(input.speechDiagnostics?.stage == .admission && input.speechDiagnostics?.failure == "anotherInstance")
        #expect(input.speechDiagnostics?.captureMilliseconds == 0 && input.speechDiagnostics?.captureActiveAtSnapshot == false)
    }
    @Test func rangeFailuresRetainOldTextAndExplainTheRejection() throws {
        var buffer = TranscriptBuffer()
        _ = try buffer.replace("all earlier speech",start:0,end:20,isFinal:true)
        #expect(buffer.preservedSegmentCount == 1)
        #expect(throws:DictationFailure.recognitionFailed) { try buffer.replace("last words",start:0,end:21) }
        #expect(buffer.lastRejection == "finalizedPrefixOverlap")
        #expect(try buffer.replace("next",start:20,end:21,isFinal:true) == "all earlier speech next")
        #expect(buffer.preservedSegmentCount == 2)
    }
    @available(macOS 26.0, *)
    @Test func deliveredAudioCountsAndSampleGapsAreObservedWithoutText() async throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate:16000,channels:1))
        let target = try #require(AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat:source,frameCapacity:64)); pcm.frameLength = 64
        for n in 0..<64 { pcm.floatChannelData![0][n] = 0 }
        let pair = AsyncThrowingStream<AnalyzerInput,any Error>.makeStream(bufferingPolicy:.bufferingOldest(32))
        let ingress = try AudioIngress(source:source,target:target,modern:pair.continuation)
        for sample: Int64 in [0,64,200] { ingress.append(pcm,at:AVAudioTime(sampleTime:sample,atRate:16000)) }
        ingress.close()
        var frames: UInt64 = 0; for try await value in pair.stream { frames += UInt64(value.buffer.frameLength) }
        #expect(frames == 192 && ingress.diagnostics.receivedFrames == 192)
        #expect(ingress.diagnostics.timestampedBuffers == 3 && ingress.diagnostics.discontinuities == 1 && ingress.diagnostics.maximumGapFrames == 72)
        #expect(ingress.diagnostics.converterDrained && ingress.diagnostics.closeReason == "endOfInput")
    }
    @available(macOS 26.0, *)
    @Test func releaseDrainsResamplerTailBeforeEndingSequence() async throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate:48000,channels:1))
        let target = try #require(AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat:source,frameCapacity:4800)); pcm.frameLength = 4800
        for n in 0..<4800 { pcm.floatChannelData![0][n] = 0.02 }
        let pair = AsyncThrowingStream<AnalyzerInput,any Error>.makeStream(bufferingPolicy:.bufferingOldest(32))
        let ingress = try AudioIngress(source:source,target:target,modern:pair.continuation)
        var iterator = pair.stream.makeAsyncIterator(), frames = 0
        for _ in 0..<10 { ingress.append(pcm); frames += Int(try #require(await iterator.next()).buffer.frameLength) }
        ingress.close()
        while let next = try await iterator.next() { frames += Int(next.buffer.frameLength) }
        #expect(abs(frames-16000) <= 1)
        #expect(ingress.diagnostics.converterDrained && ingress.diagnostics.receivedFrames == 48000)
    }
}

extension SpeechFailure38L3Tests {
    @Test func providerFinalBeforeReleaseCannotBecomeSuccessAfterActorDelay() {
        #expect(!DictationReleaseBoundary.acceptsFinal(observedAt:30,releaseAt:45))
        #expect(!DictationReleaseBoundary.acceptsFinal(observedAt:30,releaseAt:nil))
        #expect(DictationReleaseBoundary.acceptsFinal(observedAt:45.01,releaseAt:45))
        #expect(!DictationReleaseBoundary.acceptsFinal(observedAt:45.01,releaseAt:45,audioClosedCleanly:false))
        #expect(!DictationReleaseBoundary.acceptsFinal(observedAt:.nan,releaseAt:45))
    }
}


@Suite("38L3 legacy passage boundaries") struct LegacyPassage38L3Tests {
    @Test func confirmedMetadataBoundaryPreservesEarlierWordsAndRepetitions() throws {
        var b = LegacyTranscriptBuffer()
        _ = try b.replace("hello hello తెలుగు",start:0,end:29,metadataStart:0,metadataDuration:29)
        #expect(try b.replace("again",start:0,end:1,metadataStart:30,metadataDuration:1) == "hello hello తెలుగు again")
        #expect(try b.replace("again again",start:0,end:2,metadataStart:30,metadataDuration:2) == "hello hello తెలుగు again again")
        #expect(try b.replace("again again",start:0,end:2,metadataStart:30,metadataDuration:2,isFinal:true) == "hello hello తెలుగు again again")
        #expect(!b.boundaryPending && b.unmergedText == nil)
    }
    @Test func thirtySecondResetDoesNotTerminateHeldCapture() throws {
        var b = LegacyTranscriptBuffer()
        _ = try b.replace("earlier speech",start:0,end:29)
        for second in 1...40 {
            #expect(try b.replace("pending \(second)",start:0,end:Double(second)) == "earlier speech")
        }
        #expect(b.boundaryPending && b.unmergedText == "pending 40")
        #expect(throws:DictationFailure.recognitionFailed) { try b.replace("pending 40",start:0,end:40,isFinal:true) }
        #expect(b.unmergedText == "pending 40")
    }
    @Test func pendingBoundaryCanBeResolvedByLaterPublicMetadata() throws {
        var b = LegacyTranscriptBuffer()
        _ = try b.replace("first",start:0,end:29,metadataStart:0,metadataDuration:29)
        #expect(try b.replace("second",start:0,end:1) == "first")
        #expect(try b.replace("second complete",start:0,end:3,metadataStart:31,metadataDuration:3) == "first second complete")
        #expect(!b.boundaryPending && b.unmergedText == nil)
    }
    @Test func overlappingAnchorNeverAuthorizesAutomaticAppend() throws {
        var b = LegacyTranscriptBuffer()
        _ = try b.replace("earlier",start:0,end:29,metadataStart:0,metadataDuration:29)
        #expect(try b.replace("ambiguous",start:0,end:1,metadataStart:10,metadataDuration:1) == "earlier")
        #expect(throws:DictationFailure.recognitionFailed) { try b.replace("ambiguous",start:0,end:1,metadataStart:30,metadataDuration:1,isFinal:true) }
        #expect(b.unmergedText == "ambiguous")
    }
    @Test(arguments:[60,180,300]) func metadataPassagesWithPausesHaveNoMissingOrDuplicateSegments(seconds:Int) throws {
        var b = LegacyTranscriptBuffer(), expected = ""
        for tick in stride(from:0,to:seconds,by:10) {
            let phrase = "phrase\(tick) తెలుగు hello hello"
            expected += expected.isEmpty ? phrase : " " + phrase
            _ = try b.replace("phrase\(tick)",start:0,end:1,metadataStart:Double(tick),metadataDuration:1)
            #expect(try b.replace(phrase,start:0,end:4,metadataStart:Double(tick),metadataDuration:4,isFinal:tick+10>=seconds) == expected)
        }
        #expect(!b.boundaryPending && b.unmergedText == nil)
    }
    @Test func staleCallbacksHaveNoAuthorityToOverwriteText() {
        var b = LegacyTranscriptBuffer()
        let first = b.acceptResult(sequence:1), next = b.acceptResult(sequence:3)
        let stale = b.acceptResult(sequence:2), duplicate = b.acceptResult(sequence:3)
        #expect(first && next && !stale && !duplicate)
    }
    @Test func multipleUnverifiedPassagesRemainAvailableForManualRecovery() throws {
        var b = LegacyTranscriptBuffer()
        _ = try b.replace("first",start:0,end:29)
        _ = try b.replace("second",start:0,end:10)
        #expect(try b.replace("third",start:0,end:1) == "first")
        #expect(b.unmergedText == "second\n\nthird")
    }
    @Test func pendingRecoveryIsBoundedAndNeverReplacesAcceptedText() throws {
        var b = LegacyTranscriptBuffer()
        _ = try b.replace("first",start:0,end:29)
        _ = try b.replace("second",start:0,end:1)
        #expect(throws:DictationFailure.overflow) { try b.replace(String(repeating:"a",count:DictationText.maximumBytes+1),start:0,end:2) }
        #expect(b.unmergedText == "second")
    }
}


extension SpeechFailure38L3Tests {
    @Test func nativeLegacyDeliveryPreservesFIFOAcrossActorHop() async {
        var observed: [UInt64] = []
        await withCheckedContinuation { (done: CheckedContinuation<Void,Never>) in
            let delivery = NativeLegacyDelivery { item in
                observed.append(item.sequence)
                if item.sequence == 20 { done.resume() }
            }
            DispatchQueue.global().async {
                for n in 1...20 { delivery.enqueue(.init(text:"fixture",start:0,end:1,isFinal:n==20,failure:nil,observedAt:Double(n),metadataStart:nil,metadataDuration:nil,sequence:UInt64(n))) }
            }
        }
        #expect(observed == Array(1...20).map(UInt64.init))
    }
    @Test func nativeLegacyDeliveryOverflowReportsFailureInsteadOfCompletingFragment() async {
        var count = 0
        await withCheckedContinuation { (done: CheckedContinuation<Void,Never>) in
            let delivery = NativeLegacyDelivery { item in
                count += 1
                if let failure = item.failure {
                    #expect(failure.primary.domain == "WesleyFlowSpeechDeliveryError")
                    #expect(!item.isFinal); done.resume()
                }
            }
            // Keep this actor occupied until all callbacks have queued.
            for n in 1...100 { delivery.enqueue(.init(text:"fixture",start:0,end:1,isFinal:false,failure:nil,observedAt:Double(n),metadataStart:nil,metadataDuration:nil,sequence:UInt64(n))) }
        }
        #expect(count == 32)
    }
}

@Suite("38L3R2 provider range reconciliation") struct SpeechRange38L3R2Tests {
    func time(_ seconds:Double)->CMTime { CMTime(seconds:seconds,preferredTimescale:48000) }
    func range(_ start:Double,_ end:Double)->CMTimeRange { CMTimeRange(start:time(start),end:time(end)) }
    @available(macOS 26.0, *)
    func timed(_ words:[(String,Double,Double)])->AttributedString {
        var result=AttributedString()
        for (text,start,end) in words { var word=AttributedString(text);word.audioTimeRange=range(start,end);result.append(word) }
        return result
    }
    @available(macOS 26.0, *)
    @Test func overlappingModernRevisionPreservesUnaffectedBeginningAndEnd() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("first ",0,2),("middle ",2,4),("end",4,6)]),range:range(0,6),isFinal:false)
        #expect(try b.replace(timed([("revised",2,4)]),range:range(2,4),isFinal:false)=="first revised end")
        #expect(b.lastDecision=="revisedVolatile")
        #expect(try b.finishAfterAnalyzerFinalization()=="first revised end")
        #expect(b.finalizedSegmentCount==3)
    }
    @available(macOS 26.0, *)
    @Test func revisedFullPhraseMayMoveBothTimeBoundaries() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("tentative phrase",0,6)]),range:range(0,6),isFinal:false)
        #expect(try b.replace(timed([("correct phrase",0.1,5.9)]),range:range(0.1,5.9),isFinal:true)=="correct phrase")
        #expect(try b.replace(timed([("correct phrase",0.1,5.9)]),range:range(0.1,5.9),isFinal:true)=="correct phrase")
    }
    @available(macOS 26.0, *)
    @Test func emptyModernRevisionRevokesOnlyItsAudioRange() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("first ",0,2),("revoked ",2,4),("end",4,6)]),range:range(0,6),isFinal:false)
        #expect(try b.replace(AttributedString(),range:range(2,4),isFinal:false)=="first end")
    }
    @available(macOS 26.0, *)
    @Test func finalizationMetadataCommitsUnchangedEarlierVolatileSpeech() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("first",0,2)]),range:range(0,2),isFinal:false,finalization:time(0))
        #expect(try b.replace(timed([("second",2,4)]),range:range(2,4),isFinal:false,finalization:time(2))=="first second")
        #expect(b.finalizedSegmentCount==1)
        #expect(try b.finishAfterAnalyzerFinalization()=="first second")
        #expect(b.finalizedSegmentCount==2)
    }
    @available(macOS 26.0, *)
    @Test func genuinelyConflictingFinalCannotRewriteCommittedSpeech() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("first",0,2)]),range:range(0,2),isFinal:true)
        #expect(throws:DictationFailure.recognitionFailed) { try b.replace(timed([("different",0,2)]),range:range(0,2),isFinal:true) }
        #expect(b.lastRejection=="conflictingFinalizedRange" && b.snapshot=="first")
        #expect(try b.replace(timed([("stale",0,1)]),range:range(0,1),isFinal:false)=="first")
    }
    @Test func invalidTimebasesAreRejectedTransactionally() throws {
        let invalid:[CMTimeRange]=[.invalid,CMTimeRange(start:.indefinite,duration:time(1)),CMTimeRange(start:CMTime(value:1,timescale:1,flags:.valid,epoch:1),duration:time(1)),CMTimeRange(start:time(0),duration:time(-1))]
        for value in invalid {
            var b=TranscriptBuffer();_ = try b.replace("earlier",start:0,end:1)
            #expect(throws:DictationFailure.recognitionFailed) { try b.replace(AttributedString("candidate"),range:value,isFinal:false) }
            #expect(b.lastRejection=="invalidCMTime" && b.snapshot=="earlier")
        }
    }
    @Test func sampleExactBoundaryNeedsNoArbitraryTolerance() throws {
        var b=TranscriptBuffer()
        let first=CMTimeRange(start:.zero,duration:CMTime(value:1,timescale:48000))
        let second=CMTimeRange(start:CMTime(value:2,timescale:96000),duration:CMTime(value:1,timescale:48000))
        _ = try b.replace(AttributedString("first"),range:first,isFinal:true)
        #expect(try b.replace(AttributedString("second"),range:second,isFinal:true)=="first second")
    }
    @Test func legacyRevisedHypothesisDoesNotAppendItsEarlierWordsTwice() throws {
        var b=LegacyTranscriptBuffer()
        _ = try b.replace("earlier tentative",start:0,end:10,metadataStart:0,metadataDuration:10)
        #expect(try b.replace("earlier corrected",start:0.1,end:10,metadataStart:0,metadataDuration:10)=="earlier corrected")
        #expect(try b.replace("earlier final",start:0.2,end:9.5,metadataStart:0,metadataDuration:9.5,isFinal:true)=="earlier final")
        #expect(!b.boundaryPending)
    }
    @available(macOS 26.0, *)
    @Test(arguments:[10,20,45]) func modernRecordingRevisionsPreserveWholeTranscript(seconds:Int) throws {
        var b=TranscriptBuffer(),expected:[String]=[]
        for second in 0..<seconds {
            let start=Double(second),end=start+1,phrase="word\(second) తెలుగు"
            _ = try b.replace(timed([("tentative",start,end)]),range:range(start,end),isFinal:false)
            expected.append(phrase)
            #expect(try b.replace(timed([(phrase,start+0.01,end-0.01)]),range:range(start+0.01,end-0.01),isFinal:true)==expected.joined(separator:" "))
        }
        #expect(b.finalizedSegmentCount==seconds)
    }
    @Test func preciseFailureLabelsDoNotConfuseRangeAndNativeErrors() {
        var d=DictationSpeechDiagnostics();d.provider = .speechTranscriber;d.mergeRejection="invalidCMTime"
        #expect(d.compactFailure=="Invalid speech timing")
        d.mergeRejection="unverifiedLegacyPassageBoundary";#expect(d.compactFailure=="Speech boundary unclear")
        d.mergeRejection="conflictingFinalizedRange";#expect(d.compactFailure=="Final speech conflict")
    }
}


extension SpeechRange38L3R2Tests {
    @available(macOS 26.0, *)
    @Test func overlapInSilenceInsertsBetweenTimedWords() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("first ",0,1),("end",4,6)]),range:range(0,6),isFinal:false)
        #expect(try b.replace(timed([("middle",2,3)]),range:range(2,3),isFinal:false)=="first middle end")
    }
    @available(macOS 26.0, *)
    @Test func finalizationMaySplitPriorVolatilePhraseAtVerifiedWordBoundary() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("first ",0,2),("middle ",2,4),("end",4,6)]),range:range(0,6),isFinal:false)
        #expect(try b.replace(timed([("next",6,7)]),range:range(6,7),isFinal:false,finalization:time(2))=="first middle end next")
        #expect(b.finalizedSegmentCount==1)
        #expect(try b.replace(timed([("next",6,7)]),range:range(6,7),isFinal:true)=="first middle end next")
    }
    @Test func zeroLengthVolatileHypothesisIsNotPrematurelyCommitted() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(AttributedString("tentative"),range:range(0,0),isFinal:false)
        #expect(b.finalizedSegmentCount==0)
        #expect(try b.replace(AttributedString("correct"),range:range(0,1),isFinal:true)=="correct")
    }
    @available(macOS 26.0, *)
    @Test func partialFinalizationInsideUntimedWordFailsWithoutLosingEarlierText() throws {
        var b=TranscriptBuffer()
        _ = try b.replace(timed([("indivisible",0,6)]),range:range(0,6),isFinal:false)
        #expect(throws:DictationFailure.recognitionFailed) { try b.replace(timed([("next",6,7)]),range:range(6,7),isFinal:false,finalization:time(2)) }
        #expect(b.snapshot=="indivisible" && b.lastRejection=="unmappedFinalizationBoundary")
    }
}

extension SpeechRange38L3R2Tests {
    @Test func legacyMetadataCannotRoundAnOverlappingBoundaryIntoAnAppend() throws {
        var b=LegacyTranscriptBuffer()
        _ = try b.replace("first",start:0,end:30.000001,metadataStart:0,metadataDuration:30.000001)
        #expect(try b.replace("candidate",start:0,end:1,metadataStart:30.0000005,metadataDuration:1)=="first")
        #expect(b.boundaryPending && b.unmergedText=="candidate")
    }
}
