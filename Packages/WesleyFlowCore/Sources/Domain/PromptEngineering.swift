import Foundation

/// App-owned prompt layout preserves every source unit in order.
/// Explicit AI mode accepts guarded prose edits; local formatting remains extractive.
public struct PromptEngineeringContract: Sendable {
    public let numberedMaskedText: String
    private let lines: [String]
    private let immutableUnits:Set<Int>
    private let rewriteSources:[ProtectedRewriteText]
    private let rewritePassages:[GrammarPolishText]
    private let rewriteMap:[(unit:Int,passage:Int)]
    private struct UnitRewrite:Decodable { let index:Int; let edits:[GrammarPassageEdit] }
    private struct Plan: Decodable {
        let rewrites:[UnitRewrite]
        let objective: [Int]
        let context: [Int]
        let requirements: [Int]
        let constraints: [Int]
        let expectedOutput: [Int]
        private enum Keys: String, CodingKey, CaseIterable { case objective, context, requirements, constraints, expectedOutput }
        private struct AnyKey: CodingKey {
            let stringValue: String; var intValue: Int? { nil }
            init?(stringValue:String) { self.stringValue = stringValue }; init?(intValue:Int) { return nil }
        }
        init(from decoder:any Decoder) throws {
            let all = try decoder.container(keyedBy:AnyKey.self)
            let keys = Set(all.allKeys.map(\.stringValue)), required = Set(Keys.allCases.map(\.rawValue))
            guard keys == required || keys == required.union(["rewrites"]) else { throw ProtectedRewriteText.Failure.invalidOutput }
            rewrites = try all.decodeIfPresent([UnitRewrite].self,forKey:AnyKey(stringValue:"rewrites")!) ?? []
            let c = try decoder.container(keyedBy:Keys.self)
            objective = try c.decode([Int].self,forKey:.objective); context = try c.decode([Int].self,forKey:.context)
            requirements = try c.decode([Int].self,forKey:.requirements); constraints = try c.decode([Int].self,forKey:.constraints)
            expectedOutput = try c.decode([Int].self,forKey:.expectedOutput)
        }
    }
    public init(_ request:OfflineRewriteRequest,allowRewriting:Bool = false) throws {
        let protected = try ProtectedRewriteText(request)
        let units = try protected.promptUnits()
        let original = units.map(\.original), masked = units.map(\.masked)
        guard !original.isEmpty, original.count <= 16, original.count == masked.count,
              !request.text.contains("```"),
              !original.contains(where:{ $0.trimmingCharacters(in:.whitespaces).hasPrefix("$") || $0.range(of:#"^\s*(?:sudo|rm|curl|bash|sh|python3?|swift|git|npm)\s"#,options:.regularExpression) != nil }) else { throw ProtectedRewriteText.Failure.invalidInput }
        lines = original
        let constraintPrefixes = ["keep ","preserve ","do not ","don't ","never ","without ","constraints:"]
        immutableUnits = Set(original.indices.filter { index in constraintPrefixes.contains { original[index].trimmingCharacters(in:.whitespaces).lowercased().hasPrefix($0) } })
        if allowRewriting {
            rewriteSources = try original.enumerated().map { index,text in
                // Strip only an explicit request preamble, never an asserted fact or negation.
                var prose = text.replacingOccurrences(of:#"(?i)^(?:I want (?:you )?to |I would like (?:you )?to |I'd like (?:you )?to |Please )"#,with:"",options:.regularExpression)
                if let first = prose.first { prose = String(first).uppercased()+prose.dropFirst() }
                let action = prose.split(whereSeparator:{ !$0.isLetter }).first.map(String.init) ?? ""
                let actions:Set<String> = Set("check fix create implement build investigate inspect review compare summarize explain write add remove update return provide deliver report ensure keep preserve help".split(separator:" ").map(String.init))
                let vocabulary = request.vocabulary + (actions.contains(action.lowercased()) ? [action] : [])
                return try ProtectedRewriteText(.init(id:"prompt-\(index)",text:prose,localeIdentifier:request.localeIdentifier,vocabulary:vocabulary,polishStyle:.grammar))
            }
            rewritePassages = try rewriteSources.map { try GrammarPolishText($0.masked) }
            var mapping:[(unit:Int,passage:Int)] = [], editable:[[String:Any]] = []
            for (unit,contract) in rewritePassages.enumerated() where !immutableUnits.contains(unit) {
                for (passage,text) in contract.editablePassages.enumerated() {
                    editable.append(["index":mapping.count,"text":text]); mapping.append((unit,passage))
                }
            }
            rewriteMap = mapping
            let data = try JSONSerialization.data(withJSONObject:["sourceUnits":rewritePassages.map(\.sourceContext),"editablePassages":editable],options:.sortedKeys)
            numberedMaskedText = String(decoding:data,as:UTF8.self)
        } else {
            rewriteSources = []; rewritePassages = []; rewriteMap = []
            numberedMaskedText = masked.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator:"\n")
        }
        guard numberedMaskedText.utf8.count <= 16384 else { throw ProtectedRewriteText.Failure.invalidInput }
    }
    /// Local extractive structure: exact source units, no generated requirements.
    private func localPlan() -> [String:[Int]] {
        var sections = Array(repeating:[Int](),count:5), current = 0
        for (index,line) in lines.enumerated() {
            if index > 0 {
                let lower = line.trimmingCharacters(in:.whitespaces).lowercased()
                let prefixes:[(Int,[String])] = [(1,["context:","background:"]),(2,["requirements:","must ","ensure "]),(3,["constraints:","keep ","preserve ","do not ","don't ","without "]),(4,["output:","return ","deliver ","report ","provide "])]
                if let next = prefixes.first(where:{ $0.1.contains(where:{lower.hasPrefix($0)}) })?.0, next >= current { current = next }
            }
            sections[current].append(index)
        }
        let keys = ["objective","context","requirements","constraints","expectedOutput"]
        return Dictionary(uniqueKeysWithValues:zip(keys,sections))
    }
    public func renderLocally() throws -> String {
        let plan = localPlan()
        let data = try JSONSerialization.data(withJSONObject:plan,options:.sortedKeys)
        let output = try render(String(decoding:data,as:UTF8.self))
        try validateRendered(output)
        return output
    }
    /// Revalidate the existing renderer's restored output, never accept invented section content.
    public func validateRendered(_ output:String) throws {
        guard output.utf8.count <= 4096 else { throw ProtectedRewriteText.Failure.invalidOutput }
        let headings = ["## Objective","## Context","## Requirements","## Constraints","## Expected output"]
        var section = -1, body:[String] = []
        for line in output.components(separatedBy:"\n").filter({ !$0.isEmpty }) {
            if let next = headings.firstIndex(of:line) {
                guard next > section, section >= 0 || next == 0 else { throw ProtectedRewriteText.Failure.invalidOutput }
                section = next
            } else { guard section >= 0 else { throw ProtectedRewriteText.Failure.invalidOutput }; body.append(line) }
        }
        guard section >= 0, body.count == lines.count else { throw ProtectedRewriteText.Failure.invalidOutput }
        if rewriteSources.isEmpty { guard body == lines else { throw ProtectedRewriteText.Failure.invalidOutput } }
        else { for i in lines.indices where body[i] != lines[i] { guard !immutableUnits.contains(i) else { throw ProtectedRewriteText.Failure.invalidOutput }; try rewriteSources[i].validateRestored(body[i]) } }
    }
    public func render(_ output:String) throws -> String {
        guard output.utf8.count <= 4096, !output.contains("\\") else { throw ProtectedRewriteText.Failure.invalidOutput }
        if !rewriteSources.isEmpty, let object = try JSONSerialization.jsonObject(with:Data(output.utf8)) as? [String:Any], Set(object.keys) == ["edits"] {
            let editKeys = try NSRegularExpression(pattern:#""edits"\s*:"#)
            guard editKeys.numberOfMatches(in:output,range:NSRange(output.startIndex...,in:output)) == 1 else { throw ProtectedRewriteText.Failure.invalidOutput }
            struct Reply:Decodable { let edits:[GrammarPassageEdit] }
            let edits = try JSONDecoder().decode(Reply.self,from:Data(output.utf8)).edits
            guard edits.count <= 16, Set(edits.map(\.index)).count == edits.count else { throw ProtectedRewriteText.Failure.invalidOutput }
            var grouped:[Int:[GrammarPassageEdit]] = [:]
            for edit in edits {
                guard rewriteMap.indices.contains(edit.index) else { throw ProtectedRewriteText.Failure.invalidOutput }
                let mapping = rewriteMap[edit.index]
                grouped[mapping.unit,default:[]].append(.init(index:mapping.passage,text:edit.text))
            }
            var plan:[String:Any] = localPlan().mapValues { $0 as Any }
            plan["rewrites"] = grouped.keys.sorted().map { unit in ["index":unit,"edits":grouped[unit]!.map { ["index":$0.index,"text":$0.text] as [String:Any] }] as [String:Any] }
            let data = try JSONSerialization.data(withJSONObject:plan,options:.sortedKeys)
            return try render(String(decoding:data,as:UTF8.self))
        }
        // Keys may not be duplicated or escaped to bypass duplicate detection.
        for key in ["objective","context","requirements","constraints","expectedOutput"] {
            let regex = try NSRegularExpression(pattern:"\""+key+"\"\\s*:")
            guard regex.numberOfMatches(in:output,range:NSRange(output.startIndex...,in:output)) == 1 else { throw ProtectedRewriteText.Failure.invalidOutput }
        }
        let duplicates = try NSRegularExpression(pattern:#""rewrites"\s*:"#)
        guard duplicates.numberOfMatches(in:output,range:NSRange(output.startIndex...,in:output)) <= 1 else { throw ProtectedRewriteText.Failure.invalidOutput }
        let plan = try JSONDecoder().decode(Plan.self,from:Data(output.utf8))
        guard plan.rewrites.count <= 16, Set(plan.rewrites.map(\.index)).count == plan.rewrites.count else { throw ProtectedRewriteText.Failure.invalidOutput }
        var prose = lines
        for rewrite in plan.rewrites {
            guard rewritePassages.indices.contains(rewrite.index) else { throw ProtectedRewriteText.Failure.invalidOutput }
            let candidate = try rewritePassages[rewrite.index].render(rewrite.edits)
            let restored = try rewriteSources[rewrite.index].restoreAndValidate(candidate)
            guard !restored.contains("\n"), !restored.contains("\r") else { throw ProtectedRewriteText.Failure.invalidOutput }
            guard !immutableUnits.contains(rewrite.index) || restored == lines[rewrite.index] else { throw ProtectedRewriteText.Failure.invalidOutput }
            prose[rewrite.index] = restored
        }
        let sections = [("Objective",plan.objective),("Context",plan.context),("Requirements",plan.requirements),("Constraints",plan.constraints),("Expected output",plan.expectedOutput)]
        guard !plan.objective.isEmpty, sections.flatMap({$0.1}) == Array(lines.indices) else { throw ProtectedRewriteText.Failure.invalidOutput }
        let rendered = sections.filter { !$0.1.isEmpty }.map { title,indices in "## "+title+"\n"+indices.map { prose[$0] }.joined(separator:"\n") }.joined(separator:"\n\n")
        guard rendered.utf8.count <= 4096 else { throw ProtectedRewriteText.Failure.invalidOutput }
        return rendered
    }
}

public enum PreviewShortcutSignal: Sendable { case pressed(OfflinePreviewKind), released(OfflinePreviewKind), cancelled }
/// A release invokes at most once, only for a valid matching press in the same focus context.
public struct PreviewShortcutGesture: Sendable {
    private var held: Set<OfflinePreviewKind> = []
    private var context: Int32?
    public init() {}
    public mutating func accept(_ signal:PreviewShortcutSignal,secureInput:Bool,focus:Int32) -> OfflinePreviewKind? {
        guard !secureInput else { held.removeAll(); context = nil; return nil }
        switch signal {
        case .cancelled: held.removeAll(); context = nil
        case .pressed(let kind):
            if context != nil && context != focus { held.removeAll() }
            context = focus; held.insert(kind)
        case .released(let kind):
            let valid = held.remove(kind) != nil && context == focus
            if held.isEmpty { context = nil }
            return valid ? kind : nil
        }
        return nil
    }
}
public enum PreviewShortcutFailure: Error, Sendable { case systemConflict, registration(Int32), layoutUnsupported, secureInput, holdToTalkConflict }
public enum PreviewShortcutNotification: Sendable { case invoke(OfflinePreviewKind), invokeFrom(OfflinePreviewKind, processIdentifier: Int32), unavailable, secureInput, suspended, resumed }
@MainActor public protocol PreviewShortcutRegistering: AnyObject {
    func enable(kinds:Set<OfflinePreviewKind>,receive:@escaping @MainActor @Sendable (PreviewShortcutNotification) -> Void) throws
    func disable()
}
