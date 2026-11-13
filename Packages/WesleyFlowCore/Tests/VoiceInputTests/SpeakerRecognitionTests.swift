import AVFoundation
import Domain
import Foundation
import Testing
@testable import VoiceInput

private let model = SpeakerModel(identifier: "fixture", artifactSHA256: String(repeating: "a", count: 64), dimension: 2)
private let usable = SpeakerAudioSegment(startFrame: 400, samples: Array(repeating: 0.1, count: 16_000))

private actor FixtureProfiles: SpeakerProfileRepository {
    var entries: [UUID: SpeakerProfile] = [:]
    func saveProfile(_ profile: SpeakerProfile) async throws { entries[profile.id] = profile }
    func getProfiles() async throws -> [SpeakerProfile] { Array(entries.values) }
    func getProfile(id: UUID) async throws -> SpeakerProfile? { entries[id] }
    func deleteProfile(id: UUID) async throws { entries[id] = nil }
    func deleteAllProfiles() async throws { entries.removeAll() }
}

private actor FixtureSpeakerEngine: SpeakerEmbeddingEngine {
    nonisolated let model: SpeakerModel
    private let suspend: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?

    init(model: SpeakerModel, suspend: Bool = false) {
        self.model = model
        self.suspend = suspend
    }
    func loadModel() async throws {}
    func unloadModel() async {}
    func extractEmbedding(from audio: SpeakerAudioSegment) async throws -> [Float] {
        if suspend {
            await withCheckedContinuation {
                pending = $0
                waiting?.resume()
                waiting = nil
            }
        }
        return audio.samples.first == 0.2 ? [0, 2] : [2, 0]
    }

    func waitForInference() async {
        if pending == nil { await withCheckedContinuation { waiting = $0 } }
    }

    func finishInference() {
        pending?.resume()
        pending = nil
    }
}

@Suite struct SpeakerRecognitionTests {
    @Test func audioQuality() {
        #expect(usable.isUsable)
        for samples: [Float] in [[], [0.1], Array(repeating: 0, count: 16_000),
                                 Array(repeating: 1, count: 16_000), Array(repeating: .nan, count: 16_000)] {
            #expect(!SpeakerAudioSegment(startFrame: 0, samples: samples).isUsable)
        }
        #expect(!SpeakerAudioSegment(startFrame: .max, samples: usable.samples).isUsable)
    }

    @Test func timedEnergyGatePreservesOffsetsAcrossBuffers() {
        var gate = TeluguUtteranceSegmenter()
        let silence = Array(repeating: Float.zero, count: 8_000)
        let speech = Array(repeating: Float(0.1), count: 16_000)
        #expect(gate.appendTimed(Array(silence.prefix(3_333))).isEmpty)
        let first = gate.appendTimed(Array(silence.dropFirst(3_333)) + speech + silence)
        let second = gate.appendTimed(silence + speech, final: true)
        #expect(first.map(\.startFrame) == [5_440])
        #expect(first.map { $0.samples.count } == [26_560])
        #expect(second.map(\.startFrame) == [37_440])
    }

    @Test func delayedIntervalsPreserveTranscriptAndLeaveBoundaryUnlabeled() {
        let fragments: [SpeakerTranscriptFragment] = [
            .init(text: "Hello", frames: 0..<80),
            .init(text: " there", frames: 80..<120),
            .init(text: " friend", frames: 120..<200),
            .init(text: ".", frames: nil)
        ]
        let first = SpeakerInterval(frames: 0..<100, clusterID: 1, match: .unknown)
        let second = SpeakerInterval(frames: 100..<200, clusterID: 2, match: .unknown)
        let provisional = SpeakerTranscriptMerger.merge(fragments, intervals: [second])
        let final = SpeakerTranscriptMerger.merge(fragments, intervals: [second, first])
        #expect(provisional.map { $0.speaker?.clusterID } == [nil, nil, 2, nil])
        #expect(final.map { $0.speaker?.clusterID } == [1, nil, 2, nil])
        #expect(final.map { $0.fragment } == fragments)
    }

    @Test func sequentialClustersSeparateUnknownSpeakersAndReset() async throws {
        let engine = FixtureSpeakerEngine(model: model)
        let repository = FixtureProfiles()
        let calibration = try SpeakerCalibration(model: model, acceptance: 0.8, minimumMargin: 0.1)
        let identification = try SpeakerIdentification(engine: engine, repository: repository, calibration: calibration)
        let diarization = try SequentialSpeakerDiarization(engine: engine, identification: identification,
                                                           clustering: calibration)
        let a = try await diarization.processSegment(usable)
        let b = try await diarization.processSegment(.init(startFrame: 17_000,
                                                          samples: Array(repeating: 0.2, count: 16_000)))
        let aAgain = try await diarization.processSegment(.init(startFrame: 34_000, samples: usable.samples))
        #expect(a?.frames == 400..<16_400)
        #expect(a?.match == .unknown && b?.match == .unknown)
        #expect([a?.clusterID, b?.clusterID, aAgain?.clusterID] == [1, 2, 1])
        #expect(try await diarization.processSegment(usable) == nil)
        await diarization.resetSession()
        #expect(try await diarization.processSegment(usable)?.clusterID == 1)
    }

