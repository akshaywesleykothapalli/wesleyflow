import AVFoundation
import Darwin
import Domain
import Foundation

@main
struct Probe {
    static func main() async {
        do {
            try await run()
        } catch let error as WeSpeakerError {
            FileHandle.standardError.write(Data("Speaker probe failed: \(error)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("Speaker probe could not read the model or fixture.\n".utf8))
            exit(1)
        }
    }

    private static func run() async throws {
        let arguments = CommandLine.arguments.dropFirst()
        guard let modelPath = arguments.first, arguments.count >= 2 else {
            print("Usage: probe MODEL.onnx FIXTURE.wav [FIXTURE.wav ...]")
            exit(2)
        }
        let engine = WeSpeakerEngine(artifact: URL(fileURLWithPath: modelPath))
        let clock = ContinuousClock()
        let started = clock.now
        try await engine.loadModel()
        print("load=\(started.duration(to: clock.now)) dimension=\(engine.model.dimension)")
        for path in arguments.dropFirst() {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
                  (16_000...240_000).contains(file.length),
                  let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else {
                throw SpeakerRecognitionError.insufficientAudio
            }
            try file.read(into: pcm)
            guard let channel = pcm.floatChannelData?[0] else { throw SpeakerRecognitionError.insufficientAudio }
            let audio = SpeakerAudioSegment(startFrame: 0,
                samples: Array(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength))))
            let before = clock.now
            let embedding = try await engine.extractEmbedding(from: audio)
            print("frames=\(pcm.frameLength) dimension=\(embedding.count) inference=\(before.duration(to: clock.now))")
        }
        await engine.unloadModel()
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 { print("peakRSSBytes=\(usage.ru_maxrss)") }
    }
}
