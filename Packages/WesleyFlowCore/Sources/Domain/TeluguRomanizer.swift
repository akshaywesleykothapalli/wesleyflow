import Foundation

public enum DictationLanguageMode: String, Codable, CaseIterable, Sendable {
    case english, teluguRomanised
    public var label: String { self == .english ? "English (existing engine)" : "Telugu (Romanised)" }
}
public enum TeluguRecognitionLanguage: String, Codable, CaseIterable, Sendable {
    case automatic, teluguOnly
    public var label: String { self == .automatic ? "Automatic · Telugu + English" : "Telugu only" }
    public var whisperLanguage: String { self == .automatic ? "auto" : "te" }
}
/// Independent of audio, UI, dictionaries and recognizers. Latin spans remain byte-for-byte unchanged.
public enum TeluguRomanizer {
    private static let vowels: [UInt32:String] = [
        0x0C05:"a",0x0C06:"aa",0x0C07:"i",0x0C08:"ee",0x0C09:"u",0x0C0A:"oo",
        0x0C0B:"ru",0x0C0C:"lu",0x0C0E:"e",0x0C0F:"e",0x0C10:"ai",0x0C12:"o",0x0C13:"o",0x0C14:"au",
        0x0C60:"roo",0x0C61:"loo"]
    private static let signs: [UInt32:String] = [
        0x0C3E:"aa",0x0C3F:"i",0x0C40:"ee",0x0C41:"u",0x0C42:"oo",0x0C43:"ru",0x0C44:"roo",
        0x0C46:"e",0x0C47:"e",0x0C48:"ai",0x0C4A:"o",0x0C4B:"o",0x0C4C:"au",0x0C62:"lu",0x0C63:"loo"]
    private static let consonants: [UInt32:String] = [
        0x0C15:"k",0x0C16:"kh",0x0C17:"g",0x0C18:"gh",0x0C19:"ng",
        0x0C1A:"ch",0x0C1B:"chh",0x0C1C:"j",0x0C1D:"jh",0x0C1E:"ny",
        0x0C1F:"t",0x0C20:"th",0x0C21:"d",0x0C22:"dh",0x0C23:"n",
        0x0C24:"t",0x0C25:"th",0x0C26:"d",0x0C27:"dh",0x0C28:"n",
        0x0C2A:"p",0x0C2B:"ph",0x0C2C:"b",0x0C2D:"bh",0x0C2E:"m",
        0x0C2F:"y",0x0C30:"r",0x0C31:"r",0x0C32:"l",0x0C33:"l",0x0C34:"l",0x0C35:"v",
        0x0C36:"sh",0x0C37:"sh",0x0C38:"s",0x0C39:"h",0x0C58:"ts",0x0C59:"dz",0x0C5A:"r"]
    public static func romanise(_ text: String) -> String {
        // Normalize only Telugu runs: decomposed Latin identifiers must remain untouched.
        var normalized = "", run = ""
        func flush() { normalized += run.precomposedStringWithCanonicalMapping; run = "" }
        for scalar in text.unicodeScalars {
            if (0x0C00...0x0C7F).contains(scalar.value) || scalar.value == 0x200C || scalar.value == 0x200D { run.unicodeScalars.append(scalar) }
            else { flush(); normalized.unicodeScalars.append(scalar) }
        }
        flush()
        var result = "", inherent = false, teluguContext = false
        func finishConsonant() { if inherent { result += "a"; inherent = false } }
        let scalars = Array(normalized.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            let value = scalar.value
            if let stem = consonants[value] { finishConsonant(); result += stem; inherent = true; teluguContext = true }
            else if let vowel = signs[value] { inherent = false; result += vowel; teluguContext = true }
            else if value == 0x0C4D { inherent = false; teluguContext = true }
            else if value == 0x0C3C { continue } // Nukta modifies pronunciation, never adds a vowel.
            else if (value == 0x200C || value == 0x200D) && teluguContext { continue }
            else {
                finishConsonant()
                if let vowel = vowels[value] { result += vowel }
                else if value == 0x0C00 || value == 0x0C01 || value == 0x0C02 {
                    // Colloquial nasal spelling before velar/palatal/retroflex/dental stops.
                    let next = index + 1 < scalars.count ? scalars[index + 1].value : 0
                    result += (0x0C15...0x0C28).contains(next) ? "n" : "m"
                }
                else if value == 0x0C03 { result += "h" }
                else if (0x0C66...0x0C6F).contains(value) { result += String(value - 0x0C66) }
                else if value == 0x0C55 { result += "e" }
                else if value == 0x0C56 { result += "ai" }
                else { result.unicodeScalars.append(scalar) }
                teluguContext = (0x0C00...0x0C7F).contains(value)
            }
        }
        finishConsonant(); return result
    }
}

/// Conservative whole-token restoration only; never guesses arbitrary English from similar sounds.
public enum TeluguDictationText {
    public static let loanwords = ["మీటింగ్":"meeting", "కాల్":"call", "ఆఫీస్":"office", "ఫైల్":"file", "మెసేజ్":"message", "ఈమెయిల్":"email", "ప్రాజెక్ట్":"project", "కోడ్":"code", "టీమ్":"team", "లింక్":"link", "అప్డేట్":"update"]
    public static func render(_ raw: String, overrides: [DictationPhraseReplacement] = [], whitespace: Bool = true) -> String {
        guard raw.utf8.count <= DictationText.maximumBytes else { return raw }
        let rules = overrides.filter { !$0.phrase.isEmpty }.sorted { $0.phrase.count > $1.phrase.count }
        func replace(_ input: String, transform: (String) -> String) -> String {
            let escaped = rules.map { NSRegularExpression.escapedPattern(for:$0.phrase) }
            guard !escaped.isEmpty, let regex = try? NSRegularExpression(pattern:"(?i)(?<![\\p{L}\\p{M}\\p{N}_])(?:" + escaped.joined(separator:"|") + ")(?![\\p{L}\\p{M}\\p{N}_])") else { return transform(input) }
            var output = "", cursor = input.startIndex
            for match in regex.matches(in:input,range:NSRange(input.startIndex...,in:input)) {
                guard let range = Range(match.range,in:input) else { continue }
                output += transform(String(input[cursor..<range.lowerBound]))
                output += rules.first { $0.phrase.caseInsensitiveCompare(String(input[range])) == .orderedSame }?.replacement ?? String(input[range])
                cursor = range.upperBound
            }
            return output + transform(String(input[cursor...]))
        }
        let output = replace(raw) { span in
            let regex = try! NSRegularExpression(pattern:#"[\p{L}\p{M}\p{N}_\x{200C}\x{200D}]+"#)
            var rendered = "", cursor = span.startIndex
            for match in regex.matches(in:span,range:NSRange(span.startIndex...,in:span)) {
                guard let range = Range(match.range,in:span) else { continue }
                let token = String(span[range])
                let containsTelugu = token.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) }
                rendered += span[cursor..<range.lowerBound]
                if containsTelugu {
                    let roman = TeluguRomanizer.romanise(token)
                    let restored = loanwords[token.precomposedStringWithCanonicalMapping] ?? roman
                    rendered += rules.first { $0.phrase.caseInsensitiveCompare(roman) == .orderedSame || $0.phrase.caseInsensitiveCompare(restored) == .orderedSame }?.replacement ?? restored
                } else { rendered += token }
                cursor = range.upperBound
            }
            rendered += span[cursor...]
            return rendered
        }
        return whitespace ? DictationText.cleaned(output) : output
    }
}
