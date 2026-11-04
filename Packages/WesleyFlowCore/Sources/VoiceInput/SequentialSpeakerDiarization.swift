import Domain

/// Assigns clusters to already segmented, sequential speech. A segment containing
/// multiple voices needs a separate change detector before it reaches this actor.
public actor SequentialSpeakerDiarization: SpeakerDiarizationService {
    private let engine: any SpeakerEmbeddingEngine
    private let identification: SpeakerIdentification
    private let clustering: SpeakerCalibration
    private var clusters: [[Float]] = []
    private var lastEnd: Int64 = 0
    private var generation = 0
    private var processing = false

    public init(engine: any SpeakerEmbeddingEngine, identification: SpeakerIdentification,
                clustering: SpeakerCalibration) throws {
        guard engine.model == clustering.model, identification.model == clustering.model else {
            throw SpeakerRecognitionError.invalidCalibration
        }
        self.engine = engine
        self.identification = identification
        self.clustering = clustering
    }

    public func processSegment(_ segment: SpeakerAudioSegment) async throws -> SpeakerInterval? {
        guard segment.isUsable, segment.startFrame >= lastEnd else { return nil }
        guard !processing else { throw SpeakerRecognitionError.sampleInProgress }
        processing = true
        defer { processing = false }
        let token = generation
        try Task.checkCancellation()
        let embedding = try await engine.extractEmbedding(from: segment)
        let vector = try SpeakerMatching.normalize(embedding, dimension: clustering.model.dimension)
        let match = try await identification.identifyEmbedding(vector)
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }

        let ranked = clusters.enumerated().map { index, template in
            let score = zip(vector, template).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
            return (id: index + 1, score: min(1, max(-1, score)))
        }.sorted { $0.score > $1.score }

        // Keep the first clean template as an anchor to avoid drift after a bad match.
        let clusterID: Int?
        if let best = ranked.first, best.score >= clustering.acceptance {
            clusterID = ranked.count == 1 || best.score - ranked[1].score >= clustering.minimumMargin
                ? best.id : nil
        } else if clusters.count < 32 {
            clusters.append(vector)
            clusterID = clusters.count
        } else {
            clusterID = nil
        }
        let end = segment.startFrame + Int64(segment.samples.count)
        lastEnd = end
        return .init(frames: segment.startFrame..<end, clusterID: clusterID, match: match)
    }

    public func resetSession() {
        generation += 1
        clusters.removeAll()
        lastEnd = 0
    }
}
