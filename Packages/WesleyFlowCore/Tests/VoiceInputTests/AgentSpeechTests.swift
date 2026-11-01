import Foundation
import AVFoundation
import Speech
import Testing
import Domain
@testable import VoiceInput

@Suite("Opt-in recorded Agent command recognition",.serialized) @MainActor struct AgentSpeechTests {
    @Test(.enabled(if:ProcessInfo.processInfo.environment["WESLEY_AGENT_AUDIO_DIRECTORY"] != nil))
    func modernCommandSpeechRecognizesLanguageAndBatteryWithoutMicrophone() async throws {
        let directory = URL(fileURLWithPath:try #require(ProcessInfo.processInfo.environment["WESLEY_AGENT_AUDIO_DIRECTORY"]))
        let locale = try #require(await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:"en-IN")))
        let installed = await SpeechTranscriber.installedLocales
        try #require(installed.contains { SpeechEngineResources.sameLocale($0.identifier,locale.identifier) })
        for name in ["telugu","english","battery"] {
            let file = try AVAudioFile(forReading:directory.appendingPathComponent(name+".wav"))
            try #require(file.processingFormat.sampleRate == 16000 && file.processingFormat.channelCount == 1)
            let original = try #require(AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:UInt32(file.length)))
            try file.read(into:original)
            let pcm = Array(UnsafeBufferPointer(start:try #require(original.floatChannelData?[0]),count:Int(original.frameLength)))
            let module = AppleSpeechModules.speech(locale)
            let target = try #require(await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[module]))
            let layout = try #require(AVAudioChannelLayout(layoutTag:kAudioChannelLayoutTag_DiscreteInOrder | 3))
            let source = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,interleaved:false,channelLayout:layout)
            let pair = AsyncThrowingStream<AnalyzerInput,any Error>.makeStream(bufferingPolicy:.bufferingOldest(256))
            let ingress = try AudioIngress(source:source,target:target,modern:pair.continuation)
            let analyzer = SpeechAnalyzer(modules:[module],options:.init(priority:.userInitiated,modelRetention:.whileInUse))
            try await analyzer.setContext(AgentSpeechContext.make(applicationNames:["Notes"]))
            let results = Task { @MainActor in
                var text = ""
                for try await result in module.results { if result.isFinal { text += String(result.text.characters) } }
                return text
            }
            do {
                try await analyzer.prepareToAnalyze(in:target); try await analyzer.start(inputSequence:pair.stream)
                let frames = pcm.count*3
                for start in stride(from:0,to:frames,by:4800) {
                    let length = min(4800,frames-start)
                    let buffer = try #require(AVAudioPCMBuffer(pcmFormat:source,frameCapacity:UInt32(length))); buffer.frameLength = UInt32(length)
                    for channel in 0..<3 { for frame in 0..<length { buffer.floatChannelData![channel][frame] = pcm[(start+frame)/3] } }
                    ingress.append(buffer,at:AVAudioTime(sampleTime:Int64(start),atRate:48000))
                }
                ingress.close(); try await analyzer.finalizeAndFinishThroughEndOfInput()
                let text = try await results.value
                print("Recorded Agent \(name): \(text)")
                if name == "telugu" { #expect(FlowVoiceControl.parse(text) == .language(.teluguRomanised,.teluguOnly)) }
                else if name == "english" { #expect(FlowVoiceControl.parse(text) == .language(.english,nil)) }
                else { #expect(try PersonalMacControl.parse(text,now:Date())?.steps.first?.tool == .macControl) }
            } catch { results.cancel(); await analyzer.cancelAndFinishNow(); throw error }
        }
    }
}
