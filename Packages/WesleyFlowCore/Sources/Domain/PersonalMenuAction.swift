import Foundation
public struct PersonalMenuAction:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case lock,reopenTab,bookmark,openBookmark,zoomIn,zoomOut,zoomReset,podcastSpeed}
    public let action:Action
    public let appID:String
    public let query:String
    public var processID:Int32?
    public init(action:Action,appID:String,query:String="") throws {
        guard ["self","com.apple.Safari","com.brave.Browser","com.apple.podcasts"].contains(appID),query.utf8.count<=200,!query.unicodeScalars.contains(where:{$0.value<32}) else {throw PersonalAgentError.invalidCommand}
        let allowed:Bool=switch action {case .lock:appID=="self";case .reopenTab,.bookmark:appID=="com.apple.Safari";case .openBookmark:appID=="com.brave.Browser";case .podcastSpeed:appID=="com.apple.podcasts";case .zoomIn,.zoomOut,.zoomReset:["com.apple.Safari","com.brave.Browser"].contains(appID)}
        guard allowed else {throw PersonalAgentError.invalidCommand}
        self.action=action;self.appID=appID;self.query=query
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));_ = try Self(action:c.action,appID:c.appID,query:c.query);return c}
    public var summary:String {
        switch action {case .lock:"Lock this Mac using its native Lock Screen menu action";case .reopenTab:"Reopen the last closed Safari tab through its native menu";case .bookmark:"Open Safari’s native Add Bookmark review; you choose the folder and confirm in Safari";case .openBookmark:"Open the unique Brave bookmark “"+query+"” through its native menu";case .zoomIn:"Zoom in through the named browser’s native menu";case .zoomOut:"Zoom out through the named browser’s native menu";case .zoomReset:"Reset zoom through the named browser’s native menu";case .podcastSpeed:"Set Apple Podcasts playback speed to 1.5× if its native control is available"}
    }
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input),lower=text.lowercased()
        let fixed:[String:(Action,String)]=["lock my mac":(.lock,"self"),"reopen the last closed tab in safari":(.reopenTab,"com.apple.Safari"),"bookmark this page in safari":(.bookmark,"com.apple.Safari"),"zoom in on this safari tab":(.zoomIn,"com.apple.Safari"),"zoom out on this brave tab":(.zoomOut,"com.brave.Browser"),"reset zoom in safari":(.zoomReset,"com.apple.Safari"),"play this podcast at one and a half speed":(.podcastSpeed,"com.apple.podcasts")]
        var c:Self?
        if let item=fixed[lower] {c=try .init(action:item.0,appID:item.1)}
        if let re=try? NSRegularExpression(pattern:#"^open my (.+) bookmark in Brave$"#,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) {c=try .init(action:.openBookmark,appID:"com.brave.Browser",query:String(text[range]))}
        guard let c else {return nil};return try .init(steps:[.init(tool:.menuAction,text:try c.encoded())],createdAt:now)
    }
}
