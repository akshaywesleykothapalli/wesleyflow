/// Speech produces editable data, never task/permission authority.
public enum DictationFailure: Error, Sendable, Equatable {
    case microphoneDenied, speechDenied, unavailable, assetsMissing, audioUnavailable
    case busy, recognitionFailed, overflow, timedOut, providerEnded, anotherInstance
    case unsupportedRecognitionScript, repetitiveRecognition
    case noAudioCaptured, speechBelowThreshold, noSpeechRecognized
}
public struct DictationInfo: Sendable, Equatable {
    public let engine: String
    public let localeIdentifier: String
    public init(engine: String, localeIdentifier: String) { self.engine = engine; self.localeIdentifier = localeIdentifier }
}
public enum DictationEvent: Sendable, Equatable {
    case transcript(String), finished, failed(DictationFailure)
}
@MainActor public protocol DictationInput: AnyObject {
    func start(localeIdentifier: String, receive: @escaping @MainActor @Sendable (DictationEvent) -> Void) async throws -> DictationInfo
    func stop()
    func cancel()
}
/// Agent-only short-command startup. Uses the same exclusive speech session as dictation.
@MainActor public protocol AgentDictationInput: DictationInput {
    func startAgent(localeIdentifier:String,receive:@escaping @MainActor @Sendable (DictationEvent)->Void) async throws -> DictationInfo
}
public enum DictationText {
    public static let maximumBytes = 65_536
    public static let maximumDurationMilliseconds: Int64 = 86_400_000
    /// Whitespace only: no inferred punctuation, filler deletion, capitalization or LLM rewrite.
    public static func cleaned(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Explicit draft rewriting only: no tools, project context, execution or effect authority.
public protocol PromptRewriting: Sendable {
    func rewrite(_ text: String, modelName: String, requestID: String) async throws -> String
    func cancel(requestID: String) async -> InferenceCancellation
    func settle() async -> InferenceCancellation
}

/// Privacy-safe live state: no transcript, audio, clipboard or editor contents.
@MainActor public protocol DictationCaptureReporting: AnyObject {
    var captureDiagnosticSummary: String { get }
    var speechDiagnostics: DictationSpeechDiagnostics? { get }
}

public enum DictationSpeechProvider: String, Codable, Sendable { case unselected, legacyOnDevice, speechTranscriber, dictationTranscriber }
public enum DictationSpeechStage: String, Codable, Sendable {
    case admission, authorization, resourceInspection, modernPreparation, modernStart, legacyRecognition
    case modernResults, modernFinalization, audioIngress, audioConfiguration, transcriptMerge, userCancellation, finalizationWatchdog
}
public struct SpeechErrorCode: Codable, Sendable, Equatable {
    public let domain: String
    public let code: Int
    public init(domain: String, code: Int) {
        self.domain = !domain.isEmpty && domain.utf8.count <= 120 && domain.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) ? domain : "InvalidErrorDomain"
        self.code = code
    }
}
public struct SpeechNativeError: Codable, Sendable, Equatable {
    public let primary: SpeechErrorCode
    public let underlying: [SpeechErrorCode]
    public init(primary: SpeechErrorCode, underlying: [SpeechErrorCode] = []) { self.primary = primary; self.underlying = Array(underlying.prefix(4)) }
}
public struct DictationAudioDelivery: Codable, Sendable, Equatable {
    public var receivedBuffers: UInt64 = 0, receivedFrames: UInt64 = 0, queuedBuffers: UInt64 = 0, queuedFrames: UInt64 = 0
    public var inputSampleRate: Double = 0
    public var timestampedBuffers: UInt64 = 0, discontinuities: UInt64 = 0, maximumGapFrames: Int64 = 0
    public var trimmedPaddingFrames: UInt64 = 0
    public var closeReason = "open"
    public var nativeError: SpeechNativeError?
    public var converterDrained = false
    public init() {}
}
/// No text/audio/clipboard/userInfo. Terminal values describe the instant BEFORE cleanup.
public struct DictationSpeechDiagnostics: Codable, Sendable, Equatable {
    public var sessionIdentifier = "notStarted", recognitionTaskIdentifier = "notStarted"
    public var recognitionTaskGeneration: UInt64 = 0
    public var timebase = "unselected", resultClassification = "none"
    public var incomingRangeStart: Double?, incomingRangeEnd: Double?, previousAcceptedRangeStart: Double?, previousAcceptedRangeEnd: Double?
    public var finalizedSegmentCount = 0
    public var rangeEvents: [String] = []
    public var provider: DictationSpeechProvider = .unselected
    public var requestedLocale = "unknown", resolvedLocale = "unknown", phase = "idle", taskState = "unknown"
    public var modernSpeechAssets = "uninspected", modernDictationAssets = "uninspected", preparation = "notAttempted", fallbackReason = "none"
    public var captureMilliseconds: Int64 = 0, recognitionMilliseconds: Int64 = 0
    public var captureActiveAtSnapshot = false, releaseRequested = false, stoppedBeforeRelease = false
    public var partialResults = 0, finalResults = 0, preservedSegments = 0, preservedBytes = 0
    public var unmergedCandidateBytes = 0, unmergedCandidateTooLarge = false
    public var legacyMetadataResults = 0, ignoredLegacyCallbacks = 0
    public var legacyMetadataStart: Double?, legacyMetadataDuration: Double?, legacyRangeStart: Double?, legacyRangeEnd: Double?
    public var legacyBoundaryPending = false
    public var stage: DictationSpeechStage?
    public var failure = "none", mergeRejection = "none"
    public var nativeError: SpeechNativeError?
    public var audio = DictationAudioDelivery()
    public init() {}
    private func locale(_ value: String) -> String {
        value.utf8.count <= 100 && value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,64,95].contains($0) }) ? value : "invalidLocale"
    }
    public var summary: String {
        let codes = nativeError.map { "error=\($0.primary.domain):\($0.primary.code) underlying=" + $0.underlying.map { "\($0.domain):\($0.code)" }.joined(separator:",") } ?? "error=none underlying=none"
        return "speechSession=\(sessionIdentifier) speechTask=\(recognitionTaskIdentifier) taskGeneration=\(recognitionTaskGeneration) timebase=\(timebase) resultClass=\(resultClassification) incomingStart=\(incomingRangeStart.map(String.init(describing:)) ?? "none") incomingEnd=\(incomingRangeEnd.map(String.init(describing:)) ?? "none") previousStart=\(previousAcceptedRangeStart.map(String.init(describing:)) ?? "none") previousEnd=\(previousAcceptedRangeEnd.map(String.init(describing:)) ?? "none") finalizedSegments=\(finalizedSegmentCount) rangeEvents=[\(rangeEvents.suffix(16).joined(separator:";"))] speechProvider=\(provider.rawValue) requestedLocale=\(locale(requestedLocale)) resolvedLocale=\(locale(resolvedLocale)) speechPhase=\(phase) taskState=\(taskState) captureMs=\(captureMilliseconds) recognitionMs=\(recognitionMilliseconds) activeAtSnapshot=\(captureActiveAtSnapshot) releaseRequested=\(releaseRequested) stoppedBeforeRelease=\(stoppedBeforeRelease) partialResults=\(partialResults) finalResults=\(finalResults) preservedSegments=\(preservedSegments) preservedBytes=\(preservedBytes) unmergedCandidateBytes=\(unmergedCandidateBytes) unmergedCandidateTooLarge=\(unmergedCandidateTooLarge) stage=\(stage?.rawValue ?? "none") failure=\(failure) mergeRejection=\(mergeRejection) legacyMetadataResults=\(legacyMetadataResults) ignoredLegacyCallbacks=\(ignoredLegacyCallbacks) legacyMetadataStart=\(legacyMetadataStart.map(String.init(describing:)) ?? "none") legacyMetadataDuration=\(legacyMetadataDuration.map(String.init(describing:)) ?? "none") legacyRangeStart=\(legacyRangeStart.map(String.init(describing:)) ?? "none") legacyRangeEnd=\(legacyRangeEnd.map(String.init(describing:)) ?? "none") legacyBoundaryPending=\(legacyBoundaryPending) preparation=\(preparation) modernSpeechAssets=\(modernSpeechAssets) modernDictationAssets=\(modernDictationAssets) fallback=\(fallbackReason) \(codes) audioBuffers=\(audio.receivedBuffers) audioFrames=\(audio.receivedFrames) queuedBuffers=\(audio.queuedBuffers) queuedFrames=\(audio.queuedFrames) inputRate=\(audio.inputSampleRate) timestampedBuffers=\(audio.timestampedBuffers) discontinuities=\(audio.discontinuities) maxGapFrames=\(audio.maximumGapFrames) audioClose=\(audio.closeReason) converterDrained=\(audio.converterDrained) trimmedPaddingFrames=\(audio.trimmedPaddingFrames)"
    }
    /// Apple documents these domain/code pairs for legacy tasks only.
    public var compactFailure: String {
        if stage == .audioConfiguration { return "Microphone interrupted" }
        if failure == "anotherInstance" { return "Another Flow copy" }
        if failure == "microphoneDenied" { return "Microphone access" }
        if failure == "speechDenied" { return "Speech access" }
        if failure == "assetsMissing" || failure == "unavailable" { return "Speech assets missing" }
        if failure == "busy" { return "Speech busy" }
        if failure == "audioUnavailable" { return "Microphone unavailable" }
        if failure == "noAudioCaptured" { return "No microphone audio" }
        if failure == "speechBelowThreshold" { return "Audio below speech threshold" }
        if failure == "noSpeechRecognized" { return "Local model returned no words" }
        if failure == "unsupportedRecognitionScript" { return "Wrong recognition script" }
        if failure == "repetitiveRecognition" { return "Recognition repeated" }
        if stage == .modernPreparation { return "Speech preparation failed" }
        if let error = nativeError {
            if provider == .legacyOnDevice {
                let errors = error.underlying + [error.primary]
                for value in errors {
                    switch (value.domain,value.code) {
                    case ("kLSRErrorDomain",102): return "Speech assets missing"
                    case ("kLSRErrorDomain",201): return "System dictation off"
                    case ("kLSRErrorDomain",300): return "Recognizer init failed"
                    case ("kLSRErrorDomain",301): return "Speech request cancelled"
                    case ("kAFAssistantErrorDomain",203): return "Recognition failed"
                    case ("kAFAssistantErrorDomain",1100): return "Speech already active"
                    case ("kAFAssistantErrorDomain",1101): return "Speech service reset"
                    case ("kAFAssistantErrorDomain",1107): return "Speech interrupted"
                    case ("kAFAssistantErrorDomain",1110): return "No speech recognized"
                    case ("kAFAssistantErrorDomain",1700): return "Speech access denied"
                    default: break
                    }
                }
            }
            return "Speech error \(error.primary.code)"
        }
        switch mergeRejection {
        case "volatilePrefixOverlap", "unmappedFinalizationBoundary": return "Speech timing unavailable"
        case "finalizedPrefixOverlap", "conflictingFinalizedRange": return "Final speech conflict"
        case "invalidRange", "invalidCMTime", "invalidWordTimebase", "invalidLegacyMetadata": return "Invalid speech timing"
        case "unverifiedLegacyPassageBoundary", "awaitingLegacyPassageAnchor": return "Speech boundary unclear"
        case "textBudget", "segmentBudget", "legacyRecoveryBudget": return "Dictation limit"
        case "regressedFinalization": return "Speech boundary regressed"
        case "none": break
        default: return "Speech range conflict"
        }
        if stage == .audioIngress { return "Audio delivery failed" }
        if failure == "providerEnded" { return "Speech provider ended" }
        if failure == "overflow" { return "Dictation limit" }
        if stage == .finalizationWatchdog { return "Finalization timed out" }
        return "Speech failed"
    }
    public var failureDescription: String {
        if failure == "anotherInstance" { return "Another Wesley Flow copy owns dictation. Finish or cancel recording and resolve clipboard recovery, then quit the other copy normally. Nothing was recorded or inserted." }
        let error = nativeError.map { " Native error \($0.primary.domain), code \($0.primary.code)." } ?? ""
        return compactFailure + "." + error + (preservedBytes > 0 ? " Available recognized text is incomplete and retained for review and explicit copy. Nothing was inserted." : " No recoverable text is available. Nothing was inserted.")
    }
}
public extension DictationCaptureReporting {
    var speechDiagnostics: DictationSpeechDiagnostics? { nil }
}

