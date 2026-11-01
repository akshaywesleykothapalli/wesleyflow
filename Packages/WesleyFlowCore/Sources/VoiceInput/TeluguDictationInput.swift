import Foundation
import AVFoundation
import Domain

@MainActor public protocol TeluguLanguageConfiguring: DictationInput { var language:TeluguRecognitionLanguage { get set } }

@MainActor public final class TeluguDictationInput: TeluguLanguageConfiguring, DictationAudioMetering {
    private let recognizer: any LocalPCMRecognizing
    private let exclusiveCapture: @MainActor () throws -> Void
    private let microphoneAccess: @MainActor () async -> Bool
    private var engine:AVAudioEngine?, ring:TeluguAudioRing?, meter:AudioLevelMailbox?
    private var receive: (@MainActor @Sendable (DictationEvent) -> Void)?
    private var session:UUID?, cancellation:SpeechCancellation?
    private var producer:Task<Void,Never>?, consumer:Task<Void,Never>?
    private var stopping = false
    private var configurationObserver: (any NSObjectProtocol)?
    public var language:TeluguRecognitionLanguage = .automatic
    public init(recognizer:any LocalPCMRecognizing = LocalWhisperRecognizer(), exclusiveCapture:@escaping @MainActor () throws -> Void = {}, microphoneAccess:(@MainActor () async -> Bool)? = nil) {
        self.recognizer = recognizer; self.exclusiveCapture = exclusiveCapture
        self.microphoneAccess = microphoneAccess ?? {
            switch AVCaptureDevice.authorizationStatus(for:.audio) {
            case .authorized: return true
            case .notDetermined: return await AVCaptureDevice.requestAccess(for:.audio)
            default: return false
            }
        }
    }
    public func audioLevel() -> DictationAudioLevel { meter?.snapshot() ?? .init() }
    public func start(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo {
        guard session == nil else { throw DictationFailure.busy }
        try exclusiveCapture()
        let id = UUID(), cancellation = SpeechCancellation(), language = language
        self.session = id; self.cancellation = cancellation; self.receive = receive; stopping = false
        do {
            // Hash/load off the main actor, before permission prompts or microphone capture.
            try await recognizer.prepare()
            guard self.session == id, !Task.isCancelled, !cancellation.isCancelled else { throw CancellationError() }
            let allowed = await microphoneAccess()
            guard self.session == id, !Task.isCancelled, !cancellation.isCancelled else { throw CancellationError() }
            guard allowed else { throw DictationFailure.microphoneDenied }
            let engine = AVAudioEngine(), format = engine.inputNode.outputFormat(forBus:0)
            guard format.commonFormat == .pcmFormatFloat32, format.sampleRate.isFinite,
                  (8000...192000).contains(format.sampleRate), (1...8).contains(format.channelCount) else { throw DictationFailure.audioUnavailable }
            let ring = TeluguAudioRing(sampleRate:format.sampleRate), meter = AudioLevelMailbox()
            let (stream, continuation) = AsyncThrowingStream<[Float],any Error>.makeStream(bufferingPolicy:.bufferingOldest(2))
            self.ring = ring; self.engine = engine; self.meter = meter
            engine.inputNode.installTap(onBus:0,bufferSize:1024,format:format) { buffer,time in
                meter.append(buffer); ring.append(buffer,at:time)
            }
            producer = Task.detached { [weak self] in
                await produceTeluguUtterances(ring:ring,cancellation:cancellation,stream:continuation,onFailure:{ [weak self] error in
                    Task { @MainActor [weak self] in self?.fail(error,id:id) }
                })
            }
            consumer = Task { [weak self, recognizer] in
                var transcript = ""
                do {
                    for try await utterance in stream {
                        let text = try await recognizer.transcribe(utterance,language:language,cancellation:cancellation)
                        guard let self, self.session == id, !cancellation.isCancelled, !Task.isCancelled else { return }
                        if !text.isEmpty { transcript += (transcript.isEmpty ? "" : " ") + text }
                        guard transcript.utf8.count <= DictationText.maximumBytes else { throw DictationFailure.overflow }
                        self.receive?(.transcript(transcript))
                    }
                    guard let self, self.session == id, !cancellation.isCancelled, !Task.isCancelled else { return }
                    guard self.stopping else { throw DictationFailure.providerEnded }
                    let callback = self.receive; self.clearCapture(cancel:true); self.session = nil; self.receive = nil
                    callback?(.finished)
                } catch {
                    guard let self, self.session == id, !cancellation.isCancelled else { return }
                    let callback = self.receive; self.cancel()
                    callback?(.failed(error as? DictationFailure ?? .recognitionFailed))
                }
            }
            engine.prepare(); try engine.start()
            configurationObserver = NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.stopping else { return }
                    self.fail(.audioUnavailable,id:id)
                }
            }
            return .init(engine:"whisper.cpp 1.8.2 · multilingual Small · local",localeIdentifier:language.whisperLanguage)
        } catch {
            if session == id { cancel() }
            throw error
        }
    }
    public func stop() {
        guard session != nil, !stopping else { return }; stopping = true
        stopEngine()
        ring?.ended.store(true,ordering:.sequentiallyConsistent)
    }
    private func clearCapture(cancel:Bool) {
        stopEngine()
        if cancel { cancellation?.cancel(); producer?.cancel(); consumer?.cancel() }
        ring?.ended.store(true,ordering:.sequentiallyConsistent)
        producer = nil; consumer = nil; ring = nil; meter = nil; cancellation = nil
    }
    private func stopEngine() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        engine?.stop(); engine?.inputNode.removeTap(onBus:0); engine = nil
    }
    private func fail(_ error: DictationFailure, id: UUID) {
        guard session == id else { return }
        let callback = receive; cancel(); callback?(.failed(error))
    }
    public func cancel() {
        session = nil; receive = nil; clearCapture(cancel:true); stopping = false
    }
}

