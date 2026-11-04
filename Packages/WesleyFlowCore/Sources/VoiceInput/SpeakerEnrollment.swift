import Domain
import Foundation

public actor SpeakerEnrollment {
    private struct Session {
        let token = UUID()
        let name: String
        let replacing: SpeakerProfile?
        var embeddings: [[Float]] = []
    }

    private let engine: any SpeakerEmbeddingEngine
    private let repository: any SpeakerProfileRepository
    private var session: Session?
    private var busy = false
    private var restoreOnSaveFailure = false

    public init(engine: any SpeakerEmbeddingEngine, repository: any SpeakerProfileRepository) {
        self.engine = engine
        self.repository = repository
    }

    /// The caller must obtain explicit consent before starting.
    public func startEnrollment(displayName: String, replacing: SpeakerProfile? = nil) throws {
        guard session == nil, !busy else { throw SpeakerRecognitionError.enrollmentActive }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeakerProfile.validName(name) else { throw SpeakerRecognitionError.invalidName }
        session = Session(name: name, replacing: replacing)
    }

    public func addEnrollmentSample(_ audio: SpeakerAudioSegment) async throws {
        guard let current = session else { throw SpeakerRecognitionError.noEnrollment }
        guard !busy else { throw SpeakerRecognitionError.sampleInProgress }
        guard current.embeddings.count < 5 else { throw SpeakerRecognitionError.sampleLimit }
        guard audio.isUsable else { throw SpeakerRecognitionError.insufficientAudio }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        let embedding = try await engine.extractEmbedding(from: audio)
        try Task.checkCancellation()
        guard session?.token == current.token else { throw CancellationError() }
        session?.embeddings.append(try SpeakerMatching.normalize(embedding, dimension: engine.model.dimension))
    }

    public func finishEnrollment() async throws -> SpeakerProfile {
        guard let current = session else { throw SpeakerRecognitionError.noEnrollment }
        guard !busy else { throw SpeakerRecognitionError.sampleInProgress }
        guard current.embeddings.count >= 3 else { throw SpeakerRecognitionError.insufficientAudio }
        try Task.checkCancellation()
        var centroid = [Float](repeating: 0, count: engine.model.dimension)
        for embedding in current.embeddings {
            for index in centroid.indices { centroid[index] += embedding[index] }
        }
        let now = Date()
        let profile = try SpeakerProfile(id: current.replacing?.id ?? UUID(),
                                         displayName: current.name, model: engine.model,
                                         embedding: centroid, createdAt: current.replacing?.createdAt ?? now,
                                         modifiedAt: now, sampleCount: current.embeddings.count,
                                         minimumSimilarity: SpeakerMatching.enrollmentCutoff(current.embeddings, dimension: engine.model.dimension))
        // Saving is the commit point. A cancellation during the write cannot undo it.
        session = nil
        restoreOnSaveFailure = true
        busy = true
        defer { busy = false }
        do {
            try await repository.saveProfile(profile)
            return profile
        } catch {
            if restoreOnSaveFailure { session = current }
            throw error
        }
    }

    public func cancelEnrollment() {
        restoreOnSaveFailure = false
        session = nil
    }
}

public struct SpeakerIdentification: Sendable {
    private let engine: any SpeakerEmbeddingEngine
    private let repository: any SpeakerProfileRepository
    private let calibration: SpeakerCalibration
    public var model: SpeakerModel { calibration.model }

    public init(engine: any SpeakerEmbeddingEngine, repository: any SpeakerProfileRepository,
                calibration: SpeakerCalibration) throws {
        guard engine.model == calibration.model else { throw SpeakerRecognitionError.invalidCalibration }
        self.engine = engine
        self.repository = repository
        self.calibration = calibration
    }

    public func identify(_ audio: SpeakerAudioSegment) async throws -> SpeakerMatch {
        guard audio.isUsable else { return .insufficientAudio }
        try Task.checkCancellation()
        let embedding = try await engine.extractEmbedding(from: audio)
        return try await identifyEmbedding(embedding)
    }

    public func identifyEmbedding(_ embedding: [Float]) async throws -> SpeakerMatch {
        try Task.checkCancellation()
        let profiles = try await repository.getProfiles()
        try Task.checkCancellation()
        return try SpeakerMatching.identify(embedding, profiles: profiles, calibration: calibration)
    }
}
