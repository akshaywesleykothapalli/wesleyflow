import Domain
import Foundation
import AVFoundation
import Speech
import os
import CoreMedia

/// Microphone arrays may expose an unlabelled/discrete channel layout. Core Audio's
/// implicit multichannel-to-mono mapping can be [-1] (silence). Average explicitly
/// before conversion; mono input and audio sample positions are unchanged.
enum SpeechAudioDownmix {
    static func mono(_ input:AVAudioPCMBuffer,format:AVAudioFormat?) throws -> AVAudioPCMBuffer {
        guard let format else { return input }
        guard input.format.commonFormat == .pcmFormatFloat32, let channels = input.floatChannelData,
              let output = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:input.frameLength),
              let destination = output.floatChannelData?[0] else { throw DictationFailure.audioUnavailable }
        let count = Int(input.format.channelCount), stride = input.stride
        output.frameLength = input.frameLength
        for frame in 0..<Int(input.frameLength) {
            var mixed:Float = 0
            for channel in 0..<count {
                let value = channels[input.format.isInterleaved ? 0 : channel][frame*stride + (input.format.isInterleaved ? channel : 0)]
                guard value.isFinite else { throw DictationFailure.audioUnavailable }
                mixed += value/Float(count)
            }
            destination[frame] = mixed
        }
        return output
    }
}

/// Tap delivery metrics contain counts and sample positions only, never PCM or text.
final class AudioIngress: Sendable {
    struct State {
        var open = true
        let inputFormat: AVAudioFormat
        let monoFormat: AVAudioFormat?
        let converter: AVAudioConverter?
        let format: AVAudioFormat
        let modern: AsyncThrowingStream<AnalyzerInput, any Error>.Continuation?
        let legacy: SFSpeechAudioBufferRecognitionRequest?
        var delivery = DictationAudioDelivery()
        var expectedSample: AVAudioFramePosition?
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
        let mono:AVAudioFormat?
        if source.channelCount > 1 {
            guard source.commonFormat == .pcmFormatFloat32,
                  let format = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:source.sampleRate,channels:1,interleaved:false) else { throw DictationFailure.audioUnavailable }
            mono = format
        } else { mono = nil }
        let converter = AVAudioConverter(from:mono ?? source,to:target)
        guard legacy != nil || converter != nil else { throw DictationFailure.audioUnavailable }
        // Apple conversion pattern: don't add resampler priming/timestamp drift.
        converter?.primeMethod = .none
        var initial = State(inputFormat:source,monoFormat:mono,converter:converter,format:target,modern:modern,legacy:legacy)
        initial.delivery.inputSampleRate = source.sampleRate
        state = OSAllocatedUnfairLock(uncheckedState:initial)
    }
    var diagnostics: DictationAudioDelivery { state.withLockUnchecked { $0.delivery } }
    private func fail(_ reason: DictationFailure, code: String, native: SpeechNativeError? = nil, state s: inout State) {
        s.open = false; s.delivery.closeReason = code; s.delivery.nativeError = native; s.modern?.finish(throwing:reason); onFailure(reason)
    }
    private func enqueue(_ output: AVAudioPCMBuffer, state s: inout State) -> Bool {
        // Resamplers can emit filter padding at EOF. Preserve every frame up to
        // the received media duration, without adding artificial trailing audio.
        let expected = ceil(Double(s.delivery.receivedFrames)*s.format.sampleRate/s.delivery.inputSampleRate)
        guard expected.isFinite, expected >= 0, expected < Double(UInt64.max) else { fail(.overflow,code:"frameBudget",state:&s); return false }
        let remaining = UInt64(expected) > s.delivery.queuedFrames ? UInt64(expected)-s.delivery.queuedFrames : 0
        let originalFrames = output.frameLength
        output.frameLength = AVAudioFrameCount(min(UInt64(originalFrames),remaining))
        s.delivery.trimmedPaddingFrames += UInt64(originalFrames-output.frameLength)
        guard output.frameLength > 0 else { return true }
        if let result = s.modern?.yield(AnalyzerInput(buffer:output)) {
            switch result {
            case .enqueued: s.delivery.queuedBuffers += 1; s.delivery.queuedFrames += UInt64(output.frameLength); return true
            case .dropped: fail(.overflow,code:"queueOverflow",state:&s)
            case .terminated: fail(.recognitionFailed,code:"inputTerminated",state:&s)
            @unknown default: fail(.recognitionFailed,code:"unknownYield",state:&s)
            }
            return false
        }
        return true
    }
    func append(_ input: AVAudioPCMBuffer, at time: AVAudioTime? = nil) {
        state.withLockUnchecked { s in
            guard s.open else { return }
            guard input.frameLength <= 8192, input.format == s.inputFormat else {
                fail(.audioUnavailable,code:"inputFormatChanged",state:&s); return
            }
            s.delivery.receivedBuffers += 1; s.delivery.receivedFrames += UInt64(input.frameLength)
            if let time, time.isSampleTimeValid, time.sampleRate == input.format.sampleRate {
                s.delivery.timestampedBuffers += 1
                if let expected = s.expectedSample, time.sampleTime != expected {
                    s.delivery.discontinuities += 1
                    let difference = time.sampleTime.subtractingReportingOverflow(expected)
                    if !difference.overflow { s.delivery.maximumGapFrames = max(s.delivery.maximumGapFrames,difference.partialValue) }
                }
                let next = time.sampleTime.addingReportingOverflow(Int64(input.frameLength))
                s.expectedSample = next.overflow ? nil : next.partialValue
            }
            let mono:AVAudioPCMBuffer
            do { mono = try SpeechAudioDownmix.mono(input,format:s.monoFormat) }
            catch { fail(.audioUnavailable,code:"downmixFailed",state:&s); return }
            if let legacy = s.legacy {
                legacy.append(mono); s.delivery.queuedBuffers += 1; s.delivery.queuedFrames += UInt64(input.frameLength); return
            }
            guard let converter = s.converter, input.frameLength > 0 else { return }
            let frames = ceil(Double(input.frameLength) * s.format.sampleRate / input.format.sampleRate) + 32
            guard frames.isFinite, frames > 0, frames <= 65_536,
                  let output = AVAudioPCMBuffer(pcmFormat:s.format,frameCapacity:AVAudioFrameCount(frames)) else {
                fail(.overflow,code:"conversionCapacity",state:&s); return
            }
            var supplied = false; var error: NSError?
            let status = converter.convert(to:output,error:&error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return mono
            }
            guard error == nil, status != .error else { fail(.audioUnavailable,code:"conversionFailed",native:NativeSpeechCallbacks.errorMetadata(error),state:&s); return }
            _ = enqueue(output,state:&s)
        }
    }
    func close(flush: Bool = true) {
        state.withLockUnchecked { s in
            guard s.open else { return }; s.open = false
            if flush, s.modern != nil, let converter = s.converter {
                // Bounded end-of-stream drain before closing the analyzer input. The
                // engine/tap have stopped first; no converter buffer can race this call.
                var drained = false
                for _ in 0..<8 {
                    guard let output = AVAudioPCMBuffer(pcmFormat:s.format,frameCapacity:8192) else { fail(.overflow,code:"drainCapacity",state:&s); return }
                    var error: NSError?
                    let status = converter.convert(to:output,error:&error) { _, inputStatus in inputStatus.pointee = .endOfStream; return nil }
                    guard error == nil, status != .error else { fail(.audioUnavailable,code:"drainFailed",native:NativeSpeechCallbacks.errorMetadata(error),state:&s); return }
                    guard enqueue(output,state:&s) else { return }
                    if status == .endOfStream { drained = true; break }
                }
                guard drained else { fail(.overflow,code:"drainBoundExceeded",state:&s); return }
                s.delivery.converterDrained = true
            }
            s.delivery.closeReason = flush ? "endOfInput" : "cancelled"
            s.modern?.finish(); s.legacy?.endAudio()
        }
    }
}

