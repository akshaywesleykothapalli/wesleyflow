import Foundation
public struct PersonalFileAction:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case rename,move,copy,reveal,info,compress,restore}
    public let action:Action
    public let folder:Bool
    public var name:String
    public var location:PersonalFolderLocation?
    public var destinationName:String
    public var destinationLocation:PersonalFolderLocation?
    public var sourceIdentity:String?
    public var rootIdentity:String?
    public var destinationRootIdentity:String?
    public var trashPath:String?
    public init(action:Action,folder:Bool,name:String,location:PersonalFolderLocation?,destinationName:String="",destinationLocation:PersonalFolderLocation?=nil) throws {
        guard !name.isEmpty else {throw PersonalAgentError.invalidCommand};_ = try PersonalFolderCommand(name:name,location:location ?? .documents)
        if !destinationName.isEmpty {_ = try PersonalFolderCommand(name:destinationName,location:destinationLocation ?? location ?? .documents)}
        self.action=action;self.folder=folder;self.name=name;self.location=location;self.destinationName=destinationName;self.destinationLocation=destinationLocation
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {
        let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));var checked=try Self(action:c.action,folder:c.folder,name:c.name,location:c.location,destinationName:c.destinationName,destinationLocation:c.destinationLocation)
        checked.sourceIdentity=c.sourceIdentity;checked.rootIdentity=c.rootIdentity;checked.destinationRootIdentity=c.destinationRootIdentity;checked.trashPath=c.trashPath
        guard [checked.sourceIdentity,checked.rootIdentity,checked.destinationRootIdentity,checked.trashPath].allSatisfy({($0?.utf8.count ?? 0)<=1024}) else {throw PersonalAgentError.invalidCommand};return checked
    }
    public var summary:String {if action == .restore {return "Restore folder “"+destinationName+"” from Trash to "+(destinationLocation ?? location ?? .documents).rawValue+"; never overwrite an existing item"};return action.rawValue+" "+(folder ? "folder":"file")+" “"+name+"” in "+(location?.rawValue ?? "location needed")+(destinationName.isEmpty ? "":" → “"+destinationName+"” in "+(destinationLocation ?? location ?? .documents).rawValue)}
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input)
        func capture(_ p:String)->[String]? {guard let re=try? NSRegularExpression(pattern:p,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else {return nil};return (1..<m.numberOfRanges).compactMap{Range(m.range(at:$0),in:text).map{String(text[$0])}}}
        var c:Self?
        if let v=capture(#"^rename (folder|file) (.+?) to (.+?) in (Documents|Desktop|Downloads)$"#) {c=try .init(action:.rename,folder:v[0].lowercased()=="folder",name:v[1],location:.init(rawValue:v[3].lowercased()),destinationName:v[2])}
        if let v=capture(#"^(move|copy) (folder|file) (.+?) from (Documents|Desktop|Downloads) to (Documents|Desktop|Downloads)$"#) {c=try .init(action:v[0].lowercased()=="move" ? .move:.copy,folder:v[1].lowercased()=="folder",name:v[2],location:.init(rawValue:v[3].lowercased()),destinationName:v[2],destinationLocation:.init(rawValue:v[4].lowercased()))}
        if let v=capture(#"^move file (.+?) to (Documents|Desktop|Downloads)$"#) {c=try .init(action:.move,folder:false,name:v[0],location:nil,destinationName:v[0],destinationLocation:.init(rawValue:v[1].lowercased()))}
        if let v=capture(#"^duplicate folder (.+?) in (Documents|Desktop|Downloads)(?: as (.+))?$"#) {c=try .init(action:.copy,folder:true,name:v[0],location:.init(rawValue:v[1].lowercased()),destinationName:v.count>2 ? v[2]:v[0]+" copy")}
        if let v=capture(#"^reveal file (.+?) in Finder(?: from (Documents|Desktop|Downloads))?$"#) {c=try .init(action:.reveal,folder:false,name:v[0],location:v.count>1 ? .init(rawValue:v[1].lowercased()):nil)}
        if let v=capture(#"^show information for folder (.+?) in (Documents|Desktop|Downloads)$"#) {c=try .init(action:.info,folder:true,name:v[0],location:.init(rawValue:v[1].lowercased()))}
        if let v=capture(#"^compress folder (.+?) in (Documents|Desktop|Downloads)$"#) {c=try .init(action:.compress,folder:true,name:v[0],location:.init(rawValue:v[1].lowercased()),destinationName:v[0]+".aar")}
        guard let command=c else {return nil}
        if command.location==nil {throw PersonalFileLocationRequired(command:command)}
        return try .init(steps:[.init(tool:.fileAction,text:try command.encoded())],createdAt:now)
    }
}
public struct PersonalFileLocationRequired:Error,Sendable {public let command:PersonalFileAction}
