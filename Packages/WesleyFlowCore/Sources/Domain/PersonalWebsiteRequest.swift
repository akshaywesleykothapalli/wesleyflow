import Foundation

/// Website navigation is distinct from searching for arbitrary text. Never deduplicate query payloads.
public struct PersonalWebsiteRequest:Codable,Sendable,Equatable {
    public enum Browser:String,Codable,Sendable,CaseIterable {
        case brave,safari,chrome,firefox,edge,opera,arc
        public var bundleID:String {switch self {case .brave:"com.brave.Browser";case .safari:"com.apple.Safari";case .chrome:"com.google.Chrome";case .firefox:"org.mozilla.firefox";case .edge:"com.microsoft.edgemac";case .opera:"com.operasoftware.Opera";case .arc:"company.thebrowser.Browser"}}
        public static func named(_ input:String)->Self? {
            let name=input.lowercased().replacingOccurrences(of:" browser",with:"")
            switch name {case "google chrome":return .chrome;case "microsoft edge":return .edge;default:return Self(rawValue:name)}
        }
    }
    public let address:String
    public let browser:Browser?
    public init(address:String,browser:Browser?=nil) throws {
        guard let url=Self.url(address) else {throw PersonalAgentError.invalidCommand}
        self.address=url.absoluteString;self.browser=browser
    }
    public static func url(_ input:String)->URL? {
        guard input.utf8.count<=1600,!input.isEmpty,!input.contains("\\"),!input.unicodeScalars.contains(where:{$0.properties.isWhitespace || $0.properties.generalCategory == .control}) else {return nil}
        let raw=input.contains("://") ? input:"https://"+input
        guard var components=URLComponents(string:raw),components.scheme?.lowercased()=="https",components.user==nil,components.password==nil,components.port==nil,let host=components.host,components.percentEncodedHost?.contains("%") != true else {return nil}
        var normalized=host.lowercased()
        if normalized.hasSuffix(".") {normalized.removeLast()}
        guard normalized.utf8.count<=253,normalized.range(of:#"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#,options:.regularExpression) != nil else {return nil}
        components.scheme="https";components.host=normalized
        if components.path.isEmpty {components.path="/"}
        return components.url
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ input:String) throws ->Self {let value=try JSONDecoder().decode(Self.self,from:Data(input.utf8));return try .init(address:value.address,browser:value.browser)}
    public var label:String {"Open website "+address+" in "+(browser?.rawValue.capitalized ?? "your default browser")}
    public static func plan(_ input:String,apps:[PersonalApp],now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input)
        func captures(_ pattern:String,_ value:String)->[String]? {
            guard let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m=re.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)) else {return nil}
            return (1..<m.numberOfRanges).compactMap{Range(m.range(at:$0),in:value).map{String(value[$0])}}
        }
        if let v=captures(#"^(?:open|go to) (google|youtube) and (?:search(?: for)?|look up) (.+)$"#,PersonalAgentDialogue.stripLeadingCourtesy(input)) {
            return try .init(steps:[.init(tool:v[0].lowercased()=="youtube" ? .searchYouTube:.searchGoogle,text:v[1])],createdAt:now)
        }
        // An explicit search engine always means a search, including repeated words/URLs in its payload.
        if let v=captures(#"^(?:search|look up)(?: on)? (google|youtube)(?: for)? (.+)$"#,PersonalAgentDialogue.stripLeadingCourtesy(input)) {
            return try .init(steps:[.init(tool:v[0].lowercased()=="youtube" ? .searchYouTube:.searchGoogle,text:v[1])],createdAt:now)
        }
        func single(_ value:String)throws ->Self? {
            let re=try NSRegularExpression(pattern:#"^(?:(open|visit|go to|take me to|navigate to|head to|launch|start|search for|search) )?(.+?)(?: (?:in|on|using|with) (?:the )?(brave(?: browser)?|safari|google chrome|chrome|firefox|microsoft edge|edge|opera|arc)(?: browser)?)?$"#,options:.caseInsensitive)
            guard let m=re.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),let range=Range(m.range(at:2),in:value) else {return nil}
            var name=String(value[range]);let browser=Range(m.range(at:3),in:value).flatMap{Browser.named(String(value[$0]))}
            let explicitSite=name.range(of:#" (?:website|web site|site|homepage|home page)$"#,options:[.regularExpression,.caseInsensitive])
            if let suffix=explicitSite {name=String(name[..<suffix.lowerBound])}
            if name.lowercased().hasPrefix("the ") {name=String(name.dropFirst(4))}
            let verb=Range(m.range(at:1),in:value).map{value[$0].lowercased()}
            if browser==nil,explicitSite==nil,let verb,["open","launch","start"].contains(verb),(try? PersonalConversation.resolveApp(name,apps:apps)) != nil {return nil}
            let spokenAddress=name.replacingOccurrences(of:" dot ",with:".",options:.caseInsensitive)
            if let url=Self.url(spokenAddress) {return try .init(address:url.absoluteString,browser:browser)}
            if let address=PersonalWebsiteNames.address(name),verb != "search",verb != "search for" {return try .init(address:address,browser:browser)}
            if explicitSite != nil,verb != nil {throw PersonalWebsiteAddressRequired(browser:browser)}
            return nil
        }
        func result(_ request:Self)throws ->PersonalPlan {try .init(steps:[.init(tool:.website,text:try request.encoded())],createdAt:now)}
        if let request=try single(text) {return try result(request)}
        // Narrow Agent-only repair: identical complete website requests, never arbitrary search/note/message words.
        let words=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        for copies in 2...4 where words.count<=80 && words.count>=copies && words.count % copies==0 {
            let size=words.count/copies
            if let first=try single(words.prefix(size).joined(separator:" ")) {
                let rest=try (1..<copies).map{try single(words[$0*size..<($0+1)*size].joined(separator:" "))}
                if rest.allSatisfy({$0==first}) {return try result(first)}
                if rest.allSatisfy({$0 != nil}) {throw PersonalPlanningFailure.unsupported}
            }
        }
        if let v=captures(#"^(\S+)\s+(?:search for|search|open|visit|go to)\s+(\S+)$"#,text),let first=Self.url(v[0]),let last=Self.url(v[1]) {
            guard first==last else {throw PersonalPlanningFailure.unsupported}
            return try result(.init(address:last.absoluteString))
        }
        return nil
    }
}
