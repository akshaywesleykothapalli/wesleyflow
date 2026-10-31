import Foundation

public struct PersonalReplyOption: Sendable, Equatable, Identifiable {
    public let label:String
    public let answer:String
    public var id:String { answer }
    public init(label:String,answer:String) { self.label=label;self.answer=answer }
}
public struct PersonalQuestion: Sendable, Equatable, Identifiable {
    public let id:UUID
    public let prompt:String
    public let options:[PersonalReplyOption]
    public let expiresAt:Date
    public init(id:UUID=UUID(),prompt:String,options:[PersonalReplyOption]=[],expiresAt:Date) { self.id=id;self.prompt=prompt;self.options=Array(options.prefix(6));self.expiresAt=expiresAt }
}
public struct PersonalRecipientOption: Sendable, Equatable {
    public let name:String
    public let address:String
    public let sourceID:String?
    public init(name:String,address:String,sourceID:String?=nil) { self.name=name;self.address=address;self.sourceID=sourceID }
    public var label:String { name + " · " + address }
}
public struct PersonalRecipientChoiceRequired: Error, Sendable {
    public let plan:PersonalPlan
    public let stepID:UUID
    public let options:[PersonalRecipientOption]
    public let prompt:String
    public init(plan:PersonalPlan,stepID:UUID,options:[PersonalRecipientOption],prompt:String) { self.plan=plan;self.stepID=stepID;self.options=Array(options.prefix(6));self.prompt=prompt }
    public func choosing(_ option:PersonalRecipientOption,now:Date) throws -> PersonalPlan {
        guard PersonalMessage.validAddress(option.address),let index=plan.steps.firstIndex(where:{$0.id == stepID}) else { throw PersonalAgentError.invalidCommand }
        var steps=plan.steps
        switch steps[index].tool {
        case .message:
            let prior=try PersonalMessage.decode(steps[index].text)
            steps[index] = .init(tool:.message,text:try PersonalMessage(recipient:option.name,body:prior.body,address:option.address).encoded())
        case .contactAction:
            var c=try PersonalObjectCommand.decode(steps[index].text)
            guard [.contactMessages,.contactWhatsApp].contains(c.action) else {throw PersonalAgentError.invalidCommand}
            c.name=option.name;c.value=option.address;c.targetID=option.sourceID ?? "literal:"+option.address
            steps[index] = .init(tool:.contactAction,text:try c.encoded())
        case .mailAction:
            var c=try PersonalMailCommand.decode(steps[index].text)
            guard c.action == .draft,option.address.contains("@") else {throw PersonalAgentError.invalidCommand}
            c.recipient=option.address;steps[index] = .init(tool:.mailAction,text:try c.encoded())
        default:throw PersonalAgentError.invalidCommand
        }
        return try PersonalPlan(steps:steps,createdAt:now,requiresReview:plan.requiresReview)
    }
}
public enum PersonalDialogueOutcome: Sendable { case request(String), plan(PersonalPlan), ask(PersonalQuestion), cancel, help }
public enum PersonalReviewReply: Sendable { case reject, amend(PersonalPlan), keep }

