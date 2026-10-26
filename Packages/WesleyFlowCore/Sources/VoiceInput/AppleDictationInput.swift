import Domain
import Foundation
import AVFoundation
import Speech
import os
import CoreMedia

/// The audio callback is not actor-isolated. A mutex owns its converter/request and closes
/// the producer before engine teardown; audio never crosses actors as an unowned tap buffer.
final class AudioIngress: Sendable {
    struct State {
        var open = true
        let converter: AVAudioConverter?
        let format: AVAudioFormat
        let modern: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation?
        let legacy: SFSpeechAudioBufferRecognitionRequest?
    }
    private let state: OSAllocatedUnfairLock<State>
    private let onFailure: @Sendable (DictationFailure) -> Void
    init(source: AVAudioFormat, target: AVAudioFormat,
         modern: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation? = nil,
         legacy: SFSpeechAudioBufferRecognitionRequest? = nil,
         onFailure: @escaping @Sendable (DictationFailure) -> Void = { _ in }) throws {
        self.onFailure = onFailure
        guard source.sampleRate.isFinite, target.sampleRate.isFinite,
              (8000...192000).contains(source.sampleRate), (8000...192000).contains(target.sampleRate),
              (1...8).contains(source.channelCount), (legacy != nil || target.channelCount == 1),
              modern == nil || target.commonFormat == .pcmFormatInt16 else { throw DictationFailure.audioUnavailable }
        let converter = AVAudioConverter(from: source, to: target)
        guard legacy != nil || converter != nil else { throw DictationFailure.audioUnavailable }
        // AVAudioConverter and the legacy ObjC request lack Sendable conformance.
        // All app-side mutable access is confined to this synchronous lock, including endAudio.
        // Formats are read-only; converted output buffers are fresh and never mutated after yield.
        state = OSAllocatedUnfairLock(uncheckedState: State(converter: converter, format: target, modern: modern, legacy: legacy))
    }
    func append(_ input: AVAudioPCMBuffer) {
        state.withLockUnchecked { s in
            guard s.open else { return }
            guard input.frameLength <= 8192, input.format == (s.converter?.inputFormat ?? s.format) else {
                s.open = false; s.modern?.finish(throwing: DictationFailure.audioUnavailable); onFailure(.audioUnavailable); return
            }
            if let legacy = s.legacy { legacy.append(input); return }
            guard let converter = s.converter, input.frameLength > 0 else { return }
            let frames = ceil(Double(input.frameLength) * s.format.sampleRate / input.format.sampleRate) + 32
            guard input.frameLength <= 8192, frames.isFinite, frames > 0, frames <= 65_536 else {
                s.open = false; s.modern?.finish(throwing: DictationFailure.overflow); onFailure(.overflow); return
            }
            let capacity = AVAudioFrameCount(frames)
            guard let output = AVAudioPCMBuffer(pcmFormat: s.format, frameCapacity: capacity) else {
                s.open = false; s.modern?.finish(throwing: DictationFailure.overflow); onFailure(.overflow); return
            }
            var supplied = false; var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return input
            }
            guard error == nil, status != .error else {
                s.open = false; s.modern?.finish(throwing: DictationFailure.audioUnavailable); onFailure(.audioUnavailable); return
            }
            guard output.frameLength > 0 else { return }
            // This newly allocated converted buffer belongs to AnalyzerInput, never reused by the tap.
            if let result = s.modern?.yield(AnalyzerInput(buffer: output)) {
                switch result {
                case .enqueued: break
                case .dropped: s.open = false; s.modern?.finish(throwing: DictationFailure.overflow); onFailure(.overflow)
                case .terminated: s.open = false; onFailure(.recognitionFailed)
                @unknown default: s.open = false; onFailure(.recognitionFailed)
                }
            }
        }
    }
    func close() { state.withLockUnchecked { s in s.open = false; s.modern?.finish(); s.legacy?.endAudio() } }
}