public struct DictationInstance: Sendable, Equatable {
    public let processID: Int32
    public let launchedAt: Double
    public init(processID: Int32, launchedAt: Double) { self.processID = processID; self.launchedAt = launchedAt }
}
public enum DictationInstanceAdmission {
    /// One deterministic owner; a secondary copy must never compete for the same gesture.
    public static func permits(processID: Int32, instances: [DictationInstance]) -> Bool {
        guard processID > 0, !instances.isEmpty, instances.count <= 32,
              instances.allSatisfy({ $0.processID > 0 && $0.launchedAt.isFinite }),
              Set(instances.map(\.processID)).count == instances.count else { return false }
        let owner = instances.min { $0.launchedAt == $1.launchedAt ? $0.processID < $1.processID : $0.launchedAt < $1.launchedAt }
        return owner?.processID == processID
    }
}

public enum DictationReleaseBoundary {
    public static func acceptsFinal(observedAt: Double, releaseAt: Double?, audioClosedCleanly: Bool = true) -> Bool {
        guard audioClosedCleanly, observedAt.isFinite, observedAt >= 0,
              let releaseAt, releaseAt.isFinite, releaseAt >= 0 else { return false }
        return observedAt >= releaseAt
    }
}

/// Ambiguous text is recovery data, never automatic insertion or diagnostic content.
@MainActor public protocol DictationRecoveryProviding: AnyObject {
    var unmergedRecognitionText: String? { get }
}

/// Vocabulary hints only; these names do not grant execution authority.
@MainActor public protocol AgentApplicationNameHinting: AnyObject {
    func setAgentApplicationNames(_ names:[String])
}
