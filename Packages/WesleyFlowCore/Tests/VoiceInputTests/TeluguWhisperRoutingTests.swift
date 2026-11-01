import Foundation
import AVFoundation
import CryptoKit
import Testing
import Domain
@testable import VoiceInput

private actor RoutingASRFixture: LocalPCMRecognizing {
    let text:String, language:String?, failure:DictationFailure?, rejection:String?
    private(set) var requests:[TeluguRecognitionLanguage] = []
    init(text:String = "",language:String? = nil,failure:DictationFailure? = nil,rejection:String? = nil) {
        self.text = text; self.language = language; self.failure = failure; self.rejection = rejection
    }
    private(set) var preparations = 0
    func prepare() { preparations += 1 }
    func transcribe(_ samples:[Float],language:TeluguRecognitionLanguage,cancellation:SpeechCancellation) throws -> String {
        requests.append(language); if let failure { throw failure }; return text
    }
    func recognitionReport() async -> LocalRecognitionReport { .init(summary:"fixture",language:language,rejection:rejection) }
}
@Suite("Telugu model routing and decoder windows") struct TeluguWhisperRoutingTests {
    @Test(arguments:["English words",""]) func automaticEnglishUsesGenericWithoutSpecialistDecode(_ text:String) async throws {
        let generic = RoutingASRFixture(text:text,language:text.isEmpty ? "te" : "en"), tuned = RoutingASRFixture(text:"wrong")
        let asr = TeluguWhisperPipeline(multilingual:generic,telugu:tuned)
        #expect(try await asr.transcribe([],language:.automatic,cancellation:SpeechCancellation()) == text)
        #expect(await generic.requests == [.automatic]); #expect(await tuned.requests.isEmpty)
    }
    @Test(arguments:[false,true]) func automaticTeluguAndRejectedGenericUseSpecialist(_ rejected:Bool) async throws {
        let generic = RoutingASRFixture(text:"తెలుగు",language:"te",failure:rejected ? .unsupportedRecognitionScript : nil,rejection:rejected ? "unsupportedRecognitionScript" : nil)
        let tuned = RoutingASRFixture(text:"తెలుగులో మాట్లాడుతున్నాను",language:"te")
        let asr = TeluguWhisperPipeline(multilingual:generic,telugu:tuned)
        #expect(try await asr.transcribe([],language:.automatic,cancellation:SpeechCancellation()) == "తెలుగులో మాట్లాడుతున్నాను")
        #expect(await tuned.requests == [.teluguOnly]); #expect(await generic.requests == [.automatic])
    }
    @Test func teluguOnlySkipsGenericAndCancellationNeverFallsBack() async throws {
        let generic = RoutingASRFixture(failure:.assetsMissing), tuned = RoutingASRFixture(text:"తెలుగు",language:"te")
        let asr = TeluguWhisperPipeline(multilingual:generic,telugu:tuned)
        #expect(try await asr.transcribe([],language:.teluguOnly,cancellation:SpeechCancellation()) == "తెలుగు")
        #expect(await generic.requests.isEmpty)
        let flag = SpeechCancellation(); flag.cancel()
        await #expect(throws:CancellationError.self) { _ = try await asr.transcribe([],language:.automatic,cancellation:flag) }
        #expect(await generic.requests.isEmpty); #expect(await tuned.requests.count == 1)
        await #expect(throws:DictationFailure.assetsMissing) { _ = try await asr.transcribe([],language:.automatic,cancellation:SpeechCancellation()) }
        #expect(await tuned.requests.count == 1)
    }
    @Test func quietCutsRetainEverySampleWithoutOverlapAndBoundDecoderWindow() {
        var samples = Array(repeating:Float(0.2),count:160_000)
        for i in 80_000..<80_640 { samples[i] = 0 }
        let ranges = WhisperAudioWindows.ranges(for:samples)
        #expect(ranges.count == 2); #expect((80_000..<80_640).contains(ranges[0].upperBound))
        #expect(ranges[0].lowerBound == 0 && ranges[1].upperBound == samples.count)
        #expect(ranges[0].upperBound == ranges[1].lowerBound)
        #expect(ranges.allSatisfy { $0.count <= 96_000 }); #expect(ranges.map(\.count).reduce(0,+) == samples.count)
        #expect(WhisperAudioWindows.ranges(for:[]).isEmpty)
    }
}