/// Native on-device engines only; no asset installation, files, model provider or tool port.
@MainActor public final class AppleDictationInput: DictationInput {
    private var session: UUID?
    private var receive: (@MainActor @Sendable (DictationEvent) -> Void)?
    private var engine: AVAudioEngine?
    private var ingress: AudioIngress?
    private var tapInstalled = false
    private var analyzer: SpeechAnalyzer?
    private var results: Task<Void, Never>?
    private var finalization: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?
    private var legacy: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var legacyID: UUID?
    private var observer: NSObjectProtocol?
    private var segments = TranscriptBuffer()
    public init() {}

    public func start(localeIdentifier: String, receive: @escaping @MainActor @Sendable (DictationEvent) -> Void) async throws -> DictationInfo {
        if legacy?.state == .completed { legacy = nil; legacyID = nil; recognizer = nil }
        guard session == nil, cleanup == nil, legacy == nil else { throw DictationFailure.busy }
        let id = UUID(); session = id; self.receive = receive; segments = TranscriptBuffer()
        do {
            let mic = AVCaptureDevice.authorizationStatus(for: .audio)
            let granted: Bool
            if mic == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .audio) } else { granted = mic == .authorized }
            guard granted else { throw DictationFailure.microphoneDenied }
            try current(id)
            let authorization = await NativeSpeechCallbacks.authorization { callback in
                SFSpeechRecognizer.requestAuthorization(callback)
            }
            try current(id)
            guard authorization == .authorized else { throw DictationFailure.speechDenied }
            let locale = Locale(identifier: localeIdentifier)
            if SpeechTranscriber.isAvailable, let selected = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                try current(id)
                let module = SpeechTranscriber(locale: selected, preset: .progressiveTranscription)
                if await AssetInventory.status(forModules: [module]) == .installed {
                    try current(id)
                    return try await beginModern(module, locale: selected, id: id, name: "Apple Speech")
                }
            }
            try current(id)
            if let selected = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
                try current(id)
                let module = DictationTranscriber(locale: selected, preset: .progressiveShortDictation)
                if await AssetInventory.status(forModules: [module]) == .installed {
                    try current(id)
                    return try await beginModern(module, locale: selected, id: id, name: "Apple Dictation")
                }
            }
            try current(id)
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else { throw DictationFailure.assetsMissing }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            request.taskHint = .dictation
            let audio = try makeEngine(); let format = audio.inputNode.outputFormat(forBus: 0)
            ingress = try AudioIngress(source: format, target: format, legacy: request, onFailure: failureHandler(id))
            legacyID = id; self.recognizer = recognizer
            let callback = NativeSpeechCallbacks.recognition { [weak self] text, final, failed in
                guard let self else { return }
                if self.session == id {
                    if let text { self.publish(text, id: id) }
                    if final { self.complete(id) }
                    else if failed { self.fail(.recognitionFailed, id: id) }
                }
                if (final || failed) && self.legacyID == id { self.legacy = nil; self.legacyID = nil; self.recognizer = nil }
            }
            legacy = recognizer.recognitionTask(with: request, resultHandler: callback)
            try startCapture(audio, id: id)
            return .init(engine: "Apple Speech (on-device)", localeIdentifier: recognizer.locale.identifier)
        } catch {
            if session == id { cancel() }
            if error is CancellationError { throw CancellationError() }
            throw error as? DictationFailure ?? .recognitionFailed
        }
    }
    private func failureHandler(_ id: UUID) -> @Sendable (DictationFailure) -> Void {
        { [weak self] reason in Task { @MainActor [weak self] in self?.fail(reason, id: id) } }
    }
    private func current(_ id: UUID) throws {
        guard session == id, !Task.isCancelled else { throw CancellationError() }
    }
    private func makeEngine() throws -> AVAudioEngine {
        let audio = AVAudioEngine(); let format = audio.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationFailure.audioUnavailable }
        engine = audio; return audio
    }
    private func beginModern<M: SpeechModule>(_ module: M, locale: Locale, id: UUID, name: String) async throws -> DictationInfo {
        let audio = try makeEngine()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw DictationFailure.audioUnavailable }
        try current(id)
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        ingress = try AudioIngress(source: audio.inputNode.outputFormat(forBus: 0), target: format, modern: pair.continuation, onFailure: failureHandler(id))
        let worker = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        analyzer = worker
        try await worker.prepareToAnalyze(in: format); try current(id)
        results = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self, self.session == id, !Task.isCancelled else { return }
                    let text: String
                    if let value = result as? SpeechTranscriber.Result { text = String(value.text.characters) }
                    else if let value = result as? DictationTranscriber.Result { text = String(value.text.characters) }
                    else { self.fail(.recognitionFailed, id: id); return }
                    let start = CMTimeGetSeconds(result.range.start), end = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
                    self.merge(text, start: start, end: end, id: id)
                }
            } catch { if let self { self.fail(error as? DictationFailure ?? .recognitionFailed, id: id) } }
        }
        try await worker.start(inputSequence: pair.stream); try current(id)
        try startCapture(audio, id: id)
        return .init(engine: name, localeIdentifier: locale.identifier)
    }
    private func startCapture(_ audio: AVAudioEngine, id: UUID) throws {
        try current(id)
        let format = audio.inputNode.outputFormat(forBus: 0)
        guard let ingress else { throw DictationFailure.audioUnavailable }
        audio.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: NativeSpeechCallbacks.tap(ingress))
        tapInstalled = true
        let onConfiguration: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.fail(.audioUnavailable, id: id) }
        }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main, using: onConfiguration)
        audio.prepare(); try audio.start()
    }
    private func merge(_ text: String, start: Double, end: Double, id: UUID) {
        do { publish(try segments.replace(text, start: start, end: end), id: id) }
        catch { fail(error as? DictationFailure ?? .recognitionFailed, id: id) }
    }
    private func publish(_ text: String, id: UUID) {
        guard session == id else { return }
        guard text.utf8.count <= DictationText.maximumBytes else { fail(.overflow, id: id); return }
        receive?(.transcript(text))
    }
    private func stopCapture() {
        ingress?.close(); ingress = nil
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
            engine.reset()
        }
        engine = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }
    public func stop() {
        guard let id = session, finalization == nil else { return }
        stopCapture()
        if let analyzer {
            let pendingResults = results
            finalization = Task { [weak self] in
                do {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    await pendingResults?.value
                    self?.complete(id)
                } catch { self?.fail(.recognitionFailed, id: id) }
            }
        } else { legacy?.finish() }
    }
    private func complete(_ id: UUID) {
        guard session == id else { return }
        let callback = receive
        session = nil; receive = nil; stopCapture(); analyzer = nil; results = nil; finalization = nil; segments = TranscriptBuffer()
        callback?(.finished)
    }
    private func fail(_ failure: DictationFailure, id: UUID) {
        guard session == id else { return }
        let callback = receive; cancel(); callback?(.failed(failure))
    }
    public func cancel() {
        session = nil; receive = nil; stopCapture(); results?.cancel(); results = nil
        finalization?.cancel(); finalization = nil; legacy?.cancel(); segments = TranscriptBuffer()
        if let analyzer {
            self.analyzer = nil
            cleanup = Task { [weak self] in await analyzer.cancelAndFinishNow(); self?.cleanup = nil }
        }
    }
}


/// Pure bounded range replacement for cumulative/volatile native recognition results.
struct TranscriptBuffer {
    private var segments: [(start: Double, end: Double, text: String)] = []
    mutating func replace(_ text: String, start: Double, end: Double) throws -> String {
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { throw DictationFailure.recognitionFailed }
        guard text.utf8.count <= DictationText.maximumBytes else { throw DictationFailure.overflow }
        var updated = segments.filter { !(($0.start < end && $0.end > start) || $0.start == start) }
        updated.append((start, end, text)); updated.sort { $0.start < $1.start }
        guard updated.count <= 256 else { throw DictationFailure.overflow }
        let result = updated.map(\.text).joined(separator: " ")
        guard result.utf8.count <= DictationText.maximumBytes else { throw DictationFailure.overflow }
        segments = updated
        return result
    }
}