/// Native on-device engines only; no asset installation, files, model provider or tool port.
@MainActor public final class AppleDictationInput: AgentDictationInput, AgentApplicationNameHinting, DictationAudioMetering, DictationCaptureReporting, DictationRecoveryProviding {
    public private(set) var unmergedRecognitionText: String?
    private func retainUnmerged(_ text: String) {
        diagnostic.unmergedCandidateTooLarge = text.utf8.count > DictationText.maximumBytes
        unmergedRecognitionText = diagnostic.unmergedCandidateTooLarge ? nil : text
        diagnostic.unmergedCandidateBytes = unmergedRecognitionText?.utf8.count ?? 0
    }
    private var taskGeneration: UInt64 = 0
    private var finalResults = 0, volatileResults = 0
    private var diagnostic = DictationSpeechDiagnostics()
    private var terminalDiagnostic: DictationSpeechDiagnostics?
    private var lastDelivery = DictationAudioDelivery()
    private var captureBegan: Double?, recognitionBegan: Double?, captureEnded: Double?
    private var releaseObservedAt: Double?, terminalProviderObservedAt: Double?
    private var currentStage: DictationSpeechStage = .admission
    private let uptime: @MainActor () -> Double
    private let exclusiveCapture: @MainActor () throws -> Void
    public var speechDiagnostics: DictationSpeechDiagnostics? { terminalDiagnostic ?? snapshot() }
    public var captureDiagnosticSummary: String { "micNow=\(engine?.isRunning == true) " + (speechDiagnostics?.summary ?? "speechDiagnostics=unavailable") }
    private func milliseconds(_ began: Double?, end: Double) -> Int64 {
        guard let began, began.isFinite, end.isFinite else { return 0 }
        return Int64(max(0,min(Double(DictationText.maximumDurationMilliseconds),(end-began)*1000)))
    }
    private func snapshot() -> DictationSpeechDiagnostics {
        var value = diagnostic; let now = uptime()
        value.captureMilliseconds = milliseconds(captureBegan,end:captureEnded ?? now)
        value.recognitionMilliseconds = milliseconds(recognitionBegan,end:terminalProviderObservedAt ?? now)
        value.captureActiveAtSnapshot = engine?.isRunning == true; value.releaseRequested = stopRequested
        let terminal = ["failed","cancelled","complete"].contains(diagnostic.phase)
        let eventBeforeRelease = terminalProviderObservedAt.map { event in releaseObservedAt.map { event < $0 } ?? true } ?? !stopRequested
        value.stoppedBeforeRelease = captureBegan != nil && terminal && eventBeforeRelease
        value.partialResults = volatileResults; value.finalResults = finalResults
        value.taskState = legacy.map { "legacyRawState=\($0.state.rawValue)" } ?? (analyzer == nil ? "noActiveTask" : diagnostic.phase)
        value.audio = ingress?.diagnostics ?? lastDelivery
        return value
    }
    private var meter: AudioLevelMailbox?
    public func audioLevel() -> DictationAudioLevel { meter?.snapshot() ?? .init() }
    private var agentApplicationNames:[String]=[]
    public func setAgentApplicationNames(_ names:[String]) {
        agentApplicationNames=Array(Set(names.filter { !$0.isEmpty && $0.utf8.count<=100 })).sorted().prefix(500).map { $0 }
    }
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
    private var stopRequested = false
    private var legacyPassages = LegacyTranscriptBuffer()
    public init(uptime: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }, exclusiveCapture: @escaping @MainActor () throws -> Void = {}) {
        self.uptime = uptime; self.exclusiveCapture = exclusiveCapture
    }

    public func start(localeIdentifier: String, receive: @escaping @MainActor @Sendable (DictationEvent) -> Void) async throws -> DictationInfo {
        try await startSession(localeIdentifier:localeIdentifier,fastAgent:false,receive:receive)
    }
    public func startAgent(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo {
        try await startSession(localeIdentifier:localeIdentifier,fastAgent:true,receive:receive)
    }
    private func startSession(localeIdentifier:String,fastAgent:Bool,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo {
        if legacy?.state == .completed { legacy = nil; legacyID = nil; recognizer = nil }
        guard session == nil else { throw DictationFailure.busy }
        guard cleanup == nil, legacy == nil else {
            var denied = DictationSpeechDiagnostics(); denied.requestedLocale = localeIdentifier
            denied.phase = "failed"; denied.stage = .admission; denied.failure = "busy"; denied.taskState = "previousTaskSettling"
            terminalDiagnostic = denied
            throw DictationFailure.busy
        }
        let id = UUID(); session = id; self.receive = receive; segments = TranscriptBuffer(); stopRequested = false; legacyPassages = LegacyTranscriptBuffer(); finalResults = 0; volatileResults = 0
        diagnostic = .init(); terminalDiagnostic = nil; lastDelivery = .init(); unmergedRecognitionText = nil
        diagnostic.requestedLocale = localeIdentifier; diagnostic.phase = "preparing"
        diagnostic.sessionIdentifier = id.uuidString
        captureBegan = nil; captureEnded = nil; recognitionBegan = nil; releaseObservedAt = nil; terminalProviderObservedAt = nil; currentStage = .admission
        do {
            try exclusiveCapture(); currentStage = .authorization
            let mic = AVCaptureDevice.authorizationStatus(for: .audio)
            let granted: Bool
            if mic == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .audio) } else { granted = mic == .authorized }
            guard granted else { throw DictationFailure.microphoneDenied }
            try current(id)
            let authorization:SFSpeechRecognizerAuthorizationStatus
            if fastAgent,SFSpeechRecognizer.authorizationStatus() != .notDetermined { authorization=SFSpeechRecognizer.authorizationStatus() }
            else { authorization = await NativeSpeechCallbacks.authorization { callback in SFSpeechRecognizer.requestAuthorization(callback) } }
            try current(id)
            guard authorization == .authorized else { throw DictationFailure.speechDenied }
            let locale = Locale(identifier: localeIdentifier)
            taskGeneration += 1
            diagnostic.recognitionTaskGeneration = taskGeneration; diagnostic.recognitionTaskIdentifier = UUID().uuidString
            // Do not inspect every modern inventory or prepare an analyzer for a ready short-command engine.
            let candidate=fastAgent ? SFSpeechRecognizer(locale:locale):nil
            let fastRecognizer=(candidate?.isAvailable == true && candidate?.supportsOnDeviceRecognition == true) ? candidate:nil
            if fastRecognizer == nil {
                currentStage = .resourceInspection
                let readiness = await AppleSpeechConfiguration.inspect(localeIdentifier:localeIdentifier)
                try current(id)
                diagnostic.modernSpeechAssets = readiness.speech.inventoryStatus
                diagnostic.modernDictationAssets = readiness.dictation.inventoryStatus
                if let selectedEngine = readiness.readyModernEngine,
                   let selectedLocale = readiness.resources(for:selectedEngine).resolvedLocale {
                    diagnostic.provider = selectedEngine == .speechTranscriber ? .speechTranscriber : .dictationTranscriber
                    diagnostic.resolvedLocale = selectedLocale
                    let selected = try await AppleSpeechModules.canonicalLocale(selectedEngine,locale:selectedLocale)
                    try current(id)
                    switch selectedEngine {
                    case .speechTranscriber:
                        return try await beginModern(AppleSpeechModules.speech(selected),locale:selected,id:id,name:selectedEngine.label)
                    case .dictationTranscriber:
                        return try await beginModern(AppleSpeechModules.dictation(selected),locale:selected,id:id,name:selectedEngine.label)
                    }
                }
            }
            diagnostic.provider = .legacyOnDevice; diagnostic.resolvedLocale = locale.identifier
            diagnostic.fallbackReason = fastRecognizer == nil ? "modernModuleAssetsNotReady":"agentFastOnDevice"; diagnostic.preparation = "notApplicableLegacy"
            currentStage = .legacyRecognition
            guard let recognizer = fastRecognizer ?? SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else { throw DictationFailure.assetsMissing }
            diagnostic.resolvedLocale = recognizer.locale.identifier
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if fastAgent { request.contextualStrings=agentApplicationNames }
            let audio = try makeEngine(); let format = audio.inputNode.outputFormat(forBus: 0)
            ingress = try AudioIngress(source: format, target: format, legacy: request, onFailure: failureHandler(id))
            legacyID = id; self.recognizer = recognizer
            let callback = NativeSpeechCallbacks.recognitionPassages { [weak self] observation in
                guard let self else { return }
                let text = observation.text, start = observation.start, end = observation.end, final = observation.isFinal
                let nativeError = observation.failure, observedAt = observation.observedAt
                let failure = nativeError ?? (self.legacyID == id ? NativeSpeechCallbacks.errorMetadata(self.legacy?.error) : nil)
                if self.session == id {
                    guard self.legacyPassages.acceptResult(sequence:observation.sequence) else { self.diagnostic.ignoredLegacyCallbacks += 1; return }
                    self.diagnostic.legacyRangeStart = start; self.diagnostic.legacyRangeEnd = end
                    if let anchor = observation.metadataStart, let duration = observation.metadataDuration {
                        self.diagnostic.legacyMetadataResults += 1; self.diagnostic.legacyMetadataStart = anchor; self.diagnostic.legacyMetadataDuration = duration
                    }
                    if final || failure != nil { self.terminalProviderObservedAt = nativeError != nil || final ? observedAt : self.uptime() }
                    if final { self.finalResults += 1 } else if text != nil { self.volatileResults += 1 }
                    if let text, !text.isEmpty {
                        self.observeRange(start:start,end:end,previousStart:self.legacyPassages.acceptedStart,previousEnd:self.legacyPassages.acceptedEnd,kind:final ? "legacyFinalHypothesis" : "legacyPartialHypothesis",timebase:"legacyTaskAudioSeconds")
                        do {
                            guard let start, let end else { throw DictationFailure.recognitionFailed }
                            self.publish(try self.legacyPassages.replace(text,start:start,end:end,metadataStart:observation.metadataStart,metadataDuration:observation.metadataDuration,isFinal:final),id:id)
                            self.diagnostic.legacyBoundaryPending = self.legacyPassages.boundaryPending
                            self.diagnostic.mergeRejection = self.legacyPassages.lastRejection
                            self.unmergedRecognitionText = self.legacyPassages.unmergedText
                            self.diagnostic.unmergedCandidateBytes = self.unmergedRecognitionText?.utf8.count ?? 0
                            self.diagnostic.preservedSegments = self.legacyPassages.preservedSegmentCount
                            self.diagnostic.finalizedSegmentCount = final ? self.legacyPassages.preservedSegmentCount : 0
                            self.recordRangeDecision(self.legacyPassages.boundaryPending ? "provisionalBoundary" : "hypothesisAccepted")
                        } catch {
                            self.retainUnmerged(self.legacyPassages.unmergedText ?? text)
                            self.diagnostic.legacyBoundaryPending = self.legacyPassages.boundaryPending
                            self.diagnostic.mergeRejection = self.legacyPassages.lastRejection
                            self.recordRangeDecision("rejected:" + self.legacyPassages.lastRejection)
                            self.fail(error as? DictationFailure ?? .recognitionFailed,id:id,stage:failure == nil ? .transcriptMerge : .legacyRecognition,native:failure)
                        }
                    }
                    if let failure { self.fail(.recognitionFailed,id:id,stage:.legacyRecognition,native:failure) }
                    else if final && (text?.isEmpty != false) { self.fail(.recognitionFailed,id:id,stage:.legacyRecognition) }
                    else if final {
                        if DictationReleaseBoundary.acceptsFinal(observedAt:observedAt,releaseAt:self.releaseObservedAt) { self.complete(id) }
                        else { self.fail(.providerEnded, id: id) }
                    }
                }
                if (final || failure != nil) && self.legacyID == id { self.legacy = nil; self.legacyID = nil; self.recognizer = nil }
            }
            recognitionBegan = uptime()
            legacy = recognizer.recognitionTask(with: request, resultHandler: callback)
            try startCapture(audio, id: id)
            return .init(engine: "Legacy Apple Speech compatibility (about one-minute provider limit)", localeIdentifier: recognizer.locale.identifier)
        } catch {
            if session == id {
                diagnostic.stage = currentStage; diagnostic.failure = String(describing:error as? DictationFailure ?? .recognitionFailed)
                diagnostic.nativeError = error is DictationFailure ? nil : NativeSpeechCallbacks.errorMetadata(error)
                diagnostic.phase = "failed"; if currentStage == .modernPreparation { diagnostic.preparation = "failed" }; terminalDiagnostic = snapshot(); cancel()
            }
            if error is CancellationError { throw CancellationError() }
            throw error as? DictationFailure ?? .recognitionFailed
        }
    }
    private func failureHandler(_ id: UUID) -> @Sendable (DictationFailure) -> Void {
        { [weak self] reason in Task { @MainActor [weak self] in self?.fail(reason, id: id, stage:.audioIngress) } }
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
        currentStage = .modernPreparation; diagnostic.preparation = "preparing"
        let audio = try makeEngine()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw DictationFailure.audioUnavailable }
        try current(id)
        let pair = AsyncThrowingStream<AnalyzerInput, any Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        ingress = try AudioIngress(source: audio.inputNode.outputFormat(forBus: 0), target: format, modern: pair.continuation, onFailure: failureHandler(id))
        let worker = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
        analyzer = worker
        try await worker.prepareToAnalyze(in: format); try current(id)
        diagnostic.preparation = "succeeded"
        results = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self, self.session == id, !Task.isCancelled else { return }
                    let text: AttributedString
                    if let value = result as? SpeechTranscriber.Result { text = value.text }
                    else if let value = result as? DictationTranscriber.Result { text = value.text }
                    else { self.fail(.recognitionFailed, id: id); return }
                    self.merge(text,range:result.range,isFinal:result.isFinal,finalization:result.resultsFinalizationTime,id:id)
                }
                if let self, self.session == id, !self.stopRequested, !Task.isCancelled {
                    self.fail(.providerEnded, id: id, stage:.modernResults)
                }
            } catch { if let self { self.fail(error as? DictationFailure ?? .recognitionFailed, id:id,stage:.modernResults,native:error is DictationFailure ? nil : NativeSpeechCallbacks.errorMetadata(error)) } }
        }
        currentStage = .modernStart; recognitionBegan = uptime()
        try await worker.start(inputSequence: pair.stream); try current(id)
        try startCapture(audio, id: id)
        return .init(engine: name, localeIdentifier: locale.identifier)
    }
    private func startCapture(_ audio: AVAudioEngine, id: UUID) throws {
        try current(id)
        let format = audio.inputNode.outputFormat(forBus: 0)
        guard let ingress else { throw DictationFailure.audioUnavailable }
        let meter = AudioLevelMailbox(); self.meter = meter
        audio.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: NativeSpeechCallbacks.tap(ingress,meter:meter))
        tapInstalled = true
        let onConfiguration: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.fail(.audioUnavailable, id:id,stage:.audioConfiguration) }
        }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main, using: onConfiguration)
        audio.prepare(); try audio.start()
        captureBegan = uptime(); diagnostic.phase = "capturing"
    }
    private func observeRange(start:Double?,end:Double?,previousStart:Double?,previousEnd:Double?,kind:String,timebase:String) {
        diagnostic.incomingRangeStart = start; diagnostic.incomingRangeEnd = end
        diagnostic.previousAcceptedRangeStart = previousStart; diagnostic.previousAcceptedRangeEnd = previousEnd
        diagnostic.resultClassification = kind; diagnostic.timebase = timebase
    }
    private func recordRangeDecision(_ decision:String,rawTime:String="") {
        let number:(Double?)->String = { $0.map(String.init(describing:)) ?? "none" }
        let line = "class=\(diagnostic.resultClassification),incoming=\(number(diagnostic.incomingRangeStart))..\(number(diagnostic.incomingRangeEnd)),previous=\(number(diagnostic.previousAcceptedRangeStart))..\(number(diagnostic.previousAcceptedRangeEnd)),decision=\(decision),finalized=\(diagnostic.finalizedSegmentCount),captureActive=\(engine?.isRunning == true),releaseRequested=\(stopRequested)" + rawTime
        if diagnostic.rangeEvents.count == 16 { diagnostic.rangeEvents.removeFirst() }
        diagnostic.rangeEvents.append(line)
    }
    private func merge(_ text: AttributedString, range: CMTimeRange, isFinal: Bool, finalization: CMTime, id: UUID) {
        guard session == id else { return }
        observeRange(start:range.start.isNumeric ? CMTimeGetSeconds(range.start) : nil,end:CMTimeRangeGetEnd(range).isNumeric ? CMTimeGetSeconds(CMTimeRangeGetEnd(range)) : nil,previousStart:segments.acceptedStart,previousEnd:segments.acceptedEnd,kind:isFinal ? "modernFinal" : "modernVolatile",timebase:"analyzerInputCMTime")
        let rawTime = ",startValue=\(range.start.value),startScale=\(range.start.timescale),startEpoch=\(range.start.epoch),durationValue=\(range.duration.value),durationScale=\(range.duration.timescale),finalization=\(finalization.value)/\(finalization.timescale)"
        do {
            if isFinal { finalResults += 1 } else { volatileResults += 1 }
            let snapshot = try segments.replace(text,range:range,isFinal:isFinal,finalization:finalization)
            diagnostic.preservedSegments = segments.preservedSegmentCount
            diagnostic.finalizedSegmentCount = segments.finalizedSegmentCount
            recordRangeDecision(segments.lastDecision,rawTime:rawTime)
            publish(snapshot,id:id)
        } catch {
            retainUnmerged(String(text.characters))
            diagnostic.mergeRejection = segments.lastRejection
            recordRangeDecision("rejected:" + segments.lastRejection,rawTime:rawTime)
            fail(error as? DictationFailure ?? .recognitionFailed,id:id,stage:.transcriptMerge)
        }
    }
    private func publish(_ text: String, id: UUID) {
        guard session == id else { return }
        guard text.utf8.count <= DictationText.maximumBytes else { fail(.overflow, id: id); return }
        diagnostic.preservedBytes = text.utf8.count
        receive?(.transcript(text))
    }
    private func stopCapture(flush: Bool = false) {
        if captureBegan != nil, captureEnded == nil { captureEnded = uptime() }
        meter = nil
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
            engine.reset()
        }
        engine = nil
        ingress?.close(flush:flush); if let ingress { lastDelivery = ingress.diagnostics }; ingress = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }
    public func stop() {
        guard let id = session, !stopRequested else { return }
        releaseObservedAt = uptime(); stopRequested = true; diagnostic.phase = "finalizing"
        stopCapture(flush:true)
        if let analyzer {
            let pendingResults = results
            finalization = Task { [weak self] in
                do {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    await pendingResults?.value
                    if let self, self.session == id {
                        self.publish(try self.segments.finishAfterAnalyzerFinalization(),id:id)
                        self.diagnostic.finalizedSegmentCount = self.segments.finalizedSegmentCount
                        self.complete(id)
                    }
                } catch { self?.fail(.recognitionFailed,id:id,stage:.modernFinalization,native:NativeSpeechCallbacks.errorMetadata(error)) }
            }
        }
        // Legacy endAudio is sent by ingress.close. Wait for the task's final
        // callback instead of additionally forcing recognitionTask.finish here.
    }
    private func complete(_ id: UUID) {
        guard session == id else { return }
        guard stopRequested, lastDelivery.closeReason == "endOfInput" else {
            fail(.recognitionFailed,id:id,stage:.audioIngress,native:lastDelivery.nativeError); return
        }
        let callback = receive
        diagnostic.phase = "complete"; terminalDiagnostic = snapshot()
        session = nil; receive = nil; stopCapture(); analyzer = nil; results = nil; finalization = nil; segments = TranscriptBuffer()
        // Final speech was accepted before delivery. Do not cancel this completed task
        // reentrantly from the coordinator or leave it blocking the next capture.
        legacy = nil; legacyID = nil; recognizer = nil
        callback?(.finished)
    }
    private func fail(_ failure: DictationFailure, id: UUID, stage: DictationSpeechStage? = nil, native: SpeechNativeError? = nil) {
        guard session == id else { return }
        diagnostic.phase = "failed"; diagnostic.stage = stage ?? currentStage
        diagnostic.failure = String(describing:failure); diagnostic.nativeError = native ?? (stage == .audioIngress ? (ingress?.diagnostics.nativeError ?? lastDelivery.nativeError) : nil)
        terminalDiagnostic = snapshot()
        let callback = receive; cancel(); callback?(.failed(failure))
    }
    public func cancel() {
        if session != nil, terminalDiagnostic == nil {
            diagnostic.phase = "cancelled"; diagnostic.stage = .userCancellation; terminalDiagnostic = snapshot()
        }
        session = nil; receive = nil; stopCapture(); results?.cancel(); results = nil
        finalization?.cancel(); finalization = nil; legacy?.cancel(); segments = TranscriptBuffer()
        if let analyzer {
            self.analyzer = nil
            cleanup = Task { [weak self] in await analyzer.cancelAndFinishNow(); self?.cleanup = nil }
        }
    }
}


