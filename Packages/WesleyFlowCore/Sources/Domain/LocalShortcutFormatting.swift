import Foundation

public enum FormattingShortcutAction: String, Codable, CaseIterable, Sendable {
    case lastInsertion, nextRecording
    public var label:String { self == .nextRecording ? "Next recording · local formatting" : "Last insertion · on-device AI" }
}
/// Explicit, deterministic formatting. It never runs a model or invents source content.
public enum LocalShortcutFormatting {
    public static func format(_ text:String,kind:OfflinePreviewKind) throws -> String {
        let request = OfflineRewriteRequest(id:UUID().uuidString,text:text,localeIdentifier:"en-IN",kind:kind)
        if kind == .promptEngineering { return try PromptEngineeringContract(request).renderLocally() }
        let protected = try ProtectedRewriteText(request)
        var result = protected.masked.replacingOccurrences(of:#"(?i)(?<![\p{L}\p{N}_])(?:um|uh|erm)(?![\p{L}\p{N}_])(?:[, ]+)?"#,with:"",options:.regularExpression)
        result = DictationText.cleaned(result)
        if let first = result.first, first.isLowercase { result.replaceSubrange(result.startIndex...result.startIndex,with:String(first).uppercased()) }
        if let last = result.last, last.isLetter, !result.hasSuffix("END") { result += "." }
        // If an opaque span's edge would change, preserve the source rather than guessing.
        return try protected.restoreAndValidate(result)
    }
}
