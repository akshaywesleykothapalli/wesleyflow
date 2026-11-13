import Foundation

public enum SpeakerRecognitionError: Error, Equatable {
    case invalidEmbedding, invalidModel, invalidCalibration, invalidName, invalidProfile
    case insufficientAudio, enrollmentActive, noEnrollment, sampleInProgress, sampleLimit
}

public struct SpeakerModel: Codable, Sendable, Equatable {
    public let identifier: String
    public let artifactSHA256: String
    public let dimension: Int

    public init(identifier: String, artifactSHA256: String, dimension: Int) {
        self.identifier = identifier
        self.artifactSHA256 = artifactSHA256
        self.dimension = dimension
    }

    public var isValid: Bool {
        !identifier.isEmpty && identifier.utf8.count <= 128 && (2...4096).contains(dimension)
            && artifactSHA256.utf8.count == 64
            && artifactSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Session-relative sample positions in the speaker model's 16 kHz timebase.
public struct SpeakerAudioSegment: Sendable {
    public static let sampleRate = 16_000
    public let startFrame: Int64
    public let samples: [Float]

    public init(startFrame: Int64, samples: [Float]) {
        self.startFrame = startFrame
        self.samples = samples
    }

    public var isUsable: Bool {
        guard startFrame >= 0, (16_000...240_000).contains(samples.count),
              startFrame <= Int64.max - Int64(samples.count) else { return false }
        var clipped = 0
        var active = 0
        for sample in samples {
            guard sample.isFinite, abs(sample) <= 1 else { return false }
            if abs(sample) >= 0.99 { clipped += 1 }
            if abs(sample) >= 0.01 { active += 1 }
        }
        return clipped * 100 < samples.count && active >= 1_600
    }
}

public protocol SpeakerEmbeddingEngine: Sendable {
    var model: SpeakerModel { get }
    func loadModel() async throws
    func extractEmbedding(from audio: SpeakerAudioSegment) async throws -> [Float]
    func unloadModel() async
}

public struct SpeakerProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let model: SpeakerModel
    public let embedding: [Float]
    public let createdAt: Date
    public let modifiedAt: Date
    public let sampleCount: Int
    public let minimumSimilarity: Double?

    public init(id: UUID = UUID(), displayName: String, model: SpeakerModel, embedding: [Float],
                createdAt: Date, modifiedAt: Date, sampleCount: Int, minimumSimilarity: Double? = nil) throws {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validName(self.displayName) else { throw SpeakerRecognitionError.invalidName }
        guard model.isValid else { throw SpeakerRecognitionError.invalidModel }
        guard (3...5).contains(sampleCount), createdAt <= modifiedAt else {
            throw SpeakerRecognitionError.invalidProfile
        }
        self.model = model
        self.embedding = try SpeakerMatching.normalize(embedding, dimension: model.dimension)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sampleCount = sampleCount
        guard minimumSimilarity.map({ (0...1).contains($0) }) ?? true else { throw SpeakerRecognitionError.invalidCalibration }
        self.minimumSimilarity = minimumSimilarity
    }

    public static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.utf8.count <= 160
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    public func validated() throws -> Self {
        try Self(id: id, displayName: displayName, model: model, embedding: embedding,
                 createdAt: createdAt, modifiedAt: modifiedAt, sampleCount: sampleCount, minimumSimilarity: minimumSimilarity)
    }
}

public protocol SpeakerProfileRepository: Sendable {
    func saveProfile(_ profile: SpeakerProfile) async throws
    func getProfiles() async throws -> [SpeakerProfile]
    func getProfile(id: UUID) async throws -> SpeakerProfile?
    func deleteProfile(id: UUID) async throws
    func deleteAllProfiles() async throws
}

public enum SpeakerMatch: Sendable, Equatable {
    case known(id: UUID, displayName: String, similarity: Double)
    case unknown, insufficientAudio, ambiguous
}

public struct SpeakerCalibration: Sendable {
    public let model: SpeakerModel
    public let acceptance: Double
    public let minimumMargin: Double