/// Provider time ranges are audio coordinates, never character indices or wall time.
/// Modern text retains Apple's per-word audio attributes so a volatile replacement
/// can split a previous hypothesis without deleting its unaffected beginning/end.
struct TranscriptBuffer {
    private struct Piece { let range: CMTimeRange; let text: AttributedString }
    private var committed = ""
    private var finalizedThrough = CMTime.zero
    private var committedSegments = 0
    private var segments: [Piece] = []
    private var recentFinals: [(range:CMTimeRange,text:String)] = []
    private(set) var lastRejection = "none"
    private(set) var lastDecision = "initial"
    private(set) var acceptedStart: Double?, acceptedEnd: Double?
    var finalizedSegmentCount: Int { committedSegments }
    var preservedSegmentCount: Int { committedSegments + segments.filter { !plain($0.text).isEmpty }.count }
    static func valid(_ time: CMTime) -> Bool { time.isNumeric && time.epoch == 0 && time.timescale > 0 && CMTimeCompare(time,.zero) >= 0 }
    static func valid(_ range: CMTimeRange) -> Bool { range.isValid && valid(range.start) && valid(range.duration) && valid(CMTimeRangeGetEnd(range)) }
    private func plain(_ text: AttributedString) -> String { String(text.characters).trimmingCharacters(in:.whitespacesAndNewlines) }
    private func joined(_ a:String,_ b:String) -> String { a.isEmpty ? b : b.isEmpty ? a : a + " " + b }
    private func same(_ a:CMTimeRange,_ b:CMTimeRange) -> Bool { CMTimeCompare(a.start,b.start)==0 && CMTimeCompare(CMTimeRangeGetEnd(a),CMTimeRangeGetEnd(b))==0 }
    var snapshot: String { joined(committed,segments.map { plain($0.text) }.filter { !$0.isEmpty }.joined(separator:" ")) }
    /// Scalar fixtures and legacy hypotheses have no modern word-time attributes.
    mutating func replace(_ text:String,start:Double,end:Double,isFinal:Bool=false,wholeHypothesis:Bool=false) throws -> String {
        guard start.isFinite,end.isFinite,start>=0,end>=start else { lastRejection="invalidRange";throw DictationFailure.recognitionFailed }
        let a=CMTime(seconds:start,preferredTimescale:1_000_000_000),b=CMTime(seconds:end,preferredTimescale:1_000_000_000)
        return try replace(AttributedString(text),range:CMTimeRange(start:a,end:b),isFinal:isFinal,wholeHypothesis:wholeHypothesis)
    }
    mutating func replace(_ text:AttributedString,range:CMTimeRange,isFinal:Bool,finalization:CMTime?=nil,wholeHypothesis:Bool=false) throws -> String {
        var next=self
        do { let value=try next.update(text,range:range,isFinal:isFinal,finalization:finalization,wholeHypothesis:wholeHypothesis);self=next;return value }
        catch { lastRejection=next.lastRejection;lastDecision="rejected";throw error }
    }
    private mutating func reject(_ reason:String) throws -> Never { lastRejection=reason;throw DictationFailure.recognitionFailed }
    private mutating func update(_ text:AttributedString,range:CMTimeRange,isFinal:Bool,finalization:CMTime?,wholeHypothesis:Bool) throws -> String {
        lastRejection="none";lastDecision="initial"
        guard Self.valid(range),finalization.map(Self.valid) ?? true else { try reject("invalidCMTime") }
        guard String(text.characters).utf8.count<=DictationText.maximumBytes else { lastRejection="textBudget";throw DictationFailure.overflow }
        var previousAttributeStart:CMTime?
        for run in text.runs {
            if let time=run.audioTimeRange {
                guard Self.valid(time),previousAttributeStart.map({CMTimeCompare(time.start,$0)>=0}) ?? true else { try reject("invalidWordTimebase") }
                previousAttributeStart=time.start
            }
        }
        let end=CMTimeRangeGetEnd(range)
        if CMTimeCompare(end,finalizedThrough)<=0 && CMTimeCompare(finalizedThrough,.zero)>0 {
            if isFinal,let previous=recentFinals.first(where:{same($0.range,range)}),previous.text != plain(text) { try reject("conflictingFinalizedRange") }
            lastDecision=isFinal ? "duplicateOrStaleFinal" : "staleVolatileIgnored";return snapshot
        }
        guard CMTimeCompare(range.start,finalizedThrough)>=0 else { try reject("finalizedPrefixOverlap") }
        var updated:[Piece]=[]
        var revised=false
        for old in segments {
            let oldEnd=CMTimeRangeGetEnd(old.range)
            let overlaps=CMTimeCompare(old.range.start,end)<0 && CMTimeCompare(oldEnd,range.start)>0
            if !overlaps && CMTimeCompare(old.range.start,range.start) != 0 { updated.append(old);continue }
            revised=true
            let coversOld=CMTimeCompare(range.start,old.range.start)<=0 && CMTimeCompare(end,oldEnd)>=0
            if coversOld || wholeHypothesis { continue }
            let chars:Range<AttributedString.Index>
            if let intersection=old.text.rangeOfAudioTimeRangeAttributes(intersecting:range) { chars=intersection }
            else if old.text.runs.contains(where:{$0.audioTimeRange != nil}) {
                // A range can overlap the phrase envelope but only touch silence
                // between timed words. Insert at the verified next word boundary.
                let index=old.text.runs.first(where:{run in run.audioTimeRange.map {CMTimeCompare($0.start,end)>=0} ?? false})?.range.lowerBound ?? old.text.endIndex
                chars=index..<index
            } else { try reject("volatilePrefixOverlap") }
            if CMTimeCompare(old.range.start,range.start)<0 {
                let prefix=AttributedString(old.text[..<chars.lowerBound])
                if !plain(prefix).isEmpty { updated.append(.init(range:CMTimeRange(start:old.range.start,end:range.start),text:prefix)) }
            }
            if CMTimeCompare(oldEnd,end)>0 {
                let suffix=AttributedString(old.text[chars.upperBound...])
                if !plain(suffix).isEmpty { updated.append(.init(range:CMTimeRange(start:end,end:oldEnd),text:suffix)) }
            }
        }
        if !plain(text).isEmpty { updated.append(.init(range:range,text:text)) }
        updated.sort { CMTimeCompare($0.range.start,$1.range.start)<0 }
        guard updated.count<=256 else { lastRejection="segmentBudget";throw DictationFailure.overflow }
        segments=updated
        let through=finalization ?? (isFinal ? end : finalizedThrough)
        guard CMTimeCompare(through,finalizedThrough)>=0, !isFinal || CMTimeCompare(through,end)>=0 else { try reject("regressedFinalization") }
        // Earlier unchanged volatile phrases may become final without a repeated
        // final callback, as specified by resultsFinalizationTime.
        if CMTimeCompare(through,finalizedThrough)>0 || isFinal { try commit(through:through) }
        if isFinal {
            recentFinals.append((range,plain(text)))
            if recentFinals.count>32 { recentFinals.removeFirst() }
        }
        guard snapshot.utf8.count<=DictationText.maximumBytes else { lastRejection="textBudget";throw DictationFailure.overflow }
        acceptedStart=min(acceptedStart ?? CMTimeGetSeconds(range.start),CMTimeGetSeconds(range.start))
        acceptedEnd=max(acceptedEnd ?? CMTimeGetSeconds(end),CMTimeGetSeconds(end))
        lastDecision=isFinal ? "finalized" : revised ? "revisedVolatile" : "newVolatile"
        return snapshot
    }
    private mutating func commit(through:CMTime) throws {
        var remaining:[Piece]=[]
        for piece in segments {
            if CMTimeCompare(CMTimeRangeGetEnd(piece.range),through)<=0 {
                committed=joined(committed,plain(piece.text));committedSegments += 1
            } else {
                if CMTimeCompare(piece.range.start,through)<0 {
                    let tail=CMTimeRange(start:through,end:CMTimeRangeGetEnd(piece.range))
                    guard piece.text.runs.contains(where:{$0.audioTimeRange != nil}) else { try reject("unmappedFinalizationBoundary") }
                    // A finalization boundary may commit the beginning of a prior
                    // volatile phrase without the provider resending that phrase.
                    guard !piece.text.runs.contains(where:{run in run.audioTimeRange.map {CMTimeCompare($0.start,through)<0 && CMTimeCompare(CMTimeRangeGetEnd($0),through)>0} ?? false}) else { try reject("unmappedFinalizationBoundary") }
                    let index=piece.text.rangeOfAudioTimeRangeAttributes(intersecting:tail)?.lowerBound ?? piece.text.endIndex
                    let prefix=AttributedString(piece.text[..<index]),suffix=AttributedString(piece.text[index...])
                    if !plain(prefix).isEmpty { committed=joined(committed,plain(prefix));committedSegments += 1 }
                    if !plain(suffix).isEmpty { remaining.append(.init(range:tail,text:suffix)) }
                } else { remaining.append(piece) }
            }
        }
        segments=remaining;finalizedThrough=through
    }
    mutating func finishAfterAnalyzerFinalization() throws -> String {
        // Called only after finalizeAndFinishThroughEndOfInput AND result drain.
        if let end=segments.last.map({CMTimeRangeGetEnd($0.range)}) { try commit(through:end) }
        return snapshot
    }
}

