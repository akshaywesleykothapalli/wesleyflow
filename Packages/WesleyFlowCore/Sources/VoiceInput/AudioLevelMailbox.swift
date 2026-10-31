import AVFoundation
import Domain
import Synchronization

/// One tap producer, atomic scalar transfer. No audio copy, lock, queue, actor hop or per-buffer allocation.
final class AudioLevelMailbox: Sendable {
    private let packed = Atomic<UInt64>(0)
    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, buffer.frameLength <= 8192,
              buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.format.channelCount > 0, buffer.format.channelCount <= 8,
              let channels = buffer.floatChannelData else { return }
        var sum = 0.0, peak = 0.0
        let frames = Int(buffer.frameLength), count = Int(buffer.format.channelCount), stride = buffer.stride
        for channel in 0..<count {
            for frame in 0..<frames {
                let samples = channels[buffer.format.isInterleaved ? 0 : channel]
                let value = Double(samples[frame*stride + (buffer.format.isInterleaved ? channel : 0)])
                if value.isFinite { sum += min(1,value*value); peak = max(peak,min(1,abs(value))) }
            }
        }
        let rms = Float(sqrt(sum/Double(frames*count)))
        let sequence = UInt32(truncatingIfNeeded:packed.load(ordering:.relaxed)>>32) &+ 1
        packed.store((UInt64(sequence)<<32)|(UInt64((peak*65535).rounded())<<16)|UInt64((Double(rms)*65535).rounded()),ordering:.relaxed)
    }
    func snapshot() -> DictationAudioLevel {
        let value = packed.load(ordering:.relaxed)
        return .init(sequence:UInt32(truncatingIfNeeded:value>>32),rms:Float(value & 0xffff)/65535,peak:Float((value>>16) & 0xffff)/65535)
    }
}
