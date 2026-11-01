import Foundation
import CryptoKit
import Synchronization
import Darwin
import Domain
import whisper

public final class SpeechCancellation: Sendable {
    private let flag = Atomic<Bool>(false)
    public init() {}
    public func cancel() { flag.store(true, ordering:.releasing) }
    public var isCancelled: Bool { flag.load(ordering:.acquiring) }
}
public struct LocalRecognitionReport: Sendable {
    public var summary: String
    public var language: String?
    public var rejection: String?
    public init(summary:String,language:String? = nil,rejection:String? = nil) {
        self.summary = summary; self.language = language; self.rejection = rejection
    }
}
/// Replaceable ASR boundary: native-script/Latin output, 16 kHz mono Float32 PCM.
public protocol LocalPCMRecognizing: Sendable {
    func prepare() async throws
    func prepare(language:TeluguRecognitionLanguage) async throws
    func transcribe(_ samples: [Float], language: TeluguRecognitionLanguage, cancellation: SpeechCancellation) async throws -> String
    func recognitionReport() async -> LocalRecognitionReport
}
public extension LocalPCMRecognizing {
    func prepare(language:TeluguRecognitionLanguage) async throws { try await prepare() }
    func recognitionReport() async -> LocalRecognitionReport { .init(summary:"asrMetadata=unavailable") }
}
public enum WhisperModelArtifact: String, Sendable {
    case multilingualSmall, teluguSmallQ8
    public var filename:String { self == .multilingualSmall ? "ggml-small.bin" : "ggml-telugu-small-q8_0.bin" }
    public var bytes:Int { self == .multilingualSmall ? 487_601_967 : 264_464_607 }
    public var sha256:String { self == .multilingualSmall ? "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b" : "355cef20a0d433ca6ffae35d414c817e0aeecfce21b934d68203efee1e72dcba" }
    public var revision:String { self == .multilingualSmall ? "5359861c739e955e79d9a303bcbc70fb988958b1" : "bd01ed7929666163b173b826e56d6dcdf8afb8ce" }
    public var installedURL:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("WesleyFlow/Models/" + filename)
    }
    public func verify(_ url:URL) throws {
        guard (try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) == bytes else { throw DictationFailure.assetsMissing }
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount:1_048_576), !data.isEmpty { hash.update(data:data) }
        guard hash.finalize().map({ String(format:"%02x",$0) }).joined() == sha256 else { throw DictationFailure.assetsMissing }
    }
}
public enum WhisperSmallModel {
    public static let revision = WhisperModelArtifact.multilingualSmall.revision
    public static let bytes = WhisperModelArtifact.multilingualSmall.bytes
    public static let sha256 = WhisperModelArtifact.multilingualSmall.sha256
    public static var installedURL:URL { WhisperModelArtifact.multilingualSmall.installedURL }
    public static func verify(_ url:URL) throws { try WhisperModelArtifact.multilingualSmall.verify(url) }
}
public enum WhisperTeluguSmallModel {
    public static var installedURL:URL { WhisperModelArtifact.teluguSmallQ8.installedURL }
}
/// Each actor serially owns one persistent context. No C pointer escapes to clients.
public actor LocalWhisperRecognizer: LocalPCMRecognizing {
    private final class Context: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { whisper_free(pointer) }
    }
    private var context:Context?
    private let model:URL, artifact:WhisperModelArtifact
    private var report = LocalRecognitionReport(summary:"decode=notStarted")
    public init(model:URL = WhisperSmallModel.installedURL,artifact:WhisperModelArtifact = .multilingualSmall) {
        self.model = model; self.artifact = artifact
    }
    public func recognitionReport() async -> LocalRecognitionReport { report }
    public func prepare() throws {
        if context != nil { return }
        do { try artifact.verify(model) } catch { throw DictationFailure.assetsMissing }
        try Task.checkCancellation()
        var params = whisper_context_default_params(); params.use_gpu = true
        guard let pointer = model.path.withCString({ whisper_init_from_file_with_params($0,params) }) else { throw DictationFailure.unavailable }
        let loaded = Context(pointer)
        guard whisper_is_multilingual(pointer) != 0 else { throw DictationFailure.unavailable }
        context = loaded
    }
    public func transcribe(_ samples:[Float],language:TeluguRecognitionLanguage,cancellation:SpeechCancellation) throws -> String {
        guard !cancellation.isCancelled, !Task.isCancelled else { throw CancellationError() }
        report = .init(summary:"model=\(artifact.rawValue) requested=\(language.whisperLanguage) decode=starting")
        guard samples.count >= 3200, samples.count <= 400_000, samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { throw DictationFailure.audioUnavailable }
        try prepare(); guard let context else { throw DictationFailure.unavailable }
        // The tuned model's automatic language head was unreliable in real-audio tests.
        guard artifact != .teluguSmallQ8 || language == .teluguOnly else { throw DictationFailure.unavailable }
        let ranges = artifact == .teluguSmallQ8 ? WhisperAudioWindows.ranges(for:samples) : [samples.startIndex..<samples.endIndex]
        var output = ""
        let begin = ContinuousClock.now
        for (window,range) in ranges.enumerated() {
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.n_threads = Int32(min(4,max(1,ProcessInfo.processInfo.activeProcessorCount - 1)))
            params.translate = false; params.no_context = true; params.no_timestamps = true
            params.print_progress = false; params.print_realtime = false; params.print_timestamps = false; params.print_special = false
            params.detect_language = false; params.temperature = 0; params.temperature_inc = 0
            params.abort_callback = { opaque in
                guard let opaque else { return false }
                return Unmanaged<SpeechCancellation>.fromOpaque(opaque).takeUnretainedValue().isCancelled
            }
            params.abort_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()
            let status = withExtendedLifetime(cancellation) {
                language.whisperLanguage.withCString { pointer in
                    params.language = pointer
                    return samples.withUnsafeBufferPointer {
                        whisper_full(context.pointer,params,$0.baseAddress!.advanced(by:range.lowerBound),Int32(range.count))
                    }
                }
            }
            guard !cancellation.isCancelled, !Task.isCancelled else { throw CancellationError() }
            guard status == 0 else { throw DictationFailure.recognitionFailed }
            let languageID = whisper_full_lang_id(context.pointer)
            let actualLanguage = languageID >= 0 ? whisper_lang_str(languageID).map { String(cString:$0) } : nil
            let base = "model=\(artifact.rawValue) requested=\(language.whisperLanguage) decoderLanguage=\(actualLanguage ?? "unknown") samples=\(samples.count) window=\(window + 1)/\(ranges.count) prompt=none decoder=greedy temperature=0"
            report = .init(summary:base,language:actualLanguage)
            var bytes = Data()
            for i in 0..<whisper_full_n_segments(context.pointer) {
                guard whisper_full_get_segment_no_speech_prob(context.pointer,i) < 0.6 else { continue }
                let count = whisper_full_n_tokens(context.pointer,i)
                if count >= whisper_n_text_ctx(context.pointer)/2 - 4,
                   count > 0, whisper_full_get_token_id(context.pointer,i,count - 1) != whisper_token_eot(context.pointer) {
                    report = .init(summary:base + " rejection=tokenBudget",language:actualLanguage,rejection:"tokenBudget")
                    throw DictationFailure.recognitionFailed
                }
                if let pointer = whisper_full_get_segment_text(context.pointer,i) {
                    bytes.append(UnsafeRawPointer(pointer).assumingMemoryBound(to:UInt8.self),count:strlen(pointer))
                }
                guard bytes.count <= DictationText.maximumBytes else { throw DictationFailure.overflow }
            }
            guard let text = String(data:bytes,encoding:.utf8) else {
                report = .init(summary:base + " rejection=invalidUTF8",language:actualLanguage,rejection:"invalidUTF8")
                throw DictationFailure.recognitionFailed
            }
            let counts = TeluguRecognitionQuality.scriptCounts(text)
            if let failure = TeluguRecognitionQuality.failure(in:text) {
                report = .init(summary:base + " " + counts + " rejection=\(failure)",language:actualLanguage,rejection:String(describing:failure))
                throw failure
            }
            report = .init(summary:base + " " + counts + " rejection=none elapsed=\(begin.duration(to:.now))",language:actualLanguage)
            if text.unicodeScalars.contains(where:{ CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) {
                output += (output.isEmpty ? "" : " ") + text.trimmingCharacters(in:.whitespacesAndNewlines)
            }
            guard output.utf8.count <= DictationText.maximumBytes else { throw DictationFailure.overflow }
        }
        if let failure = TeluguRecognitionQuality.failure(in:output) { throw failure }
        return output
    }
}