@Suite("Opt-in real Telugu specialist inference",.serialized) struct TeluguSpecialistIntegrationTests {
    private func pcm(_ url:URL) throws -> [Float] {
        let audio = try AVAudioFile(forReading:url)
        #expect(audio.processingFormat.sampleRate == 16000 && audio.processingFormat.channelCount == 1)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:audio.processingFormat,frameCapacity:UInt32(audio.length)))
        try audio.read(into:buffer)
        return Array(UnsafeBufferPointer(start:try #require(buffer.floatChannelData?[0]),count:Int(buffer.frameLength)))
    }
    @Test(.enabled(if:ProcessInfo.processInfo.environment["WESLEY_TELUGU_SPECIALIST_MODEL"] != nil))
    func heldOutSpeechSyntheticPhraseAndEnglishAutoUseProductionPipeline() async throws {
        let env = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath:try #require(env["WESLEY_TELUGU_FIXTURES"]))
        let tuned = LocalWhisperRecognizer(model:URL(fileURLWithPath:try #require(env["WESLEY_TELUGU_SPECIALIST_MODEL"])),artifact:.teluguSmallQ8)
        let pipeline = TeluguWhisperPipeline(telugu:tuned)
        try await pipeline.prepare()
        let cases:[(String,String,[String])] = [
            ("fleurs-te-test-1912.wav","bd35d16f1293f8d8133436d9b387ddad2a8ff31abbb272ab58513af291561f84",["ద్వీప","ఫ్రాన్స్","రిసార్","పిలుస్తారు"]),
            ("fleurs-te-test-1908.wav","7dc8baa363ec436333b2c1f4545bb62b4f445f708bcce141fa618134a80332c3",["క్రియలు","ఆబ్జెక్టు","ముఖ్యమైన","మార్గం"]),
            ("fleurs-te-test-1666.wav","7012022d111ae03810895fad4b092784056686370f70bf57ab98dc3e2dcb7464",["ఆలోచన","ప్రభుత్వాల","పౌరుల","రూపొందించ"])]
        for (name,hash,anchors) in cases {
            let url = directory.appendingPathComponent(name)
            #expect(SHA256.hash(data:try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined() == hash)
            let text = try await pipeline.transcribe(pcm(url),language:.teluguOnly,cancellation:SpeechCancellation())
            #expect(TeluguRecognitionQuality.failure(in:text) == nil)
            for anchor in anchors { #expect(Data(text.utf8).range(of:Data(anchor.utf8)) != nil) }
            let roman = TeluguDictationText.render(text)
            #expect(!roman.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) })
            print("Verified real Telugu fixture \(name): bytes=\(text.utf8.count) \((await pipeline.recognitionReport()).summary)")
        }
        let cancellation = SpeechCancellation()
        let cancellationPCM = try pcm(directory.appendingPathComponent("fleurs-te-test-1912.wav"))
        let decoding = Task { try await tuned.transcribe(cancellationPCM,language:.teluguOnly,cancellation:cancellation) }
        try await Task.sleep(for:.milliseconds(100)); cancellation.cancel()
        await #expect(throws:CancellationError.self) { _ = try await decoding.value }
        // The following real decodes reuse the same context after cancellation.
        if let sample = env["WESLEY_TELUGU_SYNTHETIC"] {
            let text = try await pipeline.transcribe(pcm(URL(fileURLWithPath:sample)),language:.teluguOnly,cancellation:SpeechCancellation())
            #expect(TeluguDictationText.render(text).contains("telugulo maatlaadutunnaanu"))
            let auto = try await pipeline.transcribe(pcm(URL(fileURLWithPath:sample)),language:.automatic,cancellation:SpeechCancellation())
            #expect(TeluguDictationText.render(auto).contains("telugulo maatlaadutunnaanu"))
        }
        if let english = env["WESLEY_TELUGU_TEST_WAV"] {
            let text = try await pipeline.transcribe(pcm(URL(fileURLWithPath:english)),language:.automatic,cancellation:SpeechCancellation())
            #expect(text.lowercased().contains("country"))
            #expect((await pipeline.recognitionReport()).summary.contains("route=multilingual"))
        }
    }
}


extension TeluguWhisperRoutingTests {
    @Test func modeAwarePreparationLoadsRequiredAssetsBeforeCapture() async throws {
        let generic = RoutingASRFixture(), tuned = RoutingASRFixture()
        let asr = TeluguWhisperPipeline(multilingual:generic,telugu:tuned)
        try await asr.prepare(language:.teluguOnly)
        #expect(await tuned.preparations == 1); #expect(await generic.preparations == 0)
        try await asr.prepare(language:.automatic)
        #expect(await tuned.preparations == 2); #expect(await generic.preparations == 1)
    }
}
