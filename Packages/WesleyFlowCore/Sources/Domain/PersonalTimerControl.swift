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
        if let re=try? NSRegularExpression(pattern:#"^set (?:a |an )?(.+?) timer for (.+?) (seconds?|minutes?|hours?)$"#,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) {
            let values=(1...3).compactMap{Range(m.range(at:$0),in:text).map{String(text[$0])}}
            guard values.count==3,values[0].utf8.count<=100,let n=PersonalControlIntents.number(values[1]),n>0,n<=525600 else {throw PersonalAgentError.invalidCommand}
            let seconds=Double(n)*(values[2].lowercased().hasPrefix("hour") ? 3600:values[2].lowercased().hasPrefix("minute") ? 60:1)
            guard seconds<=31536000 else {throw PersonalAgentError.invalidCommand}
            return try .init(steps:[.init(tool:.timer,text:values[0],date:now.addingTimeInterval(seconds))],createdAt:now)
        }
        return nil
    }
}
