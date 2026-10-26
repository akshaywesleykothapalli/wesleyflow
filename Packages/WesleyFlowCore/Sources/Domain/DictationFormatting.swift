import Foundation

public struct DictationPhraseReplacement: Codable, Equatable, Sendable {
    public var phrase: String
    public var replacement: String
    public init(phrase: String, replacement: String) { self.phrase = phrase; self.replacement = replacement }
}
public struct DictationFormattingOptions: Codable, Equatable, Sendable {
    public var spokenPunctuation = false
    public var sentenceCapitalization = false
    public var removeFillers = false
    public var removeRepeatedFillers = false
    public var correctSpelling = false
    public var smartTypography = false
    public var handleSelfCorrections = false
    public var vocabulary: [String] = []
    public var replacements: [DictationPhraseReplacement] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case spokenPunctuation, sentenceCapitalization, removeFillers, removeRepeatedFillers, correctSpelling, smartTypography, handleSelfCorrections, vocabulary, replacements }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        spokenPunctuation = try c.decode(Bool.self,forKey:.spokenPunctuation)
        sentenceCapitalization = try c.decode(Bool.self,forKey:.sentenceCapitalization)
        removeFillers = try c.decode(Bool.self,forKey:.removeFillers)
        removeRepeatedFillers = try c.decode(Bool.self,forKey:.removeRepeatedFillers)
        correctSpelling = try c.decode(Bool.self,forKey:.correctSpelling)
        smartTypography = try c.decodeIfPresent(Bool.self,forKey:.smartTypography) ?? false
        handleSelfCorrections = try c.decodeIfPresent(Bool.self,forKey:.handleSelfCorrections) ?? false
        vocabulary = try c.decode([String].self,forKey:.vocabulary)
        replacements = try c.decode([DictationPhraseReplacement].self,forKey:.replacements)
    }
    public var isValid: Bool {
        vocabulary.count <= 128 && replacements.count <= 64 &&
        vocabulary.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 && !$0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) } &&
        replacements.allSatisfy { !$0.phrase.isEmpty && $0.phrase.utf8.count <= 128 && $0.replacement.utf8.count <= 512 && !$0.phrase.contains(where: { $0.isNewline }) && !$0.replacement.unicodeScalars.contains(where:{ $0.properties.generalCategory == .control }) }
    }
}
/// Bounded literal transformations, with protected spans isolated before edits. Not a paraphraser.
public enum DictationFormatting {
    private struct Span { var text: String; var protected: Bool }
    public static func format(_ raw: String, options: DictationFormattingOptions, whitespace: Bool,
                              correction: ((String) -> String?)? = nil) -> String {
        guard raw.utf8.count <= DictationText.maximumBytes, options.isValid else { return raw }
        // Protect code, quoted paths, shell lines, URLs, identifiers, numbers and custom terms.
        var patterns = [#"(?s)```.*?```|`[^`\n]*`"#,
            #"[\"'][^\"'\n]*[/\\][^\"'\n]*[\"']"#,
            #"(?m)^[\t ]*(?:\$\s|(?:sudo|git|npm|swift|python3?|curl|rm|cd|ssh|brew)\s)[^\n]*"#,
            #"\S*[/\\_@=<>$|{}\[\]()0-9]\S*|\b[a-z]+[A-Z][A-Za-z]*\b|\b[A-Z]{2,}\b|\b[A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9]{1,12}\b"#]
        patterns += options.vocabulary.map { #"(?i)(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for:$0) + #"(?![\p{L}\p{N}_])"# }
        let ns = raw as NSString
        let baseRanges = patterns.flatMap { pattern in
            (try? NSRegularExpression(pattern:pattern).matches(in:raw,range:NSRange(location:0,length:ns.length)).map(\.range)) ?? []
        }
        // Explicit expansions become protected output; never spellcheck/rewrite their result.
        let aliases = options.replacements.flatMap { rule -> [NSRange] in
            let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for:rule.phrase) + #"(?![\p{L}\p{N}_])"#
            return ((try? NSRegularExpression(pattern:pattern).matches(in:raw,range:NSRange(location:0,length:ns.length)).map(\.range)) ?? []).filter { r in !baseRanges.contains(where:{ NSIntersectionRange($0,r).length > 0 }) }
        }
        let ranges = (baseRanges + aliases).sorted { $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location }
        var merged: [NSRange] = []
        for r in ranges {
            if let last = merged.last, r.location <= NSMaxRange(last) { merged[merged.count-1].length = max(NSMaxRange(last),NSMaxRange(r))-last.location }
            else { merged.append(r) }
        }
        var spans: [Span] = [], offset = 0
        for r in merged {
            if r.location > offset { spans.append(.init(text:ns.substring(with:NSRange(location:offset,length:r.location-offset)),protected:false)) }
            let original = ns.substring(with:r)
            let replacement = baseRanges.contains(where:{ NSIntersectionRange($0,r).length > 0 }) ? nil : options.replacements.first(where:{ $0.phrase.caseInsensitiveCompare(original) == .orderedSame })?.replacement
            spans.append(.init(text:replacement ?? original,protected:true)); offset = NSMaxRange(r)
        }
        if offset < ns.length { spans.append(.init(text:ns.substring(from:offset),protected:false)) }
        var budget = 128
        for index in spans.indices where !spans[index].protected {
            var text = spans[index].text
            // Only a fully explicit current-utterance restart, with no protected spans.
            // Bare/ambiguous correction cues and all earlier dictations remain untouched.
            if options.handleSelfCorrections, merged.isEmpty,
               let regex = try? NSRegularExpression(pattern:#"(?i)^.{1,256}[.!?]\s+scratch that[.!?]\s+(.+)$"#),
               let match = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),
               let replacement = Range(match.range(at:1),in:text) { text = String(text[replacement]) }
            if options.smartTypography {
                for (phrase,mark) in [("open quote","“"),("close quote","”"),("em dash","—")] { text = replacingWord(phrase,in:text,with:mark) }
            }
            if options.spokenPunctuation {
                for (phrase,replacement) in [("new paragraph","\n\n"),("new line","\n"),("question mark","?"),("exclamation mark","!"),("exclamation point","!"),("comma",","),("period","."),("full stop","."),("semicolon",";"),("colon",":")] {
                    text = replacingWord(phrase,in:text,with:replacement)
                }
                text = text.replacingOccurrences(of:#"[\t ]+([,.;:!?])"#,with:"$1",options:.regularExpression)
            }
            // Only isolated hesitation interjections; never delete conjunctions or repeated ordinary words.
            if options.removeFillers { text = text.replacingOccurrences(of:#"(?i)(?<![\p{L}\p{N}_])(?:um|uh|erm)(?:[, ]+|$)"#,with:"",options:.regularExpression) }
            else if options.removeRepeatedFillers { text = text.replacingOccurrences(of:#"(?i)\b(um|uh|erm)(?:[ ,]+\1)+\b"#,with:"$1",options:.regularExpression) }
            if options.correctSpelling, let correction, let regex = try? NSRegularExpression(pattern:#"\b[a-z]{3,40}\b"#) {
                let before = text
                for match in regex.matches(in:before,range:NSRange(before.startIndex...,in:before)).reversed() {
                    guard budget > 0 else { break }; budget -= 1
                    guard let r = Range(match.range,in:before) else { continue }; let word = String(before[r])
                    // Preserve programming keywords and meaningful small words, even when a dictionary disagrees.
                    guard !["and","or","but","not","let","var","func","class","struct","enum","actor","async","await","throws","nil","true","false","return","import","print"].contains(word),
                          let fixed = correction(word), fixed.count <= 64, !fixed.isEmpty,
                          fixed.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }), let destination = Range(match.range,in:text) else { continue }
                    text.replaceSubrange(destination,with:fixed)
                }
            }
            if whitespace {
                text = text.replacingOccurrences(of:options.spokenPunctuation ? #"[^\S\n]+"# : #"\s+"#,with:" ",options:.regularExpression)
                if options.spokenPunctuation { text = text.replacingOccurrences(of:#" *\n *"#,with:"\n",options:.regularExpression) }
            }
            spans[index].text = text
        }
        if options.sentenceCapitalization {
            var sentenceStart = true
            for index in spans.indices {
                if spans[index].protected { if !spans[index].text.isEmpty { sentenceStart = false }; continue }
                var output = ""
                for character in spans[index].text {
                    if sentenceStart && character.isLetter { output += String(character).uppercased(); sentenceStart = false }
                    else { output.append(character) }
                    if ".!?\n".contains(character) { sentenceStart = true }
                }
                spans[index].text = output
            }
        }
        let output = spans.map(\.text).joined().trimmingCharacters(in:.whitespacesAndNewlines)
        return output.utf8.count <= DictationText.maximumBytes ? output : raw
    }
    private static func replacingWord(_ phrase: String,in text: String,with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern:#"(?i)(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for:phrase) + #"(?![\p{L}\p{N}_])"#) else { return text }
        return regex.stringByReplacingMatches(in:text,range:NSRange(text.startIndex...,in:text),withTemplate:NSRegularExpression.escapedTemplate(for:replacement))
    }
}