/// Ephemeral, explicit slot filling. No background context, passive observation or durable memory.
public struct PersonalAgentDialogue: Sendable {
    private enum Slot:Sendable { case website(PersonalWebsiteRequest.Browser?),app(Bool), query(Bool), recipient(String?), body(String), noteBody, recordDate(PersonalRecordCommand), recordKind(PersonalRecordCommand), fileLocation(PersonalFileAction), mailFileLocation(PersonalMailCommand), scheduleDate(PersonalMessage), contactName }
    private enum Reference:Sendable { case app(PersonalApp), query(String), contact(String) }
    private struct Pending:Sendable { var slot:Slot;var question:PersonalQuestion;var attempts:Int }
    private var expiredReply=false
    private var pending:Pending?
    private var reference:(value:Reference,expiresAt:Date)?
    public init() {}
    public static func stripLeadingCourtesy(_ text:String)->String {
        var text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        for _ in 0..<8 {
            let lower=text.lowercased()
            if let range=text.range(of:#"^go (?:and )?(?=(?:open|launch|start|close|quit|search|find)\b)"#,options:[.regularExpression,.caseInsensitive]) {text.removeSubrange(range);continue}
            if let prefix=["bring up ","pull up "].first(where:{lower.hasPrefix($0)}) {text="open "+String(text.dropFirst(prefix.count));continue}
            if lower.hasPrefix("just "),text.dropFirst(5).range(of:#"^(?:open|launch|start|close|quit|search|find|create|show|set|play|pause)\b"#,options:[.regularExpression,.caseInsensitive]) != nil {text=String(text.dropFirst(5));continue}
            guard let prefix=["now ","right now ","hey wesley flow, ","hey wesley flow ","hey wesley, ","hey wesley ","hi wesley, ","hi wesley ","hey, ","hey ","okay, ","okay ","ok, ","ok ","would you mind ","do you mind ","i would like you to ","i'd like you to ","i want you to ","please ","kindly ","can you ","could you ","would you "].first(where:{text.lowercased().hasPrefix($0)}) else { break }
            text=String(text.dropFirst(prefix.count))
        }
        return text
    }
    public static func canonical(_ original:String)->String {
        var text=stripLeadingCourtesy(original).trimmingCharacters(in:CharacterSet(charactersIn:".!?"))
        for _ in 0..<2 { if text.lowercased().hasSuffix(" please") { text=String(text.dropLast(7)) };if text.lowercased().hasSuffix(" for me") { text=String(text.dropLast(7)) } }
        return text
    }
    public static func isCancel(_ text:String)->Bool { ["cancel","cancel that","cancel request","never mind","nevermind","forget it","stop"].contains(canonical(text).lowercased()) }
    public static func ordinal(_ text:String,count:Int)->Int? {
        let value=canonical(text).lowercased().replacingOccurrences(of:"the ",with:"").replacingOccurrences(of:" option",with:"").replacingOccurrences(of:" one",with:"")
        let n=["first":1,"second":2,"third":3,"fourth":4,"fifth":5,"sixth":6][value] ?? Int(value)
        guard count>0,let n,(1...count).contains(n) else { return nil };return n-1
    }
    public mutating func clear() { pending=nil;reference=nil;expiredReply=false }
    public mutating func markExpired() { clear();expiredReply=true }
    public mutating func expire(now:Date)->Bool {
        if let reference,(reference.expiresAt.timeIntervalSince(now)<=0 || reference.expiresAt.timeIntervalSince(now)>120) { self.reference=nil }
        if let pending,(pending.question.expiresAt.timeIntervalSince(now)<=0 || pending.question.expiresAt.timeIntervalSince(now)>120) { self.pending=nil;expiredReply=true;return true }
        return false
    }
    private mutating func ask(_ slot:Slot,prompt:String,options:[PersonalReplyOption]=[],now:Date,attempts:Int=0)->PersonalDialogueOutcome {
        let question=PersonalQuestion(prompt:prompt,options:options,expiresAt:now.addingTimeInterval(120))
        pending=Pending(slot:slot,question:question,attempts:attempts);return .ask(question)
    }
    public mutating func askScheduleDate(_ message:PersonalMessage,now:Date)->PersonalDialogueOutcome {
        ask(.scheduleDate(message),prompt:"What exact date and time with AM or PM? This schedules a local draft and review notification; sending still needs your review at that time.",now:now)
    }
    private func capture(_ text:String,_ pattern:String)->[String]? {
        guard let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let match=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),match.range.length==text.utf16.count else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at:$0),in:text).map { String(text[$0]) } }
    }
    public mutating func intake(_ original:String,apps:[PersonalApp],now:Date) throws -> PersonalDialogueOutcome {
        guard !original.isEmpty,original.utf8.count<=4096,now.timeIntervalSince1970.isFinite else { throw PersonalPlanningFailure.unsupported }
        let justExpired=expire(now:now),expired=justExpired || expiredReply,text=Self.canonical(original),lower=text.lowercased()
        expiredReply=false
        if Self.isCancel(original) { clear();return .cancel }
        if ["help","what can you do","show examples"].contains(lower) { clear();return .help }
        // A full new app request replaces an old app-name question, never becomes its literal answer.
        if let pending=self.pending,case .app=pending.slot,capture(text,#"^(open|opening|launch|launching|start|starting|close|closing|quit|quitting|exit|exiting) (.+)$"#) != nil { self.pending=nil }
        if let pending=self.pending,case .website=pending.slot,capture(text,#"^(?:open|visit|go to|take me to|navigate to|head to|launch|start) (.+)$"#) != nil {self.pending=nil}
        if var pending=self.pending {
            self.pending=nil
            let answer=Self.ordinal(text,count:pending.question.options.count).map { pending.question.options[$0].answer } ?? original.trimmingCharacters(in:.whitespacesAndNewlines)
            switch pending.slot {
            case .website(let browser):
                guard pending.attempts<3 else {throw PersonalPlanningFailure.unsupported}
                if let address=PersonalWebsiteNames.address(answer) ?? PersonalWebsiteRequest.url(answer)?.absoluteString {
                    let website=try PersonalWebsiteRequest(address:address,browser:browser)
                    return .plan(try .init(steps:[.init(tool:.website,text:try website.encoded())],createdAt:now))
                }
                return ask(.website(browser),prompt:"What is the exact website address? I won’t guess a domain. Nothing opened.",now:now,attempts:pending.attempts+1)
            case .app(let close):
                if let app=apps.first(where:{$0.id == answer}) ?? (try? PersonalConversation.resolveApp(answer,apps:apps)) { return .plan(try PersonalPlan(steps:[.init(tool:close ? .closeApp:.openInstalledApp,text:app.id)],createdAt:now)) }
                if !close {
                    do {if let website=try PersonalWebsiteRequest.plan("open "+answer,apps:apps,now:now) {return .plan(website)}}
                    catch let required as PersonalWebsiteAddressRequired {return ask(.website(required.browser),prompt:"What is the exact website address? I won’t guess a domain.",now:now)}
                }
            case .query(let youtube):
                guard answer.utf8.count<=1200 else { throw PersonalPlanningFailure.unsupported }
                return .plan(try PersonalPlan(steps:[.init(tool:youtube ? .searchYouTube:.searchGoogle,text:answer)],createdAt:now))
            case .recipient(let body):
                guard answer.utf8.count<=200,!answer.contains("\n") else { throw PersonalPlanningFailure.unsupported }
                if let body { return .plan(try message(recipient:answer,body:body,now:now)) }
                return ask(.body(answer),prompt:"What should the message to \(answer) say?",now:now)
            case .contactName:
                guard !answer.isEmpty,answer.utf8.count<=200 else {throw PersonalPlanningFailure.unsupported}
                let c=try PersonalObjectCommand(action:.contactPhones,name:answer)
                return .plan(try PersonalPlan(steps:[.init(tool:.contactAction,text:try c.encoded())],createdAt:now))
            case .scheduleDate(let message):
                guard pending.attempts<3 else {throw PersonalPlanningFailure.unsupported}
                if let date=PersonalRecordCommand.date(answer,now:now) {return .plan(try PersonalMessageSchedule.plan(message:message,date:date,now:now))}
                return ask(.scheduleDate(message),prompt:"Say a future day and time with AM or PM, at least one minute ahead. Nothing is sent automatically.",now:now,attempts:pending.attempts+1)
            case .mailFileLocation(var command):
                guard pending.attempts<3 else {throw PersonalPlanningFailure.unsupported}
                guard let location=PersonalFolderLocation(rawValue:answer.lowercased()) else {return ask(.mailFileLocation(command),prompt:"Is that attachment in Documents, Desktop or Downloads?",now:now,attempts:pending.attempts+1)}
                command.fileLocation=location
                return .plan(try PersonalPlan(steps:[.init(tool:.mailAction,text:try command.encoded())],createdAt:now))
            case .fileLocation(var command):
                guard let location=PersonalFolderLocation(rawValue:answer.lowercased()) else {guard pending.attempts<2 else {throw PersonalPlanningFailure.unsupported};return ask(.fileLocation(command),prompt:"Which source location: Documents, Desktop or Downloads?",now:now,attempts:pending.attempts+1)}
                command.location=location
                return .plan(try PersonalPlan(steps:[.init(tool:.fileAction,text:try command.encoded())],createdAt:now))
            case .recordDate(var command):
                guard pending.attempts<3 else {throw PersonalPlanningFailure.unsupported}
                if let date=PersonalRecordCommand.date(answer,now:now) {command.date=date;return .plan(try PersonalPlan(steps:[.init(tool:.recordAction,text:try command.encoded())],createdAt:now))}
                return ask(.recordDate(command),prompt:"Say an exact date and time with AM or PM, such as tomorrow at 10 am, or an ISO-8601 time including timezone.",now:now,attempts:pending.attempts+1)
            case .recordKind(var command):
                guard pending.attempts<3 else {throw PersonalPlanningFailure.unsupported}
                guard ["reminder","calendar event","event","calendar"].contains(answer.lowercased()) else {return ask(.recordKind(command),prompt:"Is this a reminder or a calendar event?",now:now,attempts:pending.attempts+1)}
                if answer.lowercased() != "reminder" {command = try .init(action:.calendarRename,name:command.name,value:command.value)}
                return .plan(try PersonalPlan(steps:[.init(tool:.recordAction,text:try command.encoded())],createdAt:now))
            case .noteBody:
                return .plan(try PersonalPlan(steps:[.init(tool:.note,text:answer)],createdAt:now))
            case .body(let recipient):
                return .plan(try message(recipient:recipient,body:answer,now:now))
            }
            pending.attempts+=1
            guard pending.attempts<3 else { throw PersonalPlanningFailure.unsupported }
            return ask(pending.slot,prompt:"That app was not uniquely matched. Choose a listed app or say its full installed name.",options:pending.question.options,now:now,attempts:pending.attempts)
        }
        // An expired answer must not be promoted into a new effect. Require a complete new request.
        if expired { throw PersonalPlanningFailure.unsupported }
        let prior=reference;reference=nil
        if lower=="show the phone numbers for my selected contact" {
            if let prior,case .contact(let name)=prior.value,prior.expiresAt>now {let c=try PersonalObjectCommand(action:.contactPhones,name:name);return .plan(try PersonalPlan(steps:[.init(tool:.contactAction,text:try c.encoded())],createdAt:now))}
            return ask(.contactName,prompt:"Which exact contact name? A recent unique Agent contact result can be referenced; other app selections are not guessed.",now:now)
        }
        if let referenceVerb=capture(text,#"^(open|opening|close|closing|quit|quitting|exit|exiting) (?:it|that app)$"#)?.first {
            let close = !["open","opening"].contains(referenceVerb.lowercased())
            if let prior,case .app(let app)=prior.value,prior.expiresAt>now,apps.contains(where:{$0.id==app.id}) {
                return .plan(try PersonalPlan(steps:[.init(tool:close ? .closeApp:.openInstalledApp,text:app.id)],createdAt:now))
            }
            return ask(.app(close),prompt:close ? "Which app should I quit normally?":"Which app should I open?",options:appOptions(apps),now:now)
        }
        if ["search that on youtube","search it on youtube","search youtube instead","search that on google","search it on google","search google instead"].contains(lower) {
            let youtube=lower.contains("youtube")
            if let prior,case .query(let query)=prior.value,prior.expiresAt>now { return .plan(try PersonalPlan(steps:[.init(tool:youtube ? .searchYouTube:.searchGoogle,text:query)],createdAt:now)) }
            return ask(.query(youtube),prompt:"What should I search for on \(youtube ? "YouTube":"Google")?",now:now)
        }
        if ["open","launch","start","close","quit","exit"].contains(lower) {
            let close=["close","quit","exit"].contains(lower)
            return ask(.app(close),prompt:close ? "Which app should I quit normally?":"Which app should I open?",options:appOptions(apps),now:now)
        }
        if ["search","search google","search youtube","search on google","search on youtube","google","youtube"].contains(lower) {
            let youtube=lower.contains("youtube")
            return ask(.query(youtube),prompt:"What should I search for on \(youtube ? "YouTube":"Google")?",now:now)
        }
        if capture(text,#"^(?:creat(?:e|ing)|writ(?:e|ing)|jot(?:ting)?)(?: a)? note$"#) != nil { return ask(.noteBody,prompt:"What should the note contain?",now:now) }
        if ["text","message","send a message","send a text"].contains(lower) { return ask(.recipient(nil),prompt:"Who should receive the message? Say a name, phone number or email.",now:now) }
        if let values=capture(text,#"^(?:text|message|send a message to|send a text to) (.+)$"#),!values[0].lowercased().contains(" saying "),!values[0].lowercased().contains(" that says "),!values[0].contains(":") {
            // Only unmistakable name/address-only input is incomplete; longer prose goes to the model.
            if PersonalMessage.validAddress(values[0]) || values[0].split(separator:" ").count<=2 { return ask(.body(values[0]),prompt:"What should the message to \(values[0]) say?",now:now) }
        }
        do {if let website=try PersonalWebsiteRequest.plan(original,apps:apps,now:now) {return .plan(website)}}
        catch let required as PersonalWebsiteAddressRequired {return ask(.website(required.browser),prompt:"What is the exact website address? Known names such as Google, Gmail and YouTube work locally; I won’t guess this domain.",now:now)}
        if let schedule=try PersonalMessageSchedule.parse(original,now:now) {return .plan(schedule)}
        if let menu=try PersonalMenuAction.parse(original,now:now) {return .plan(menu)}
        do {if let mail=try PersonalMailCommand.parse(original,now:now) {return .plan(mail)}}
        catch let needed as PersonalMailFileLocationRequired {return ask(.mailFileLocation(needed.command),prompt:"Is that attachment in Documents, Desktop or Downloads?",options:PersonalFolderLocation.allCases.map{.init(label:$0.rawValue.capitalized,answer:$0.rawValue)},now:now)}
        if let browser=try PersonalBrowserExtra.parse(original,now:now) {return .plan(browser)}
        if let screenshot=try PersonalScreenCapture.parse(original,now:now) {return .plan(screenshot)}
        do {if let file=try PersonalFileAction.parse(original,now:now) {return .plan(file)}}
        catch let needed as PersonalFileLocationRequired {return ask(.fileLocation(needed.command),prompt:"Which source location: Documents, Desktop or Downloads?",options:PersonalFolderLocation.allCases.map{.init(label:$0.rawValue.capitalized,answer:$0.rawValue)},now:now)}
        if let object=try PersonalObjectCommand.parse(original,now:now) {return .plan(object)}
        do {if let record=try PersonalRecordCommand.plan(original,now:now) {return .plan(record)}}
        catch let required as PersonalRecordDateRequired {return ask(.recordDate(required.command),prompt:"What exact day and time, including AM or PM? For example: Friday at 3 pm.",now:now)}
        catch let required as PersonalRecordKindRequired {return ask(.recordKind(required.command),prompt:"Is this a reminder or a calendar event?",options:[.init(label:"Reminder",answer:"reminder"),.init(label:"Calendar event",answer:"calendar event")],now:now)}
        if let timer=try PersonalTimerControl.parse(original,now:now) { return .plan(timer) }
        if let mac=try PersonalMacControl.parse(original,now:now) { return .plan(mac) }
        if let layout=try PersonalWindowLayout.parse(original,apps:apps,now:now) { return .plan(layout) }
        if let controls=try PersonalControlIntents.parse(original,now:now) { return .plan(controls) }
        if let file=try PersonalFileIntents.parse(original,now:now) { return .plan(file) }
        if let window=try PersonalConversation.windowCommand(original,apps:apps,now:now) { return .plan(window) }
        if let repeated=PersonalConversation.repeatedOpen(original,apps:apps,now:now,allowClose:true) { return .plan(repeated) }
        if let values=capture(text,#"^(open|opening|launch|launching|start|starting|close|closing|quit|quitting|exit|exiting) (.+)$"#),
           !values[1].lowercased().contains(" then "),!values[1].lowercased().contains(" and ") {
            let app=try PersonalConversation.resolveApp(values[1],apps:apps)
            return .plan(try PersonalPlan(steps:[.init(tool:["close","closing","quit","quitting","exit","exiting"].contains(values[0].lowercased()) ? .closeApp:.openInstalledApp,text:app.id)],createdAt:now))
        }
        return .request(original)
    }
    private func message(recipient:String,body:String,now:Date) throws -> PersonalPlan { try PersonalPlan(steps:[.init(tool:.message,text:try PersonalMessage(recipient:recipient,body:body).encoded())],createdAt:now) }
    private func appOptions(_ apps:[PersonalApp])->[PersonalReplyOption] { apps.prefix(6).map { app in .init(label:app.name + (apps.filter { $0.name == app.name }.count>1 ? " (" + app.id + ")":""),answer:app.id) } }
    public mutating func completed(_ plan:PersonalPlan,apps:[PersonalApp],now:Date) {
        reference=nil
        guard plan.steps.count==1,let step=plan.steps.first else { return }
        switch step.tool {
        case .openInstalledApp,.closeApp:
            if let app=apps.first(where:{$0.id==step.text}) { reference=(.app(app),now.addingTimeInterval(120)) }
        case .openApp:
            if let app=try? PersonalConversation.resolveApp(step.text,apps:apps) { reference=(.app(app),now.addingTimeInterval(120)) }
        case .contactAction:
            if let c=try? PersonalObjectCommand.decode(step.text),c.targetID != nil {reference=(.contact(c.name),now.addingTimeInterval(120))}
        case .searchGoogle,.searchYouTube: reference=(.query(step.text),now.addingTimeInterval(120))
        default: break
        }
    }
    public static func reviewReply(_ text:String,plan:PersonalPlan,now:Date) throws -> PersonalReviewReply {
        if isCancel(text) { return .reject }
        guard plan.steps.count==1,let step=plan.steps.first,step.tool == .message else { return .keep }
        let message=try PersonalMessage.decode(step.text),value=stripLeadingCourtesy(text)
        for prefix in ["change the message to ","change message to ","change the recipient to ","change recipient to "] where value.lowercased().hasPrefix(prefix) {
            let literal=String(value.dropFirst(prefix.count)).trimmingCharacters(in:.whitespacesAndNewlines)
            guard !literal.isEmpty else { return .keep }
            let recipient=prefix.contains("recipient"),amended=PersonalMessage(recipient:recipient ? literal:message.recipient,body:recipient ? message.body:literal,address:recipient ? nil:message.address)
            return .amend(try PersonalPlan(steps:[.init(tool:.message,text:try amended.encoded())],createdAt:now))
        }
        return .keep
    }
}

public extension PersonalStep {
    func userSummary(apps:[PersonalApp])->String {
        switch tool {
        case .openInstalledApp: return "Open " + (apps.first(where:{$0.id==text})?.name ?? text)
        case .minimizeApp: return "Minimise " + (apps.first(where:{$0.id==text})?.name ?? text)
        case .restoreApp: return "Restore " + (apps.first(where:{$0.id==text})?.name ?? text)
        case .fullScreenApp: return "Full screen: " + (apps.first(where:{$0.id==text})?.name ?? text)
        case .exitFullScreenApp: return "Exit full screen: " + (apps.first(where:{$0.id==text})?.name ?? text)
        case .maximizeApp: return "Maximise " + (apps.first(where:{$0.id==text})?.name ?? text)
        case .closeApp: return "Quit " + (apps.first(where:{$0.id==text})?.name ?? text) + " normally"
        case .openApp: return "Open " + text
        case .searchGoogle: return "Search Google for “" + text + "”"
        case .searchYouTube: return "Search YouTube for “" + text + "”"
        case .music,.spotify: return (tool == .music ? "Music: ":"Spotify: ") + text
        default: return displayText
        }
    }
}
