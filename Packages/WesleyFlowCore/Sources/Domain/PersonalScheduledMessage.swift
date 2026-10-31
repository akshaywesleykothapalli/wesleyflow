import Foundation
public struct PersonalScheduledMessage:Codable,Sendable,Equatable,Identifiable {
    public enum State:String,Codable,Sendable {case pending,claimed,cancelled}
    public let id:UUID
    public let message:PersonalMessage
    public let date:Date
    public var state:State
    public init(id:UUID,message:PersonalMessage,date:Date,state:State = .pending) throws {
        guard let address=message.address,PersonalMessage.validAddress(address),date.timeIntervalSince1970.isFinite else {throw PersonalAgentError.invalidCommand}
        _=try PersonalMessage.decode(message.encoded());self.id=id;self.message=message;self.date=date;self.state=state
    }
}
public struct PersonalMessageSchedule:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case create,cancel}
    public let action:Action
    public var message:PersonalMessage?
    public var date:Date?
    public var recipient:String
    public var recordID:UUID?
    public init(action:Action,message:PersonalMessage?=nil,date:Date?=nil,recipient:String="",recordID:UUID?=nil) throws {
        guard recipient.utf8.count<=200 else {throw PersonalAgentError.invalidCommand}
        if let message {_ = try PersonalMessage.decode(message.encoded())}
        if action == .create {guard let message,let address=message.address,PersonalMessage.validAddress(address),let date,date.timeIntervalSince1970.isFinite else {throw PersonalAgentError.invalidCommand}}
        else {guard !recipient.isEmpty else {throw PersonalAgentError.invalidCommand}}
        self.action=action;self.message=message;self.date=date;self.recipient=recipient;self.recordID=recordID
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));return try .init(action:c.action,message:c.message,date:c.date,recipient:c.recipient,recordID:c.recordID)}
    public var summary:String {if action == .cancel {return "Cancel the pending scheduled message to "+recipient+"; no dispatched message can be recalled"};return "Schedule a LOCAL DRAFT for "+(date?.formatted() ?? "time needed")+" · To: "+(message?.recipient ?? "")+" ("+(message?.address ?? "")+") · “"+(message?.body ?? "")+"”. At that time a notification asks you to review and send. There is no automatic sending."}
    public static func plan(message:PersonalMessage,date:Date,now:Date) throws ->PersonalPlan {
        guard date.timeIntervalSince(now)>=60,date.timeIntervalSince(now)<=90*86400 else {throw PersonalAgentError.invalidCommand}
        return try .init(steps:[.init(tool:.messageSchedule,text:try Self(action:.create,message:message,date:date).encoded())],createdAt:now,requiresReview:true)
    }
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input)
        guard let re=try? NSRegularExpression(pattern:#"^cancel my scheduled message to (.+)$"#,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) else {return nil}
        let c=try Self(action:.cancel,recipient:String(text[range]))
        return try .init(steps:[.init(tool:.messageSchedule,text:try c.encoded())],createdAt:now,requiresReview:true)
    }
}
