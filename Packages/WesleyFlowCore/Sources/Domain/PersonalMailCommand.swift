import Foundation
public struct PersonalMailSnapshot:Codable,Sendable,Equatable {
    public let id:Int
    public let sender:String
    public let subject:String
    public let body:String
    public let to:[String]
    public let cc:[String]
    public let bcc:[String]
    public let attachments:[String]
    public var attachmentDigests:[String]
    public var attachmentIdentities:[String]
    public init(id:Int,sender:String,subject:String,body:String,to:[String],cc:[String],bcc:[String],attachments:[String],attachmentDigests:[String]=[],attachmentIdentities:[String]=[]) throws {
        guard id>0,sender.utf8.count<=200,subject.utf8.count<=200,body.utf8.count<=1200,!body.unicodeScalars.contains(where:{$0.properties.generalCategory == .control && !["\n","\r","\t"].contains(String($0))}),to.count+cc.count+bcc.count<=10,attachments.count<=5,[to,cc,bcc].joined().allSatisfy({$0.contains("@") && PersonalMessage.validAddress($0)}),attachments.allSatisfy({$0.utf8.count<=1000}) else {throw PersonalAgentError.unsupported}
        self.id=id;self.sender=sender;self.subject=subject;self.body=body;self.to=to;self.cc=cc;self.bcc=bcc;self.attachments=attachments;self.attachmentDigests=attachmentDigests;self.attachmentIdentities=attachmentIdentities
    }
}
public struct PersonalMailCommand:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case draft,reply,attach,send}
    public let action:Action
    public var recipient:String
    public var subject:String
    public var body:String
    public var sourceMessageID:Int?
    public var snapshot:PersonalMailSnapshot?
    public var fileName:String?
    public var fileLocation:PersonalFolderLocation?
    public var fileIdentity:String?
    public var fileDigest:String?
    public init(action:Action,recipient:String="",subject:String="",body:String="",fileName:String?=nil,fileLocation:PersonalFolderLocation?=nil) throws {
        guard recipient.utf8.count<=200,subject.utf8.count<=200,body.utf8.count<=1200,!body.unicodeScalars.contains(where:{$0.properties.generalCategory == .control && !["\n","\r","\t"].contains(String($0))}),!subject.unicodeScalars.contains(where:{$0.value<32}) else {throw PersonalAgentError.invalidCommand}
        if let fileName {_ = try PersonalFolderCommand(name:fileName,location:fileLocation ?? .documents)}
        self.action=action;self.recipient=recipient;self.subject=subject;self.body=body;self.fileName=fileName;self.fileLocation=fileLocation
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {
        let c=try JSONDecoder().decode(Self.self,from:Data(text.utf8));_ = try Self(action:c.action,recipient:c.recipient,subject:c.subject,body:c.body,fileName:c.fileName,fileLocation:c.fileLocation)
        if let s=c.snapshot {_ = try PersonalMailSnapshot(id:s.id,sender:s.sender,subject:s.subject,body:s.body,to:s.to,cc:s.cc,bcc:s.bcc,attachments:s.attachments,attachmentDigests:s.attachmentDigests,attachmentIdentities:s.attachmentIdentities)};return c
    }
    public var summary:String {
        if let s=snapshot {return (action == .send ? "SEND EMAIL":"Attach reviewed file to draft")+" · From: "+s.sender+" · To: "+s.to.joined(separator:", ")+" · CC: "+s.cc.joined(separator:", ")+" · BCC: "+s.bcc.joined(separator:", ")+" · Subject: "+s.subject+" · Body: “"+s.body+"” · Attachments: "+s.attachments.map{URL(fileURLWithPath:$0).lastPathComponent}.joined(separator:", ")+(fileName.map{" · Add: "+$0+" in "+(fileLocation?.rawValue ?? "location needed")} ?? "")}
        return (action == .reply ? "Draft reply":"Create email draft")+" · To: "+recipient+" · Subject: "+subject+" · Body: “"+body+"”. Draft creation does not send."
    }
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input)
        func capture(_ p:String)->[String]? {guard let re=try? NSRegularExpression(pattern:p,options:.caseInsensitive),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else {return nil};return (1..<m.numberOfRanges).compactMap{Range(m.range(at:$0),in:text).map{String(text[$0])}}}
        var c:Self?
        if let v=capture(#"^draft an email to (.+?) about (.+)$"#) {c=try .init(action:.draft,recipient:v[0],subject:v[1])}
        if let v=capture(#"^draft a reply saying (.+)$"#) {c=try .init(action:.reply,body:v[0])}
        if let v=capture(#"^attach (.+?) to this email draft(?: from (Documents|Desktop|Downloads))?$"#) {c=try .init(action:.attach,fileName:v[0],fileLocation:v.count>1 ? .init(rawValue:v[1].lowercased()):nil)}
        if text.lowercased()=="send the email draft i just reviewed" {c=try .init(action:.send)}
        guard let c else {return nil};if c.action == .attach,c.fileLocation==nil {throw PersonalMailFileLocationRequired(command:c)}
        return try .init(steps:[.init(tool:.mailAction,text:try c.encoded())],createdAt:now)
    }
}
public struct PersonalMailFileLocationRequired:Error,Sendable {public let command:PersonalMailCommand}
