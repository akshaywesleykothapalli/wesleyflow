import Foundation
import Domain

/// Shared by initial insertion verification and native rewrite provenance.
/// The fixed original replacement range disambiguates duplicate occurrences;
/// no substring search, whitespace trimming, newline or Unicode normalization.
struct DictationInsertionExpectation: Sendable {
    let document: String
    let span: TextSelection
    let insertedText: String
    init(original:TargetTextState,insertedText:String) throws {
        guard let document = original.selection.replacing(in:original.text,with:insertedText) else { throw DictationRewriteValidationFailure.invalidRange }
        self.document = document; self.span = .init(location:original.selection.location,length:insertedText.utf16.count); self.insertedText = insertedText
    }
    static func exact(_ a:String,_ b:String) -> Bool { a.utf16.elementsEqual(b.utf16) }
    static func readSpan(_ document:String,range:TextSelection) throws -> String {
        guard range.location >= 0, range.length >= 0, range.location <= document.utf16.count,
              range.length <= document.utf16.count-range.location,
              let a = document.utf16.index(document.utf16.startIndex,offsetBy:range.location).samePosition(in:document),
              let b = document.utf16.index(document.utf16.startIndex,offsetBy:range.location+range.length).samePosition(in:document) else { throw DictationRewriteValidationFailure.invalidRange }
        return String(document[a..<b])
    }
    func verified(_ observed:String?,record:(DictationVerificationDiagnostic)->Void = { _ in }) throws -> String {
        guard let observed else { record(.init(.text,.unavailable,expected:document.utf16.count)); throw DictationRewriteValidationFailure.textUnavailable }
        try Self.validateSpan(observed,range:span,insertedText:insertedText,record:record)
        guard Self.exact(document,observed) else { record(.init(.context,.different,expected:document.utf16.count,current:observed.utf16.count)); throw DictationRewriteValidationFailure.contextChanged }
        record(.init(.context,.matched,expected:document.utf16.count,current:observed.utf16.count))
        return observed
    }
    func matches(_ observed:String?) -> Bool { (try? verified(observed)) != nil }
    static func validateSpan(_ observed:String,range:TextSelection,insertedText:String,record:(DictationVerificationDiagnostic)->Void) throws {
        let text:String
        do { text = try readSpan(observed,range:range); record(.init(.range,.valid,expected:range.length,current:observed.utf16.count)) }
        catch { record(.init(.range,.invalid,expected:range.length,current:observed.utf16.count)); throw error }
        let equal = exact(text,insertedText)
        record(.init(.text,equal ? .matched : .different,expected:insertedText.utf16.count,current:text.utf16.count))
        record(.init(.text,.exactUTF16)) // Policy: no implicit normalization is permitted.
        guard equal else { throw DictationRewriteValidationFailure.textMismatch }
    }
    static func validateCaret(_ caret:TextSelection?,span:TextSelection,selected:TextSelection? = nil) throws {
        guard let caret else { throw DictationRewriteValidationFailure.invalidRange }
        if let selected { guard caret == selected else { throw DictationRewriteValidationFailure.caretChanged }; return }
        // Standard editors may either leave the inserted span selected or place
        // a collapsed caret at its end. Both refer to the proven exact own span.
        guard caret == span || caret == TextSelection(location:span.location+span.length,length:0) else { throw DictationRewriteValidationFailure.caretChanged }
    }
}

/// Optional descriptive metadata is distinct from required read/write capabilities.
enum DictationRewriteCapabilities {
    static func validateEditor(subrole:String?,editable:Bool) throws {
        let subrole = subrole ?? ""
        guard !subrole.lowercased().contains("secure"), !subrole.lowercased().contains("password") else { throw DictationRewriteValidationFailure.secureInput }
        guard editable else { throw DictationRewriteValidationFailure.unsupportedEditor }
    }
    static func validateComposition(markedLength:Int?, standardKeyboardUnchanged:Bool = false, inputUntouched:Bool = false) throws {
        // Missing AXMarkedTextRange is common for committed native/web text.
        // Only a stable keyboard layout (never an IME) and an armed input fence
        // permit this fallback. Malformed or positive ranges never use it.
        guard let markedLength else {
            guard standardKeyboardUnchanged && inputUntouched else { throw DictationRewriteValidationFailure.compositionUnavailable }
            return
        }
        guard markedLength >= 0 else { throw DictationRewriteValidationFailure.compositionUnavailable }
        guard markedLength == 0 else { throw DictationRewriteValidationFailure.secureInput }
    }
}
