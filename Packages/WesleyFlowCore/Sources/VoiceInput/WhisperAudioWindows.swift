/// Telugu UTF-8 tokenisation can exhaust Whisper's decoder window before 30 s of audio.
/// Split at a quiet 20 ms frame near 4–6 s, retaining every sample exactly once.
enum WhisperAudioWindows {
    static let maximumSamples = 96_000
    static func ranges(for samples: [Float]) -> [Range<Int>] {
        var result: [Range<Int>] = [], start = 0
        while samples.count - start > maximumSamples {
            let lower = start + 64_000
            let upper = min(start + maximumSamples,samples.count - 32_000)
            var cut = upper, quietest = Double.infinity
            var frame = lower
            while frame + 320 <= upper {
                var energy = 0.0
                for i in frame..<(frame + 320) { energy += Double(samples[i]) * Double(samples[i]) }
                if energy <= quietest { quietest = energy; cut = frame + 160 }
                frame += 320
            }
            result.append(start..<cut); start = cut
        }
        if start < samples.count { result.append(start..<samples.count) }
        return result
    }
}
