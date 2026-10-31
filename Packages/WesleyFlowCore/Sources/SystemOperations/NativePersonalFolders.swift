import AppKit
import Darwin
import Domain

@MainActor public enum NativePersonalFolders {
    private final class Root {
        let fd:Int32
        let url:URL
        let identity:String
        init(_ url:URL) throws {
            self.url=url
            fd=Darwin.open(url.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
            guard fd>=0 else {throw PersonalAgentError.permissionDenied}
            var value=stat();guard fstat(fd,&value)==0 else {Darwin.close(fd);throw PersonalAgentError.verificationFailed}
            identity="\(value.st_dev):\(value.st_ino):\(value.st_birthtimespec.tv_sec):\(value.st_birthtimespec.tv_nsec)"
        }
        deinit {Darwin.close(fd)}
    }
    public static func rootURL(_ location:PersonalFolderLocation)->URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(location.rawValue.capitalized,isDirectory:true)
    }
    private static func node(_ root:Root,_ name:String) throws ->String {
        guard !name.isEmpty else {return root.identity}
        var value=stat()
        guard fstatat(root.fd,name,&value,AT_SYMLINK_NOFOLLOW)==0,(value.st_mode & mode_t(S_IFMT))==mode_t(S_IFDIR) else {throw PersonalAgentError.unsupported}
        return "\(value.st_dev):\(value.st_ino):\(value.st_birthtimespec.tv_sec):\(value.st_birthtimespec.tv_nsec)"
    }
    static func bind(_ command:PersonalFolderCommand,rootURL:URL) throws ->PersonalFolderCommand {
        let root=try Root(rootURL),identity=try node(root,command.name)
        if let prior=command.identity {guard prior==identity,command.rootIdentity==root.identity else {throw PersonalAgentError.verificationFailed};return command}
        return try .init(name:command.name,location:command.location,identity:identity,rootIdentity:root.identity)
    }
    static func validateTrash(_ command:PersonalFolderCommand,rootURL:URL) throws {
        guard !command.name.isEmpty,command.identity != nil,command.rootIdentity != nil else {throw PersonalAgentError.approvalRequired}
        let root=try Root(rootURL)
        guard command.rootIdentity==root.identity,try node(root,command.name)==command.identity else {throw PersonalAgentError.verificationFailed}
    }
    // Called only after native recycle returned a successful source-to-Trash mapping.
    static func verifyTrashCompletion(_ command:PersonalFolderCommand,rootURL:URL,moved:URL) throws ->Bool {
        let root=try Root(rootURL)
        guard !command.name.isEmpty,let expected=command.identity,command.rootIdentity==root.identity else {throw PersonalAgentError.verificationFailed}
        var original=stat()
        guard fstatat(root.fd,command.name,&original,AT_SYMLINK_NOFOLLOW)==(-1),errno==ENOENT else {throw PersonalAgentError.verificationFailed}
        var result=stat()
        if lstat(moved.path,&result)==0 {
            guard "\(result.st_dev):\(result.st_ino):\(result.st_birthtimespec.tv_sec):\(result.st_birthtimespec.tv_nsec)"==expected else {throw PersonalAgentError.verificationFailed}
            return true
        }
        // Native recycle completion is authoritative; do not request wider Trash permissions.
        guard errno==EACCES || errno==EPERM else {throw PersonalAgentError.verificationFailed}
        return false
    }
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .trashFolder {
            let data=try PersonalFolderCommand.decode(steps[i].text)
            guard !data.name.isEmpty else {throw PersonalAgentError.invalidCommand}
            let bound=try bind(data,rootURL:rootURL(data.location))
            steps[i] = .init(id:steps[i].id,tool:.trashFolder,text:try bound.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    static func create(_ command:PersonalFolderCommand,rootURL:URL) throws ->PersonalReceipt {
        guard !command.name.isEmpty else {throw PersonalAgentError.invalidCommand}
        let root=try Root(rootURL)
        let result=mkdirat(root.fd,command.name,0o755)
        guard result==0 || errno==EEXIST else {throw PersonalAgentError.permissionDenied}
        _=try node(root,command.name)
        return .init(identifier:rootURL.appendingPathComponent(command.name).path,evidence:result==0 ? "Folder created and directory identity verified":"Folder already exists; no contents changed")
    }
    private static func literal(_ text:String)->String {"\""+text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\""}
    static func finderCloseSource(_ url:URL)->String {
        let target=url.path.hasSuffix("/") ? url.path:url.path+"/"
        let source="""
        with timeout of 5 seconds
          tell application id "com.apple.finder"
            set wantedFolder to (POSIX file \(literal(target))) as alias
            set matches to {}
            if (count of Finder windows) > 100 then error "too-many-windows"
            repeat with w in Finder windows
              try
                considering case
                  if (target of w as alias) is wantedFolder then set end of matches to (id of w)
                end considering
              end try
            end repeat
            if (count of matches) is 0 then return "already-closed"
            if (count of matches) is not 1 then return "ambiguous"
            set selectedID to item 1 of matches
            set selectedWindow to Finder window id selectedID
            considering case
              if (target of selectedWindow as alias) is not wantedFolder then return "target-changed"
            end considering
            close selectedWindow
            if exists (Finder window id selectedID) then return "not-confirmed"
            return "closed"
          end tell
        end timeout
        """
        return source
    }
    private static func closeFinderWindow(_ url:URL) throws ->PersonalReceipt {
        let source=finderCloseSource(url)
        var error:NSDictionary?
        let result=NSAppleScript(source:source)?.executeAndReturnError(&error).stringValue
        if (error?[NSAppleScript.errorNumber] as? Int)==(-1743) {throw PersonalAgentError.permissionDenied}
        guard error==nil,["closed","already-closed"].contains(result ?? "") else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:url.path,evidence:result=="closed" ? "One matching Finder folder window closed; other windows untouched":"No Finder window for this exact folder was open")
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        try Task.checkCancellation()
        let command=try PersonalFolderCommand.decode(step.text),url=rootURL(command.location)
        if step.tool == .createFolder {return try create(command,rootURL:url)}
        let root=try Root(url)
        if step.tool == .findFolder {
            guard !command.name.isEmpty else {throw PersonalAgentError.invalidCommand}
            var queue=[(url,0)],index=0,visited=0,skipped=0,found:[URL]=[]
            while index<queue.count,visited<2048,found.count<10 {
                try Task.checkCancellation();let (folder,depth)=queue[index];index+=1
                let children:[URL]
                do {children=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey,.isPackageKey],options:[.skipsHiddenFiles])}
                catch {skipped+=1;continue}
                for child in children {
                    visited+=1;guard visited<=2048 else {break}
                    guard let v=try? child.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.isPackageKey]),v.isDirectory==true,v.isSymbolicLink != true,v.isPackage != true else {continue}
                    if child.lastPathComponent.range(of:command.name,options:[.caseInsensitive,.diacriticInsensitive]) != nil {found.append(child);if found.count==10 {break}}
                    if depth<3 {queue.append((child,depth+1))}
                }
            }
            return .init(identifier:step.id.uuidString,evidence:found.isEmpty ? "No matching folder found in bounded \(command.location.rawValue) scan (\(visited) entries; depth 4; \(skipped) unreadable folders skipped)":"Matching folders (bounded scan; \(skipped) unreadable folders skipped): "+found.map(\.path).joined(separator:"; "))
        }
        let identity=try node(root,command.name),target=command.name.isEmpty ? url:url.appendingPathComponent(command.name,isDirectory:true)
        guard (try? target.resourceValues(forKeys:[.isPackageKey]))?.isPackage != true else {throw PersonalAgentError.unsupported}
        switch step.tool {
        case .openFolder:
            guard NSWorkspace.shared.open(target) else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:target.path,evidence:"Existing directory verified and folder-open handoff accepted; Finder contents not read")
        case .closeFolder:return try closeFinderWindow(target)
        case .trashFolder:
            try validateTrash(command,rootURL:url)
            // Exact reviewed directory identity must still match immediately before native recycling.
            guard try node(root,command.name)==identity else {throw PersonalAgentError.verificationFailed}
            let moved:URL = try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.recycle([target]) { newURLs,error in
                    if let error {continuation.resume(throwing:error)}
                    else if let newURL=newURLs[target] ?? newURLs.first(where:{$0.key.standardizedFileURL.path==target.standardizedFileURL.path})?.value {continuation.resume(returning:newURL)}
                    else {continuation.resume(throwing:PersonalAgentError.verificationFailed)}
                }
            }
            let readback=try verifyTrashCompletion(command,rootURL:url,moved:moved)
            return .init(identifier:moved.path,evidence:readback ? "Reviewed folder moved to Trash; source absent and destination identity verified; no permanent deletion":"macOS confirmed the reviewed folder moved to Trash and source is absent; Trash destination readback denied; no permanent deletion")
        default:throw PersonalAgentError.unsupported
        }
    }
    public static func searchBrowser(_ text:String) async throws ->PersonalReceipt {
        let request=try PersonalBrowserQuery.decode(text),url=try NativePersonalApps.searchURL(request.query,youtube:false),browser=try NativePersonalApps.target(request.browser.bundleID)
        let configuration=NSWorkspace.OpenConfiguration();configuration.activates=true
        let app=try await NSWorkspace.shared.open([url],withApplicationAt:browser,configuration:configuration)
        guard !app.isTerminated else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:url.absoluteString,evidence:"Search URL handoff accepted by requested \(request.browser.rawValue) browser; results not read")
    }
}