/// Auto keeps generic multilingual Small for English; Telugu uses a specialised Small context.
/// At most one generic candidate and one Telugu candidate per utterance; no prompt or LLM retries.
public actor TeluguWhisperPipeline: LocalPCMRecognizing {
    private let multilingual:any LocalPCMRecognizing, telugu:any LocalPCMRecognizing
    private var report = LocalRecognitionReport(summary:"route=notStarted")
    public init(multilingual:any LocalPCMRecognizing = LocalWhisperRecognizer(),
                telugu:any LocalPCMRecognizing = LocalWhisperRecognizer(model:WhisperTeluguSmallModel.installedURL,artifact:.teluguSmallQ8)) {
        self.multilingual = multilingual; self.telugu = telugu
    }
    public func prepare() async throws { try await telugu.prepare() }
    public func prepare(language:TeluguRecognitionLanguage) async throws {
        try await telugu.prepare()
        if language == .automatic { try await multilingual.prepare() }
    }
    public func recognitionReport() async -> LocalRecognitionReport { report }
    public func transcribe(_ samples:[Float],language:TeluguRecognitionLanguage,cancellation:SpeechCancellation) async throws -> String {
        guard !cancellation.isCancelled, !Task.isCancelled else { throw CancellationError() }
        var genericReport = LocalRecognitionReport(summary:"generic=notUsed")
        if language == .automatic {
            let result:Result<String,any Error>
            do { result = .success(try await multilingual.transcribe(samples,language:.automatic,cancellation:cancellation)) }
            catch { result = .failure(error) }
            genericReport = await multilingual.recognitionReport()
            guard !cancellation.isCancelled, !Task.isCancelled else { throw CancellationError() }
            switch result {
            case .success(let text):
                if text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    report = genericReport; return ""
                }
                if genericReport.language != "te", !text.unicodeScalars.contains(where:{ (0x0C00...0x0C7F).contains($0.value) }),
                   TeluguRecognitionQuality.failure(in:text) == nil {
                    report = .init(summary:"asrRevision=te-quality-r2 route=multilingual [" + genericReport.summary + "]",language:genericReport.language)
                    return text
                }
            case .failure(let error):
                guard error as? DictationFailure == .unsupportedRecognitionScript || error as? DictationFailure == .repetitiveRecognition || (error as? DictationFailure == .recognitionFailed && genericReport.rejection != nil) else {
                    report = genericReport; throw error
                }
            }
        }
        do {
            let text = try await telugu.transcribe(samples,language:.teluguOnly,cancellation:cancellation)
            let tunedReport = await telugu.recognitionReport()
            guard !cancellation.isCancelled, !Task.isCancelled else { throw CancellationError() }
            if let failure = TeluguRecognitionQuality.failure(in:text) { throw failure }
            report = .init(summary:"asrRevision=te-quality-r2 route=teluguSpecialist generic=[" + genericReport.summary + "] specialist=[" + tunedReport.summary + "]",language:tunedReport.language)
            return text
        } catch {
            let rejected = await telugu.recognitionReport()
            report = .init(summary:"asrRevision=te-quality-r2 route=teluguSpecialist generic=[" + genericReport.summary + "] specialist=[" + rejected.summary + "]",language:rejected.language,rejection:rejected.rejection)
            throw error
        }
    }
}
