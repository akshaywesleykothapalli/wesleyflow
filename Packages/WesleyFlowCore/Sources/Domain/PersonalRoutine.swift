import Foundation
public struct PersonalRoutineDefinition:Codable,Sendable,Equatable,Identifiable {
    public let id:UUID
    public let name:String
    public let steps:[PersonalStep]
    public let createdAt:Date
    public init(id:UUID=UUID(),name:String,steps:[PersonalStep],createdAt:Date=Date()) throws {
        guard !name.isEmpty,name.utf8.count<=80,!name.unicodeScalars.contains(where:{$0.value<32}),!steps.contains(where:{$0.tool == .routineSave || $0.tool == .messageSchedule}) else {throw PersonalAgentError.invalidCommand}
        guard steps.allSatisfy({$0.date==nil || $0.tool == .timer}) else {throw PersonalAgentError.unsupported}
        for step in steps where step.tool == .recordAction {guard try PersonalRecordCommand.decode(step.text).date==nil else {throw PersonalAgentError.unsupported}}
        _ = try PersonalPlan(steps:steps,createdAt:createdAt)
        self.id=id;self.name=name;self.steps=steps;self.createdAt=createdAt
    }
    public func freshPlan(now:Date) throws ->PersonalPlan {
        let fresh=try steps.map{step in
            var date=step.date
            if let original=date {let offset=original.timeIntervalSince(createdAt);guard offset>0,offset<=31536000 else {throw PersonalAgentError.invalidCommand};date=now.addingTimeInterval(offset)}
            return PersonalStep(tool:step.tool,text:step.text,date:date)
        }
        return try .init(steps:fresh,createdAt:now,requiresReview:true)
    }
}
public struct PersonalRoutineSave:Codable,Sendable,Equatable {
    public let definition:PersonalRoutineDefinition
    public let replacing:UUID?
    public init(definition:PersonalRoutineDefinition,replacing:UUID?=nil) {self.definition=definition;self.replacing=replacing}
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));_ = try PersonalRoutineDefinition(id:c.definition.id,name:c.definition.name,steps:c.definition.steps,createdAt:c.definition.createdAt);return c}
}
