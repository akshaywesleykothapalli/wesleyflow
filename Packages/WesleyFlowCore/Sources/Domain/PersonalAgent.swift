import Foundation

/// Closed capabilities: no script, shell, generated tool, URL scheme or recipient execution.
public enum PersonalTool: String, Codable, Sendable, CaseIterable {
    case note, reminder, calendar, openApp, safari, timer, music, spotify, openInstalledApp, closeApp, minimizeApp, restoreApp, fullScreenApp, exitFullScreenApp, maximizeApp, searchGoogle, searchYouTube, createFolder, openFolder, closeFolder, findFolder, trashFolder, searchBrowser, systemAudio, browserControl, message
}
public struct PersonalStep: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let tool: PersonalTool
    public let text: String
    public let date: Date?
    public init(id: UUID = UUID(), tool: PersonalTool, text: String, date: Date? = nil) {
        self.id = id; self.tool = tool; self.text = text; self.date = date
    }
}
public struct PersonalPlan: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let steps: [PersonalStep]
    public let createdAt: Date
    public init(id: UUID = UUID(), steps: [PersonalStep], createdAt: Date = Date()) throws {
        guard !steps.isEmpty, steps.count <= 8, Set(steps.map(\.id)).count == steps.count,
              steps.allSatisfy({ !$0.text.isEmpty && $0.text.utf8.count <= 2048 }) else { throw PersonalAgentError.invalidCommand }
        self.id = id; self.steps = steps; self.createdAt = createdAt
    }
}
public enum PersonalAgentError: Error, Equatable, Sendable {
    case invalidCommand, unsupported, permissionDenied, verificationFailed, busy, storageFull, approvalRequired, interrupted
}
/// Grounded English grammar. Every clause must parse, or the entire request is rejected.
/// No inference is needed. ISO-8601 dates include timezone; relative minutes bind at intake.
public enum PersonalIntentParser {
    private static func minutes(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let words = ["one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"fifteen":15,"twenty":20,"thirty":30,"forty":40,"forty-five":45,"sixty":60]
        return words[text.lowercased()]
    }
    public static func parse(_ input: String, now: Date = Date()) throws -> PersonalPlan {
        guard input.utf8.count <= 4096, !input.isEmpty else { throw PersonalAgentError.invalidCommand }
        var clauses: [String] = []
        var remainder = input[input.startIndex...]
        while let split = remainder.range(of:" then ",options:.caseInsensitive) {
            clauses.append(String(remainder[..<split.lowerBound])); remainder = remainder[split.upperBound...]
            guard clauses.count < 8 else { throw PersonalAgentError.invalidCommand }
        }
        clauses.append(String(remainder))
        guard clauses.count <= 8 else { throw PersonalAgentError.invalidCommand }
        let steps = try clauses.map { raw -> PersonalStep in
            let clause = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let operation = clause.trimmingCharacters(in:CharacterSet(charactersIn:".!?"))
            let lower = operation.lowercased()
            func tail(_ prefix: String) -> String { String(operation.dropFirst(prefix.count)).trimmingCharacters(in:.whitespaces) }
            for prefix in ["create note ","create a note "] where lower.hasPrefix(prefix) {
                return PersonalStep(tool:.note,text:String(clause.dropFirst(prefix.count)).trimmingCharacters(in:.whitespaces))
            }
            if lower.hasPrefix("open "), let app = AppOpeningCommand.parse(clause) { return PersonalStep(tool:.openApp,text:app.rawValue) }
            if lower.hasPrefix("open safari https://"), let url = URL(string:tail("open safari ")),
               url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
                return PersonalStep(tool:.safari,text:url.absoluteString)
            }
            if lower.hasPrefix("set a timer for "), lower.hasSuffix(" minutes"),
               let count = minutes(String(operation.dropFirst(16).dropLast(8))), (1...525600).contains(count) {
                return PersonalStep(tool:.timer,text:"Timer",date:now.addingTimeInterval(Double(count)*60))
            }
            for (prefix, tool) in [("remind me ",PersonalTool.reminder),("calendar ",.calendar),("timer ",.timer)] {
                if lower.hasPrefix(prefix) {
                    let value = tail(prefix)
                    if let range = value.range(of:" in ",options:.backwards), value.hasSuffix(" minutes"),
                       let minutes = minutes(String(value[range.upperBound...].dropLast(8))), (1...525600).contains(minutes) {
                        return PersonalStep(tool:tool,text:String(value[..<range.lowerBound]),date:now.addingTimeInterval(Double(minutes)*60))
                    }
                    if let range = value.range(of:" at ",options:.backwards),
                       let date = ISO8601DateFormatter().date(from:String(value[range.upperBound...])), date > now {
                        return PersonalStep(tool:tool,text:String(value[..<range.lowerBound]),date:date)
                    }
                    throw PersonalAgentError.invalidCommand
                }
            }
            for tool in [PersonalTool.music,.spotify] {
                let prefix = tool.rawValue + " "
                if lower.hasPrefix(prefix), ["play","pause"].contains(tail(prefix)) {
                    return PersonalStep(tool:tool,text:tail(prefix))
                }
            }
            throw PersonalAgentError.unsupported
        }
        return try PersonalPlan(steps:steps,createdAt:now)
    }
}
public enum PersonalStepState: String, Codable, Sendable { case pending, executing, verified, failed, uncertain }
public enum PersonalTaskState: String, Codable, Sendable { case awaitingApproval, running, completed, failed, cancelled, needsReview }
public struct PersonalReceipt: Codable, Equatable, Sendable {
    public let identifier: String
    public let evidence: String
    public let verified: Bool
    public init(identifier: String, evidence: String, verified:Bool = true) { self.identifier = identifier; self.evidence = evidence; self.verified=verified }
    private enum CodingKeys:String,CodingKey { case identifier,evidence,verified }
    public init(from decoder:any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        identifier=try c.decode(String.self,forKey:.identifier);evidence=try c.decode(String.self,forKey:.evidence)
        verified=try c.decodeIfPresent(Bool.self,forKey:.verified) ?? true
    }
}
public struct PersonalTaskRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { plan.id }
    public let plan: PersonalPlan
    public var state: PersonalTaskState = .awaitingApproval
    public var steps: [PersonalStepState]
    public var receipts: [Int:PersonalReceipt] = [:]
    public var diagnostic: String?
    public init(plan: PersonalPlan) { self.plan = plan; self.steps = plan.steps.map { _ in .pending } }
}
@MainActor public protocol PersonalToolRunning {
    func perform(_ step: PersonalStep) async throws -> PersonalReceipt
}
