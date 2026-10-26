/// Speech produces editable data, never task/permission authority.
public enum DictationFailure: Error, Sendable, Equatable {
    case microphoneDenied, speechDenied, unavailable, assetsMissing, audioUnavailable
    case busy, recognitionFailed, overflow, timedOut
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
public enum DictationText {
    public static let maximumBytes = 16_384
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
