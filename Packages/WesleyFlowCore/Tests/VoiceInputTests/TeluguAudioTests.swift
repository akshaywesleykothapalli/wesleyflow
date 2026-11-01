import Testing
import AVFoundation
import Foundation
import Domain
@testable import VoiceInput

// Immutable test wrapper: invoke the SDK's Objective-C block on a worker just as AVAudioEngine does.
private final class TeluguNativeTapBlockFixture: @unchecked Sendable {
    let block: AVAudioNodeTapBlock
    init(_ block: @escaping AVAudioNodeTapBlock) { self.block = block }
}

@Suite("Telugu bounded PCM and segmentation") struct TeluguAudioTests {
    @Test func silenceAndShortImpulseProduceNoUtterance() {
        var s = TeluguUtteranceSegmenter()
        #expect(s.append(Array(repeating:0,count:80_000)).isEmpty)
        #expect(s.append(Array(repeating:0.3,count:1600)).isEmpty)
        #expect(s.append(Array(repeating:0,count:8000),final:true).isEmpty)
    }
    @Test func silenceBoundaryPaddingRepetitionAndMaximumAreSampleBounded() {
        var s = TeluguUtteranceSegmenter()
        #expect(s.append(Array(repeating:0,count:3840)).isEmpty)
        #expect(s.append(Array(repeating:0.2,count:8000)).isEmpty)
        let first = s.append(Array(repeating:0,count:8000))
        #expect(first.count == 1); #expect(first.first?.count == 18_560)
        let second = s.append(Array(repeating:0.2,count:8000),final:true)
        #expect(second.count == 1); #expect(second.first?.count == 8000)
        #expect(s.append([],final:true).isEmpty)
        var long = TeluguUtteranceSegmenter()
        let chunks = long.append(Array(repeating:0.2,count:800_000),final:true)
        #expect(chunks.map(\.count) == [400_000,400_000])
    }
    @Test func ringDownmixesWithFIFOAndFailsClosedOnOverflow() throws {
        let format = try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:2,interleaved:false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:320))
        buffer.frameLength = 320
        for i in 0..<320 { buffer.floatChannelData![0][i] = 0.2; buffer.floatChannelData![1][i] = 0.4 }
        let ring = TeluguAudioRing(sampleRate:48000,capacity:640)
        ring.append(buffer); #expect(ring.drain().allSatisfy { abs($0 - 0.3) < 0.0001 })
        ring.append(buffer); ring.append(buffer); ring.append(buffer)
        let overflow = ring.overflowed.load(ordering:.acquiring); #expect(overflow); #expect(ring.drain().count == 640)
    }
    @Test func producerResamplesAndDrainsWithoutMicrophone() async throws {
        let format = try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:1,interleaved:false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4800)); buffer.frameLength = 4800
        for i in 0..<4800 { buffer.floatChannelData![0][i] = Float(sin(Double(i)*0.1)*0.3) }
        let ring = TeluguAudioRing(sampleRate:48000), flag = SpeechCancellation()
        for _ in 0..<5 { ring.append(buffer) }
        ring.ended.store(true,ordering:.releasing)
        let (stream, continuation) = AsyncThrowingStream<[Float],any Error>.makeStream(bufferingPolicy:.bufferingOldest(2))
        let task = Task { await produceTeluguUtterances(ring:ring,cancellation:flag,stream:continuation) }
        var all:[Float] = []
        for try await segment in stream { all += segment }
        await task.value
        #expect(abs(all.count - 8000) <= 1); #expect(all.allSatisfy { $0.isFinite })
    }
    @Test func invalidModelAndCancelledRequestsNeverLoadOrRecognize() async {
        let asr = LocalWhisperRecognizer(model:URL(fileURLWithPath:"/missing/ggml-small.bin"))
        await #expect(throws:DictationFailure.assetsMissing) { try await asr.prepare() }
        let flag = SpeechCancellation(); flag.cancel()
        await #expect(throws:CancellationError.self) { _ = try await asr.transcribe(Array(repeating:0,count:16000),language:.automatic,cancellation:flag) }
        await #expect(throws:DictationFailure.audioUnavailable) { _ = try await asr.transcribe([.nan],language:.automatic,cancellation:SpeechCancellation()) }
    }
}

