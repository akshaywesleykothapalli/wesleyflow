import Foundation
public struct PersonalRecordCommand:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {
        case remindersToday,remindersOverdue,reminderList,reminderComplete,reminderReschedule,reminderRename,reminderMove,reminderFlag,reminderDelete,reminderFind
        case calendarAgenda,calendarFree,calendarFind,calendarOpen,calendarRename,calendarMove,calendarExtend,calendarDelete,calendarAlarm,calendarLocation
    }
    public let action:Action
    public var name:String
    public var value:String
    public var date:Date?
    public var identity:String?
    public var fingerprint:String?
    public var calendarID:String?
    public var scopeName:String?
    public init(action:Action,name:String="",value:String="",date:Date?=nil,identity:String?=nil,fingerprint:String?=nil,calendarID:String?=nil,scopeName:String?=nil) throws {
        guard name.utf8.count<=200,value.utf8.count<=200,identity?.utf8.count ?? 0<=512,fingerprint?.utf8.count ?? 0<=1000,!name.unicodeScalars.contains(where:{$0.value<32}),!value.unicodeScalars.contains(where:{$0.value<32}),date?.timeIntervalSince1970.isFinite ?? true else {throw PersonalAgentError.invalidCommand}
        self.action=action;self.name=name;self.value=value;self.date=date;self.identity=identity;self.fingerprint=fingerprint;self.calendarID=calendarID;self.scopeName=scopeName
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));return try .init(action:c.action,name:c.name,value:c.value,date:c.date,identity:c.identity,fingerprint:c.fingerprint,calendarID:c.calendarID,scopeName:c.scopeName)}
    public var isMutation:Bool {![.remindersToday,.remindersOverdue,.reminderFind,.calendarAgenda,.calendarFree,.calendarFind,.calendarOpen,.calendarLocation].contains(action)}
    public var summary:String {
        let verb:String=switch action {case .remindersToday:"Show reminders due today";case .remindersOverdue:"Show overdue reminders";case .reminderList:"Create reminder list";case .reminderComplete:"Complete reminder";case .reminderReschedule:"Reschedule reminder";case .reminderRename:"Rename reminder";case .reminderMove:"Move reminder";case .reminderFlag:"Set reminder priority";case .reminderDelete:"DELETE reminder (recovery not guaranteed)";case .reminderFind:"Find reminders";case .calendarAgenda:"Show tomorrow’s agenda";case .calendarFree:"Find a free hour in this calendar";case .calendarFind:"Find calendar events";case .calendarOpen:"Open next calendar event";case .calendarRename:"Rename personal event";case .calendarMove:"Reschedule personal event";case .calendarExtend:"Extend personal event by minutes";case .calendarDelete:"DELETE personal event (no attendees; recovery not guaranteed)";case .calendarAlarm:"Add an event alert, minutes before";case .calendarLocation:"Show next event location"}
        return verb+(name.isEmpty ? "":" · “"+name+"”")+(value.isEmpty ? "":" → “"+value+"”")+(date.map{" · "+$0.formatted()} ?? "")+(scopeName.map{" · Scope: "+$0} ?? "")
    }
    public static func date(_ text:String,now:Date,calendar:Calendar = .current)->Date? {
        if let iso=ISO8601DateFormatter().date(from:text),iso>now {return iso}
        let raw=text.lowercased().trimmingCharacters(in:.whitespaces)
        guard let range=raw.range(of:" at ",options:.backwards) else {return nil}
        let day=String(raw[..<range.lowerBound]),clock=String(raw[range.upperBound...]).replacingOccurrences(of:".",with:"")
        guard let expression=try? NSRegularExpression(pattern:#"^([a-z -]+|[0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)$"#),let match=expression.firstMatch(in:clock,range:NSRange(clock.startIndex...,in:clock)),let hourRange=Range(match.range(at:1),in:clock),let periodRange=Range(match.range(at:3),in:clock),let hour=PersonalControlIntents.number(String(clock[hourRange]).trimmingCharacters(in:.whitespaces)),(1...12).contains(hour) else {return nil}
        let minute=Range(match.range(at:2),in:clock).flatMap{Int(clock[$0])} ?? 0
        guard (0...59).contains(minute) else {return nil}
        let h=hour%12+(clock[periodRange]=="pm" ? 12:0)
        var base:Date
        if day=="tomorrow" {guard let next=calendar.date(byAdding:.day,value:1,to:now) else {return nil};base=next}
        else if day=="today" {base=now}
        else if let weekday=["sunday","monday","tuesday","wednesday","thursday","friday","saturday"].firstIndex(of:day),let next=calendar.nextDate(after:now,matching:DateComponents(weekday:weekday+1),matchingPolicy:.nextTime) {base=calendar.component(.weekday,from:now)==weekday+1 ? now:next}
        else {return nil}
        guard let result=calendar.date(bySettingHour:h,minute:minute,second:0,of:base),result>now else {return nil};return result
    }
    public static func parse(_ input:String,now:Date)->Self? {
        let text=PersonalAgentDialogue.canonical(input)
        if let expression=try? NSRegularExpression(pattern:#"^(.+?) (?:in|from) (?:my |the )?(.+?) (list|calendar)$"#,options:.caseInsensitive),let m=expression.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let baseRange=Range(m.range(at:1),in:text),let scopeRange=Range(m.range(at:2),in:text),var scoped=parse(String(text[baseRange]),now:now) {
            let scope=String(text[scopeRange]);guard scope.utf8.count<=200 else {return nil};scoped.scopeName=scope;return scoped
        }
        func request(_ pattern:String,_ action:Action,_ map:([String])->(String,String)={($0.first ?? "",$0.count>1 ? $0[1]:"")})->Self? {
            guard let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else {return nil}
            let fields=(1..<m.numberOfRanges).compactMap{Range(m.range(at:$0),in:text).map{String(text[$0])}};let (a,b)=map(fields)
            return try? Self(action:action,name:a,value:b)
        }
        let fixed:[String:Action]=["show reminders due today":.remindersToday,"show overdue reminders":.remindersOverdue,"what is on my calendar tomorrow":.calendarAgenda,"find a free hour tomorrow afternoon":.calendarFree,"open my next meeting":.calendarOpen,"show my next event location":.calendarLocation]
        if let action=fixed[text.lowercased()] {return try? Self(action:action)}
        let patterns:[(String,Action)]=[
            (#"^create a reminder list called (.+)$"#,.reminderList),
            (#"^mark (.+) as complete$"#,.reminderComplete),
            (#"^(?:move|reschedule) reminder (.+) to (.+)$"#,.reminderReschedule),
            (#"^move (?!my )(.+) to ((?:tomorrow|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday) at .+)$"#,.reminderReschedule),
            (#"^rename reminder (.+) to (.+)$"#,.reminderRename),
            (#"^move (.+) to my (.+) list$"#,.reminderMove),
            (#"^flag (.+) as important$"#,.reminderFlag),
            (#"^delete the reminder (.+)$"#,.reminderDelete),
            (#"^find reminders mentioning (.+)$"#,.reminderFind),
            (#"^find my (.+) appointment$"#,.calendarFind),
            (#"^find calendar events (.+)$"#,.calendarFind),
            (#"^rename (.+) (?:event|appointment|meeting) to (.+)$"#,.calendarRename),
            (#"^move my (.+) appointment to (.+)$"#,.calendarMove),
            (#"^extend my (.+) by (.+?) minutes?$"#,.calendarExtend),
            (#"^cancel my (.+?(?:block|event|appointment|meeting))$"#,.calendarDelete)]
        for (pattern,action) in patterns {if let result=request(pattern,action) {return result}}
        if let bare=request(#"^rename (.+) to (.+)$"#,.reminderRename) {return bare}
        return request(#"^remind me (.+?) minutes? before my (.+)$"#,.calendarAlarm,{($0[1],$0[0])})
    }
    public static func plan(_ input:String,now:Date) throws ->PersonalPlan? {
        guard var c=parse(input,now:now) else {return nil}
        if c.action == .reminderRename && !PersonalAgentDialogue.canonical(input).lowercased().hasPrefix("rename reminder ") {throw PersonalRecordKindRequired(command:c)}
        if [.reminderReschedule,.calendarMove].contains(c.action) {
            guard let date=Self.date(c.value,now:now) else {throw PersonalRecordDateRequired(command:c)};c.date=date
        }
        return try .init(steps:[.init(tool:.recordAction,text:try c.encoded())],createdAt:now)
    }
}
public struct PersonalRecordDateRequired:Error,Sendable {public let command:PersonalRecordCommand}

public struct PersonalRecordKindRequired:Error,Sendable {public let command:PersonalRecordCommand}
