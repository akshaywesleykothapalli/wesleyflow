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
        let buffer = TeluguAudioRing(sampleRate: format.sampleRate, capacity: Int(format.sampleRate * 14), retainPrefix: true)
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
            return Task.isCancelled ? nil : Self.trimQuietEdges(mono)
        }
    }

    private nonisolated static func trimQuietEdges(_ samples: [Float]) -> SpeakerAudioSegment? {
        let original = SpeakerAudioSegment(startFrame: 0, samples: samples)
        guard original.isUsable else { return nil }

        let rate = SpeakerAudioSegment.sampleRate
        let window = rate / 50
        let context = rate * 4 / 25
        var firstActive: Int?
        var lastActiveEnd = 0
        for start in stride(from: 0, to: samples.count, by: window) {
            let end = min(start + window, samples.count)
            let energy = samples[start..<end].reduce(0.0) { $0 + Double($1) * Double($1) }
            if energy > 0.000025 * Double(end - start) {
                if firstActive == nil { firstActive = start }
                lastActiveEnd = end
            }
        }
        guard let firstActive else { return nil }

        let start = max(0, firstActive - context)
        let end = min(samples.count, lastActiveEnd + context)
        // Keep a full second for the embedding model, even for a short phrase.
        let paddedStart = min(start, max(0, end - rate))
        let paddedEnd = max(end, paddedStart + rate)
        guard paddedStart > 0 || paddedEnd < samples.count else { return original }
        let trimmed = SpeakerAudioSegment(startFrame: Int64(paddedStart),
                                          samples: Array(samples[paddedStart..<paddedEnd]))
        return trimmed.isUsable ? trimmed : nil
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