    @Test func profileSpecificCutoffLabelsOneCandidateAndRejectsAmbiguity() throws {
        let samples: [[Float]] = [[1, 0], [1, 0.1], [1, -0.1]]
        let cutoff = try SpeakerMatching.enrollmentCutoff(samples, dimension: 2)
        let now = Date()
        let first = try SpeakerProfile(displayName: "Alice", model: model, embedding: [1, 0],
                                       createdAt: now, modifiedAt: now, sampleCount: 3, minimumSimilarity: cutoff)
        let second = try SpeakerProfile(displayName: "Bob", model: model, embedding: [0, 1],
                                        createdAt: now, modifiedAt: now, sampleCount: 3, minimumSimilarity: cutoff)
        #expect(try SpeakerMatching.enrolledLabel([1, 0], model: model, profiles: [first, second]) ==
                .init(profileID: first.id, name: "Alice"))
        #expect(try SpeakerMatching.enrolledLabel([0, 1], model: model, profiles: [first, second]) ==
                .init(profileID: second.id, name: "Bob"))
        #expect(try SpeakerMatching.enrolledLabel([-1, 0], model: model, profiles: [first, second]) == .unknown)
        let ambiguous = try SpeakerProfile(displayName: "Other", model: model, embedding: [1, 0],
                                           createdAt: now, modifiedAt: now, sampleCount: 3, minimumSimilarity: cutoff)
        #expect(try SpeakerMatching.enrolledLabel([1, 0], model: model, profiles: [first, ambiguous]) == .unknown)
    }

    @Test func shortDictationRecoversOnlyStrongUnambiguousNearMatches() throws {
        let now = Date()
        let first = try SpeakerProfile(displayName: "Alice", model: model, embedding: [1, 0],
                                       createdAt: now, modifiedAt: now, sampleCount: 3, minimumSimilarity: 0.96)
        let neighbor = try SpeakerProfile(displayName: "Bob", model: model, embedding: [0.999, 0.04],
                                          createdAt: now, modifiedAt: now, sampleCount: 3, minimumSimilarity: 0.99)
        let candidate: [Float] = [0.91, sqrt(1 - 0.91 * 0.91)]
        let lowerScore: [Float] = [0.88, sqrt(1 - 0.88 * 0.88)]
        let rate = SpeakerAudioSegment.sampleRate
        #expect(try SpeakerMatching.enrolledLabel(candidate, model: model, profiles: [first],
                                                 audioFrameCount: 2 * rate) ==
                .init(profileID: first.id, name: first.displayName))
        #expect(try SpeakerMatching.enrolledLabel(candidate, model: model, profiles: [first],
                                                 audioFrameCount: 5 * rate) == .unknown)
        #expect(try SpeakerMatching.enrolledLabel(lowerScore, model: model, profiles: [first],
                                                 audioFrameCount: 2 * rate) == .unknown)
        #expect(try SpeakerMatching.enrolledLabel(candidate, model: model, profiles: [first, neighbor],
                                                 audioFrameCount: 2 * rate) == .unknown)
    }

    @Test func historySpeakerLabelRoundTripsAndOldPayloadDecodes() throws {
        let entry = DictationHistoryEntry(id: UUID().uuidString, timestamp: Date(), raw: "Test", cleaned: "Test",
            sourceApplication: nil, durationMilliseconds: 1_500, insertion: .init(.unsupportedTarget, .manualOnly),
            speaker: .init(profileID: UUID(), name: "Alice"))
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(DictationHistoryEntry.self, from: data) == entry)
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "speaker")
        let oldData = try JSONSerialization.data(withJSONObject: old)
        #expect(try JSONDecoder().decode(DictationHistoryEntry.self, from: oldData).speaker == nil)
    }

    @MainActor @Test func sideChannelConvertsWithoutMicrophone() async throws {
        let capture = SpeakerCapture()
        capture.armed = true
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                channels: 1, interleaved: false))
        let ring = try #require(capture.prepare(format: format))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        pcm.frameLength = 4_800
        let samples = try #require(pcm.floatChannelData?[0])
        for index in 0..<4_800 { samples[index] = sin(Float(index) * 0.025) * 0.2 }
        for index in 0..<15 {
            ring.append(pcm, at: AVAudioTime(sampleTime: Int64(index * 4_800), atRate: 48_000))
        }
        let task = try #require(capture.take())
        let converted = try #require(await task.value)
        #expect(converted.startFrame == 0)
        #expect(converted.samples.count == 24_000)
        #expect(!capture.armed)
    }

    @MainActor @Test func speakerCaptureKeepsBoundedAudioAndTrimsQuietEdges() async throws {
        let capture = SpeakerCapture()
        capture.armed = true
        let rate = Double(SpeakerAudioSegment.sampleRate)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                                channels: 1, interleaved: false))
        let ring = try #require(capture.prepare(format: format))
        let blockSize = 4_000
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(blockSize)))
        pcm.frameLength = AVAudioFrameCount(blockSize)
        let samples = try #require(pcm.floatChannelData?[0])
        // Two seconds of audio between pauses, with 16 seconds of input overall.
        for block in 0..<64 {
            let voiced = (8..<16).contains(block)
            for index in 0..<blockSize { samples[index] = voiced ? sin(Float(index) * 0.025) * 0.2 : 0 }
            ring.append(pcm, at: AVAudioTime(sampleTime: Int64(block * blockSize), atRate: rate))
        }
        let task = try #require(capture.take())
        let converted = try #require(await task.value)
        #expect(converted.startFrame == 32_000 - 2_560)
        #expect(converted.samples.count == 32_000 + 2 * 2_560)
    }

    @MainActor @Test func speakerCaptureRejectsDiscontinuousAudio() async throws {
        let capture = SpeakerCapture()
        capture.armed = true
        let rate = Double(SpeakerAudioSegment.sampleRate)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                                channels: 1, interleaved: false))
        let ring = try #require(capture.prepare(format: format))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        pcm.frameLength = 8_000
        let samples = try #require(pcm.floatChannelData?[0])
        for index in 0..<8_000 { samples[index] = sin(Float(index) * 0.025) * 0.2 }
        for start in [0, 8_000, 16_000, 32_000] {
            ring.append(pcm, at: AVAudioTime(sampleTime: Int64(start), atRate: rate))
        }
        let task = try #require(capture.take())
        #expect(await task.value == nil)
    }

    @Test func vectorValidation() throws {
        #expect(try SpeakerMatching.normalize([3, 4], dimension: 2) == [0.6, 0.8])
        for vector: [Float] in [[], [0, 0], [1, .infinity]] {
            #expect(throws: SpeakerRecognitionError.invalidEmbedding) {
                try SpeakerMatching.normalize(vector, dimension: 2)
            }
        }
    }

    @Test func enrollmentIdentificationAndDeletion() async throws {
        let engine = FixtureSpeakerEngine(model: model)
        let repository = FixtureProfiles()
        let service = SpeakerEnrollment(engine: engine, repository: repository)
        let calibration = try SpeakerCalibration(model: model, acceptance: 0.8, minimumMargin: 0.1)
        let identification = try SpeakerIdentification(engine: engine, repository: repository, calibration: calibration)
        try await service.startEnrollment(displayName: "  Alice  ")
        await #expect(throws: SpeakerRecognitionError.insufficientAudio) { try await service.finishEnrollment() }
        for _ in 0..<3 { try await service.addEnrollmentSample(usable) }
        let profile = try await service.finishEnrollment()
        #expect(profile.embedding == [1, 0])
        #expect(try await identification.identify(usable) == .known(id: profile.id, displayName: "Alice", similarity: 1))
        #expect(try await identification.identifyEmbedding([0, 1]) == .unknown)
        #expect(try await identification.identify(.init(startFrame: 0, samples: [])) == .insufficientAudio)

        try await service.startEnrollment(displayName: "Alicia", replacing: profile)
        for _ in 0..<3 { try await service.addEnrollmentSample(usable) }
        let replacement = try await service.finishEnrollment()
        #expect(replacement.id == profile.id)
        #expect(replacement.createdAt == profile.createdAt)
        #expect(try await repository.getProfiles().map(\.displayName) == ["Alicia"])
        try await repository.deleteProfile(id: profile.id)
        #expect(try await identification.identify(usable) == .unknown)
    }

    @Test func ambiguousAndIncompatibleProfiles() throws {
        let calibration = try SpeakerCalibration(model: model, acceptance: 0.8, minimumMargin: 0.1)
        let now = Date()
        let a = try SpeakerProfile(displayName: "Alice", model: model, embedding: [1, 0],
                                   createdAt: now, modifiedAt: now, sampleCount: 3)
        let b = try SpeakerProfile(displayName: "Bob", model: model, embedding: [1, 0.1],
                                   createdAt: now, modifiedAt: now, sampleCount: 3)
        let old = SpeakerModel(identifier: model.identifier, artifactSHA256: String(repeating: "b", count: 64), dimension: 2)
        let stale = try SpeakerProfile(displayName: "Old", model: old, embedding: [1, 0],
                                       createdAt: now, modifiedAt: now, sampleCount: 3)
        #expect(try SpeakerMatching.identify([1, 0], profiles: [a, b], calibration: calibration) == .ambiguous)
        #expect(try SpeakerMatching.identify([1, 0], profiles: [stale], calibration: calibration) == .unknown)
    }

    @Test func lateInferenceCannotEnrollAfterCancellation() async throws {
        let engine = FixtureSpeakerEngine(model: model, suspend: true)
        let repository = FixtureProfiles()
        let service = SpeakerEnrollment(engine: engine, repository: repository)
        try await service.startEnrollment(displayName: "Alice")
        let adding = Task { try await service.addEnrollmentSample(usable) }
        await engine.waitForInference()
        await service.cancelEnrollment()
        await engine.finishInference()
        await #expect(throws: CancellationError.self) { try await adding.value }
        #expect(try await repository.getProfiles().isEmpty)
        try await service.startEnrollment(displayName: "Bob")
    }
}
