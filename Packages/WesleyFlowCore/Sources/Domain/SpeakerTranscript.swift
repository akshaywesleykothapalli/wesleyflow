import Foundation

/// All ranges use one session's 16 kHz frame clock and have exclusive upper bounds.
public struct SpeakerInterval: Sendable, Equatable {
    public let frames: Range<Int64>
    public let clusterID: Int?
    public let match: SpeakerMatch

    public init(frames: Range<Int64>, clusterID: Int?, match: SpeakerMatch) {
        self.frames = frames
        self.clusterID = clusterID
        self.match = match
    }
}

public struct SpeakerTranscriptFragment: Sendable, Equatable {
    public let text: String
    public let frames: Range<Int64>?

    public init(text: String, frames: Range<Int64>?) {
        self.text = text
        self.frames = frames
    }
}

public enum SpeakerTranscriptMerger {
    /// Call again with updated intervals when inference completes. Input order and text are preserved.
    /// A label needs a strict majority of a fragment; boundary-spanning fragments can stay unlabeled.
    public static func merge(_ transcript: [SpeakerTranscriptFragment], intervals: [SpeakerInterval])
        -> [(fragment: SpeakerTranscriptFragment, speaker: SpeakerInterval?)] {
        transcript.map { fragment in
            guard let frames = fragment.frames, frames.lowerBound >= 0, !frames.isEmpty else {
                return (fragment, nil)
            }
            var majority: SpeakerInterval?
            for interval in intervals {
                let start = max(frames.lowerBound, interval.frames.lowerBound)
                let end = min(frames.upperBound, interval.frames.upperBound)
                guard end > start, end - start > frames.count / 2 else { continue }
                guard majority == nil else { return (fragment, nil) }
                majority = interval
            }
            return (fragment, majority)
        }
    }
}

public protocol SpeakerDiarizationService: Sendable {
    func processSegment(_ segment: SpeakerAudioSegment) async throws -> SpeakerInterval?
    func resetSession() async
}
