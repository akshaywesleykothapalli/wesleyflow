import Foundation

public enum PersonalFolderLocation:String,Codable,Sendable,CaseIterable { case documents,desktop,downloads }
public struct PersonalFolderCommand:Codable,Sendable,Equatable {
    public let name:String
    public let location:PersonalFolderLocation
    public var identity:String?
    public var rootIdentity:String?
    public init(name:String,location:PersonalFolderLocation,identity:String?=nil,rootIdentity:String?=nil) throws {
        guard name.utf8.count<=200,!name.contains("/"),!name.contains("\\"),!name.contains(":"),!name.hasPrefix("."),!name.unicodeScalars.contains(where:{$0.properties.generalCategory == .control}), (identity==nil)==(rootIdentity==nil) else { throw PersonalAgentError.invalidCommand }
        self.name=name;self.location=location;self.identity=identity;self.rootIdentity=rootIdentity
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {
        let value=try JSONDecoder().decode(Self.self,from:Data(text.utf8))
        return try Self(name:value.name,location:value.location,identity:value.identity,rootIdentity:value.rootIdentity)
    }
    public var label:String { name.isEmpty ? location.rawValue.capitalized:"“"+name+"” in "+location.rawValue.capitalized }
}
public struct PersonalBrowserQuery:Codable,Sendable {
    public enum Browser:String,Codable,Sendable {case brave,safari;public var bundleID:String {self == .brave ? "com.brave.Browser":"com.apple.Safari"}}
    public let browser:Browser
    public let query:String
    public init(browser:Browser,query:String) throws {guard !query.isEmpty,query.utf8.count<=1200 else {throw PersonalAgentError.invalidCommand};self.browser=browser;self.query=query}
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let v=try JSONDecoder().decode(Self.self,from:Data(text.utf8));return try Self(browser:v.browser,query:v.query)}
}
public enum PersonalFileIntents {
    public static func isFolderRequest(_ text:String)->Bool {
        PersonalAgentDialogue.stripLeadingCourtesy(text).range(of:#"^(?:create|make|open|close|delete|trash|remove|find|search for)(?: a| the)? folder\b"#,options:[.regularExpression,.caseInsensitive]) != nil
    }
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let raw=PersonalAgentDialogue.stripLeadingCourtesy(input),text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        func capture(_ pattern:String)->[String]? {
            guard let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else {return nil}
            return (1..<m.numberOfRanges).compactMap {Range(m.range(at:$0),in:text).map {String(text[$0])}}
        }
        let words=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        if words.count<=80 {
            for copies in 2...4 where words.count>=copies*2 && words.count % copies==0 {
                let size=words.count/copies,part=words.prefix(words.count/copies).joined(separator:" ")
                if (1..<copies).allSatisfy({n in words[n*size..<(n+1)*size].joined(separator:" ").caseInsensitiveCompare(part) == .orderedSame}),let plan=try parse(part,now:now) {return plan}
            }
        }
        if let v=capture(#"^(?:search|look up|find)(?: for)? (.+) (?:on|in|using) (brave|safari)[.!]?$"#),let browser=PersonalBrowserQuery.Browser(rawValue:v[1].lowercased()) {
            return try PersonalPlan(steps:[.init(tool:.searchBrowser,text:try PersonalBrowserQuery(browser:browser,query:v[0]).encoded())],createdAt:now)
        }
        if let v=capture(#"^search (brave|safari)(?: for)? (.+)$"#),let browser=PersonalBrowserQuery.Browser(rawValue:v[0].lowercased()) {
            return try PersonalPlan(steps:[.init(tool:.searchBrowser,text:try PersonalBrowserQuery(browser:browser,query:v[1]).encoded())],createdAt:now)
        }
        let forms:[(String,PersonalTool)]=[(#"^(?:create|make)(?: a)? folder(?: called| named)? (.+) (?:in|on) (?:my |the )?(documents|desktop|downloads)[.!]?$"#,.createFolder),(#"^open(?: the)? folder (.+) (?:in|on) (?:my |the )?(documents|desktop|downloads)[.!]?$"#,.openFolder),(#"^(?:close|close the)(?: folder) (.+) (?:in|on) (?:my |the )?(documents|desktop|downloads)[.!]?$"#,.closeFolder),(#"^(?:find|search for)(?: a| the)? folder(?: called| named)? (.+) (?:in|on) (?:my |the )?(documents|desktop|downloads)[.!]?$"#,.findFolder),(#"^(?:delete|trash|remove)(?: the)? folder (.+) (?:in|on) (?:my |the )?(documents|desktop|downloads)[.!]?$"#,.trashFolder)]
        for (pattern,tool) in forms {
            if let v=capture(pattern),let location=PersonalFolderLocation(rawValue:v[1].lowercased()) {
                var name=v[0].trimmingCharacters(in:.whitespaces)
                let quoted=name.hasPrefix("\"") && name.hasSuffix("\"") && name.count>=2
                if quoted {name=String(name.dropFirst().dropLast())}
                guard !name.isEmpty,quoted || (name.range(of:#"\b(?:then|and)\b|\b(?:in|on) (?:my |the )?(?:documents|desktop|downloads)\b"#,options:[.regularExpression,.caseInsensitive])==nil) else {throw PersonalPlanningFailure.unsupported}
                return try PersonalPlan(steps:[.init(tool:tool,text:try PersonalFolderCommand(name:name,location:location).encoded())],createdAt:now)
            }
        }
        if let v=capture(#"^open(?: my| the)? (documents|desktop|downloads)(?: folder)?[.!]?$"#),let location=PersonalFolderLocation(rawValue:v[0].lowercased()) {
            return try PersonalPlan(steps:[.init(tool:.openFolder,text:try PersonalFolderCommand(name:"",location:location).encoded())],createdAt:now)
        }
        if isFolderRequest(text) {throw PersonalPlanningFailure.unsupported}
        return nil
    }
}
public enum PersonalCommandLibrary {
    public static let examples=["Open Brave","Close Safari","Minimise Notes","Restore Notes","Make VS Code full screen","Exit full screen VS Code","Maximise Safari","Create folder Projects in Documents","Open folder Projects in Documents","Open Downloads","Find folder Projects in Documents","Close folder Projects in Documents","Delete folder Projects in Documents","Search for Swift tutorials in Brave","Search Safari for train times","Search YouTube for guitar lessons","Create a note Buy milk","Remind me call Sam in ten minutes","Set a timer for two minutes","Set volume to 40 percent","Volume up","Mute","Unmute","What is the volume","New tab in Safari","Next tab in Brave","Previous tab in Safari","New window in Brave","Next track in Spotify","Previous track in Music","Play some music","Pause music","Text +15555550123 saying hello"]
}
