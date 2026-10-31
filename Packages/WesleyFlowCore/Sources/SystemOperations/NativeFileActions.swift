import AppKit
import Darwin
import CryptoKit
import AppleArchive
import System
import Domain
@MainActor public enum NativeFileActions {
    private final class Root {
        let fd:Int32
        let url:URL
        let identity:String
        init(_ url:URL) throws {self.url=url;fd=Darwin.open(url.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard fd>=0 else {throw PersonalAgentError.permissionDenied};var st=stat();guard fstat(fd,&st)==0 else {Darwin.close(fd);throw PersonalAgentError.verificationFailed};identity=NativeFileActions.identity(st)}
        init(parent:Root,name:String) throws {
            url=parent.url.appendingPathComponent(name)
            fd=openat(parent.fd,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
            guard fd>=0 else {throw PersonalAgentError.permissionDenied}
            var st=stat();guard fstat(fd,&st)==0 else {Darwin.close(fd);throw PersonalAgentError.verificationFailed}
            identity=NativeFileActions.identity(st)
        }
        deinit {Darwin.close(fd)}
    }
    nonisolated private static func identity(_ st:stat)->String {"\(st.st_dev):\(st.st_ino):\(st.st_birthtimespec.tv_sec):\(st.st_birthtimespec.tv_nsec)"}
    private static func node(_ root:Root,_ name:String,folder:Bool,allowHidden:Bool=false) throws ->stat {
        var st=stat();guard fstatat(root.fd,name,&st,AT_SYMLINK_NOFOLLOW)==0 else {throw PersonalAgentError.unsupported}
        let kind=st.st_mode & mode_t(S_IFMT)
        guard kind==mode_t(folder ? S_IFDIR:S_IFREG),(allowHidden || !name.hasPrefix(".")),!(["app","bundle","framework","photoslibrary","pages","numbers","key"].contains(URL(fileURLWithPath:name).pathExtension.lowercased()) && folder) else {throw PersonalAgentError.unsupported};return st
    }
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .fileAction {
            var c=try PersonalFileAction.decode(steps[i].text);guard let location=c.location else {throw PersonalAgentError.invalidCommand}
            if c.action == .restore {
                guard let path=c.trashPath else {throw PersonalAgentError.approvalRequired}
                let trash=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
                guard URL(fileURLWithPath:path).standardizedFileURL.deletingLastPathComponent().path==trash.standardizedFileURL.path,URL(fileURLWithPath:path).lastPathComponent==c.name else {throw PersonalAgentError.unsupported}
                c=try bindRestore(c,trashRoot:trash,destinationRoot:NativePersonalFolders.rootURL(c.destinationLocation ?? location))
                steps[i] = .init(id:steps[i].id,tool:.fileAction,text:try c.encoded());continue
            }
            let root=try Root(NativePersonalFolders.rootURL(location));let st=try node(root,c.name,folder:c.folder)
            c.sourceIdentity=identity(st);c.rootIdentity=root.identity
            if [.rename,.move,.copy,.compress].contains(c.action) {let to=try Root(NativePersonalFolders.rootURL(c.destinationLocation ?? location));c.destinationRootIdentity=to.identity;try absent(to,c.destinationName)}
            steps[i] = .init(id:steps[i].id,tool:.fileAction,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    private static func absent(_ root:Root,_ name:String) throws {guard !name.isEmpty else {throw PersonalAgentError.invalidCommand};var st=stat();guard fstatat(root.fd,name,&st,AT_SYMLINK_NOFOLLOW)==(-1),errno==ENOENT else {throw PersonalAgentError.unsupported}}
    private struct Budget {var entries=0;var bytes=0}
    private static func copy(_ from:Root,_ source:String,_ to:Root,_ destination:String,folder:Bool,budget:inout Budget,depth:Int=0) async throws {
        try Task.checkCancellation();await Task.yield();budget.entries+=1;guard budget.entries<=1000,depth<=8 else {throw PersonalAgentError.unsupported}
        let original=try node(from,source,folder:folder,allowHidden:depth>0)
        if folder {
            guard mkdirat(to.fd,destination,0o700)==0 else {throw PersonalAgentError.unsupported}
            let src=try Root(parent:from,name:source),dst=try Root(parent:to,name:destination)
            let duplicate=Darwin.dup(src.fd);guard duplicate>=0,let directory=fdopendir(duplicate) else {if duplicate>=0 {Darwin.close(duplicate)};throw PersonalAgentError.permissionDenied};defer {closedir(directory)}
            while let entry=readdir(directory) {
                let name=withUnsafePointer(to:&entry.pointee.d_name) {ptr in ptr.withMemoryRebound(to:CChar.self,capacity:MemoryLayout.size(ofValue:entry.pointee.d_name)) {String(cString:$0)}}
                if [".",".."].contains(name) {continue}
                var st=stat();guard fstatat(src.fd,name,&st,AT_SYMLINK_NOFOLLOW)==0 else {throw PersonalAgentError.verificationFailed}
                try await copy(src,name,dst,name,folder:(st.st_mode & mode_t(S_IFMT))==mode_t(S_IFDIR),budget:&budget,depth:depth+1)
            }
        } else {
            guard original.st_size>=0,original.st_size<=16*1024*1024,budget.bytes+Int(original.st_size)<=64*1024*1024 else {throw PersonalAgentError.unsupported}
            let input=openat(from.fd,source,O_RDONLY|O_NOFOLLOW);guard input>=0 else {throw PersonalAgentError.permissionDenied};defer {Darwin.close(input)}
            var opened=stat();guard fstat(input,&opened)==0,identity(opened)==identity(original) else {throw PersonalAgentError.verificationFailed}
            let output=openat(to.fd,destination,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600);guard output>=0 else {throw PersonalAgentError.unsupported};defer {Darwin.close(output)}
            var buffer=[UInt8](repeating:0,count:16384),copied=0,hasher=SHA256()
            while true {
                try Task.checkCancellation();await Task.yield();let count=Darwin.read(input,&buffer,buffer.count)
                if count==0 {break};if count<0 && errno==EINTR {continue};guard count>0 else {throw PersonalAgentError.verificationFailed}
                copied+=count;budget.bytes+=count;guard copied<=16*1024*1024,budget.bytes<=64*1024*1024 else {throw PersonalAgentError.unsupported}
                hasher.update(data:Data(buffer.prefix(count)))
                var offset=0
                while offset<count {let n=buffer.withUnsafeBytes{Darwin.write(output,$0.baseAddress!.advanced(by:offset),count-offset)};if n<0 && errno==EINTR {continue};guard n>0 else {throw PersonalAgentError.verificationFailed};offset+=n}
            }
            var final=stat();guard fstat(input,&final)==0,identity(final)==identity(original),final.st_size==original.st_size,final.st_mtimespec.tv_sec==original.st_mtimespec.tv_sec,final.st_mtimespec.tv_nsec==original.st_mtimespec.tv_nsec,fsync(output)==0 else {throw PersonalAgentError.verificationFailed}
            let verify=openat(to.fd,destination,O_RDONLY|O_NOFOLLOW);guard verify>=0 else {throw PersonalAgentError.verificationFailed}
            let reader=FileHandle(fileDescriptor:verify,closeOnDealloc:true);defer {try? reader.close()}
            var written=stat(),readback=stat();guard fstat(output,&written)==0,fstat(verify,&readback)==0,identity(written)==identity(readback) else {throw PersonalAgentError.verificationFailed}
            var observed=SHA256(),observedBytes=0
            while let chunk=try reader.read(upToCount:16384),!chunk.isEmpty {try Task.checkCancellation();await Task.yield();observedBytes+=chunk.count;guard observedBytes<=copied else {throw PersonalAgentError.verificationFailed};observed.update(data:chunk)}
            guard observedBytes==copied,observed.finalize()==hasher.finalize() else {throw PersonalAgentError.verificationFailed}
        }
        let finalSource=try node(from,source,folder:folder,allowHidden:depth>0)
        guard identity(finalSource)==identity(original),finalSource.st_mtimespec.tv_sec==original.st_mtimespec.tv_sec,finalSource.st_mtimespec.tv_nsec==original.st_mtimespec.tv_nsec else {throw PersonalAgentError.verificationFailed}
    }
    static func writeExclusive(_ data:Data,name:String,rootURL:URL,subfolder:String?=nil) throws ->URL {
        guard data.count<=128*1024*1024 else {throw PersonalAgentError.unsupported}
        _=try PersonalFolderCommand(name:name,location:.documents)
        let parent=try Root(rootURL),root:Root
        if let subfolder {
            _=try PersonalFolderCommand(name:subfolder,location:.documents)
            guard mkdirat(parent.fd,subfolder,0o700)==0 || errno==EEXIST else {throw PersonalAgentError.permissionDenied}
            _=try node(parent,subfolder,folder:true)
            root=try Root(parent:parent,name:subfolder)
        } else {root=parent}
        let fd=openat(root.fd,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
        guard fd>=0 else {throw PersonalAgentError.unsupported}
        let writer=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer {try? writer.close()}
        try writer.write(contentsOf:data);guard fsync(fd)==0 else {throw PersonalAgentError.verificationFailed}
        var original=stat();guard fstat(fd,&original)==0 else {throw PersonalAgentError.verificationFailed}
        let check=openat(root.fd,name,O_RDONLY|O_NOFOLLOW);guard check>=0 else {throw PersonalAgentError.verificationFailed}
        let reader=FileHandle(fileDescriptor:check,closeOnDealloc:true);defer {try? reader.close()}
        var observed=stat();guard fstat(check,&observed)==0,identity(original)==identity(observed),try reader.read(upToCount:data.count+1)==data else {throw PersonalAgentError.verificationFailed}
        return (subfolder.map{rootURL.appendingPathComponent($0)} ?? rootURL).appendingPathComponent(name)
    }
    static func fixtureOperation(_ c:PersonalFileAction,sourceRoot:URL,destinationRoot:URL) async throws ->PersonalReceipt {try await execute(c,sourceRoot:sourceRoot,destinationRoot:destinationRoot,requireBinding:false)}
    private static func execute(_ c:PersonalFileAction,sourceRoot:URL,destinationRoot:URL,requireBinding:Bool=true) async throws ->PersonalReceipt {
        let from=try Root(sourceRoot),st=try node(from,c.name,folder:c.folder)
        if requireBinding {guard c.rootIdentity==from.identity,c.sourceIdentity==identity(st) else {throw PersonalAgentError.verificationFailed}}
        let target=sourceRoot.appendingPathComponent(c.name),to=try Root(destinationRoot)
        if [.rename,.move,.copy,.compress].contains(c.action) {if requireBinding {guard c.destinationRootIdentity==to.identity else {throw PersonalAgentError.verificationFailed}};try absent(to,c.destinationName)}
        switch c.action {
        case .rename,.move:
            guard renameatx_np(from.fd,c.name,to.fd,c.destinationName,UInt32(RENAME_EXCL))==0 else {throw PersonalAgentError.verificationFailed}
            guard identity(try node(to,c.destinationName,folder:c.folder))==identity(st) else {throw PersonalAgentError.verificationFailed};try absent(from,c.name)
            return .init(identifier:destinationRoot.appendingPathComponent(c.destinationName).path,evidence:"Reviewed item moved/renamed with exclusive destination; directory entry identities verified.")
        case .copy:
            var budget=Budget();try await copy(from,c.name,to,c.destinationName,folder:c.folder,budget:&budget)
            return .init(identifier:destinationRoot.appendingPathComponent(c.destinationName).path,evidence:"Reviewed item copied without overwriting: \(budget.entries) entries, \(budget.bytes) bytes. File digests verified. Packages/symlinks refused; hidden children copied within the selected folder; failure may leave an incomplete copy for review.")
        case .info:return .init(identifier:target.path,evidence:"Metadata: "+target.path+" · \(st.st_size) bytes · modified "+Date(timeIntervalSince1970:Double(st.st_mtimespec.tv_sec)).formatted()+". Folder size is its directory entry, not recursive content size.")
        case .reveal:
            let q=NativeAgentScript.literal(target.path)
            _=try NativeAgentScript.execute("with timeout of 5 seconds\ntell application id \"com.apple.finder\"\nset wanted to (POSIX file \(q)) as alias\nreveal wanted\nactivate\nif (count of selection) is not 1 then error \"selection-unconfirmed\"\nif (item 1 of selection as alias) is not wanted then error \"selection-changed\"\nreturn \"verified\"\nend tell\nend timeout")
            return .init(identifier:target.path,evidence:"Exact reviewed file alias selected in Finder; selection read back.")
        case .compress:
            let scratch=FileManager.default.temporaryDirectory.appendingPathComponent("WesleyFlowArchive-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer {try? FileManager.default.removeItem(at:scratch)}
            let staging=try Root(scratch);var budget=Budget();try await copy(from,c.name,staging,"Contents",folder:true,budget:&budget)
            let fd=openat(to.fd,c.destinationName,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600);guard fd>=0 else {throw PersonalAgentError.unsupported}
            guard let stream=ArchiveByteStream.fileStream(fd:FileDescriptor(rawValue:fd)) else {Darwin.close(fd);throw PersonalAgentError.unsupported}
            guard let compression=ArchiveByteStream.compressionStream(using:.lzfse,writingTo:stream,threadCount:1) else {try? stream.close();throw PersonalAgentError.unsupported}
            guard let encoder=ArchiveStream.encodeStream(writingTo:compression,threadCount:1),let keys=ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD") else {try? compression.close();try? stream.close();throw PersonalAgentError.unsupported}
            do {try encoder.writeDirectoryContents(archiveFrom:FilePath(scratch.appendingPathComponent("Contents").path),keySet:keys,threadCount:1);try encoder.close();try compression.close();try stream.close()}
            catch {try? encoder.close();try? compression.close();try? stream.close();throw error}
            let archive=try node(to,c.destinationName,folder:false);guard archive.st_size>0 else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:destinationRoot.appendingPathComponent(c.destinationName).path,evidence:"Reviewed folder saved as LZFSE Apple Archive (.aar), \(archive.st_size) bytes, from a bounded verified copy. Archive creation verified; full extraction requires acceptance.")
        case .restore:throw PersonalAgentError.unsupported
        }
    }
    static func bindRestore(_ request:PersonalFileAction,trashRoot:URL,destinationRoot:URL,requireExpected:Bool=true) throws ->PersonalFileAction {
        var c=request;guard c.action == .restore,c.folder,!c.destinationName.isEmpty else {throw PersonalAgentError.invalidCommand}
        let from=try Root(trashRoot),to=try Root(destinationRoot),st=try node(from,c.name,folder:true)
        if requireExpected {guard c.sourceIdentity==identity(st),c.destinationRootIdentity==to.identity else {throw PersonalAgentError.verificationFailed}}
        try absent(to,c.destinationName)
        c.sourceIdentity=identity(st);c.rootIdentity=from.identity;c.destinationRootIdentity=to.identity;return c
    }
    static func restore(_ c:PersonalFileAction,trashRoot:URL,destinationRoot:URL) throws ->PersonalReceipt {
        let from=try Root(trashRoot),to=try Root(destinationRoot),st=try node(from,c.name,folder:true)
        guard c.action == .restore,c.folder,c.rootIdentity==from.identity,c.destinationRootIdentity==to.identity,c.sourceIdentity==identity(st) else {throw PersonalAgentError.verificationFailed}
        try absent(to,c.destinationName)
        guard renameatx_np(from.fd,c.name,to.fd,c.destinationName,UInt32(RENAME_EXCL))==0,identity(try node(to,c.destinationName,folder:true))==identity(st) else {throw PersonalAgentError.verificationFailed}
        try absent(from,c.name)
        return .init(identifier:destinationRoot.appendingPathComponent(c.destinationName).path,evidence:"Exact reviewed folder restored from Trash; original identity and exclusive destination verified.")
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let c=try PersonalFileAction.decode(step.text);guard let location=c.location else {throw PersonalAgentError.invalidCommand}
        if c.action == .restore {
            let trash=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            guard let path=c.trashPath,URL(fileURLWithPath:path).standardizedFileURL.deletingLastPathComponent().path==trash.standardizedFileURL.path,URL(fileURLWithPath:path).lastPathComponent==c.name else {throw PersonalAgentError.unsupported}
            return try restore(c,trashRoot:trash,destinationRoot:NativePersonalFolders.rootURL(c.destinationLocation ?? location))
        }
        return try await execute(c,sourceRoot:NativePersonalFolders.rootURL(location),destinationRoot:NativePersonalFolders.rootURL(c.destinationLocation ?? location))
    }
}
