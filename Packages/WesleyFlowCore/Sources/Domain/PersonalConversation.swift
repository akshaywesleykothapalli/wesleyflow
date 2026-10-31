import Foundation

public struct PersonalApp: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public init(id:String,name:String,aliases:[String] = []) { self.id=id; self.name=name; self.aliases=aliases }
}
public struct PersonalMessage: Codable, Sendable, Equatable {
    public let recipient: String
    public let body: String
    public var address: String?
    public init(recipient:String,body:String,address:String? = nil) { self.recipient=recipient; self.body=body; self.address=address }
    public func encoded() throws -> String { String(decoding:try JSONEncoder().encode(self),as:UTF8.self) }
    public static func decode(_ text:String) throws -> Self {
        let value = try JSONDecoder().decode(Self.self,from:Data(text.utf8))
        guard !value.recipient.isEmpty, value.recipient.utf8.count<=200, !value.body.isEmpty, value.body.utf8.count<=1200 else { throw PersonalAgentError.invalidCommand }
        return value
    }
    public static func validAddress(_ text:String) -> Bool {
        let value = text.trimmingCharacters(in:.whitespaces)
        if value.contains("@") { return value.range(of:#"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#,options:.regularExpression) != nil }
        let digits = value.filter(\.isNumber)
        return (7...15).contains(digits.count) && value.allSatisfy { $0.isASCII && ($0.isNumber || "+()- ".contains($0)) }
    }
}
public struct PersonalIntentRequest: Sendable {
    public let id: String
    public let text: String
    public let locale: String
    public let apps: [PersonalApp]
    public let now: Date
    public init(id:String = UUID().uuidString,text:String,locale:String,apps:[PersonalApp],now:Date = Date()) { self.id=id;self.text=text;self.locale=locale;self.apps=apps;self.now=now }
}
public enum PersonalPlanningFailure: Error, Sendable, Equatable { case appNotFound, appAmbiguous, unsupported, modelUnavailable, resourceBlocked, timedOut, busy, invalidOutput, recipientAmbiguous, contactsDenied }
public protocol PersonalIntentPlanning: Sendable {
    func plan(_ request:PersonalIntentRequest) async throws -> PersonalPlan
    func cancel(id:String) async
}
/// The language model proposes bounded slots; it never chooses code, a permission or an execution grant.
public struct PersonalIntentSlots: Codable, Sendable {
    public let action:String
    public let app:String
    public let content:String
    public let recipient:String
    public init(action:String,app:String = "",content:String = "",recipient:String = "") { self.action=action;self.app=app;self.content=content;self.recipient=recipient }
}
public enum PersonalConversation {
    public static let maximumApps=2048
    public static func resolveApp(_ mention:String,apps:[PersonalApp]) throws -> PersonalApp {
        func normalized(_ value:String)->String { value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")).lowercased().filter { $0.isLetter || $0.isNumber } }
        func match(_ value:String) throws -> PersonalApp? {
            let key=normalized(value)
            guard !key.isEmpty else { return nil }
            let matches=apps.filter { ([$0.name,$0.id]+$0.aliases).contains { normalized($0)==key } }
            guard Set(matches.map(\.id)).count<=1 else { throw PersonalPlanningFailure.appAmbiguous }
            return matches.first
        }
        if let exact=try match(mention) { return exact }
        // Strip only spoken wrappers, after trying the complete installed name (e.g. The Unarchiver).
        var name=mention.trimmingCharacters(in:.whitespacesAndNewlines)
        if let range=name.range(of:#"^(?:the (?:app|application)|(?:app|application)|the)\s+"#,options:[.regularExpression,.caseInsensitive]) { name.removeSubrange(range) }
        if let range=name.range(of:#"(?:\s+(?:app|application)|\.app)$"#,options:[.regularExpression,.caseInsensitive]) { name.removeSubrange(range) }
        if let wrapped=try match(name) { return wrapped }
        if let range=name.range(of:#"^(?:up\s+)?(?:the\s+)?"#,options:[.regularExpression,.caseInsensitive]),!range.isEmpty {
            name.removeSubrange(range)
            if let spoken=try match(name) { return spoken }
        }
        throw PersonalPlanningFailure.appNotFound
    }
    /// Repeated identical app-open requests are idempotent. Never deduplicate payload data or other tools.
    public static func repeatedOpen(_ text:String,apps:[PersonalApp],now:Date,allowClose:Bool=false) -> PersonalPlan? {
        let words=text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count>=3,words.count<=80 else { return nil }
        let opening=["open","opening","launch","launching","start","starting"],closing=["close","closing","quit","quitting","exit","exiting"]
        let verb=words[0].lowercased()
        // A complete installed name always takes priority over repetition handling.
        if (opening+closing).contains(verb),(try? resolveApp(words.dropFirst().joined(separator:" "),apps:apps)) != nil { return nil }
        if opening.contains(verb) || (allowClose && closing.contains(verb)) {
            let count=words.prefix(while:{$0.lowercased()==verb}).count
            if (2...4).contains(count),count<words.count,let app=try? resolveApp(words.dropFirst(count).joined(separator:" "),apps:apps) {
                return try? PersonalPlan(steps:[.init(tool:closing.contains(verb) ? .closeApp:.openInstalledApp,text:app.id)],createdAt:now)
            }
        }
        for copies in 2...4 where words.count % copies == 0 {
            let size=words.count/copies
            let first=PersonalAgentDialogue.canonical(words.prefix(size).joined(separator:" "))
            guard (1..<copies).allSatisfy({ n in
                PersonalAgentDialogue.canonical(words[(n*size)..<((n+1)*size)].joined(separator:" ")).caseInsensitiveCompare(first) == .orderedSame
            }) else { continue }
            guard let re=try? NSRegularExpression(pattern:#"^(?:open|opening|launch|launching|start|starting|close|closing|quit|quitting|exit|exiting) (.+)$"#,options:.caseInsensitive),let match=re.firstMatch(in:first,range:NSRange(first.startIndex...,in:first)),let range=Range(match.range(at:1),in:first),let app=try? resolveApp(String(first[range]),apps:apps) else { continue }
            let isClose=closing.contains(first.split(separator:" ").first?.lowercased() ?? "")
            if isClose && !allowClose { continue }
            return try? PersonalPlan(steps:[.init(tool:isClose ? .closeApp:.openInstalledApp,text:app.id)],createdAt:now)
        }
        return nil
    }
    public static func windowCommand(_ input:String,apps:[PersonalApp],now:Date) throws -> PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input),words=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard words.count<=80 else { return nil }
        let forms:[(String,PersonalTool)]=[(#"^(?:minimi[sz]e|hide the window of) (.+)$"#,.minimizeApp),(#"^(?:restore|unminimi[sz]e|bring back) (.+)$"#,.restoreApp),(#"^(?:maximi[sz]e|enlarge) (.+)$"#,.maximizeApp),(#"^(?:full screen|fullscreen) (.+)$"#,.fullScreenApp),(#"^(?:make|put) (.+) (?:full screen|fullscreen)$"#,.fullScreenApp),(#"^(?:exit full screen|exit fullscreen|leave full screen) (.+)$"#,.exitFullScreenApp)]
        // Repeat only a complete identical window request; message/note replies bypass this entry point.
        for copies in 2...4 where words.count>=copies*2 && words.count % copies==0 {
            let size=words.count/copies,part=words.prefix(words.count/copies).joined(separator:" ")
            if (1..<copies).allSatisfy({n in PersonalAgentDialogue.canonical(words[n*size..<(n+1)*size].joined(separator:" ")).caseInsensitiveCompare(PersonalAgentDialogue.canonical(part)) == .orderedSame}),let plan=try windowCommand(part,apps:apps,now:now) { return plan }
        }
        for (pattern,tool) in forms {
            let re=try NSRegularExpression(pattern:pattern,options:.caseInsensitive)
            if let match=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(match.range(at:1),in:text) {
                let app=try resolveApp(String(text[range]),apps:apps)
                return try PersonalPlan(steps:[.init(tool:tool,text:app.id)],createdAt:now)
            }
        }
        return nil
    }
    public static func validate(_ request:PersonalIntentRequest) throws {
        guard !request.text.isEmpty, request.text.utf8.count<=4096, request.apps.count<=maximumApps else { throw PersonalPlanningFailure.unsupported }
    }
    /// Slot text must be copied from the user's request, not invented by the model.
    public static func ground(_ slots:[PersonalIntentSlots],request:PersonalIntentRequest) throws -> PersonalPlan {
        try validate(request)
        guard !slots.isEmpty, slots.count<=8 else { throw PersonalPlanningFailure.invalidOutput }
        // Irrelevant generated fields cannot hide request words from intent checks.
        for slot in slots {
            switch slot.action {
            case "open","close": guard slot.content.isEmpty,slot.recipient.isEmpty else { throw PersonalPlanningFailure.invalidOutput }
            case "message": guard slot.app.isEmpty else { throw PersonalPlanningFailure.invalidOutput }
            default: guard slot.app.isEmpty,slot.recipient.isEmpty else { throw PersonalPlanningFailure.invalidOutput }
            }
        }
        func literal(_ value:String)->Bool { !value.isEmpty && value.utf8.count<=1200 && request.text.range(of:value,options:[.caseInsensitive,.diacriticInsensitive]) != nil }
        func verb(_ pattern:String)->Bool { request.text.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil }
        var outsidePayloads=request.text
        for slot in slots where ["google","youtube","message","note"].contains(slot.action) && literal(slot.content) {
            outsidePayloads=outsidePayloads.replacingOccurrences(of:slot.content,with:" [literal data] ",options:[.caseInsensitive,.diacriticInsensitive])
        }
        guard outsidePayloads.range(of:#"\b(don't|do not|never|instead|actually|not|delete|erase|remove|buy|pay|purchase|transfer|install|download|execute|script|shell)\b"#,options:[.regularExpression,.caseInsensitive]) == nil else { throw PersonalPlanningFailure.unsupported }
        if outsidePayloads.range(of:#"\b(search|look up|google|youtube)\b"#,options:[.regularExpression,.caseInsensitive]) != nil,
           !slots.contains(where:{["google","youtube"].contains($0.action)}) { throw PersonalPlanningFailure.invalidOutput }
        if outsidePayloads.range(of:#"\b(text|message|send)\b"#,options:[.regularExpression,.caseInsensitive]) != nil,
           !slots.contains(where:{$0.action == "message"}) { throw PersonalPlanningFailure.invalidOutput }
        for (pattern,action) in [(#"\b(clos(?:e|ing)|quit(?:ting)?|exit(?:ing)?)\b"#,"close"),(#"\b(open(?:ing)?|launch(?:ing)?)\b"#,"open")] {
            if outsidePayloads.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil,!slots.contains(where:{$0.action == action}) { throw PersonalPlanningFailure.invalidOutput }
        }
        var skeleton=outsidePayloads
        for slot in slots where !slot.app.isEmpty { skeleton=skeleton.replacingOccurrences(of:slot.app,with:" [app] ",options:[.caseInsensitive,.diacriticInsensitive]) }
        for slot in slots where slot.action == "message" && literal(slot.recipient) { skeleton=skeleton.replacingOccurrences(of:slot.recipient,with:" [recipient] ",options:[.caseInsensitive,.diacriticInsensitive]) }
        if skeleton.range(of:#"\b(how (?:do|can|should|to)|should i|what if|maybe|thinking about)\b"#,options:[.regularExpression,.caseInsensitive]) != nil { throw PersonalPlanningFailure.unsupported }
        if slots.count==1,["open","close"].contains(slots[0].action) {
            let verbs=try NSRegularExpression(pattern:#"\b(open(?:ing)?|launch(?:ing)?|start(?:ing)?|clos(?:e|ing)|quit(?:ting)?|exit(?:ing)?|shut(?:ting)?)\b"#,options:.caseInsensitive)
            if verbs.numberOfMatches(in:skeleton,range:NSRange(skeleton.startIndex...,in:skeleton))>1 { throw PersonalPlanningFailure.invalidOutput }
        }
        if slots.count==1,skeleton.range(of:#"\b(and|then)\b"#,options:[.regularExpression,.caseInsensitive]) != nil { throw PersonalPlanningFailure.unsupported }
        if outsidePayloads.range(of:#"\b(?:create|write|jot)(?: a)? note\b"#,options:[.regularExpression,.caseInsensitive]) != nil,!slots.contains(where:{$0.action == "note"}) { throw PersonalPlanningFailure.invalidOutput }
        let steps = try slots.map { slot -> PersonalStep in
            switch slot.action {
            case "open", "close":
                guard literal(slot.app), outsidePayloads.range(of:slot.app,options:[.caseInsensitive,.diacriticInsensitive]) != nil, verb(slot.action == "open" ? #"\b(open(?:ing)?|launch(?:ing)?|start(?:ing)?|bring(?:ing)? up)\b"# : #"\b(clos(?:e|ing)|quit(?:ting)?|exit(?:ing)?|shut(?:ting)?)\b"#) else { throw PersonalPlanningFailure.invalidOutput }
                let app = try resolveApp(slot.app,apps:request.apps)
                return PersonalStep(tool:slot.action == "open" ? .openInstalledApp : .closeApp,text:app.id)
            case "google", "youtube":
                guard literal(slot.content), verb(#"\b(search|find|look|google|youtube)\b"#) else { throw PersonalPlanningFailure.invalidOutput }
                return PersonalStep(tool:slot.action == "google" ? .searchGoogle : .searchYouTube,text:slot.content)
            case "note":
                guard literal(slot.content),verb(#"\b(note|writ(?:e|ing)|jot(?:ting)?|sav(?:e|ing)|creat(?:e|ing))\b"#) else { throw PersonalPlanningFailure.invalidOutput }
                return PersonalStep(tool:.note,text:slot.content)
            case "music", "spotify":
                guard verb(slot.action == "spotify" ? #"\bspotify\b"# : #"\bmusic\b"#), ["play","pause"].contains(slot.content), verb(slot.content == "play" ? #"\b(play|listen|put on|resume)\b"# : #"\b(pause|stop)\b"#) else { throw PersonalPlanningFailure.invalidOutput }
                return PersonalStep(tool:slot.action == "music" ? .music : .spotify,text:slot.content)
            case "message":
                guard outsidePayloads.range(of:#"\b(?:on|via|using) (?:whatsapp|telegram|signal|sms|email)\b"#,options:[.regularExpression,.caseInsensitive]) == nil else { throw PersonalPlanningFailure.unsupported }
                guard literal(slot.recipient), literal(slot.content), verb(#"\b(text|message|send)\b"#) else { throw PersonalPlanningFailure.invalidOutput }
                return PersonalStep(tool:.message,text:try PersonalMessage(recipient:slot.recipient,body:slot.content).encoded())
            default: throw PersonalPlanningFailure.unsupported
            }
        }
        let result=try PersonalPlan(steps:steps,createdAt:request.now)
        if slots.count>1 {
            let reference=try quick(request)
            guard reference.steps.map({ signature($0,apps:request.apps) }) == steps.map({ signature($0,apps:request.apps) }) else { throw PersonalPlanningFailure.invalidOutput }
        }
        return result
    }
    private static func signature(_ step:PersonalStep,apps:[PersonalApp])->String {
        let kind = step.tool == .openApp ? PersonalTool.openInstalledApp : step.tool
        let text = step.tool == .openApp ? ((try? resolveApp(step.text,apps:apps).id) ?? step.text) : step.text
        return kind.rawValue + ":" + text + ":" + (step.date?.ISO8601Format() ?? "")
    }
    private static func appSequence(_ text:String,request:PersonalIntentRequest) throws -> PersonalPlan {
        let re=try NSRegularExpression(pattern:#"\s+(?:and then|then|and)\s+"#,options:.caseInsensitive)
        let split=re.stringByReplacingMatches(in:text,range:NSRange(text.startIndex...,in:text),withTemplate:"\u{001F}").components(separatedBy:"\u{001F}")
        guard split.count>1,split.count<=8 else { throw PersonalPlanningFailure.unsupported }
        var previous:String?,steps:[PersonalStep]=[]
        for raw in split {
            let value=PersonalAgentDialogue.canonical(raw)
            let pattern=try NSRegularExpression(pattern:#"^(open(?:ing)?|launch(?:ing)?|start(?:ing)?|clos(?:e|ing)|quit(?:ting)?|exit(?:ing)?) (.+)$"#,options:.caseInsensitive)
            let operation:String,mention:String
            if let m=pattern.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),let v=Range(m.range(at:1),in:value),let a=Range(m.range(at:2),in:value) { operation=String(value[v]).lowercased();mention=String(value[a]);previous=operation }
            else if let inherited=previous { operation=inherited;mention=value }
            else { throw PersonalPlanningFailure.unsupported }
            let app=try resolveApp(mention,apps:request.apps)
            steps.append(.init(tool:["close","closing","quit","quitting","exit","exiting"].contains(operation) ? .closeApp:.openInstalledApp,text:app.id))
        }
        return try PersonalPlan(steps:steps,createdAt:request.now)
    }
    /// Fast whole-request understanding for common phrases; other phrasing goes to local model slots.
    public static func quick(_ request:PersonalIntentRequest) throws -> PersonalPlan {
        try validate(request)
        let raw=PersonalAgentDialogue.stripLeadingCourtesy(request.text)
        if let website=try PersonalWebsiteRequest.plan(raw,apps:request.apps,now:request.now) {return website}
        if let schedule=try PersonalMessageSchedule.parse(raw,now:request.now) {return schedule}
        if let menu=try PersonalMenuAction.parse(raw,now:request.now) {return menu}
        if let mail=try PersonalMailCommand.parse(raw,now:request.now) {return mail}
        if let browser=try PersonalBrowserExtra.parse(raw,now:request.now) {return browser}
        if let screenshot=try PersonalScreenCapture.parse(raw,now:request.now) {return screenshot}
        if let file=try PersonalFileAction.parse(raw,now:request.now) {return file}
        if let object=try PersonalObjectCommand.parse(raw,now:request.now) {return object}
        if let record=try PersonalRecordCommand.plan(raw,now:request.now) { return record }
        if let timer=try PersonalTimerControl.parse(raw,now:request.now) { return timer }
        if let mac=try PersonalMacControl.parse(raw,now:request.now) { return mac }
        if let layout=try PersonalWindowLayout.parse(raw,apps:request.apps,now:request.now) { return layout }
        if let controls=try PersonalControlIntents.parse(raw,now:request.now) { return controls }
        if let file=try PersonalFileIntents.parse(raw,now:request.now) { return file }
        if let window=try windowCommand(raw,apps:request.apps,now:request.now) { return window }
        if let repeated=repeatedOpen(raw,apps:request.apps,now:request.now,allowClose:true) { return repeated }
        if let exact = try? PersonalIntentParser.parse(raw,now:request.now) { return exact }
        // Expand only app-only conjunctions. Every named app must resolve before any effect.
        if let apps=try? appSequence(raw,request:request) { return apps }
        let payload = raw.range(of:#"^(?:search|look up|find|google|youtube|text|message|send|create|write|jot)\b"#,options:[.regularExpression,.caseInsensitive]) != nil
        let text = payload ? raw : PersonalAgentDialogue.canonical(raw)
        func capture(_ pattern:String)->[String]? {
            guard let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive), let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)), match.range.length == text.utf16.count else { return nil }
            return (1..<match.numberOfRanges).compactMap { Range(match.range(at:$0),in:text).map { String(text[$0]) } }
        }
        if let values=capture(#"^(?:writ(?:e|ing)|jot(?:ting)?|save)(?: a)? note (.+)$"#) {
            return try ground([.init(action:"note",content:values[0])],request:request)
        }
        if let values=capture(#"^(open(?:ing)?|launch(?:ing)?|start(?:ing)?|clos(?:e|ing)|quit(?:ting)?|exit(?:ing)?) (.+)$"#) {
            return try ground([.init(action:["close","closing","quit","quitting","exit","exiting"].contains(values[0].lowercased()) ? "close" : "open",app:values[1])],request:request)
        }
        if let values=capture(#"^(?:search|look up|find)(?: for)? (.+) (?:on|in) (google|youtube)$"#) {
            return try ground([.init(action:values[1].lowercased(),content:values[0])],request:request)
        }
        if let values=capture(#"^(google|youtube|search google|search youtube|search for|search) (.+)$"#) {
            return try ground([.init(action:values[0].lowercased().contains("youtube") ? "youtube" : "google",content:values[1])],request:request)
        }
        if let values=capture(#"^(play|pause|stop|resume) (?:some )?music(?: on (spotify))?$"#) {
            return try ground([.init(action:values.count>1 ? "spotify" : "music",content:["pause","stop"].contains(values[0].lowercased()) ? "pause" : "play")],request:request)
        }
        if let values=capture(#"^(?:text|message|send a message to|send a text to) (.+?) (?:saying|that says|:) (.+)$"#) {
            return try ground([.init(action:"message",content:values[1],recipient:values[0])],request:request)
        }
        throw PersonalPlanningFailure.unsupported
    }
}
public enum PersonalAuthorization {
    public static func routine(_ plan:PersonalPlan)->Bool {
        guard !plan.requiresReview else {return false}
        return plan.steps.allSatisfy { step in
            switch step.tool {
            case .message,.trashFolder,.routineSave,.messageSchedule,.screenCapture:return false
            case .recordAction:guard let c=try? PersonalRecordCommand.decode(step.text) else {return false};return !c.isMutation
            case .notesAction:guard let c=try? PersonalObjectCommand.decode(step.text) else {return false};return [.noteFolders,.noteFind,.noteOpen,.noteCreateFolder].contains(c.action)
            case .fileAction:guard let c=try? PersonalFileAction.decode(step.text) else {return false};return [.reveal,.info].contains(c.action)
            case .browserExtra:guard let c=try? PersonalBrowserExtra.decode(step.text) else {return false};return c.action != .close
            case .menuAction:guard let c=try? PersonalMenuAction.decode(step.text) else {return false};return c.action != .lock
            case .macControl:guard let c=try? PersonalMacControl.decode(step.text) else {return false};return c.action != .lowPower
            case .mailAction:guard let c=try? PersonalMailCommand.decode(step.text) else {return false};return c.action == .draft
            default:return true
            }
        }
    }
}
public extension PersonalStep {
    var displayText:String {
        if [.createFolder,.openFolder,.closeFolder,.findFolder,.trashFolder].contains(tool),let folder=try? PersonalFolderCommand.decode(text) {
            let verb:String = switch tool {case .createFolder:"Create folder";case .openFolder:"Open folder";case .closeFolder:"Close Finder window for";case .findFolder:"Find folders matching";case .trashFolder:"Move folder to Trash:";default:"Folder"}
            return verb+" "+folder.label
        }
        if tool == .messageSchedule,let c=try? PersonalMessageSchedule.decode(text) {return c.summary}
        if tool == .website,let c=try? PersonalWebsiteRequest.decode(text) {return c.label}
        if tool == .menuAction,let c=try? PersonalMenuAction.decode(text) {return c.summary}
        if tool == .mailAction,let c=try? PersonalMailCommand.decode(text) {return c.summary}
        if tool == .routineSave,let c=try? PersonalRoutineSave.decode(text) {return "Save routine “"+c.definition.name+"”: "+c.definition.steps.map(\.displayText).joined(separator:" → ")+". Saving executes no steps."}
        if tool == .browserExtra,let c=try? PersonalBrowserExtra.decode(text) {return c.summary}
        if tool == .screenCapture,let c=try? PersonalScreenCapture.decode(text) {return "Capture "+(c.region ? "a user-selected area":"the reviewed display")+" into Documents/Wesley Flow Screenshots; no upload"}
        if tool == .fileAction,let c=try? PersonalFileAction.decode(text) {return c.summary}
        if [.notesAction,.mediaAction,.contactAction].contains(tool),let c=try? PersonalObjectCommand.decode(text) {return c.summary}
        if tool == .recordAction,let request=try? PersonalRecordCommand.decode(text) {return request.summary}
        if tool == .layoutApp,let layout=try? PersonalWindowLayout.decode(text) { return "Arrange "+layout.appID+": "+layout.layout.rawValue }
        if tool == .systemAudio,let request=try? PersonalAudioCommand.decode(text) { return request.label }
        if tool == .browserControl,let request=try? PersonalBrowserControl.decode(text) { return request.label }
        if tool == .searchBrowser,let request=try? PersonalBrowserQuery.decode(text) { return "Search in "+request.browser.rawValue.capitalized+": “"+request.query+"”" }
        if tool == .message, let message=try? PersonalMessage.decode(text) { return "Messages → " + message.recipient + " (" + (message.address ?? "recipient not resolved") + "): “" + message.body + "”" }
        return tool.rawValue + ": " + text + (date.map { " · " + $0.formatted() } ?? "")
    }
}
