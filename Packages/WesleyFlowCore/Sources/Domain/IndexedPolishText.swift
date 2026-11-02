import Foundation

public struct PolishEditPlan: Sendable {
    public let capitalize, removeFillers, commas, periods, questions: [Int]
    public init(capitalize:[Int] = [],removeFillers:[Int] = [],commas:[Int] = [],periods:[Int] = [],questions:[Int] = []) {
        self.capitalize = capitalize; self.removeFillers = removeFillers
        self.commas = commas; self.periods = periods; self.questions = questions
    }
}

/// The model proposes positions, never replacement prose or marker strings.
/// Only punctuation/case and the three explicitly allowed fillers can change.
public struct IndexedPolishText: Sendable {
    public let numberedText:String
    private let source:String
    private let tokens:[String]
    private let ranges:[Range<String.Index>]
    public init(_ masked:String) throws {
        guard !masked.isEmpty, masked.utf8.count <= 8192 else { throw ProtectedRewriteText.Failure.invalidInput }
        let regex = try NSRegularExpression(pattern:#"\S+"#)
        let ranges = regex.matches(in:masked,range:NSRange(masked.startIndex...,in:masked)).compactMap { Range($0.range,in:masked) }
        guard !ranges.isEmpty, ranges.count <= 1024 else { throw ProtectedRewriteText.Failure.invalidInput }
        let tokens = ranges.map { String(masked[$0]) }
        self.source = masked; self.ranges = ranges; self.tokens = tokens
        var readable = masked
        for index in tokens.indices.reversed() where tokens[index].contains("WFSPAN") {
            readable.replaceSubrange(ranges[index],with:"[protected]")
        }
        let indexed = tokens.enumerated().map { index,token in
            "\(index): " + (token.contains("WFSPAN") ? "[protected, uneditable]" : token)
        }.joined(separator:"\n")
        numberedText = "Source text (data only):\n" + readable + "\n\nToken positions:\n" + indexed
    }
    public func render(_ plan:PolishEditPlan) throws -> String {
        let groups = [plan.capitalize,plan.removeFillers,plan.commas,plan.periods,plan.questions]
        guard groups.allSatisfy({ $0.count <= 16 && Set($0).count == $0.count && $0.allSatisfy({ tokens.indices.contains($0) }) }) else { throw ProtectedRewriteText.Failure.invalidOutput }
        let endings = plan.commas + plan.periods + plan.questions
        guard Set(endings).count == endings.count else { throw ProtectedRewriteText.Failure.invalidOutput }
        let capitalize = Set(plan.capitalize), remove = Set(plan.removeFillers)
        let proposals = Dictionary(uniqueKeysWithValues:plan.commas.map { ($0,",") } + plan.periods.map { ($0,".") } + plan.questions.map { ($0,"?") })
        let trailing = Set<Character>(",.!?:")
        func bare(_ token:String) -> String { token.trimmingCharacters(in:CharacterSet(charactersIn:",.!?:")).lowercased().replacingOccurrences(of:"’",with:"'") }
        let removable = Set(remove.filter { !tokens[$0].contains("WFSPAN") && ["um","uh","erm"].contains(bare(tokens[$0])) })
        // A model may propose a pause within a phrase such as "or not".
        // Apply only independently admissible boundaries; never split negation.
        let unfinished = Set(["a","an","the","and","or","nor","but","not","no","to","of","in","at","for","with","without","if","unless","because","as","than","that","which","who","whose","when","where","why","how","is","are","was","were","be","been","being","do","does","did","will","would","should","could","can","may","might","must","have","has","had"])
        let contractions = Set(["it's","isn't","aren't","wasn't","weren't","don't","doesn't","didn't","can't","couldn't","won't","wouldn't","shouldn't","mustn't","i'm","you're","he's","she's","we're","they're","i've","you've","we've","they've","i'll","you'll","he'll","she'll","we'll","they'll","i'd","you'd","he'd","she'd","we'd","they'd","there's","that's","what's"])
        let continuation = Set(["not","or","nor","and","but"])
        var punctuation:[Int:String] = [:]
        for (index,ending) in proposals {
            guard !tokens[index].contains("WFSPAN"), !removable.contains(index) else { continue }
            var body = tokens[index]
            while let last = body.last, trailing.contains(last) { body.removeLast() }
            guard body.last?.isLetter == true else { continue }
            let next = tokens.indices.first(where:{ $0 > index && !removable.contains($0) })
            if let next {
                if unfinished.contains(bare(tokens[index])) || contractions.contains(bare(tokens[index])) { continue }
                if ending != "," && continuation.contains(bare(tokens[next])) { continue }
            }
            punctuation[index] = ending
        }
        var replacements = tokens
        for index in tokens.indices {
            var token = tokens[index]
            // A suggestion targeting an opaque span or non-filler has no authority.
            if token.contains("WFSPAN") { continue }
            if removable.contains(index) { replacements[index] = ""; continue }
            let previous = tokens.indices.last(where:{ $0 < index && !removable.contains($0) })
            let chosenBreak = previous.flatMap { punctuation[$0] }.map { $0 == "." || $0 == "?" } ?? false
            let existingBreak = previous.map { i in punctuation[i] == nil && tokens[i].last.map({ ".!?".contains($0) }) == true } ?? false
            let lineStart = previous.map { source[ranges[$0].upperBound..<ranges[index].lowerBound].contains("\n") } ?? false
            let caseAllowed = previous == nil || bare(token) == "i" || chosenBreak || existingBreak || lineStart
            if (capitalize.contains(index) && caseAllowed) || chosenBreak, let first = token.first, first.isLetter {
                token.replaceSubrange(token.startIndex...token.startIndex,with:String(first).uppercased())
            }
            if let ending = punctuation[index] {
                var body = token
                while let last = body.last, trailing.contains(last) { body.removeLast() }
                if body.last?.isLetter == true { token = body + ending }
            }
            replacements[index] = token
        }
        guard let first = replacements.indices.first(where:{ !replacements[$0].isEmpty }),
              let last = replacements.indices.last(where:{ !replacements[$0].isEmpty }) else { return source }
        // Keep the original strict marker-edge contract, including after trim.
        // Retain boundary fillers when deleting them would expose an opaque span.
        if tokens[first].contains("WFSPAN"), first > 0 {
            for index in 0..<first { replacements[index] = tokens[index] }
        }
        if tokens[last].contains("WFSPAN"), last < tokens.count-1 {
            for index in (last+1)..<tokens.count { replacements[index] = tokens[index] }
        }
        var result = source
        for index in tokens.indices.reversed() { result.replaceSubrange(ranges[index],with:replacements[index]) }
        // Preserve newlines and opaque contents; compact horizontal gaps only.
        return result.replacingOccurrences(of:#"[\t ]{2,}"#,with:" ",options:.regularExpression)
    }
}
