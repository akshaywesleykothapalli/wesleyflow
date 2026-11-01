import Foundation
import CryptoKit
import Synchronization
import Domain
import whisper

public final class SpeechCancellation: Sendable {
    private let flag = Atomic<Bool>(false)
    public init() {}
    public func cancel() { flag.store(true, ordering:.releasing) }
    public var isCancelled: Bool { flag.load(ordering:.acquiring) }
}
/// Replaceable ASR boundary: native-script output, exactly 16 kHz mono Float32 PCM.
public protocol LocalPCMRecognizing: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float], language: TeluguRecognitionLanguage, cancellation: SpeechCancellation) async throws -> String
}
public enum WhisperSmallModel {
    public static let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    public static let bytes = 487_601_967
    public static let sha256 = "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
    public static var installedURL: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("WesleyFlow/Models/ggml-small.bin")
    }
    public static func verify(_ url: URL) throws {
        guard (try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) == bytes else { throw DictationFailure.assetsMissing }
        let handle = try FileHandle(forReadingFrom:url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount:1_048_576), !data.isEmpty { hash.update(data:data) }
        guard hash.finalize().map({ String(format:"%02x",$0) }).joined() == sha256 else { throw DictationFailure.assetsMissing }
    }
}
/// Only this actor accesses the persistent context; whisper_full is synchronous and has no actor reentrancy.
public actor LocalWhisperRecognizer: LocalPCMRecognizing {
    // The wrapper only crosses the actor's deinitializer boundary. No pointers escape to clients.
    private final class Context: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { whisper_free(pointer) }
    }
    private var context: Context?
    private let model: URL
    public init(model: URL = WhisperSmallModel.installedURL) { self.model = model }
    public func prepare() throws {
        if context != nil { return }
        do { try WhisperSmallModel.verify(model) } catch { throw DictationFailure.assetsMissing }
        try Task.checkCancellation()
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let pointer = model.path.withCString({ whisper_init_from_file_with_params($0,params) }) else { throw DictationFailure.unavailable }
        context = Context(pointer)
    }
    public func transcribe(_ samples: [Float], language: TeluguRecognitionLanguage, cancellation: SpeechCancellation) throws -> String {
        guard !cancellation.isCancelled, !Task.isCancelled else { throw CancellationError() }
        guard samples.count >= 3_200, samples.count <= 400_000, samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { throw DictationFailure.audioUnavailable }
        try prepare()
        guard let context else { throw DictationFailure.unavailable }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(min(4,max(1,ProcessInfo.processInfo.activeProcessorCount - 1)))
        params.translate = false; params.no_context = true; params.no_timestamps = true
        params.print_progress = false; params.print_realtime = false; params.print_timestamps = false; params.print_special = false
        // detect_language=true would return after language detection without transcription.
        params.detect_language = false
        params.temperature = 0; params.temperature_inc = 0
        params.abort_callback = { opaque in
            guard let opaque else { return false }
            return Unmanaged<SpeechCancellation>.fromOpaque(opaque).takeUnretainedValue().isCancelled
        }
        params.abort_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()
        let result = withExtendedLifetime(cancellation) {
            language.whisperLanguage.withCString { languagePointer in
                params.language = languagePointer
                return samples.withUnsafeBufferPointer { whisper_full(context.pointer,params,$0.baseAddress,Int32($0.count)) }
            }
        }
        guard !cancellation.isCancelled, !Task.isCancelled else { throw CancellationError() }
        guard result == 0 else { throw DictationFailure.recognitionFailed }
        var text = ""
        for index in 0..<whisper_full_n_segments(context.pointer) {
            // Do not publish high no-speech segments or raw audio in diagnostics.
            guard whisper_full_get_segment_no_speech_prob(context.pointer,index) < 0.6 else { continue }
            if let value = whisper_full_get_segment_text(context.pointer,index) { text += String(cString:value) }
            guard text.utf8.count <= DictationText.maximumBytes else { throw DictationFailure.overflow }
        }
        guard text.unicodeScalars.contains(where:{ CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) else { return "" }
        return text.trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
