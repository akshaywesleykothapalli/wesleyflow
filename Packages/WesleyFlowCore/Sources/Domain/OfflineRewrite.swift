import Foundation

public enum OfflineRewriteStatus: String, Sendable, Codable {
    case rewritten, unchanged, modelUnavailable, resourceBlocked, cancelled, invalidOutput, timedOut
}
public enum OfflineRewriteTone: String, Codable, CaseIterable, Sendable {
    case natural, professional, concise, friendly, direct
    public var instruction: String {
        switch self {
        case .natural: "Natural: make everyday speech easy to read with normal sentence boundaries. Remove isolated um/uh/erm; retain conversational wording."
        case .professional: "Professional: use workplace-appropriate sentence capitalization and restrained punctuation. Remove um/uh/erm; no greetings, emphasis or added wording."
        case .concise: "Concise: remove every isolated um/uh/erm and redundant whitespace; use minimal punctuation. Preserve every requirement and all content words."
        case .friendly: "Friendly: keep an approachable conversational rhythm with gentle punctuation; retain informal wording. No invented enthusiasm, sentiment or greetings."
        case .direct: "Direct: separate requests into clear statements; remove um/uh/erm and avoid exclamation marks. Preserve politeness, negations and requirements."
        }
    }
}
public enum OfflinePreviewKind: String, Codable, CaseIterable, Sendable { case polish, promptEngineering }
public struct OfflineRewriteRequest: Sendable {
    public let id: String
    public let text: String
    public let localeIdentifier: String
    public let vocabulary: [String]
    public let kind: OfflinePreviewKind
    public let tone: OfflineRewriteTone
    public init(id: String, text: String, localeIdentifier: String, vocabulary: [String] = [], tone: OfflineRewriteTone = .natural, kind: OfflinePreviewKind = .polish) {
        self.id = id; self.text = text; self.localeIdentifier = localeIdentifier; self.vocabulary = vocabulary; self.tone = tone; self.kind = kind
    }
}
public struct OfflineRewriteOutcome: Sendable {
    public let status: OfflineRewriteStatus
    public let text: String
    public let elapsedMilliseconds: Int64
    public let reason: String
    public init(_ status: OfflineRewriteStatus, text: String, elapsedMilliseconds: Int64 = 0, reason: String = "") {
        self.status = status; self.text = text; self.elapsedMilliseconds = elapsedMilliseconds; self.reason = reason
    }
}
public protocol OfflineTranscriptRewriting: Sendable {
    func rewrite(_ request: OfflineRewriteRequest) async -> OfflineRewriteOutcome
    func cancel(requestID: String) async
}

