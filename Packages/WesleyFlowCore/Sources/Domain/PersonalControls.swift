import Foundation

public struct PersonalAudioCommand:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case status,set,up,down,mute,unmute}
    public let action:Action
    public let percent:Int?
    public init(action:Action,percent:Int?=nil) throws {
        guard action == .set ? (percent.map{(0...100).contains($0)} ?? false) : percent==nil else {throw PersonalAgentError.invalidCommand}
        self.action=action;self.percent=percent
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let v=try JSONDecoder().decode(Self.self,from:Data(text.utf8));return try Self(action:v.action,percent:v.percent)}
    public var label:String {switch action {case .status:"Check output volume";case .set:"Set output volume to \(percent ?? 0)%";case .up:"Raise output volume by 10 points";case .down:"Lower output volume by 10 points";case .mute:"Mute output audio";case .unmute:"Unmute output audio"}}
}
public struct PersonalBrowserControl:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case newTab,newWindow,nextTab,previousTab}
    public let browser:PersonalBrowserQuery.Browser
    public let action:Action
    public init(browser:PersonalBrowserQuery.Browser,action:Action) {self.browser=browser;self.action=action}
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {try JSONDecoder().decode(Self.self,from:Data(text.utf8))}
    public var label:String {let verb=switch action {case .newTab:"New tab";case .newWindow:"New window";case .nextTab:"Next tab";case .previousTab:"Previous tab"};return verb+" in "+browser.rawValue.capitalized}
}
public enum PersonalControlIntents {
    public static func number(_ text:String)->Int? {
        let value=text.replacingOccurrences(of:"-",with:" ").lowercased()
        if let n=Int(value) {return n}
        let small=["zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19]
        let tens=["twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90]
        if let n=small[value] ?? tens[value] {return n};if ["one hundred","a hundred"].contains(value) {return 100}
        let parts=value.split(separator:" ").map(String.init)
        if parts.count==2,let a=tens[parts[0]],let b=small[parts[1]],(1...9).contains(b) {return a+b};return nil
    }
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(PersonalAgentDialogue.stripLeadingCourtesy(input)).lowercased()
        let words=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        for copies in 2...4 where words.count>=copies && words.count<=80 && words.count % copies==0 {
            let size=words.count/copies,part=words.prefix(size).joined(separator:" ")
            if (1..<copies).allSatisfy({n in words[n*size..<(n+1)*size].joined(separator:" ")==part}),let p=try parse(part,now:now) {return p}
        }
        func capture(_ pattern:String)->[String]? {
            guard let re=try? NSRegularExpression(pattern:pattern),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else {return nil}
            return (1..<m.numberOfRanges).compactMap{Range(m.range(at:$0),in:text).map{String(text[$0])}}
        }
        let fixed:[PersonalAudioCommand.Action:[String]]=[.status:["what is the volume","what's the volume","check volume","check the volume","volume status"],.up:["volume up","turn volume up","turn the volume up","turn system volume up","turn up the volume","increase volume","increase the volume","raise the volume"],.down:["volume down","turn volume down","turn the volume down","turn system volume down","turn down the volume","decrease volume","decrease the volume","lower the volume"],.mute:["mute","mute audio","mute the sound","mute the volume"],.unmute:["unmute","unmute audio","unmute the sound","unmute the volume"]]
        for (action,phrases) in fixed where phrases.contains(text) {return try PersonalPlan(steps:[.init(tool:.systemAudio,text:try PersonalAudioCommand(action:action).encoded())],createdAt:now)}
        if let v=capture(#"^(?:set|change|turn)(?: the)? volume to (.+?)(?: percent|%)?$"#) {
            guard let n=number(v[0]) else {throw PersonalPlanningFailure.unsupported}
            return try PersonalPlan(steps:[.init(tool:.systemAudio,text:try PersonalAudioCommand(action:.set,percent:n).encoded())],createdAt:now)
        }
        if let v=capture(#"^(?:open |create |switch to |go to )?(?:a |the )?(new tab|new window|next tab|previous tab) (?:in|on|of) (safari|brave)$"#),let browser=PersonalBrowserQuery.Browser(rawValue:v[1]) {
            let action:PersonalBrowserControl.Action = switch v[0] {case "new tab":.newTab;case "new window":.newWindow;case "next tab":.nextTab;default:.previousTab}
            return try PersonalPlan(steps:[.init(tool:.browserControl,text:try PersonalBrowserControl(browser:browser,action:action).encoded())],createdAt:now)
        }
        if let v=capture(#"^(?:play |skip to |go to )?(?:the )?(next|previous) (?:track|song)(?: (?:in|on|using) (music|apple music|spotify))?$"#) {
            let player=v.count>1 ? v[1]:"music"
            return try PersonalPlan(steps:[.init(tool:player=="spotify" ? .spotify:.music,text:v[0])],createdAt:now)
        }
        // Unsupported control requests must not be misinterpreted as an app launch or a search.
        if text.range(of:#"^(?:mute|unmute|volume|(?:set|change|turn|raise|lower|increase|decrease)(?: the)? volume|(?:open |create |switch to |go to )?(?:a |the )?(?:new tab|new window|next tab|previous tab)|(?:play |skip to |go to )?(?:the )?(?:next|previous) (?:track|song))\b"#,options:.regularExpression) != nil {throw PersonalPlanningFailure.unsupported}
        return nil
    }
}
