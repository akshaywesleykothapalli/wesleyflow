import AppKit
import EventKit
import CryptoKit
import Domain

@MainActor public enum NativeRecordTools {
    private static let store=EKEventStore()
    private static func grant(_ reminder:Bool) async throws {
        let type:EKEntityType=reminder ? .reminder:.event
        if EKEventStore.authorizationStatus(for:type) == .notDetermined {
            let granted=reminder ? try await store.requestFullAccessToReminders():try await store.requestFullAccessToEvents()
            guard granted else {throw PersonalAgentError.permissionDenied}
        }
        guard EKEventStore.authorizationStatus(for:type) == .fullAccess else {throw PersonalAgentError.permissionDenied}
    }
    private static func isReminder(_ c:PersonalRecordCommand)->Bool {c.action.rawValue.hasPrefix("reminder")}
    private static func primary(_ reminder:Bool) throws ->EKCalendar {
        guard let calendar=reminder ? store.defaultCalendarForNewReminders():store.defaultCalendarForNewEvents else {throw PersonalAgentError.unsupported};return calendar
    }
    private static func reminders(_ calendar:EKCalendar) async throws ->[EKReminder] {
        let p=store.predicateForReminders(in:[calendar])
        let result:[String]=try await withCheckedThrowingContinuation {resume in store.fetchReminders(matching:p) {items in if let items {resume.resume(returning:items.map{$0.calendarItemIdentifier})} else {resume.resume(throwing:PersonalAgentError.permissionDenied)}}}
        guard result.count<=2000 else {throw PersonalAgentError.unsupported};return result.compactMap{store.calendarItem(withIdentifier:$0) as? EKReminder}
    }
    private static func events(_ calendar:EKCalendar,now:Date) throws ->[EKEvent] {
        let found=store.events(matching:store.predicateForEvents(withStart:now.addingTimeInterval(-86400),end:now.addingTimeInterval(90*86400),calendars:[calendar]))
        guard found.count<=2000,found.allSatisfy({$0.startDate != nil && $0.endDate != nil}) else {throw PersonalAgentError.unsupported};return found
    }
    static func digest(_ values:[String])->String {SHA256.hash(data:Data(values.joined(separator:"\u{001F}").utf8)).map{String(format:"%02x",$0)}.joined()}
    private static func fingerprint(_ item:EKCalendarItem)->String {
        var values=[item.calendarItemIdentifier,item.calendar.calendarIdentifier,item.title ?? "",String(item.lastModifiedDate?.timeIntervalSince1970 ?? 0)]
        if let r=item as? EKReminder {values += [String(r.isCompleted),String(r.priority),r.dueDateComponents.flatMap{Calendar.current.date(from:$0)}?.ISO8601Format() ?? ""]}
        if let event=item as? EKEvent {values += [event.startDate.ISO8601Format(),event.endDate.ISO8601Format(),String(event.hasAttendees),String(event.hasRecurrenceRules)]}
        return digest(values)
    }
    private static func item(_ c:PersonalRecordCommand,calendar:EKCalendar) async throws ->EKCalendarItem {
        if let id=c.identity,let item=store.calendarItem(withIdentifier:id) {guard item.calendar.calendarIdentifier==calendar.calendarIdentifier,(item.title ?? "").caseInsensitiveCompare(c.name) == .orderedSame else {throw PersonalAgentError.verificationFailed};return item}
        let items:[EKCalendarItem]=isReminder(c) ? try await reminders(calendar):try events(calendar,now:Date())
        let matches=items.filter{($0.title ?? "").caseInsensitiveCompare(c.name) == .orderedSame}
        guard matches.count==1,let item=matches.first else {throw PersonalAgentError.unsupported};return item
    }
    public static func resolve(_ plan:PersonalPlan) async throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .recordAction {
            var c=try PersonalRecordCommand.decode(steps[i].text)
            try await grant(isReminder(c));store.reset()
            let calendar:EKCalendar
            if let id=c.calendarID {guard let bound=store.calendar(withIdentifier:id) else {throw PersonalAgentError.verificationFailed};calendar=bound}
            else if let name=c.scopeName {
                let candidates=store.calendars(for:isReminder(c) ? .reminder:.event).filter{calendar in [calendar.title,calendar.title+" ("+calendar.source.title+")"].contains(where:{$0.caseInsensitiveCompare(name) == .orderedSame})}
                guard candidates.count==1,let chosen=candidates.first else {throw PersonalAgentError.unsupported};calendar=chosen
            } else {calendar=try primary(isReminder(c))}
            c.calendarID=calendar.calendarIdentifier;c.scopeName=calendar.title+" ("+calendar.source.title+")"
            if c.isMutation && c.action != .reminderList {
                let target=try await item(c,calendar:calendar)
                guard target.calendar.allowsContentModifications,!target.hasAttendees,!target.hasRecurrenceRules else {throw PersonalAgentError.unsupported}
                c.identity=target.calendarItemIdentifier;c.fingerprint=fingerprint(target)
            }
            steps[i] = .init(id:steps[i].id,tool:.recordAction,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let c=try PersonalRecordCommand.decode(step.text),reminder=isReminder(c)
        try await grant(reminder);try Task.checkCancellation();store.reset()
        guard let calendarID=c.calendarID,let calendar=store.calendar(withIdentifier:calendarID),(reminder ? calendar.allowedEntityTypes.contains(.reminder):calendar.allowedEntityTypes.contains(.event)) else {throw PersonalAgentError.approvalRequired}
        let now=Date(),cal=Calendar.current
        func receipt(_ text:String,_ id:String?=nil)->PersonalReceipt {.init(identifier:id ?? step.id.uuidString,evidence:text+" · scope: "+calendar.title)}
        switch c.action {
        case .remindersToday,.remindersOverdue,.reminderFind:
            let start=cal.startOfDay(for:now),end=cal.date(byAdding:.day,value:1,to:start)!
            let items=try await reminders(calendar).filter {r in
                if c.action == .reminderFind {return (r.title ?? "").localizedCaseInsensitiveContains(c.name)}
                guard !r.isCompleted,let components=r.dueDateComponents,let due=cal.date(from:components) else {return false}
                return c.action == .remindersToday ? due>=start && due<end:due<start
            }
            return receipt(items.isEmpty ? "No matching reminders.":"Reminders (first 50): "+items.prefix(50).map{$0.title ?? "Untitled"}.joined(separator:"; "))
        case .reminderList:
            let calendars=store.calendars(for:.reminder).filter{($0.title ?? "").caseInsensitiveCompare(c.name) == .orderedSame}
            if calendars.count==1 {return receipt("Reminder list already exists; no duplicate created.",calendars[0].calendarIdentifier)}
            guard calendars.isEmpty else {throw PersonalAgentError.unsupported}
            let list=EKCalendar(for:.reminder,eventStore:store);list.title=c.name;list.source=calendar.source
            try store.saveCalendar(list,commit:true)
            guard store.calendar(withIdentifier:list.calendarIdentifier)?.title==c.name else {throw PersonalAgentError.verificationFailed}
            return receipt("Reminder list created and title read back: "+c.name,list.calendarIdentifier)
        case .calendarAgenda,.calendarFree,.calendarFind,.calendarOpen,.calendarLocation:
            let all=try events(calendar,now:now).sorted{$0.startDate<$1.startDate}
            if c.action == .calendarAgenda {
                let start=cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:now))!,end=cal.date(byAdding:.day,value:1,to:start)!
                let selected=all.filter{$0.startDate<end && $0.endDate>start}
                return receipt(selected.isEmpty ? "No events tomorrow.":"Tomorrow (first 30): "+selected.prefix(30).map{($0.title ?? "Untitled")+" at "+$0.startDate.formatted()}.joined(separator:"; "))
            }
            if c.action == .calendarFree {
                let tomorrow=cal.date(byAdding:.day,value:1,to:now)!,start=cal.date(bySettingHour:12,minute:0,second:0,of:tomorrow)!,end=cal.date(bySettingHour:18,minute:0,second:0,of:tomorrow)!
                var candidate=start
                for event in all.filter({$0.startDate<end && $0.endDate>start}) {if event.startDate.timeIntervalSince(candidate)>=3600 {break};candidate=max(candidate,event.endDate)}
                return receipt(candidate.addingTimeInterval(3600)<=end ? "Free hour in this calendar: "+candidate.formatted()+" to "+candidate.addingTimeInterval(3600).formatted()+". Other calendars not checked.":"No free hour found tomorrow between noon and 6 pm in this calendar.")
            }
            if c.action == .calendarFind {return receipt("Events (first 30): "+all.filter{($0.title ?? "").localizedCaseInsensitiveContains(c.name)}.prefix(30).map{($0.title ?? "Untitled")+" · "+$0.startDate.formatted()}.joined(separator:"; "))}
            guard let next=all.first(where:{$0.startDate>=now}) else {throw PersonalAgentError.unsupported}
            if c.action == .calendarLocation {return receipt("Next event: "+(next.title ?? "Untitled")+" · Location: "+(next.location ?? "No location"))}
            guard let external=next.calendarItemExternalIdentifier,!external.isEmpty else {throw PersonalAgentError.unsupported}
            let quote=NativeAgentScript.literal
            let shown=try NativeAgentScript.execute("""
            with timeout of 8 seconds
              tell application id "com.apple.iCal"
                set sources to calendars whose name is \(quote(calendar.title))
                if (count of sources)>20 then error "ambiguous-calendar"
                set matches to {}
                repeat with sourceCalendar in sources
                  set candidates to events of sourceCalendar whose uid is \(quote(external))
                  repeat with candidate in candidates
                    set end of matches to candidate
                  end repeat
                end repeat
                if (count of matches) is not 1 then error "ambiguous-event"
                set chosen to item 1 of matches
                if (summary of chosen) is not \(quote(next.title ?? "")) then error "event-changed"
                show chosen
                activate
                return uid of chosen
              end tell
            end timeout
            """)
            guard shown==external else {throw PersonalAgentError.verificationFailed}
            return receipt("Calendar accepted display of the exact next event UID; event identity returned by native show.",next.calendarItemIdentifier)
        default:break
        }
        guard let id=c.identity,let expected=c.fingerprint else {throw PersonalAgentError.approvalRequired}
        let target=try await item(c,calendar:calendar)
        guard target.calendarItemIdentifier==id,fingerprint(target)==expected,target.calendar.allowsContentModifications,!target.hasAttendees,!target.hasRecurrenceRules else {throw PersonalAgentError.verificationFailed}
        if let r=target as? EKReminder {
            switch c.action {
            case .reminderComplete:r.isCompleted=true
            case .reminderReschedule:guard let date=c.date,date>now else {throw PersonalAgentError.invalidCommand};r.dueDateComponents=cal.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone],from:date)
            case .reminderRename:r.title=c.value
            case .reminderFlag:r.priority=1
            case .reminderMove:
                let matches=store.calendars(for:.reminder).filter{$0.title.caseInsensitiveCompare(c.value) == .orderedSame && $0.allowsContentModifications && $0.source.sourceIdentifier==calendar.source.sourceIdentifier}
                guard matches.count==1,let to=matches.first else {throw PersonalAgentError.unsupported};r.calendar=to
            case .reminderDelete:
                try store.remove(r,commit:true);guard store.calendarItem(withIdentifier:id)==nil else {throw PersonalAgentError.verificationFailed};return receipt("Reviewed reminder deleted; absence verified. This is not a guaranteed recoverable Trash operation.",id)
            default:throw PersonalAgentError.unsupported
            }
            let wantedTitle=r.title,wantedCalendar=r.calendar.calendarIdentifier,wantedDue=r.dueDateComponents,wantedPriority=r.priority,wantedComplete=r.isCompleted
            try store.save(r,commit:true);store.reset()
            guard let saved=store.calendarItem(withIdentifier:id) as? EKReminder,saved.title==wantedTitle,saved.calendar.calendarIdentifier==wantedCalendar,saved.dueDateComponents==wantedDue,saved.priority==wantedPriority,saved.isCompleted==wantedComplete else {throw PersonalAgentError.verificationFailed}
            return receipt("Reviewed reminder change saved and requested fields read back.",id)
        }
        guard let event=target as? EKEvent else {throw PersonalAgentError.unsupported}
        switch c.action {
        case .calendarRename:event.title=c.value
        case .calendarMove:guard let date=c.date,date>now else {throw PersonalAgentError.invalidCommand};let duration=event.endDate.timeIntervalSince(event.startDate);event.startDate=date;event.endDate=date.addingTimeInterval(duration)
        case .calendarExtend:guard let minutes=PersonalControlIntents.number(c.value),(1...1440).contains(minutes) else {throw PersonalAgentError.invalidCommand};event.endDate=event.endDate.addingTimeInterval(Double(minutes)*60)
        case .calendarAlarm:guard let minutes=PersonalControlIntents.number(c.value),(1...10080).contains(minutes),event.alarms?.count ?? 0<5 else {throw PersonalAgentError.invalidCommand};event.addAlarm(EKAlarm(relativeOffset:-Double(minutes)*60))
        case .calendarDelete:try store.remove(event,span:.thisEvent,commit:true);guard store.calendarItem(withIdentifier:id)==nil else {throw PersonalAgentError.verificationFailed};return receipt("Reviewed personal event removed; no attendees notified.",id)
        default:throw PersonalAgentError.unsupported
        }
        let title=event.title,start=event.startDate,end=event.endDate,alarms=event.alarms?.map{ $0.relativeOffset } ?? []
        if [.calendarMove,.calendarExtend].contains(c.action) {guard try !events(calendar,now:now).contains(where:{$0.calendarItemIdentifier != id && $0.startDate<end! && $0.endDate>start!}) else {throw PersonalAgentError.unsupported}}
        try store.save(event,span:.thisEvent,commit:true);store.reset()
        guard let saved=store.calendarItem(withIdentifier:id) as? EKEvent,saved.title==title,saved.startDate==start,saved.endDate==end,saved.alarms?.map({$0.relativeOffset}) ?? []==alarms else {throw PersonalAgentError.verificationFailed}
        return receipt("Reviewed personal calendar change saved; title, times and alerts read back.",id)
    }
}
