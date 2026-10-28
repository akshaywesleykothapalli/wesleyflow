import Foundation

public enum DictationRewriteValidationFailure: String, Error, Sendable, CaseIterable {
    case permission, secureInput, editorUnavailable, targetChanged, expired, consumed
    case unsupportedEditor, compositionUnavailable, invalidRange, textUnavailable
    case textMismatch, contextChanged, caretChanged
}
/// Metadata only. Deliberately cannot carry text, hashes, titles or application content.
public struct DictationVerificationDiagnostic: Sendable, Equatable {
    public enum Stage: String, Sendable { case target, element, freshness, composition, range, text, context, caret }
    public enum Result: String, Sendable { case matched, different, unavailable, valid, invalid, fresh, expired, unsupported, exactUTF16 }
    public let stage: Stage
    public let result: Result
    public let expectedUTF16: Int?
    public let currentUTF16: Int?
    public init(_ stage: Stage,_ result: Result,expected: Int? = nil,current: Int? = nil) {
        self.stage = stage; self.result = result; self.expectedUTF16 = expected; self.currentUTF16 = current
    }
}
