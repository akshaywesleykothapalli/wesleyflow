import AppKit
import Contacts
import CryptoKit
import Darwin
import Domain
@MainActor public enum NativeMailActions {
    private static let q=NativeAgentScript.literal
    static func source(_ body:String)->String {"with timeout of 8 seconds\ntell application id \"com.apple.mail\"\n"+body+"\nend tell\nend timeout"}
    private static func descriptor(_ body:String) throws ->NSAppleEventDescriptor {
        var error:NSDictionary?;guard let script=NSAppleScript(source:source(body)) else {throw PersonalAgentError.invalidCommand}
        let result=script.executeAndReturnError(&error)
        if (error?[NSAppleScript.errorNumber] as? Int)==(-1743) {throw PersonalAgentError.permissionDenied}
        guard error==nil else {throw PersonalAgentError.verificationFailed};return result
    }
    private static func execute(_ body:String) throws ->String {guard let value=try descriptor(body).stringValue else {throw PersonalAgentError.verificationFailed};return value}
    private static func list(_ descriptor:NSAppleEventDescriptor?)->[String]? {
        guard let descriptor,descriptor.numberOfItems<=10 else {return nil}
        var result:[String]=[]
        for index in 1...max(1,descriptor.numberOfItems) where descriptor.numberOfItems>0 {guard let item=descriptor.atIndex(index)?.stringValue else {return nil};result.append(item)};return result
    }
    static func snapshotBody(_ id:Int?=nil)->String {
        let select:String
        if let id {select="set d to outgoing message id \(id)"}
        else {select="set draftsFound to outgoing messages whose visible is true\nif (count of draftsFound) is not 1 then error \"ambiguous-draft\"\nset d to item 1 of draftsFound"}
        return """
        \(select)
        set links to {}
        set parts to attachments of content of d
        if (count of parts)>5 then error "too-many-attachments"
        repeat with part in parts
          set end of links to POSIX path of (file name of part)
        end repeat
        return {id of d, sender of d, subject of d, (content of d) as text, address of to recipients of d, address of cc recipients of d, address of bcc recipients of d, links}
        """
    }
    static func file(_ url:URL,expectedIdentity:String?=nil) throws ->(identity:String,digest:String) {
        let fd=Darwin.open(url.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else {throw PersonalAgentError.permissionDenied}
        let reader=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer {try? reader.close()}
        var original=stat();guard fstat(fd,&original)==0,(original.st_mode & mode_t(S_IFMT))==mode_t(S_IFREG),original.st_size<=16*1024*1024 else {throw PersonalAgentError.unsupported}
        let originalIdentity="\(original.st_dev):\(original.st_ino):\(original.st_birthtimespec.tv_sec):\(original.st_birthtimespec.tv_nsec)"
        if let expectedIdentity {guard originalIdentity==expectedIdentity else {throw PersonalAgentError.verificationFailed}}
        var hasher=SHA256(),bytes=0
        while let data=try reader.read(upToCount:16384),!data.isEmpty {try Task.checkCancellation();bytes+=data.count;guard bytes<=16*1024*1024 else {throw PersonalAgentError.unsupported};hasher.update(data:data)}
        var final=stat();guard fstat(fd,&final)==0,final.st_ino==original.st_ino,final.st_dev==original.st_dev,final.st_size==original.st_size,final.st_mtimespec.tv_sec==original.st_mtimespec.tv_sec,final.st_mtimespec.tv_nsec==original.st_mtimespec.tv_nsec else {throw PersonalAgentError.verificationFailed}
        return ("\(original.st_dev):\(original.st_ino):\(original.st_birthtimespec.tv_sec):\(original.st_birthtimespec.tv_nsec)",hasher.finalize().map{String(format:"%02x",$0)}.joined())
    }
    typealias AddedAttachment=(before:PersonalMailSnapshot,url:URL,identity:String,digest:String)
    static func sameEnvelope(_ a:PersonalMailSnapshot,_ b:PersonalMailSnapshot)->Bool {a.id==b.id && a.sender==b.sender && a.subject==b.subject && a.body==b.body && a.to==b.to && a.cc==b.cc && a.bcc==b.bcc && a.attachments==b.attachments}
    private static func snapshot(_ id:Int?=nil,expected:PersonalMailSnapshot?=nil,adding:AddedAttachment?=nil) throws ->PersonalMailSnapshot {
        let value=try descriptor(snapshotBody(id))
        guard value.numberOfItems==8,let id=Int(value.atIndex(1)?.stringValue ?? ""),let sender=value.atIndex(2)?.stringValue,let subject=value.atIndex(3)?.stringValue,let body=value.atIndex(4)?.stringValue,let to=list(value.atIndex(5)),let cc=list(value.atIndex(6)),let bcc=list(value.atIndex(7)),let files=list(value.atIndex(8)) else {throw PersonalAgentError.unsupported}
        let metadata=try PersonalMailSnapshot(id:id,sender:sender,subject:subject,body:body,to:to,cc:cc,bcc:bcc,attachments:files)
        var expectedIDs:[String]=[]
        if let expected {
            // Reject changed envelopes/paths before reading any newly substituted file.
            guard sameEnvelope(metadata,expected),expected.attachmentIdentities.count==files.count,expected.attachmentDigests.count==files.count else {throw PersonalAgentError.verificationFailed}
            expectedIDs=expected.attachmentIdentities
        }
        if let adding {
            let before=adding.before
            let oldText=before.body.replacingOccurrences(of:"\u{FFFC}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
            let newText=body.replacingOccurrences(of:"\u{FFFC}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
            guard metadata.id==before.id,sender==before.sender,subject==before.subject,to==before.to,cc==before.cc,bcc==before.bcc,newText==oldText,files==before.attachments+[adding.url.path],before.attachmentIdentities.count==before.attachments.count else {throw PersonalAgentError.verificationFailed}
            // If Mail hides attachments behind a different opaque cache path, remain unverified;
            // do not widen filesystem access to inspect an unapproved path.
            expectedIDs=before.attachmentIdentities+[adding.identity]
        }
        var digests:[String]=[],identities:[String]=[]
        for (i,path) in files.enumerated() {
            let bound=expectedIDs.isEmpty ? nil:expectedIDs[i]
            let result=try file(URL(fileURLWithPath:path),expectedIdentity:bound);digests.append(result.digest);identities.append(result.identity)
        }
        return try .init(id:id,sender:sender,subject:subject,body:body,to:to,cc:cc,bcc:bcc,attachments:files,attachmentDigests:digests,attachmentIdentities:identities)
    }
    private static func email(_ query:String,plan:PersonalPlan,stepID:UUID) async throws ->String {
        if query.contains("@"),PersonalMessage.validAddress(query) {return query}
        let store=CNContactStore()
        if CNContactStore.authorizationStatus(for:.contacts) == .notDetermined {guard try await store.requestAccess(for:.contacts) else {throw PersonalAgentError.permissionDenied}}
        guard CNContactStore.authorizationStatus(for:.contacts) == .authorized else {throw PersonalAgentError.permissionDenied}
        let contacts=try store.unifiedContacts(matching:CNContact.predicateForContacts(matchingName:query),keysToFetch:[CNContactFormatter.descriptorForRequiredKeys(for:.fullName),CNContactEmailAddressesKey as CNKeyDescriptor]).filter{NativePersonalMessages.matches(query,fullName:CNContactFormatter.string(from:$0,style:.fullName) ?? "",givenName:$0.givenName)}
        var choices:[PersonalRecipientOption]=[]
        for contact in contacts {let name=CNContactFormatter.string(from:contact,style:.fullName) ?? query;for value in contact.emailAddresses {let address=String(value.value);if PersonalMessage.validAddress(address) {let option=PersonalRecipientOption(name:name,address:address,sourceID:contact.identifier);if !choices.contains(option) {choices.append(option)}}}}
        guard choices.count==1,let choice=choices.first else {throw PersonalRecipientChoiceRequired(plan:plan,stepID:stepID,options:Array(choices.prefix(6)),prompt:"Which exact contact/email address should receive this draft? Nothing is sent.")};return choice.address
    }
    public static func resolve(_ plan:PersonalPlan) async throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .mailAction {
            var c=try PersonalMailCommand.decode(steps[i].text)
            switch c.action {
            case .draft:c.recipient=try await email(c.recipient,plan:plan,stepID:steps[i].id)
            case .reply:
                let data=try descriptor("if (count of selection) is not 1 then error \"ambiguous-message\"\nset original to item 1 of selection\nreturn {id of original, extract address from sender of original, subject of original}")
                guard data.numberOfItems==3,let id=Int(data.atIndex(1)?.stringValue ?? ""),let address=data.atIndex(2)?.stringValue,PersonalMessage.validAddress(address),let subject=data.atIndex(3)?.stringValue else {throw PersonalAgentError.unsupported}
                c.sourceMessageID=id;c.recipient=address;c.subject="Re: "+subject
            case .attach,.send:
                c.snapshot=try snapshot()
                if c.action == .attach {
                    guard let location=c.fileLocation,let name=c.fileName else {throw PersonalAgentError.invalidCommand}
                    let root=NativePersonalFolders.rootURL(location)
                    guard (try root.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else {throw PersonalAgentError.unsupported}
                    let info=try file(root.appendingPathComponent(name));c.fileIdentity=info.identity;c.fileDigest=info.digest
                }
            }
            steps[i] = .init(id:steps[i].id,tool:.mailAction,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    public static func perform(_ step:PersonalStep) throws ->PersonalReceipt {
        try perform(step,execute:{try Self.execute($0)},readSnapshot:{try Self.snapshot($0,expected:$1,adding:$2)},inspectFile:{try Self.file($0,expectedIdentity:$1)})
    }
    static func perform(_ step:PersonalStep,execute:(String) throws ->String,readSnapshot:(Int,PersonalMailSnapshot?,AddedAttachment?) throws ->PersonalMailSnapshot,inspectFile:(URL,String?) throws ->(identity:String,digest:String)) throws ->PersonalReceipt {
        let c=try PersonalMailCommand.decode(step.text)
        switch c.action {
        case .draft:
            guard c.recipient.contains("@"),PersonalMessage.validAddress(c.recipient) else {throw PersonalAgentError.approvalRequired}
            let id=try execute("""
            set created to make new outgoing message with properties {subject:\(q(c.subject)),content:\(q(c.body)),visible:true,message signature:missing value}
            tell created
              make new to recipient at end of to recipients with properties {address:\(q(c.recipient))}
            end tell
            return (id of created) as text
            """)
            guard let draftID=Int(id) else {throw PersonalAgentError.verificationFailed}
            let state=try readSnapshot(draftID,nil,nil)
            guard state.subject==c.subject,state.to==[c.recipient],state.cc.isEmpty,state.bcc.isEmpty,state.attachments.isEmpty,state.body.trimmingCharacters(in:.whitespacesAndNewlines)==c.body.trimmingCharacters(in:.whitespacesAndNewlines) else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:id,evidence:"Mail draft created; exact recipient, subject and literal body read back. Nothing sent.")
        case .reply:
            guard let id=c.sourceMessageID,PersonalMessage.validAddress(c.recipient) else {throw PersonalAgentError.approvalRequired}
            let newID=try execute("""
            set originals to messages of inbox whose id is \(id)
            if (count of originals) is not 1 then
              if (count of selection) is not 1 then error "original-unavailable"
              set original to item 1 of selection
              if id of original is not \(id) then error "selection-changed"
            else
              set original to item 1 of originals
            end if
            if (extract address from sender of original) is not \(q(c.recipient)) then error "sender-changed"
            set created to reply original opening window true reply to all false
            set message signature of created to missing value
            set content of created to \(q(c.body))
            return (id of created) as text
            """)
            guard let draftID=Int(newID) else {throw PersonalAgentError.verificationFailed};let state=try readSnapshot(draftID,nil,nil)
            guard state.to==[c.recipient],state.cc.isEmpty,state.bcc.isEmpty,state.body.trimmingCharacters(in:.whitespacesAndNewlines)==c.body.trimmingCharacters(in:.whitespacesAndNewlines) else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:newID,evidence:"Literal reply drafted for the exact selected message/sender and body read back. Nothing sent.")
        case .attach:
            guard let before=c.snapshot,let name=c.fileName,let location=c.fileLocation else {throw PersonalAgentError.approvalRequired}
            guard try readSnapshot(before.id,before,nil)==before else {throw PersonalAgentError.verificationFailed}
            let url=NativePersonalFolders.rootURL(location).appendingPathComponent(name),info=try inspectFile(url,c.fileIdentity)
            guard info.identity==c.fileIdentity,info.digest==c.fileDigest else {throw PersonalAgentError.verificationFailed}
            _=try execute("set d to outgoing message id \(before.id)\ntell content of d\nmake new attachment with properties {file name:(POSIX file \(q(url.path)))} at after last paragraph\nend tell\nreturn \"attachment-call-returned\"")
            let after=try readSnapshot(before.id,nil,(before,url,info.identity,info.digest))
            guard after.sender==before.sender,after.subject==before.subject,after.to==before.to,after.cc==before.cc,after.bcc==before.bcc,after.attachments.count==before.attachments.count+1,after.attachmentDigests.filter({$0==info.digest}).count==before.attachmentDigests.filter({$0==info.digest}).count+1 else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:String(before.id),evidence:"Reviewed file attached to the exact draft; attachment content digest read back. Nothing sent.")
        case .send:
            guard let before=c.snapshot,!before.to.isEmpty else {throw PersonalAgentError.approvalRequired}
            guard try readSnapshot(before.id,before,nil)==before else {throw PersonalAgentError.verificationFailed}
            let result=try execute("set d to outgoing message id \(before.id)\nif send d is not true then error \"send-not-accepted\"\nreturn \"send-accepted\"")
            guard result=="send-accepted" else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:String(before.id),evidence:"Mail accepted sending the exact reviewed sender, recipients, subject, body and attachment digests. Delivery unverified; inspect Mail before any retry.",verified:false)
        }
    }
}
