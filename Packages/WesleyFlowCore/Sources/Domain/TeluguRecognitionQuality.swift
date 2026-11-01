import Foundation

/// Output admission for Telugu/English dictation. Rejects unreliable output; never guesses a correction.
public enum TeluguRecognitionQuality {
    public static func failure(in text: String) -> DictationFailure? {
        if text.unicodeScalars.contains(where:{ $0.value == 0xFFFD }) { return .recognitionFailed }
        if text.unicodeScalars.contains(where:{ scalar in
            guard CharacterSet.letters.contains(scalar) else { return false }
            let value = scalar.value
            return !((0x0041...0x007A).contains(value) || (0x00C0...0x024F).contains(value) ||
                     (0x1E00...0x1EFF).contains(value) || (0x0C00...0x0C7F).contains(value) ||
                     (0x0300...0x036F).contains(value) || (0x1AB0...0x1AFF).contains(value) ||
                     (0x1DC0...0x1DFF).contains(value) || (0xFE20...0xFE2F).contains(value) ||
                     (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value))
        }) { return .unsupportedRecognitionScript }
        // Long runs within a word, not ordinary repeated words or doubled Telugu consonants.
        // Eight identical motifs and >=24 graphemes is deliberately conservative.
        for word in text.split(whereSeparator:{ $0.isWhitespace || $0.isPunctuation }) {
            let letters = Array(word.lowercased())
            if word.unicodeScalars.contains(where:{ (0x0C00...0x0C7F).contains($0.value) }) {
                var repeated = 1
                for i in letters.indices.dropFirst() {
                    repeated = letters[i] == letters[i - 1] ? repeated + 1 : 1
                    if repeated >= 6 { return .repetitiveRecognition }
                }
            }
            guard letters.count >= 24 else { continue }
            for width in 1...min(8,letters.count / 8) {
                var run = width
                for i in width..<letters.count {
                    if letters[i] == letters[i - width] {
                        run += 1
                        if run >= max(24,width * 8) { return .repetitiveRecognition }
                    } else { run = width }
                }
            }
        }
        let words = text.lowercased().split(whereSeparator:{ $0.isWhitespace || $0.isPunctuation }).map(String.init)
        if words.count >= 24 {
            for width in 1...min(8,words.count / 12) {
                var run = width
                for i in width..<words.count {
                    if words[i] == words[i - width] {
                        run += 1
                        if run >= max(24,width * 12) { return .repetitiveRecognition }
                    } else { run = width }
                }
            }
        }
        return nil
    }
    /// Metadata only. No transcript fragments, token IDs or user vocabulary.
    public static func scriptCounts(_ text: String) -> String {
        var telugu = 0, latin = 0, other = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            switch scalar.value {
            case 0x0C00...0x0C7F: telugu += 1
            case 0x0041...0x007A,0x00C0...0x024F,0x1E00...0x1EFF: latin += 1
            default: other += 1
            }
        }
        return "teluguLetters=\(telugu) latinLetters=\(latin) otherLetters=\(other)"
    }
}