    public init(model: SpeakerModel, acceptance: Double, minimumMargin: Double) throws {
        guard model.isValid, (0...1).contains(acceptance), minimumMargin > 0,
              minimumMargin <= 2 else { throw SpeakerRecognitionError.invalidCalibration }
        self.model = model
        self.acceptance = acceptance
        self.minimumMargin = minimumMargin
    }
}

public enum SpeakerMatching {
    public static func normalize(_ vector: [Float], dimension: Int) throws -> [Float] {
        guard vector.count == dimension, vector.allSatisfy(\.isFinite) else {
            throw SpeakerRecognitionError.invalidEmbedding
        }
        let norm = sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard norm > 0 else { throw SpeakerRecognitionError.invalidEmbedding }
        return vector.map { Float(Double($0) / norm) }
    }

    public static func identify(_ embedding: [Float], profiles: [SpeakerProfile],
                                calibration: SpeakerCalibration) throws -> SpeakerMatch {
        let query = try normalize(embedding, dimension: calibration.model.dimension)
        let scores = profiles.compactMap { profile -> (SpeakerProfile, Double)? in
            guard profile.model == calibration.model,
                  let vector = try? normalize(profile.embedding, dimension: query.count) else { return nil }
            let dot = zip(query, vector).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
            return (profile, min(1, max(-1, dot)))
        }.sorted { $0.1 > $1.1 }

        guard let (best, score) = scores.first, score >= calibration.acceptance else { return .unknown }
        if scores.count > 1, score - scores[1].1 < calibration.minimumMargin { return .ambiguous }
        return .known(id: best.id, displayName: best.displayName, similarity: score)
    }
}

public extension SpeakerMatching {
    /// A provisional per-profile cutoff from the lower-quartile pairwise enrollment score.
    /// This requires real impostor trials before making any accuracy claim.
    static func enrollmentCutoff(_ samples: [[Float]], dimension: Int) throws -> Double {
        let vectors = try samples.map { try normalize($0, dimension: dimension) }
        guard (3...5).contains(vectors.count) else { throw SpeakerRecognitionError.invalidCalibration }
        let scores = vectors.indices.flatMap { first in
            vectors.indices.dropFirst(first + 1).map { second in cosine(vectors[first], vectors[second]) }
        }.sorted()
        let cutoff = scores[(scores.count - 1) / 4]
        guard cutoff > 0 else { throw SpeakerRecognitionError.invalidCalibration }
        return cutoff
    }

    static func enrolledLabel(_ embedding: [Float], model: SpeakerModel, profiles: [SpeakerProfile],
                              audioFrameCount: Int? = nil) throws -> DictationSpeakerLabel {
        let query = try normalize(embedding, dimension: model.dimension)
        let scores = profiles.compactMap { profile -> (profile: SpeakerProfile, score: Double, cutoff: Double)? in
            guard profile.model == model, let cutoff = profile.minimumSimilarity,
                  let template = try? normalize(profile.embedding, dimension: model.dimension) else { return nil }
            return (profile, cosine(query, template), cutoff)
        }
        let matches = scores.filter { $0.score >= $0.cutoff }
        if let match = matches.first {
            guard matches.count == 1 else { return .unknown }
            return .init(profileID: match.profile.id, name: match.profile.displayName)
        }

        // Short dictations can score below cutoffs derived from longer enrollment passages.
        // Only recover a high absolute score near its cutoff, with no close competitor.
        let rate = SpeakerAudioSegment.sampleRate
        guard let audioFrameCount, (rate...(4 * rate)).contains(audioFrameCount),
              let best = scores.max(by: { $0.score < $1.score }),
              best.score >= max(0.89, best.cutoff - 0.07),
              !scores.contains(where: { $0.profile.id != best.profile.id && best.score - $0.score < 0.08 }) else {
            return .unknown
        }
        return .init(profileID: best.profile.id, name: best.profile.displayName)
    }

    private static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        min(1, max(-1, zip(lhs, rhs).reduce(0) { $0 + Double($1.0) * Double($1.1) }))
    }
}

public struct DictationSpeakerLabel: Codable, Equatable, Sendable {
    public let profileID: UUID?
    public let name: String
    public static let unknown = Self(profileID: nil, name: "Unknown speaker")

    public init(profileID: UUID?, name: String) {
        self.profileID = profileID
        self.name = name
    }
}
