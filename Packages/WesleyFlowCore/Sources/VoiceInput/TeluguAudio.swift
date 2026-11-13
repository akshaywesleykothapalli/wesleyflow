import Foundation
import AVFoundation
import Synchronization
import Domain

/// Single tap producer / single worker consumer. Storage is allocated before engine.start.
/// The callback only reads PCM, averages channels and copies to the ring; it never locks or allocates.
final class TeluguAudioRing: @unchecked Sendable {
    private let capacity: Int
    private let retainPrefix: Bool
    private let samples: UnsafeMutablePointer<Float>
    private let written = Atomic<Int>(0), read = Atomic<Int>(0)
    let ended = Atomic<Bool>(false), overflowed = Atomic<Bool>(false)
    private let writing = Atomic<Bool>(false)
    var isWriting: Bool { writing.load(ordering:.sequentiallyConsistent) }
    private var expectedSample: AVAudioFramePosition?
    let sampleRate: Double
    init(sampleRate: Double, capacity: Int = 524_288, retainPrefix: Bool = false) {
        self.sampleRate = sampleRate; self.capacity = capacity
        self.retainPrefix = retainPrefix
        samples = .allocate(capacity:capacity); samples.initialize(repeating:0,count:capacity)
    }
    deinit { samples.deinitialize(count:capacity); samples.deallocate() }
    func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime? = nil) {
        writing.store(true,ordering:.sequentiallyConsistent)
        defer { writing.store(false,ordering:.sequentiallyConsistent) }
        guard !ended.load(ordering:.sequentiallyConsistent), buffer.frameLength > 0 else { return }
        let start = written.load(ordering: .relaxed)
        // Speaker capture takes a single bounded prefix. Dictation still streams and detects overflow.
        if retainPrefix && start == capacity { return }
        guard buffer.format.commonFormat == .pcmFormatFloat32, buffer.format.sampleRate == sampleRate,
              (1...8).contains(buffer.format.channelCount), buffer.frameLength <= 8192,
              let channels = buffer.floatChannelData else { overflowed.store(true,ordering:.releasing); return }
        if let time, time.isSampleTimeValid {
            guard time.sampleRate == sampleRate, expectedSample == nil || expectedSample == time.sampleTime else {
                overflowed.store(true,ordering:.releasing); return
            }
            let next = time.sampleTime.addingReportingOverflow(Int64(buffer.frameLength))
            guard !next.overflow else { overflowed.store(true,ordering:.releasing); return }
            expectedSample = next.partialValue
        }
        let count = retainPrefix ? min(Int(buffer.frameLength), capacity - start) : Int(buffer.frameLength)
        guard start - read.load(ordering:.acquiring) + count <= capacity, start < Int.max - count else {
            overflowed.store(true,ordering:.releasing); return
        }
        let channelCount = Int(buffer.format.channelCount), stride = buffer.stride
        for index in 0..<count {
            var sum: Float = 0
            for channel in 0..<channelCount {
                let value = channels[buffer.format.isInterleaved ? 0 : channel][index*stride + (buffer.format.isInterleaved ? channel : 0)]
                guard value.isFinite else { overflowed.store(true,ordering:.releasing); return }
                sum += value / Float(channelCount)
            }
            samples[(start + index) % capacity] = min(1,max(-1,sum))
        }
        written.store(start + count,ordering:.releasing)
    }
    func drain() -> [Float] {
        let start = read.load(ordering:.relaxed), end = written.load(ordering:.acquiring)
        let result = (start..<end).map { samples[$0 % capacity] }
        read.store(end,ordering:.releasing); return result
    }
}

/// Initial energy gate, not a learned VAD: 20 ms windows, 200 ms speech, 500 ms silence,
/// 160 ms preroll and 25 s maximum. No overlapping segments or word-based deduplication.
struct TeluguUtteranceSegmenter {
    private var pending:[Float] = [], preroll:[Float] = [], utterance:[Float] = []
    private var voiced = 0, silence = 0
    private var consumedFrames: Int64 = 0, utteranceStart: Int64 = 0
    private(set) var gatedSamples = 0
    mutating func append(_ samples: [Float], final: Bool = false) -> [[Float]] {
        appendTimed(samples, final: final).map(\.samples)
    }