/// Freezes a backend per gesture. Agent capture always uses the original Apple input.
@MainActor public final class LanguageDictationInput: AgentDictationInput, AgentApplicationNameHinting, DictationAudioMetering, DictationCaptureReporting, DictationRecoveryProviding {
    private let english:any DictationInput
    private let telugu:any TeluguLanguageConfiguring
    private var selected:(any DictationInput)?
    public var mode:DictationLanguageMode = .english
    public var recognitionLanguage:TeluguRecognitionLanguage = .automatic
    public init(english:any DictationInput,telugu:any TeluguLanguageConfiguring) { self.english = english; self.telugu = telugu }
    public func setAgentApplicationNames(_ names:[String]) { (english as? any AgentApplicationNameHinting)?.setAgentApplicationNames(names) }
    public func start(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo {
        telugu.language = recognitionLanguage
        selected = mode == .english ? english : telugu
        return try await selected!.start(localeIdentifier:localeIdentifier,receive:receive)
    }
    public func startAgent(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo {
        selected = english
        if let agent = english as? any AgentDictationInput { return try await agent.startAgent(localeIdentifier:localeIdentifier,receive:receive) }
        return try await english.start(localeIdentifier:localeIdentifier,receive:receive)
    }
    public func stop() { selected?.stop() }
    public func cancel() { selected?.cancel() }
    public func audioLevel() -> DictationAudioLevel { (selected as? any DictationAudioMetering)?.audioLevel() ?? .init() }
    public var captureDiagnosticSummary:String { (selected as? any DictationCaptureReporting)?.captureDiagnosticSummary ?? "localWhisper=true" }
    public var speechDiagnostics:DictationSpeechDiagnostics? { (selected as? any DictationCaptureReporting)?.speechDiagnostics }
    public var unmergedRecognitionText:String? { (selected as? any DictationRecoveryProviding)?.unmergedRecognitionText }
}