/// Pure reversible protection plus a conservative lexical fidelity gate. Not semantic proof.
public struct ProtectedRewriteText: Sendable {
    public let masked: String
    private let spans: [(marker: String, text: String)]
    private let original: String
    private let prefix: String
    public init(_ request: OfflineRewriteRequest) throws {
        guard !request.id.isEmpty, request.id.utf8.count <= 64,
              request.id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }),
              !request.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, request.text.utf8.count <= 2048,
              request.vocabulary.count <= 128, request.vocabulary.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { throw Failure.invalidInput }
        let prefix = "WFSPAN" + request.id.replacingOccurrences(of:"-",with:"") + "X"
        guard !request.text.contains("WFSPAN") else { throw Failure.invalidInput }
        var patterns = [#"(?s)```.*?```|`[^`\n]*`"#,
            #"(?m)^[\t ]*(?:\$\s|(?:sudo|git|npm|swift|python3?|curl|rm|cd|ssh|brew)\s)[^\n]*"#,
            #"\S*[/\\_@=<>$|{}\[\]()0-9+⌘⌥⌃⇧]\S*|\b[a-z]+[A-Z][A-Za-z]*\b|\b[A-Z][A-Za-z]+\b"#,
            #"\b[0-9]+(?:\.[0-9]+)?\s*(?:kg|g|mg|km|cm|mm|m|ms|seconds?|minutes?|hours?|GB|GiB|MB|MiB|percent|%)\b"#]
        patterns.append(#"\b[A-Za-z][A-Za-z0-9_-]*\.[A-Za-z0-9]{1,12}\b|(?<!\S)\.[A-Za-z][A-Za-z0-9_-]*"#)
        patterns += request.vocabulary.map { #"(?i)(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for:$0) + #"(?![\p{L}\p{N}_])"# }
        let ns = request.text as NSString
        var ranges: [NSRange] = []
        for pattern in patterns {
            let expression = try NSRegularExpression(pattern:pattern)
            ranges.append(contentsOf:expression.matches(in:request.text,range:NSRange(location:0,length:ns.length)).map { $0.range })
        }
        ranges.sort { left,right in left.location == right.location ? left.length > right.length : left.location < right.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, range.location <= NSMaxRange(last) { merged[merged.count-1].length = max(NSMaxRange(last),NSMaxRange(range))-last.location }
            else { merged.append(range) }
        }
        guard merged.count <= 32 else { throw Failure.invalidInput }
        var spans: [(marker: String,text: String)] = [], masked = request.text
        for (index,range) in merged.enumerated() { spans.append((prefix+String(index)+"END",ns.substring(with:range))) }
        for (range,span) in zip(merged,spans).reversed() {
            guard let r = Range(range,in:masked) else { throw Failure.invalidInput }; masked.replaceSubrange(r,with:span.marker)
        }
        guard masked.utf8.count <= 8192 else { throw Failure.invalidInput }
        // Initial release supports English prose only. Mixed scripts fail closed,
        // while exact protected vocabulary/code may contain any valid Unicode.
        guard !masked.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.value > 127 }) else { throw Failure.unsupportedLanguage }
        self.masked = masked; self.spans = spans; original = request.text; self.prefix = prefix
    }
    /// Segment only visible prose boundaries: code, URLs, decimal values and
    /// protected vocabulary are opaque markers before splitting. No source words
    /// are generated, removed or reordered. Conservative missed splits are safe.
    func promptUnits() throws -> [(original: String, masked: String)] {
        let expression = try NSRegularExpression(pattern: #"(?<=[.!?;])[^\S\n]+|\n+"#)
        let separated = expression.stringByReplacingMatches(in: masked, range: NSRange(masked.startIndex..., in: masked), withTemplate: "\n")
        let units = separated.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !units.isEmpty, units.count <= 16 else { throw Failure.invalidInput }
        return units.map { unit in
            var restored = unit
            for span in spans { restored = restored.replacingOccurrences(of: span.marker, with: span.text) }
            return (restored, unit)
        }
    }
    /// Revalidate an already restored provider response before an optional destructive effect.
    public func validateRestored(_ text:String) throws {
        var masked = text
        var cursor = masked.startIndex
        for span in spans {
            guard let range = masked.range(of:span.text,range:cursor..<masked.endIndex) else { throw Failure.invalidOutput }
            let offset = masked.distance(from:masked.startIndex,to:range.lowerBound)
            masked.replaceSubrange(range,with:span.marker)
            cursor = masked.index(masked.startIndex,offsetBy:offset + span.marker.count)
        }
        guard try restoreAndValidate(masked) == text else { throw Failure.invalidOutput }
    }
    public enum Failure: Error, Equatable { case invalidInput, unsupportedLanguage, invalidOutput }
    public func restoreAndValidate(_ output: String) throws -> String {
        guard !output.isEmpty, output.utf8.count <= 8192,
              !output.unicodeScalars.contains(where:{ CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) else { throw Failure.invalidOutput }
        let regex = try NSRegularExpression(pattern:NSRegularExpression.escapedPattern(for:prefix)+#"[0-9]+END"#)
        let actual = regex.matches(in:output,range:NSRange(output.startIndex...,in:output)).map { (output as NSString).substring(with:$0.range) }
        guard actual == spans.map(\.marker) else { throw Failure.invalidOutput }
        // Prevent added signs, command suffixes or punctuation attaching to an
        // opaque identifier/number/path. Preserve newline versus space boundaries.
        func edge(_ text: String,_ range: Range<String.Index>,before: Bool) -> String {
            let c: Character?
            if before { c = range.lowerBound == text.startIndex ? nil : text[text.index(before:range.lowerBound)] }
            else { c = range.upperBound == text.endIndex ? nil : text[range.upperBound] }
            guard let c else { return "" }; return c.isNewline ? "\n" : c.isWhitespace ? " " : String(c)
        }
        for span in spans {
            guard let sourceRange = masked.range(of:span.marker), let resultRange = output.range(of:span.marker),
                  edge(masked,sourceRange,before:true) == edge(output,resultRange,before:true),
                  edge(masked,sourceRange,before:false) == edge(output,resultRange,before:false) else { throw Failure.invalidOutput }
        }
        var restored = output
        for span in spans { restored = restored.replacingOccurrences(of:span.marker,with:span.text) }
        guard !restored.contains("WFSPAN"), restored.utf8.count <= 4096,
              Self.ledger(output) == Self.ledger(masked) else { throw Failure.invalidOutput }
        // Marker restoration is exact and ordered; content words may not be
        // added/removed/reordered. Only fillers, punctuation and case can differ.
        let refined = restored.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !refined.isEmpty else { throw Failure.invalidOutput }
        return refined
    }
    private static func ledger(_ text: String) -> [String] {
        let regex = try? NSRegularExpression(pattern:#"[\p{L}\p{N}_]+|[^\p{L}\p{N}_\s.,!?:'"“”‘’…]"#)
        return (regex?.matches(in:text,range:NSRange(text.startIndex...,in:text)) ?? []).map { (text as NSString).substring(with:$0.range).lowercased() }
            .filter { !["um","uh","erm"].contains($0) }
    }
}

/// Read-only readiness inspection; it never creates a model session or reserves resources.
public struct OfflineRewriteReadiness: Equatable, Sendable {
    public enum Status: String, Sendable { case ready, busy, unsupportedLanguage, modelUnavailable, resourcesBlocked, observationFailed }
    public let status:Status
    public let explanation:String
    public init(_ status:Status,_ explanation:String) { self.status = status; self.explanation = explanation }
}
public protocol OfflineRewriteReadinessInspecting: Sendable {
    func inspectReadiness(localeIdentifier:String) async -> OfflineRewriteReadiness
}