    mutating func appendTimed(_ samples: [Float], final: Bool = false) -> [SpeakerAudioSegment] {
        pending += samples
        var output: [SpeakerAudioSegment] = []
        var cursor = 0
        while pending.count - cursor >= 320 || (final && cursor < pending.count) {
            let end = min(cursor + 320,pending.count), frame = Array(pending[cursor..<end])
            let frameStart = consumedFrames + Int64(cursor)
            cursor = end
            let energy = frame.reduce(0.0) { $0 + Double($1)*Double($1) } / Double(frame.count)
            let speech = energy > 0.000025 // RMS > 0.005; tuning/real-device acceptance still required.
            if utterance.isEmpty {
                if speech {
                    utteranceStart = frameStart - Int64(preroll.count)
                    utterance = preroll + frame; preroll = []; voiced = frame.count; silence = 0
                }
                else { preroll += frame; if preroll.count > 2560 { preroll.removeFirst(preroll.count - 2560) } }
            } else {
                utterance += frame
                if speech { voiced += frame.count; silence = 0 } else { silence += frame.count }
                if silence >= 8000 || utterance.count >= 400_000 {
                    if voiced >= 3200 { output.append(.init(startFrame: utteranceStart, samples: utterance)); gatedSamples += utterance.count }
                    utterance = []; voiced = 0; silence = 0
                }
            }
        }
        consumedFrames += Int64(cursor)
        pending.removeFirst(cursor)
        if final {
            if voiced >= 3200 { output.append(.init(startFrame: utteranceStart, samples: utterance)); gatedSamples += utterance.count }
            utterance = []; preroll = []; pending = []; voiced = 0; silence = 0
        }
        return output
    }
}

/// Lives entirely in the producer task. AVAudioConverter never executes in the tap or main actor.
final class TeluguPCMConverter {
    let source: AVAudioFormat, target: AVAudioFormat, converter: AVAudioConverter
    var received = 0, emitted = 0
    init(rate: Double) throws {
        guard rate.isFinite, (8000...192000).contains(rate),
              let source = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:1,interleaved:false),
              let target = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false),
              let converter = AVAudioConverter(from:source,to:target) else { throw DictationFailure.audioUnavailable }
        self.source = source; self.target = target; self.converter = converter; converter.primeMethod = .none
    }
    func convert(_ samples:[Float], final:Bool) throws -> [Float] {
        received += samples.count
        var input:AVAudioPCMBuffer?
        if !samples.isEmpty {
            guard let buffer = AVAudioPCMBuffer(pcmFormat:source,frameCapacity:UInt32(samples.count)), let pointer = buffer.floatChannelData?[0] else { throw DictationFailure.audioUnavailable }
            buffer.frameLength = UInt32(samples.count)
            samples.withUnsafeBufferPointer { pointer.update(from:$0.baseAddress!,count:$0.count) }; input = buffer
        }
        var supplied = false, result:[Float] = []
        for _ in 0..<128 {
            guard let output = AVAudioPCMBuffer(pcmFormat:target,frameCapacity:8192) else { throw DictationFailure.audioUnavailable }
            var error:NSError?
            let status = converter.convert(to:output,error:&error) { _, status in
                if !supplied, let input { supplied = true; status.pointee = .haveData; return input }
                status.pointee = final ? .endOfStream : .noDataNow; return nil
            }
            guard error == nil, status != .error else { throw DictationFailure.audioUnavailable }
            let remaining = max(0,Int(ceil(Double(received)*16000/source.sampleRate)) - emitted)
            let count = min(Int(output.frameLength),remaining)
            if count > 0, let pointer = output.floatChannelData?[0] { result += UnsafeBufferPointer(start:pointer,count:count); emitted += count }
            if status == .endOfStream || (!final && status == .inputRanDry) { return result }
        }
        throw DictationFailure.overflow
    }
}

