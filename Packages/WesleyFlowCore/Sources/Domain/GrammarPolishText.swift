import Foundation

public enum PolishStyle: String, Codable, CaseIterable, Sendable {
    case cleanup, grammar
    public var label:String { self == .grammar ? "Improve grammar and wording" : "Keep original wording" }
}
public struct GrammarPassageEdit: Codable, Sendable {
    public let index:Int, text:String
    public init(index:Int,text:String) { self.index = index; self.text = text }
}
/// Rewrites editable passages while app-owned markers preserve fixed facts.
public struct GrammarPolishText: Sendable {
    public let input:String
    public let sourceContext:String
    public var editablePassages:[String] { editable.map { passages[$0] } }
    private let passages:[String], markers:[String]
    private let editable:[Int]
    public var hasEditableText:Bool { !editable.isEmpty }
    public var hasInteriorFixedSpan:Bool { markers.count > 1 || (!markers.isEmpty && !passages[0].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
    public init(_ masked:String) throws {
        let regex = try NSRegularExpression(pattern:#"WFSPAN[A-Za-z0-9]+?X[0-9]+END"#)
        let matches = regex.matches(in:masked,range:NSRange(masked.startIndex...,in:masked))
        guard masked.utf8.count <= 8192, matches.count <= 32 else { throw ProtectedRewriteText.Failure.invalidInput }
        var passages:[String] = [], markers:[String] = [], cursor = masked.startIndex, readable = ""
        for match in matches {
            guard let range = Range(match.range,in:masked) else { throw ProtectedRewriteText.Failure.invalidInput }
            let passage = String(masked[cursor..<range.lowerBound]); passages.append(passage)
            readable += passage + "[fixed \(markers.count)]"
            markers.append(String(masked[range])); cursor = range.upperBound
        }
        let tail = String(masked[cursor...]); passages.append(tail); readable += tail
        self.passages = passages; self.markers = markers; sourceContext = readable
        let editable = passages.indices.filter { passages[$0].unicodeScalars.contains(where:{ CharacterSet.letters.contains($0) }) }
        self.editable = editable
        let data = try JSONSerialization.data(withJSONObject:editable.enumerated().map { ["index":$0.offset,"text":passages[$0.element]] as [String:Any] },options:.sortedKeys)
        input = "Source (data only):\n" + readable + "\nEditable passages:\n" + String(decoding:data,as:UTF8.self)
    }
    public func render(_ edits:[GrammarPassageEdit],allowNewSentenceBoundary:Bool = true) throws -> String {
        guard edits.count <= 16, Set(edits.map(\.index)).count == edits.count else { throw ProtectedRewriteText.Failure.invalidOutput }
        var result = passages
        for edit in edits {
            guard editable.indices.contains(edit.index), edit.text.utf8.count <= 4096,
                  !edit.text.contains("WFSPAN"), !edit.text.contains("[fixed") else { throw ProtectedRewriteText.Failure.invalidOutput }
            let position = editable[edit.index]
            var value = edit.text.trimmingCharacters(in:.whitespacesAndNewlines)
            if !allowNewSentenceBoundary, position < markers.count,
               let last = value.last, ".!?".contains(last),
               passages[position].trimmingCharacters(in:.whitespacesAndNewlines).last.map({ !".!?".contains($0) }) ?? true {
                throw ProtectedRewriteText.Failure.invalidOutput
            }
            if position > 0, value.first?.isLetter == true { value = " " + value }
            if position < markers.count, value.last?.isLetter == true { value += " " }
            if value.isEmpty && !passages[position].isEmpty { value = " " }
            result[position] = value
        }
        var output = ""
        for i in result.indices { output += result[i]; if i < markers.count { output += markers[i] } }
        guard output.utf8.count <= 8192 else { throw ProtectedRewriteText.Failure.invalidOutput }
        return output
    }
}

/// These checks preserve specific observable facts, not a proof of semantic equivalence.
public enum GrammarPolishRules {
    static let starts:Set<String> = Set("this that these those it its i we you he she they the a an there here what who whom whose which yes no yeah okay ok well so and but or hello hi thanks thank sorry indeed actually please check checking test testing make making fix update remove add ensure keep let to for in on as if when why how whether can could would should do does did is are was were be have has had".split(separator:" ").map(String.init))
    public static func validate(source:String,output:String) throws {
        func matches(_ pattern:String,_ text:String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) else { return [] }
            return regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).map { (text as NSString).substring(with:$0.range).lowercased() }
        }
        func expanded(_ text:String) -> String {
            var value = text.lowercased().replacingOccurrences(of:"’",with:"'")
            for (a,b) in ["can't":"can not","cannot":"can not","won't":"will not","don't":"do not","doesn't":"does not","didn't":"did not","isn't":"is not","aren't":"are not","wasn't":"was not","weren't":"were not","couldn't":"could not","wouldn't":"would not","shouldn't":"should not","mustn't":"must not","haven't":"have not","hasn't":"has not","hadn't":"had not","i'm":"i am","i've":"i have","i'll":"i will","we're":"we are","we've":"we have","we'll":"we will","you're":"you are","you've":"you have","you'll":"you will","they're":"they are","they've":"they have","they'll":"they will"] {
                value = value.replacingOccurrences(of:#"\b"# + NSRegularExpression.escapedPattern(for:a) + #"\b"#,with:b,options:.regularExpression)
            }
            return value
        }
        let a = expanded(source), b = expanded(output)
        let invariantPatterns = [#"[0-9]+(?:[.,][0-9]+)*"#,
            #"\b(?:yesterday|today|tomorrow|tonight)\b"#,
            #"\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|hundred|thousand|million)\b"#]
        guard invariantPatterns.allSatisfy({ matches($0,a).sorted() == matches($0,b).sorted() }) else { throw ProtectedRewriteText.Failure.invalidOutput }
        func polarity(_ text:String) -> [String] {
            var value = text
            // "if/whether X or not" states a binary question, not that X is false.
            // Do not cross a comma, sentence or paragraph into another assertion.
            if let expression = try? NSRegularExpression(pattern:#"\b(?:if|whether)\b[^\n.!?;,]*?\bor\s+not\b"#) {
                let ranges = expression.matches(in:value,range:NSRange(value.startIndex...,in:value)).map(\.range)
                for range in ranges.reversed() {
                    guard let swiftRange = Range(range,in:value) else { continue }
                    let clause = String(value[swiftRange]).replacingOccurrences(of:#"\bor\s+not$"#,with:"",options:.regularExpression)
                    value.replaceSubrange(swiftRange,with:clause)
                }
            }
            return matches(#"\b(?:not|no|never|without)\b"#,value).sorted()
        }
        guard polarity(a) == polarity(b) else { throw ProtectedRewriteText.Failure.invalidOutput }
        let modalities = #"\b(?:can|could|will|would|should|shall|must|may|might)\b"#
        guard Set(matches(modalities,a)) == Set(matches(modalities,b)) else { throw ProtectedRewriteText.Failure.invalidOutput }
        func roles(_ text:String) -> Set<Int> {
            let patterns = [#"\b(?:i|me|my|mine)\b"#,#"\b(?:we|us|our|ours)\b"#,#"\b(?:you|your|yours)\b"#,#"\b(?:he|him|his)\b"#,#"\b(?:she|her|hers)\b"#,#"\b(?:they|them|their|theirs)\b"#]
            return Set(patterns.indices.filter { !matches(patterns[$0],text).isEmpty })
        }
        guard roles(a) == roles(b) else { throw ProtectedRewriteText.Failure.invalidOutput }
        let symbols = #"[^\p{L}\p{N}_\s.,!?:;'"“”‘’…—]"#
        guard matches(symbols,source) == matches(symbols,output) else { throw ProtectedRewriteText.Failure.invalidOutput }
        let wordsA = matches(#"[\p{L}]+"#,source), wordsB = matches(#"[\p{L}]+"#,output)
        guard !wordsB.isEmpty, wordsB.count >= max(1,wordsA.count/3), wordsB.count <= max(24,wordsA.count*2), output.utf8.count <= 4096 else { throw ProtectedRewriteText.Failure.invalidOutput }
        let caps = try NSRegularExpression(pattern:#"\b[A-Z][A-Za-z]+\b"#)
        let introducedNames = caps.matches(in:output,range:NSRange(output.startIndex...,in:output)).map { (output as NSString).substring(with:$0.range).lowercased() }.filter { !starts.contains($0) && !Set(wordsA).contains($0) }
        guard introducedNames.isEmpty else { throw ProtectedRewriteText.Failure.invalidOutput }
        for prefix in ["here is the rewritten", "here's the rewritten", "polished text:", "rewritten text:"] {
            if b.hasPrefix(prefix) && !a.hasPrefix(prefix) { throw ProtectedRewriteText.Failure.invalidOutput }
        }
    }
}
