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
    public init(name:String,address:String) { self.name=name;self.address=address }
    public var label:String { name + " · " + address }
}
public struct PersonalRecipientChoiceRequired: Error, Sendable {
    public let plan:PersonalPlan
    public let stepID:UUID
    public let options:[PersonalRecipientOption]
    public let prompt:String
    public init(plan:PersonalPlan,stepID:UUID,options:[PersonalRecipientOption],prompt:String) { self.plan=plan;self.stepID=stepID;self.options=Array(options.prefix(6));self.prompt=prompt }
    public func choosing(_ option:PersonalRecipientOption,now:Date) throws -> PersonalPlan {
        guard PersonalMessage.validAddress(option.address),let index=plan.steps.firstIndex(where:{$0.id == stepID && $0.tool == .message}) else { throw PersonalAgentError.invalidCommand }
        let prior=try PersonalMessage.decode(plan.steps[index].text)
        var steps=plan.steps
        steps[index] = .init(tool:.message,text:try PersonalMessage(recipient:option.name,body:prior.body,address:option.address).encoded())
        return try PersonalPlan(steps:steps,createdAt:now)
    }
}
public enum PersonalDialogueOutcome: Sendable { case request(String), plan(PersonalPlan), ask(PersonalQuestion), cancel, help }
public enum PersonalReviewReply: Sendable { case reject, amend(PersonalPlan), keep }

/// Ephemeral, explicit slot filling. No background context, passive observation or durable memory.
public struct PersonalAgentDialogue: Sendable {
    private enum Slot:Sendable { case app(Bool), query(Bool), recipient(String?), body(String), noteBody }
    private enum Reference:Sendable { case app(PersonalApp), query(String) }
    private struct Pending:Sendable { var slot:Slot;var question:PersonalQuestion;var attempts:Int }
    private var expiredReply=false
    private var pending:Pending?
    private var reference:(value:Reference,expiresAt:Date)?
    public init() {}
    public static func stripLeadingCourtesy(_ text:String)->String {
        var text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        for _ in 0..<4 {
            guard let prefix=["would you mind ","do you mind ","i would like you to ","i'd like you to ","i want you to ","please ","kindly ","can you ","could you ","would you "].first(where:{text.lowercased().hasPrefix($0)}) else { break }
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
        if var pending=self.pending {
            self.pending=nil
            let answer=Self.ordinal(text,count:pending.question.options.count).map { pending.question.options[$0].answer } ?? original.trimmingCharacters(in:.whitespacesAndNewlines)
            switch pending.slot {
            case .app(let close):
                if let app=apps.first(where:{$0.id == answer}) ?? (try? PersonalConversation.resolveApp(answer,apps:apps)) { return .plan(try PersonalPlan(steps:[.init(tool:close ? .closeApp:.openInstalledApp,text:app.id)],createdAt:now)) }
            case .query(let youtube):
                guard answer.utf8.count<=1200 else { throw PersonalPlanningFailure.unsupported }
                return .plan(try PersonalPlan(steps:[.init(tool:youtube ? .searchYouTube:.searchGoogle,text:answer)],createdAt:now))
            case .recipient(let body):
                guard answer.utf8.count<=200,!answer.contains("\n") else { throw PersonalPlanningFailure.unsupported }
                if let body { return .plan(try message(recipient:answer,body:body,now:now)) }
                return ask(.body(answer),prompt:"What should the message to \(answer) say?",now:now)
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
