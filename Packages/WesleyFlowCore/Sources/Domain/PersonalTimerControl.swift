import Foundation
public struct PersonalTimerControl:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case list,cancel}
    public let action:Action
    public let name:String
    public init(action:Action,name:String="") throws {guard name.utf8.count<=100,!name.unicodeScalars.contains(where:{$0.value<32}),action == .list || !name.isEmpty else {throw PersonalAgentError.invalidCommand};self.action=action;self.name=name}
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let v=try JSONDecoder().decode(Self.self,from:Data(text.utf8));return try Self(action:v.action,name:v.name)}
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input)
        if ["show my active timers","show active timers","list timers"].contains(text.lowercased()) {return try .init(steps:[.init(tool:.ownedTimers,text:try Self(action:.list).encoded())],createdAt:now)}
        if let re=try? NSRegularExpression(pattern:#"^cancel(?: my| the)? (.+?) timer$"#,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) {return try .init(steps:[.init(tool:.ownedTimers,text:try Self(action:.cancel,name:String(text[range])).encoded())],createdAt:now)}
        let pattern = #"^(?:set|start) (?:(?:a|an|the) )?(?:(.+?) )?timer for (.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let duration = Range(match.range(at: 2), in: text) {
            let name = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? "Timer"
            guard let plan = try durationReply(String(text[duration]), name: name, now: now, defaultToMinutes: false) else {
                throw PersonalAgentError.invalidCommand
            }
            return plan
        }
        return nil
    }

    static func durationReply(_ input: String, name: String = "Timer", now: Date, defaultToMinutes: Bool = true) throws -> PersonalPlan? {
        var words = PersonalAgentDialogue.canonical(input).lowercased().split(whereSeparator: \.isWhitespace)
        if words.first == "for" { words.removeFirst() }
        let multipliers = ["second": 1, "seconds": 1, "minute": 60, "minutes": 60, "hour": 3600, "hours": 3600]
        let multiplier: Int
        if let unit = words.last, let explicit = multipliers[String(unit)] {
            multiplier = explicit
            words.removeLast()
        } else {
            guard defaultToMinutes else { return nil }
            multiplier = 60
        }
        guard let amount = PersonalControlIntents.number(words.joined(separator: " ")),
              amount > 0, amount <= min(525_600, 31_536_000 / multiplier), name.utf8.count <= 100 else { return nil }
        return try PersonalPlan(steps: [.init(tool: .timer, text: name,
            date: now.addingTimeInterval(Double(amount * multiplier)))], createdAt: now)
    }
}
