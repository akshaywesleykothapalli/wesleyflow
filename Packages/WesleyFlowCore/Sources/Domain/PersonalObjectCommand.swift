import Foundation
public struct PersonalObjectCommand:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {
        case noteFolders,noteCreateFolder,noteFind,noteOpen,noteAppend,noteRename,noteMove,noteDuplicate,notePDF,noteTrash,mediaAlbum
        case mediaTrack,mediaPlaylist,mediaShuffleOn,mediaShuffleOff,mediaRepeatOne,mediaRepeatOff,mediaSeek,mediaStatus
        case contactsFind,contactPhones,contactMessages,contactWhatsApp
    }
    public let action:Action
    public var name:String
    public var value:String
    public var targetID:String?
    public var containerID:String?
    public var version:String?
    public var scopeName:String?
    public init(action:Action,name:String="",value:String="",targetID:String?=nil,containerID:String?=nil,version:String?=nil,scopeName:String?=nil) throws {
        guard name.utf8.count<=200,value.utf8.count<=1200,!value.unicodeScalars.contains(where:{$0.properties.generalCategory == .control && !["\n","\r","\t"].contains(String($0))}),(targetID?.utf8.count ?? 0)<=300,(containerID?.utf8.count ?? 0)<=300,(version?.utf8.count ?? 0)<=500,!name.unicodeScalars.contains(where:{$0.value<32}) else {throw PersonalAgentError.invalidCommand}
        self.action=action;self.name=name;self.value=value;self.targetID=targetID;self.containerID=containerID;self.version=version;self.scopeName=scopeName
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));return try .init(action:c.action,name:c.name,value:c.value,targetID:c.targetID,containerID:c.containerID,version:c.version,scopeName:c.scopeName)}
    public var summary:String {
        let verb:String=switch action {case .noteFolders:"Show Notes folders";case .noteCreateFolder:"Create Notes folder";case .noteFind:"Find note titles";case .noteOpen:"Open note";case .noteAppend:"Append literal text to note";case .noteRename:"Rename note";case .noteMove:"Move note";case .noteDuplicate:"Duplicate attachment-free note";case .notePDF:"Export attachment-free note as plain-text PDF to Documents";case .noteTrash:"Move ordinary modern note to Recently Deleted; recovery must be verified";case .mediaTrack:"Play exact Music library track";case .mediaPlaylist:"Play exact Music playlist";case .mediaShuffleOn:"Enable shuffle";case .mediaShuffleOff:"Disable shuffle";case .mediaRepeatOne:"Repeat current Music track";case .mediaRepeatOff:"Disable Music repeat";case .mediaSeek:"Seek forward seconds in current Music track";case .mediaStatus:"Show current track metadata";case .mediaAlbum:"Find the requested album in Spotify for native selection";case .contactsFind:"Find contact names";case .contactPhones:"Show this contact’s phone numbers";case .contactMessages:"Open exact-number Messages chat; no text sent";case .contactWhatsApp:"Open exact-number WhatsApp chat link; no text sent"}
        return verb+(name.isEmpty ? "":" · “"+name+"”")+(value.isEmpty ? "":" → “"+value+"”")+(scopeName.map{" · Account: "+$0} ?? "")
    }
    public var tool:PersonalTool {action.rawValue.hasPrefix("note") ? .notesAction:action.rawValue.hasPrefix("media") ? .mediaAction:.contactAction}
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.stripLeadingCourtesy(input).trimmingCharacters(in:CharacterSet(charactersIn:".!?"))
        let fixed:[String:Action]=["show my notes folders":.noteFolders,"turn shuffle off in music":.mediaShuffleOff,"turn shuffle on in spotify":.mediaShuffleOn,"repeat this track in music":.mediaRepeatOne,"turn repeat off in music":.mediaRepeatOff,"what song is playing in spotify":.mediaStatus]
        var command:Self?
        if let action=fixed[text.lowercased()] {command=try Self(action:action,name:action == .noteFolders ? "":(action == .mediaShuffleOn || action == .mediaStatus ? "spotify":"music"))}
        func capture(_ pattern:String)->[String]? {guard let re=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else {return nil};return (1..<m.numberOfRanges).compactMap{Range(m.range(at:$0),in:text).map{String(text[$0])}}}
        let patterns:[(String,Action)]=[(#"^create a Notes folder called (.+)$"#,.noteCreateFolder),(#"^find notes titled (.+)$"#,.noteFind),(#"^open the note titled (.+)$"#,.noteOpen),(#"^rename my note (.+) to (.+)$"#,.noteRename),(#"^move my (.+) note to (.+)$"#,.noteMove),(#"^duplicate my (.+) note$"#,.noteDuplicate),(#"^export my (.+) note as PDF$"#,.notePDF),(#"^move my (.+) note to Recently Deleted$"#,.noteTrash),(#"^play the song named (.+) in Music$"#,.mediaTrack),(#"^play the album named (.+) in Spotify$"#,.mediaAlbum),(#"^play my (.+) playlist in Music$"#,.mediaPlaylist),(#"^find (.+) in Contacts$"#,.contactsFind),(#"^show the phone numbers for (.+)$"#,.contactPhones),(#"^open my chat with (.+) in Messages$"#,.contactMessages),(#"^open my chat with (.+) in WhatsApp$"#,.contactWhatsApp)]
        for (pattern,action) in patterns {if let v=capture(pattern) {command=try Self(action:action,name:v[0],value:v.count>1 ? v[1]:"");break}}
        if let v=capture(#"^play the song named (.+?) by (.+?)(?: from album (.+?))? in Music$"#) {command=try Self(action:.mediaTrack,name:v[0],value:v[1],scopeName:v.count>2 ? v[2]:nil)}
        if let v=capture(#"^move my (.+) note to Recently Deleted$"#) {command=try Self(action:.noteTrash,name:v[0])}
        if let v=capture(#"^append (.+) to my (.+) note$"#) {command=try Self(action:.noteAppend,name:v[1],value:v[0])}
        if let v=capture(#"^skip forward (.+?) seconds? in Music$"#),let count=PersonalControlIntents.number(v[0]),(1...3600).contains(count) {command=try Self(action:.mediaSeek,name:"music",value:String(count))}
        guard let command else {return nil}
        return try .init(steps:[.init(tool:command.tool,text:try command.encoded())],createdAt:now)
    }
}
