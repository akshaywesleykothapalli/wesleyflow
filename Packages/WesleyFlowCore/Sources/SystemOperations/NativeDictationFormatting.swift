import AppKit
import Domain

/// Apple spelling service only, opt-in, bounded and per-document. No model or network client.
@MainActor public enum NativeDictationFormatting {
    public static func format(_ text: String, options: DictationFormattingOptions, whitespace: Bool, locale: String) -> String {
        guard options.correctSpelling else { return DictationFormatting.format(text,options:options,whitespace:whitespace) }
        let checker = NSSpellChecker.shared
        let language = locale.replacingOccurrences(of:"-",with:"_")
        guard let selected = checker.availableLanguages.first(where:{ $0 == language }) ?? checker.availableLanguages.first(where:{ $0.split(separator:"_").first == language.split(separator:"_").first }) else {
            return DictationFormatting.format(text,options:options,whitespace:whitespace)
        }
        let tag = NSSpellChecker.uniqueSpellDocumentTag(); defer { checker.closeSpellDocument(withTag:tag) }
        checker.setIgnoredWords(options.vocabulary,inSpellDocumentWithTag:tag)
        return DictationFormatting.format(text,options:options,whitespace:whitespace) { word in
            checker.correction(forWordRange:NSRange(word.startIndex...,in:word),in:word,language:selected,inSpellDocumentWithTag:tag)
        }
    }
}
