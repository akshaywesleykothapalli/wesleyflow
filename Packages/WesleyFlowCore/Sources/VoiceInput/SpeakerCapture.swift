import AVFoundation
import Domain

/// One side channel of the active microphone tap. Only the worker allocates conversion buffers.
@MainActor public final class SpeakerCapture {
    private var ring: TeluguAudioRing?
    public var armed = false
    public init() {}

    func prepare(format: AVAudioFormat) -> TeluguAudioRing? {
        ring = nil
        guard armed, format.sampleRate.isFinite, (8_000...192_000).contains(format.sampleRate),
              format.commonFormat == .pcmFormatFloat32, (1...8).contains(format.channelCount) else { return nil }
        let buffer = TeluguAudioRing(sampleRate: format.sampleRate, capacity: Int(format.sampleRate * 14))
        ring = buffer
        return buffer
    }

    public func reset() { ring = nil; armed = false }

    /// Call after stopping and removing the input tap. Overflow discards only the label.
    public func take() -> Task<SpeakerAudioSegment?, Never>? {
        defer { reset() }
        guard let ring else { return nil }
        return Task.detached {
            guard !Task.isCancelled, !ring.isWriting, !ring.overflowed.load(ordering: .acquiring) else { return nil }
            let samples = ring.drain()
            guard !samples.isEmpty, let converter = try? TeluguPCMConverter(rate: ring.sampleRate),
                  let mono = try? converter.convert(samples, final: true) else { return nil }
            let segment = SpeakerAudioSegment(startFrame: 0, samples: mono)
            return !Task.isCancelled && segment.isUsable ? segment : nil
        }
    }

    /// Enrollment owns the microphone exclusively, independently of speech transcription.
    public func startEnrollmentCapture() throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        armed = true
        guard let buffer = prepare(format: format) else { reset(); throw DictationFailure.audioUnavailable }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.enrollmentTap(buffer))
        do { engine.prepare(); try engine.start(); return engine }
        catch { engine.inputNode.removeTap(onBus: 0); reset(); throw error }
    }

    private nonisolated static func enrollmentTap(_ ring: TeluguAudioRing) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { pcm, time in ring.append(pcm, at: time) }
    }
}
