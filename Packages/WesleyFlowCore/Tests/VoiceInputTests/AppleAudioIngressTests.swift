import Testing
import AVFoundation
import Speech
import Foundation
import Domain
@testable import VoiceInput

@Suite("Apple microphone array downmix") struct AppleAudioIngressTests {
    @Test(arguments:[1,2,3], [false,true])
    func unlabeledChannelsReachAnalyzerAsAudibleMono(_ count:Int,_ interleaved:Bool) async throws {
        let layout = try #require(AVAudioChannelLayout(layoutTag:kAudioChannelLayoutTag_DiscreteInOrder | UInt32(count)))
        let source = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,interleaved:interleaved,channelLayout:layout)
        let target = try #require(AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false))
        // Exercise every channel separately: selecting only channel zero would lose speech.
        for active in 0..<count {
            let pair = AsyncThrowingStream<AnalyzerInput,any Error>.makeStream(bufferingPolicy:.bufferingOldest(32))
            let ingress = try AudioIngress(source:source,target:target,modern:pair.continuation)
            for chunk in 0..<10 {
                let input = try #require(AVAudioPCMBuffer(pcmFormat:source,frameCapacity:4800)); input.frameLength = 4800
                let channels = try #require(input.floatChannelData)
                for channel in 0..<count {
                    for frame in 0..<4800 {
                        let value = channel == active ? Float(sin(Double(chunk*4800 + frame)*2*Double.pi*440/48000)*0.1) : 0
                        channels[interleaved ? 0 : channel][frame*input.stride + (interleaved ? channel : 0)] = value
                    }
                }
                ingress.append(input,at:AVAudioTime(sampleTime:Int64(chunk*4800),atRate:48000))
            }
            ingress.close()
            var samples:[Double] = []
            for try await item in pair.stream {
                let buffer = item.buffer
                let pointer = try #require(buffer.int16ChannelData?[0])
                samples += (0..<Int(buffer.frameLength)).map { Double(pointer[$0])/32768 }
            }
            #expect(samples.count == 16000)
            let rms = sqrt(samples.reduce(0) { $0+$1*$1 }/Double(samples.count))
            #expect(abs(rms - 0.07071/Double(count)) < 0.002)
            #expect(ingress.diagnostics.converterDrained)
            #expect(ingress.diagnostics.discontinuities == 0)
            #expect(ingress.diagnostics.queuedFrames == 16000)
        }
    }
    @Test func nonFiniteArrayInputFailsBeforeAnalyzerDelivery() async throws {
        let format = try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:2,interleaved:false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:320)); buffer.frameLength = 320
        for frame in 0..<320 { buffer.floatChannelData![0][frame] = .nan; buffer.floatChannelData![1][frame] = 0.1 }
        let target = try #require(AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false))
        let pair = AsyncThrowingStream<AnalyzerInput,any Error>.makeStream()
        let ingress = try AudioIngress(source:format,target:target,modern:pair.continuation)
        ingress.append(buffer)
        await #expect(throws:DictationFailure.audioUnavailable) { for try await _ in pair.stream { Issue.record("Invalid audio reached analyzer") } }
        #expect(ingress.diagnostics.closeReason == "downmixFailed")
    }
}

@Suite("Opt-in real Apple English recognition",.serialized) @MainActor struct NativeAppleAudioIntegrationTests {
    @Test(.enabled(if:ProcessInfo.processInfo.environment["WESLEY_APPLE_AUDIO_FIXTURE"] != nil))
    func prerecordedEnglishArrayUsesInstalledSpeechTranscriberWithoutMicrophone() async throws {
        let url = URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["WESLEY_APPLE_AUDIO_FIXTURE"]))
        let locale = try #require(await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:"en-IN")))
        let installed = await SpeechTranscriber.installedLocales
        try #require(installed.contains { SpeechEngineResources.sameLocale($0.identifier,locale.identifier) }, "Only already-installed resources may be used")
        let file = try AVAudioFile(forReading:url)
        let original = try #require(AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:UInt32(file.length)))
        try file.read(into:original)
        try #require(file.processingFormat.sampleRate == 16000 && file.processingFormat.channelCount == 1)
        let pcm = Array(UnsafeBufferPointer(start:try #require(original.floatChannelData?[0]),count:Int(original.frameLength)))
        for (count,gain) in [(UInt32(1),Float(1)),(3,1),(3,0.05)] {
            let module = AppleSpeechModules.speech(locale)
            let target = try #require(await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[module]))
            let layout = try #require(AVAudioChannelLayout(layoutTag:kAudioChannelLayoutTag_DiscreteInOrder | count))
            let source = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,interleaved:false,channelLayout:layout)
            // Fixture is fed faster than real time; retain bounded 11 s input without timing sleeps.
            let pair = AsyncThrowingStream<AnalyzerInput,any Error>.makeStream(bufferingPolicy:.bufferingOldest(256))
            let ingress = try AudioIngress(source:source,target:target,modern:pair.continuation)
            let analyzer = SpeechAnalyzer(modules:[module],options:.init(priority:.userInitiated,modelRetention:.whileInUse))
            let results = Task { @MainActor in
                var text = ""
                for try await result in module.results { if result.isFinal { text += String(result.text.characters) } }
                return text
            }
            do {
                try await analyzer.prepareToAnalyze(in:target)
                try await analyzer.start(inputSequence:pair.stream)
                let frames = pcm.count*3
                for start in stride(from:0,to:frames,by:4800) {
                    let length = min(4800,frames-start)
                    let buffer = try #require(AVAudioPCMBuffer(pcmFormat:source,frameCapacity:UInt32(length))); buffer.frameLength = UInt32(length)
                    for channel in 0..<Int(count) {
                        for frame in 0..<length { buffer.floatChannelData![channel][frame] = pcm[(start+frame)/3]*gain }
                    }
                    ingress.append(buffer,at:AVAudioTime(sampleTime:Int64(start),atRate:48000))
                }
                ingress.close()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let text = try await results.value
                #expect(text.lowercased().contains("country"))
                print("Real Apple en-IN recognition: sourceChannels=\(count) gain=\(gain) sourceFrames=\(frames) finalBytes=\(text.utf8.count)")
            } catch {
                results.cancel(); await analyzer.cancelAndFinishNow(); throw error
            }
        }
    }
}
