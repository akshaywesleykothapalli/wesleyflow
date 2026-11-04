import CSpeakerRuntime
import CryptoKit
import Domain
import Foundation

public actor BundledSpeakerEngine: SpeakerEmbeddingEngine {
    public nonisolated let model = SpeakerModel(
        identifier: "wespeaker-voxceleb-resnet34-70503b6",
        artifactSHA256: "5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94",
        dimension: 256
    )
    public enum Failure: Error, Equatable { case missingModel, invalidModel, runtimeUnavailable, inferenceFailed }

    private final class Context {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { WFSpeakerClose(pointer) }
    }

    private let artifact: URL
    private let library: URL?
    private var context: Context?

    public init(artifact: URL, frameworks: URL? = Bundle.main.privateFrameworksURL) {
        self.artifact = artifact
        library = frameworks?.appendingPathComponent("libsherpa-onnx-c-api.dylib")
    }

    public func loadModel() throws {
        guard context == nil else { return }
        try Task.checkCancellation()
        guard let library, FileManager.default.isReadableFile(atPath: library.path) else { throw Failure.runtimeUnavailable }
        guard let source = try? FileHandle(forReadingFrom: artifact) else { throw Failure.missingModel }
        defer { try? source.close() }
        guard let data = try source.read(upToCount: 28_000_001), data.count <= 28_000_000,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == model.artifactSHA256 else {
            throw Failure.invalidModel
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let verified = directory.appendingPathComponent("speaker.onnx")
        try data.write(to: verified)
        guard let pointer = WFSpeakerOpen(library.path, verified.path, Int32(model.dimension)) else {
            throw Failure.runtimeUnavailable
        }
        let loaded = Context(pointer)
        try Task.checkCancellation()
        context = loaded
    }

    public func extractEmbedding(from audio: SpeakerAudioSegment) throws -> [Float] {
        try Task.checkCancellation()
        guard audio.isUsable else { throw SpeakerRecognitionError.insufficientAudio }
        guard let context else { throw Failure.runtimeUnavailable }
        var output = Array(repeating: Float.zero, count: model.dimension)
        guard WFSpeakerEmbed(context.pointer, audio.samples, Int32(audio.samples.count), &output, Int32(output.count)) != 0 else {
            throw Failure.inferenceFailed
        }
        try Task.checkCancellation()
        return try SpeakerMatching.normalize(output, dimension: model.dimension)
    }

    public func unloadModel() { context = nil }
}