@Suite("Opt-in real offline Small inference",.serialized) struct WhisperSmallIntegrationTests {
    @Test(.enabled(if:ProcessInfo.processInfo.environment["WESLEY_TELUGU_TEST_MODEL"] != nil))
    func actualEnglishAutoAndTeluguOnlyAreExplicitAndCancellationIsReusable() async throws {
        let env = ProcessInfo.processInfo.environment
        let url = URL(fileURLWithPath:try #require(env["WESLEY_TELUGU_TEST_MODEL"]))
        let wav = URL(fileURLWithPath:try #require(env["WESLEY_TELUGU_TEST_WAV"]))
        let audio = try AVAudioFile(forReading:wav)
        #expect(audio.processingFormat.sampleRate == 16000); #expect(audio.processingFormat.channelCount == 1)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:audio.processingFormat,frameCapacity:UInt32(audio.length)))
        try audio.read(into:buffer)
        let pointer = try #require(buffer.floatChannelData?[0])
        let pcm = Array(UnsafeBufferPointer(start:pointer,count:Int(buffer.frameLength)))
        let asr = LocalWhisperRecognizer(model:url)
        let clock = ContinuousClock(); let load = clock.now
        try await asr.prepare(); print("Small model verified + loaded: \(load.duration(to:clock.now))")
        let begin = clock.now
        let english = try await asr.transcribe(pcm,language:.automatic,cancellation:SpeechCancellation())
        print("Small auto inference, public JFK sample \(Double(pcm.count)/16000)s: \(begin.duration(to:clock.now))")
        #expect(english.lowercased().contains("country"))
        let te = try await asr.transcribe(pcm,language:.teluguOnly,cancellation:SpeechCancellation())
        #expect(te != english) // Forced-te is deliberately tested on English; no accuracy claim.
        print("Forced-te on English sample: Latin=\(te.unicodeScalars.contains { (65...122).contains($0.value) }) Telugu=\(te.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) })")
        let cancelled = SpeechCancellation(); cancelled.cancel()
        await #expect(throws:CancellationError.self) { _ = try await asr.transcribe(pcm,language:.automatic,cancellation:cancelled) }
        let inFlight = SpeechCancellation()
        let decoding = Task { try await asr.transcribe(pcm,language:.automatic,cancellation:inFlight) }
        try await Task.sleep(for:.milliseconds(100)); inFlight.cancel()
        await #expect(throws:CancellationError.self) { _ = try await decoding.value }
        let again = try await asr.transcribe(pcm,language:.automatic,cancellation:SpeechCancellation())
        #expect(again == english)
    }
}

private actor HeldTeluguPreparation: LocalPCMRecognizing {
    private var pending:CheckedContinuation<Void,Never>?
    private var waiter:CheckedContinuation<Void,Never>?
    func prepare() async {
        await withCheckedContinuation { pending = $0; waiter?.resume(); waiter = nil }
    }
    func waitUntilPreparing() async { if pending == nil { await withCheckedContinuation { waiter = $0 } } }
    func release() { pending?.resume(); pending = nil }
    func transcribe(_ samples:[Float],language:TeluguRecognitionLanguage,cancellation:SpeechCancellation) throws -> String { throw DictationFailure.recognitionFailed }
}
extension TeluguAudioTests {
    @Test @MainActor func cancellationDuringLoadingAndMissingModelNeverRequestMicrophone() async {
        let held = HeldTeluguPreparation()
        var permissionRequests = 0
        let input = TeluguDictationInput(recognizer:held,microphoneAccess:{ permissionRequests += 1; return false })
        let starting = Task { try await input.start(localeIdentifier:"auto") { _ in Issue.record("Cancelled startup delivered an event") } }
        await held.waitUntilPreparing(); input.cancel(); await held.release()
        await #expect(throws:CancellationError.self) { _ = try await starting.value }
        #expect(permissionRequests == 0)
        let missing = TeluguDictationInput(recognizer:LocalWhisperRecognizer(model:URL(fileURLWithPath:"/missing/model.bin")),microphoneAccess:{ permissionRequests += 1; return false })
        await #expect(throws:DictationFailure.assetsMissing) { _ = try await missing.start(localeIdentifier:"auto") { _ in Issue.record("Missing model delivered an event") } }
        #expect(permissionRequests == 0)
    }
    @Test func arbitraryBufferSplitsDoNotChangeSegmentationAndTimestampGapsFailClosed() throws {
        let pcm = Array(repeating:Float(0),count:3840) + Array(repeating:Float(0.1),count:8000) + Array(repeating:Float(0),count:9000) + Array(repeating:Float(0.2),count:8000)
        var whole = TeluguUtteranceSegmenter(), fragmented = TeluguUtteranceSegmenter()
        let expected = whole.append(pcm,final:true)
        var actual:[[Float]] = [], offset = 0
        while offset < pcm.count {
            let end = min(offset + 137,pcm.count)
            actual += fragmented.append(Array(pcm[offset..<end])); offset = end
        }
        actual += fragmented.append([],final:true)
        #expect(actual == expected)
        let format = try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:1,interleaved:false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:320)); buffer.frameLength = 320
        buffer.floatChannelData![0].initialize(repeating:0,count:320)
        let ring = TeluguAudioRing(sampleRate:48000)
        ring.append(buffer,at:AVAudioTime(sampleTime:0,atRate:48000))
        ring.append(buffer,at:AVAudioTime(sampleTime:640,atRate:48000))
        let failed = ring.overflowed.load(ordering:.acquiring)
        #expect(failed); #expect(ring.drain().count == 320)
    }
    @Test func fullSegmentQueueFailsRatherThanDroppingAudio() async throws {
        let format = try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:8000)); buffer.frameLength = 8000
        let ring = TeluguAudioRing(sampleRate:16000)
        for _ in 0..<4 {
            for i in 0..<8000 { buffer.floatChannelData![0][i] = 0.2 }; ring.append(buffer)
            for i in 0..<8000 { buffer.floatChannelData![0][i] = 0 }; ring.append(buffer)
        }
        ring.ended.store(true,ordering:.sequentiallyConsistent)
        let (stream, continuation) = AsyncThrowingStream<[Float],any Error>.makeStream(bufferingPolicy:.bufferingOldest(2))
        await produceTeluguUtterances(ring:ring,cancellation:SpeechCancellation(),stream:continuation)
        await #expect(throws:DictationFailure.overflow) { for try await _ in stream {} }
    }
}