/// A legacy task may reset result-local times without ending the request. Only
/// distinct, non-overlapping public speech-metadata anchors can retire an epoch.
/// An unverified reset is provisional while held, never a reason to stop capture.
struct LegacyTranscriptBuffer {
    private var current = TranscriptBuffer()
    private var prefix = ""
    private var prefixSegments = 0
    private var latestEnd = 0.0
    private var epochOffset = 0.0
    private var metadataStart: Double?, metadataDuration: Double?
    private var pending: String?, pendingEnd = 0.0
    private var pendingEarlier: [String] = []
    private var conflictingAnchor = false
    private var lastSequence: UInt64 = 0
    private(set) var lastRejection = "none"
    var acceptedStart: Double? { current.acceptedStart }
    var acceptedEnd: Double? { current.acceptedEnd }
    var boundaryPending: Bool { pending != nil }
    var preservedSegmentCount: Int { prefixSegments + current.preservedSegmentCount }
    var unmergedText: String? {
        let pieces = pendingEarlier + (pending.map { [$0] } ?? [])
        return pieces.isEmpty ? nil : pieces.joined(separator:"\n\n")
    }
    mutating func acceptResult(sequence: UInt64) -> Bool {
        guard sequence > lastSequence else { return false }; lastSequence = sequence; return true
    }
    mutating func replace(_ text: String, start: Double, end: Double, metadataStart: Double? = nil, metadataDuration: Double? = nil, isFinal: Bool = false) throws -> String {
        var next = self
        do {
            let result = try next.update(text,start:start,end:end,anchor:metadataStart,duration:metadataDuration,isFinal:isFinal)
            self = next; return result
        } catch {
            lastRejection = next.lastRejection
            // Retain the bounded unresolved data even when finalization cannot
            // establish a safe boundary. It is never part of automatic insertion.
            if let recovery = next.unmergedText, recovery.utf8.count <= DictationText.maximumBytes {
                pending = next.pending; pendingEnd = next.pendingEnd; pendingEarlier = next.pendingEarlier
                conflictingAnchor = next.conflictingAnchor
            }
            throw error
        }
    }
    private func joined(_ a: String, _ b: String) -> String { a.isEmpty ? b : b.isEmpty ? a : a + " " + b }
    private mutating func deferBoundary(_ text: String, end: Double, conflicting: Bool) throws {
        if let pending, end < pendingEnd { pendingEarlier.append(pending) }
        self.pending = text; pendingEnd = end; conflictingAnchor = conflictingAnchor || conflicting
        guard pendingEarlier.count < 8, (unmergedText?.utf8.count ?? 0) <= DictationText.maximumBytes else {
            lastRejection = "legacyRecoveryBudget"; throw DictationFailure.overflow
        }
        lastRejection = "awaitingLegacyPassageAnchor"
    }
    private mutating func update(_ text: String, start: Double, end: Double, anchor: Double?, duration: Double?, isFinal: Bool) throws -> String {
        lastRejection = "none"
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { lastRejection = "invalidRange"; throw DictationFailure.recognitionFailed }
        guard text.utf8.count <= DictationText.maximumBytes else { lastRejection = "textBudget"; throw DictationFailure.overflow }
        if let anchor, (!anchor.isFinite || anchor < 0) { lastRejection = "invalidLegacyMetadata"; throw DictationFailure.recognitionFailed }
        if let duration, (!duration.isFinite || duration < 0) { lastRejection = "invalidLegacyMetadata"; throw DictationFailure.recognitionFailed }
        let reset = end < latestEnd
        if reset || boundaryPending {
            if let anchor, let duration, anchor == metadataStart, pendingEarlier.isEmpty, !conflictingAnchor {
                let revision = try current.replace(text,start:start,end:end,wholeHypothesis:true)
                latestEnd = end; metadataDuration = duration; pending = nil; pendingEnd = 0
                return joined(prefix,revision)
            }
            let priorEnd = max(epochOffset + latestEnd, (metadataStart ?? 0) + (metadataDuration ?? 0))
            let verified = anchor.map { value in
                metadataStart.map { value > $0 && value >= priorEnd } ?? false
            } ?? false
            if verified, let anchor, let duration, duration > 0, pendingEarlier.isEmpty, !conflictingAnchor {
                let retired = joined(prefix,current.snapshot)
                var fresh = TranscriptBuffer()
                let nextText = try fresh.replace(text,start:start,end:end,wholeHypothesis:true)
                let result = joined(retired,nextText)
                guard result.utf8.count <= DictationText.maximumBytes else { lastRejection = "textBudget"; throw DictationFailure.overflow }
                prefix = retired; prefixSegments += current.preservedSegmentCount; current = fresh
                epochOffset = anchor-start; latestEnd = end; metadataStart = anchor; metadataDuration = duration
                pending = nil; pendingEarlier = []; pendingEnd = 0; conflictingAnchor = false
                return result
            }
            // Same/backwards/overlapping metadata is NOT permission to discard or
            // append old speech. Keep recording and await a verifiable boundary.
            try deferBoundary(text,end:end,conflicting:anchor != nil && !verified)
            if isFinal { lastRejection = "unverifiedLegacyPassageBoundary"; throw DictationFailure.recognitionFailed }
            return joined(prefix,current.snapshot)
        }
        let result: String
        do { result = try current.replace(text,start:start,end:end,wholeHypothesis:true) }
        catch { lastRejection = current.lastRejection; throw error }
        let all = joined(prefix,result)
        guard all.utf8.count <= DictationText.maximumBytes else { lastRejection = "textBudget"; throw DictationFailure.overflow }
        latestEnd = max(latestEnd,end)
        if let anchor, let duration { metadataStart = anchor; metadataDuration = duration }
        return all
    }
}
