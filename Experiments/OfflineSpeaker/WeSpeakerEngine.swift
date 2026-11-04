import CSherpaOnnx
import CryptoKit
import Domain
import Foundation

enum WeSpeakerError: Error {
    case artifactMismatch, notLoaded, initializationFailed, inferenceFailed
}

/// Development adapter, isolated from the production app and its signing configuration.
actor WeSpeakerEngine: SpeakerEmbeddingEngine {
    nonisolated let model = SpeakerModel(
        identifier: "wespeaker-voxceleb-resnet34-70503b6",
        artifactSHA256: "5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94",
        dimension: 256
    )

    private final class Context {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { SherpaOnnxDestroySpeakerEmbeddingExtractor(pointer) }
    }

    private let artifact: URL
    private var context: Context?

    init(artifact: URL) {
        self.artifact = artifact
    }

    func loadModel() throws {
        if context != nil { return }
        try Task.checkCancellation()
        let source = try FileHandle(forReadingFrom: artifact)
        defer { try? source.close() }
        let maximumBytes = 28_000_000
        guard let bytes = try source.read(upToCount: maximumBytes + 1),
              bytes.count <= maximumBytes,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == model.artifactSHA256 else {
            throw WeSpeakerError.artifactMismatch
        }
        // Pass the exact verified bytes to the native loader through a private staging file.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let staged = folder.appendingPathComponent("speaker.onnx")
        try bytes.write(to: staged)
        let native = staged.path.withCString { path in
            "cpu".withCString { provider in
                var config = SherpaOnnxSpeakerEmbeddingExtractorConfig()
                config.model = path
                config.provider = provider
                config.num_threads = 1
                return SherpaOnnxCreateSpeakerEmbeddingExtractor(&config)
            }
        }
        guard let native else { throw WeSpeakerError.initializationFailed }
        let owner = Context(native)
        guard SherpaOnnxSpeakerEmbeddingExtractorDim(owner.pointer) == model.dimension else {
            throw WeSpeakerError.artifactMismatch
        }
        try Task.checkCancellation()
        context = owner
    }

    func extractEmbedding(from audio: SpeakerAudioSegment) throws -> [Float] {
        try Task.checkCancellation()
        guard audio.isUsable else { throw SpeakerRecognitionError.insufficientAudio }
        guard let context else { throw WeSpeakerError.notLoaded }
        guard let stream = SherpaOnnxSpeakerEmbeddingExtractorCreateStream(context.pointer) else {
            throw WeSpeakerError.inferenceFailed
        }
        defer { SherpaOnnxDestroyOnlineStream(stream) }
        audio.samples.withUnsafeBufferPointer {
            SherpaOnnxOnlineStreamAcceptWaveform(stream, Int32(SpeakerAudioSegment.sampleRate),
                                                 $0.baseAddress, Int32($0.count))
        }
        SherpaOnnxOnlineStreamInputFinished(stream)
        guard SherpaOnnxSpeakerEmbeddingExtractorIsReady(context.pointer, stream) != 0,
              let result = SherpaOnnxSpeakerEmbeddingExtractorComputeEmbedding(context.pointer, stream) else {
            throw WeSpeakerError.inferenceFailed
        }
        defer { SherpaOnnxSpeakerEmbeddingExtractorDestroyEmbedding(result) }
        try Task.checkCancellation()
        return try SpeakerMatching.normalize(Array(UnsafeBufferPointer(start: result, count: model.dimension)),
                                             dimension: model.dimension)
    }

    func unloadModel() { context = nil }
}