/// Worker-only measurements; the real-time tap never takes this lock or stores audio here.
final class TeluguCaptureStatistics: Sendable {
    private struct Counts: Sendable { var sourceFrames = 0, modelFrames = 0, utterances = 0; var energy = 0.0, peak = 0.0 }
    private let counts = Mutex(Counts())
    func record(sourceFrames:Int, converted:[Float], utterances:Int) {
        let energy = converted.reduce(0.0) { $0 + Double($1)*Double($1) }
        let peak = converted.reduce(0.0) { max($0,abs(Double($1))) }
        counts.withLock { value in
            value.sourceFrames += sourceFrames; value.modelFrames += converted.count; value.utterances += utterances
            value.energy += energy; value.peak = max(value.peak,peak)
        }
    }
    var emptyCaptureFailure: DictationFailure? {
        counts.withLock { $0.sourceFrames == 0 ? .noAudioCaptured : ($0.utterances == 0 ? .speechBelowThreshold : nil) }
    }
    var summary: String {
        counts.withLock { value in
            let rms = value.modelFrames == 0 ? 0 : sqrt(value.energy/Double(value.modelFrames))
            return "audioSourceFrames=\(value.sourceFrames) audio16kFrames=\(value.modelFrames) admittedUtterances=\(value.utterances) audioRMS=\(rms) audioPeak=\(value.peak)"
        }
    }
}

nonisolated func produceTeluguUtterances(ring: TeluguAudioRing, cancellation: SpeechCancellation,
                                        stream: AsyncThrowingStream<[Float],any Error>.Continuation,
                                        statistics: TeluguCaptureStatistics = TeluguCaptureStatistics(),
                                        onFailure: @Sendable (DictationFailure) -> Void = { _ in }) async {
    do {
        let converter = try TeluguPCMConverter(rate:ring.sampleRate)
        var segmenter = TeluguUtteranceSegmenter()
        while !Task.isCancelled && !cancellation.isCancelled {
            if ring.overflowed.load(ordering:.acquiring) { throw DictationFailure.overflow }
            let final = ring.ended.load(ordering:.sequentiallyConsistent)
            if final && ring.isWriting { try await Task.sleep(for:.milliseconds(1)); continue }
            let samples = ring.drain()
            let converted = try converter.convert(samples,final:final)
            let utterances = segmenter.append(converted,final:final)
            statistics.record(sourceFrames:samples.count,converted:converted,utterances:utterances.count)
            for utterance in utterances {
                switch stream.yield(utterance) {
                case .enqueued: break
                case .dropped: throw DictationFailure.overflow
                case .terminated: return
                @unknown default: throw DictationFailure.overflow
                }
            }
            if final {
                if let failure = statistics.emptyCaptureFailure { throw failure }
                stream.finish(); return
            }
            try await Task.sleep(for:.milliseconds(20))
        }
        throw CancellationError()
    } catch {
        stream.finish(throwing:error)
        if !cancellation.isCancelled && !(error is CancellationError) { onFailure(error as? DictationFailure ?? .audioUnavailable) }
    }
}


/// AVAudioNodeTapBlock is explicitly non-Sendable in the SDK and may run on an audio thread.
/// Construct callbacks outside MainActor so Swift never inserts a main-executor assertion.
enum TeluguNativeCallbacks {
    nonisolated static func tap(ring: TeluguAudioRing, meter: AudioLevelMailbox, speaker: TeluguAudioRing? = nil) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, time in meter.append(buffer); ring.append(buffer,at:time); speaker?.append(buffer,at:time) }
    }
    nonisolated static func configurationChanged(deliver: @escaping @MainActor @Sendable () -> Void) -> @Sendable (Notification) -> Void {
        { _ in Task { @MainActor in deliver() } }
    }
}
