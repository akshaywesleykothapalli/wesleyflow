import Foundation

/// Extractive planning: the model supplies section indices, never new requirements or commands.
/// The renderer retains every source unit exactly once and in original order.
public struct PromptEngineeringContract: Sendable {
    public let numberedMaskedText: String
    private let lines: [String]
    private struct Plan: Decodable {
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
            guard Set(all.allKeys.map(\.stringValue)) == Set(Keys.allCases.map(\.rawValue)) else { throw ProtectedRewriteText.Failure.invalidOutput }
            let c = try decoder.container(keyedBy:Keys.self)
            objective = try c.decode([Int].self,forKey:.objective); context = try c.decode([Int].self,forKey:.context)
            requirements = try c.decode([Int].self,forKey:.requirements); constraints = try c.decode([Int].self,forKey:.constraints)
            expectedOutput = try c.decode([Int].self,forKey:.expectedOutput)
        }
    }
    public init(_ request:OfflineRewriteRequest) throws {
        let protected = try ProtectedRewriteText(request)
        let units = try protected.promptUnits()
        let original = units.map(\.original), masked = units.map(\.masked)
        guard !original.isEmpty, original.count <= 16, original.count == masked.count,
              !request.text.contains("```"),
              !original.contains(where:{ $0.trimmingCharacters(in:.whitespaces).hasPrefix("$") || $0.range(of:#"^\s*(?:sudo|rm|curl|bash|sh|python3?|swift|git|npm)\s"#,options:.regularExpression) != nil }) else { throw ProtectedRewriteText.Failure.invalidInput }
        lines = original
        numberedMaskedText = masked.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator:"\n")
    }
    /// Local extractive structure: exact source units, no generated requirements.
    public func renderLocally() throws -> String {
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
        let plan = Dictionary(uniqueKeysWithValues:zip(keys,sections))
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
        guard section >= 0, body == lines else { throw ProtectedRewriteText.Failure.invalidOutput }
    }
    public func render(_ output:String) throws -> String {
        guard output.utf8.count <= 4096, !output.contains("\\") else { throw ProtectedRewriteText.Failure.invalidOutput }
        // Keys may not be duplicated or escaped to bypass duplicate detection.
        for key in ["objective","context","requirements","constraints","expectedOutput"] {
            let regex = try NSRegularExpression(pattern:"\""+key+"\"\\s*:")
            guard regex.numberOfMatches(in:output,range:NSRange(output.startIndex...,in:output)) == 1 else { throw ProtectedRewriteText.Failure.invalidOutput }
        }
        let plan = try JSONDecoder().decode(Plan.self,from:Data(output.utf8))
        let sections = [("Objective",plan.objective),("Context",plan.context),("Requirements",plan.requirements),("Constraints",plan.constraints),("Expected output",plan.expectedOutput)]
        guard !plan.objective.isEmpty, sections.flatMap({$0.1}) == Array(lines.indices) else { throw ProtectedRewriteText.Failure.invalidOutput }
        let rendered = sections.filter { !$0.1.isEmpty }.map { title,indices in "## "+title+"\n"+indices.map { lines[$0] }.joined(separator:"\n") }.joined(separator:"\n\n")
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
