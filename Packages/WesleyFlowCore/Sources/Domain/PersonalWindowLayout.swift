import Foundation

public struct PersonalWindowLayout:Codable,Sendable,Equatable {
    public enum Layout:String,Codable,Sendable,CaseIterable {case left,right,top,bottom,topLeft,topRight,bottomLeft,bottomRight,nextDisplay,center}
    public let appID:String
    public let layout:Layout
    public init(appID:String,layout:Layout) throws {guard !appID.isEmpty,appID.utf8.count<=255,!appID.contains(where:{$0.isWhitespace}) else {throw PersonalAgentError.invalidCommand};self.appID=appID;self.layout=layout}
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));return try Self(appID:c.appID,layout:c.layout)}
    public static func parse(_ input:String,apps:[PersonalApp],now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input)
        let words=text.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        for copies in 2...4 where words.count>=copies*2 && words.count<=80 && words.count%copies==0 {
            let count=words.count/copies,part=words.prefix(count).joined(separator:" ")
            if (1..<copies).allSatisfy({n in words[n*count..<(n+1)*count].joined(separator:" ").caseInsensitiveCompare(part) == .orderedSame}),let plan=try parse(part,apps:apps,now:now) {return plan}
        }
        let forms:[(String,Layout)]=[("left half",.left),("right half",.right),("top half",.top),("bottom half",.bottom),("top-left quarter",.topLeft),("top-right quarter",.topRight),("bottom-left quarter",.bottomLeft),("bottom-right quarter",.bottomRight),("next display",.nextDisplay)]
        func app(_ pattern:String)->String? {guard let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) else {return nil};return String(text[range])}
        var mention:String?,layout:Layout?
        for (phrase,kind) in forms {let p=phrase.replacingOccurrences(of:"-",with:"[- ]");if let found=app("^(?:move|put|tile) (.+?)(?: window)? (?:to|on)(?: the)? "+p+"$") {mention=found;layout=kind;break}}
        if let found=app("^(?:centre|center)(?: the)? (.+?)(?: window)?$") {mention=found;layout = .center}
        guard let mention,let layout else {return nil}
        let target=try PersonalConversation.resolveApp(mention,apps:apps)
        return try .init(steps:[.init(tool:.layoutApp,text:try Self(appID:target.id,layout:layout).encoded())],createdAt:now)
    }
}
