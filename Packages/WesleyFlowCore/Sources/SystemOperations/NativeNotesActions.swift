import AppKit
import CoreText
import Domain
@MainActor public enum NativeNotesActions {
    private static func q(_ text:String)->String {NativeAgentScript.literal(text)}
    static func source(_ body:String)->String {"with timeout of 8 seconds\ntell application id \"com.apple.Notes\"\n"+body+"\nend tell\nend timeout"}
    private static func execute(_ body:String) throws ->String {try NativeAgentScript.execute(source(body))}
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .notesAction {
            var c=try PersonalObjectCommand.decode(steps[i].text)
            guard c.tool == .notesAction else {throw PersonalAgentError.invalidCommand}
            c.containerID=try execute("return id of default account");c.scopeName=try execute("return name of default account")
            if ![.noteFolders,.noteCreateFolder,.noteFind].contains(c.action) {
                c.targetID=try execute("""
                set matches to notes of default account whose name is \(q(c.name))
                if (count of matches) is not 1 then error "ambiguous-note"
                set n to item 1 of matches
                if password protected of n then error "protected-note"
                if shared of n then error "shared-note"
                return id of n
                """)
                c.version=try execute("return (modification date of note id \(q(c.targetID!)) of default account) as text")
                if c.action == .noteTrash {_ = try execute("if upgraded of default account is not true then error \"legacy-account-not-supported\"\nif (id of container of note id \(q(c.targetID!)) of default account) is not (id of default folder of default account) then error \"only-default-folder-supported\"\nreturn \"ok\"")}
            }
            steps[i] = .init(id:steps[i].id,tool:.notesAction,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    static func pdf(_ text:String)->Data? {
        guard text.utf8.count<=256*1024 else {return nil}
        let attributed=NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:12)])
        let setter=CTFramesetterCreateWithAttributedString(attributed)
        let data=NSMutableData();var mediaBox=CGRect(x:0,y:0,width:612,height:792);guard let consumer=CGDataConsumer(data:data),let context=CGContext(consumer:consumer,mediaBox:&mediaBox,nil) else {return nil}
        var offset=0,pages=0
        repeat {
            guard pages<100 else {return nil};pages+=1
            context.beginPDFPage(nil)
            let path=CGPath(rect:CGRect(x:36,y:36,width:540,height:720),transform:nil)
            let frame=CTFramesetterCreateFrame(setter,CFRange(location:offset,length:0),path,nil)
            CTFrameDraw(frame,context);let range=CTFrameGetVisibleStringRange(frame);context.endPDFPage()
            if text.isEmpty {break};guard range.length>0 else {return nil};offset+=range.length
        } while offset<attributed.length
        context.closePDF();return data as Data
    }
    public static func perform(_ step:PersonalStep) throws ->PersonalReceipt {
        try perform(step,execute:{try Self.execute($0)},writePDF:{data,name in try NativeFileActions.writeExclusive(data,name:name,rootURL:NativePersonalFolders.rootURL(.documents))})
    }
    static func perform(_ step:PersonalStep,execute:(String) throws ->String,writePDF:(Data,String) throws ->URL) throws ->PersonalReceipt {
        let c=try PersonalObjectCommand.decode(step.text)
        guard c.tool == .notesAction else {throw PersonalAgentError.invalidCommand}
        guard let account=c.containerID else {throw PersonalAgentError.approvalRequired}
        _=try execute("if (id of default account) is not \(q(account)) then error \"account-changed\"\nreturn \"ok\"")
        var body="",target=""
        if let id=c.targetID {
            target="note id "+q(id)+" of default account"
            guard let version=c.version else {throw PersonalAgentError.approvalRequired}
            body="""
            set n to \(target)
            if (name of n) is not \(q(c.name)) then error "note-renamed"
            if ((modification date of n) as text) is not \(q(version)) then error "note-changed"
            if password protected of n or shared of n then error "unsafe-note"
            """
        }
        body+="\n"
        switch c.action {
        case .noteFolders:body+="set names to name of folders of default account\nif (count of names)>50 then error \"too-many-folders\"\nset text item delimiters to \"; \"\nreturn names as text"
        case .noteCreateFolder:body+="""
            set matches to folders of default account whose name is \(q(c.name))
            if (count of matches)>1 then error "ambiguous-folder"
            if (count of matches) is 1 then return "Notes folder already exists; no duplicate created."
            set created to make new folder at default account with properties {name:\(q(c.name))}
            if name of created is not \(q(c.name)) then error "not-confirmed"
            return "Notes folder created and name verified."
            """
        case .noteFind:body+="set matches to notes of default account whose name contains \(q(c.name))\nif (count of matches)>50 then error \"too-many-notes\"\nset names to name of matches\nset text item delimiters to \"; \"\nreturn names as text"
        case .noteOpen:body+="\nshow n\nreturn \"Notes accepted the exact note ID for display.\""
        case .noteRename:body+="\nset name of n to \(q(c.value))\nif name of n is not \(q(c.value)) then error \"rename-unconfirmed\"\nreturn \"Note title change read back.\""
        case .noteMove:body+="""
            set foldersFound to folders of default account whose name is \(q(c.value))
            if (count of foldersFound) is not 1 then error "ambiguous-folder"
            set destinationFolder to item 1 of foldersFound
            if shared of destinationFolder then error "shared-folder"
            set wantedID to id of destinationFolder
            move n to destinationFolder
            if (id of container of \(target)) is not wantedID then error "move-unconfirmed"
            return "Note destination folder identity verified."
            """
        case .noteAppend:
            let html=c.value.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\n",with:"<br>")
            body+="""
            if (count of attachments of n)>0 then error "attachments-not-supported"
            set originalBody to body of n
            set originalText to plaintext of n
            if (length of originalBody)>262144 then error "note-too-large"
            if ((modification date of n) as text) is not \(q(c.version ?? "")) then error "note-changed-before-append"
            if body of n is not originalBody then error "note-body-changed"
            set body of n to originalBody & \(q("<div>"+html+"</div>"))
            if (plaintext of n) does not start with originalText then error "original-not-preserved"
            if (plaintext of n) does not contain \(q(c.value)) then error "append-unconfirmed"
            return "Literal note append and original text read back; attachment notes are excluded."
            """
        case .noteDuplicate:body+="""
            if (count of attachments of n)>0 then error "attachments-not-supported"
            set originalBody to body of n
            if (length of originalBody)>262144 then error "note-too-large"
            set created to make new note at container of n with properties {body:originalBody}
            if plaintext of created is not plaintext of n then error "copy-unconfirmed"
            return "Attachment-free note duplicated; plain text read back."
            """
        case .noteTrash:
            body+="""
            if upgraded of default account is not true then error "legacy-account-not-supported"
            if (id of container of n) is not (id of default folder of default account) then error "not-default-folder"
            set wantedID to id of n
            delete n
            set remaining to notes of default account whose id is wantedID
            if (count of remaining) is not 1 then return "recovery-unverified"
            set destinationName to name of container of item 1 of remaining
            if destinationName is not "Recently Deleted" then return "recovery-unverified"
            return "Native Notes moved the reviewed note to Recently Deleted; recovery folder name read back."
            """
        case .notePDF:
            body+="\nif (count of attachments of n)>0 then error \"attachments-not-supported\"\nreturn plaintext of n"
            let text=try execute(body);guard let data=pdf(text) else {throw PersonalAgentError.unsupported}
            _=try PersonalFolderCommand(name:c.name+".pdf",location:.documents)
            let url=try writePDF(data,c.name+".pdf")
            return .init(identifier:url.path,evidence:"Attachment-free note exported as plain-text PDF in Documents; saved bytes verified. Formatting is not preserved.")
        default:throw PersonalAgentError.unsupported
        }
        let result=try execute(body)
        return .init(identifier:c.targetID ?? step.id.uuidString,evidence:result=="recovery-unverified" ? "Native Notes deletion returned, but Recently Deleted recovery location could not be verified. Inspect Notes before retrying; no permanent deletion was requested.":result.isEmpty ? "No matching Notes metadata.":result,verified:result != "recovery-unverified")
    }
}
