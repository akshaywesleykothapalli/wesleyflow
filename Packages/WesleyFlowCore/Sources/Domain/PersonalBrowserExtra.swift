import Foundation
public struct PersonalBrowserExtra:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case close,duplicate,findTitle,findDomain}
    public let action:Action
    public let browser:PersonalBrowserQuery.Browser
    public var query:String
    public var windowID:Int?
    public var tabID:String?
    public var tabIndex:Int?
    public var url:String?
    public var title:String?
    public init(action:Action,browser:PersonalBrowserQuery.Browser,query:String="") throws {guard query.utf8.count<=200,!query.unicodeScalars.contains(where:{$0.value<32}) else {throw PersonalAgentError.invalidCommand};self.action=action;self.browser=browser;self.query=query}
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));_ = try Self(action:c.action,browser:c.browser,query:c.query);guard (c.url?.utf8.count ?? 0)<=1000,(c.title?.utf8.count ?? 0)<=300,(c.tabID?.utf8.count ?? 0)<=100 else {throw PersonalAgentError.invalidCommand};return c}
    public var summary:String {"Browser "+action.rawValue+" in "+browser.rawValue+" · "+query+(title.map{" · “"+$0+"”"} ?? "")+(url.map{" · "+$0} ?? "")+(action == .close ? " · Closing can discard unsaved content; native prompts are not bypassed.":"")}
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input)
        var c:Self?
        if text.caseInsensitiveCompare("close the current tab in Brave") == .orderedSame {c=try .init(action:.close,browser:.brave)}
        if text.caseInsensitiveCompare("duplicate this tab in Safari") == .orderedSame {c=try .init(action:.duplicate,browser:.safari)}
        func capture(_ p:String)->String? {guard let re=try? NSRegularExpression(pattern:p,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) else {return nil};return String(text[range])}
        if let name=capture(#"^find the tab named (.+) in Brave$"#) {c=try .init(action:.findTitle,browser:.brave,query:name)}
        if let domain=capture(#"^find my ([a-zA-Z0-9.-]+) tab in Safari$"#) {c=try .init(action:.findDomain,browser:.safari,query:domain)}
        guard let c else {return nil};return try .init(steps:[.init(tool:.browserExtra,text:try c.encoded())],createdAt:now)
    }
}