extension TeluguAudioTests {
    @Test @MainActor func nativeTapConstructedFromMainActorRunsOnAudioWorker() async throws {
        let ring = TeluguAudioRing(sampleRate:48000), meter = AudioLevelMailbox()
        // This is the exact callback factory used by installTap, invoked from a worker.
        // Run with -enable-actor-data-race-checks to catch the previous main-executor trap.
        let callback = TeluguNativeTapBlockFixture(TeluguNativeCallbacks.tap(ring:ring,meter:meter))
        try await Task.detached {
            func onMainThread() -> Bool { Thread.isMainThread }
            #expect(!onMainThread())
            let format = try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:1,interleaved:false))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:320)); buffer.frameLength = 320
            for i in 0..<320 { buffer.floatChannelData![0][i] = 0.25 }
            callback.block(buffer,AVAudioTime(sampleTime:0,atRate:48000))
        }.value
        let samples = ring.drain()
        #expect(samples.count == 320); #expect(samples.allSatisfy { $0 == 0.25 })
        #expect(meter.snapshot().rms > 0.2)
    }
    @Test @MainActor func configurationNotificationFromWorkerHopsToMainActor() async {
        await withCheckedContinuation { continuation in
            let callback = TeluguNativeCallbacks.configurationChanged {
                MainActor.assertIsolated(); continuation.resume()
            }
            Task.detached { callback(Notification(name:.AVAudioEngineConfigurationChange)) }
        }
    }
}
