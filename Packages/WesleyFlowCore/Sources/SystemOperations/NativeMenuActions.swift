import AppKit
import ApplicationServices
import Domain
@MainActor public enum NativeMenuActions {
    private static func read(_ element:AXUIElement,_ name:String)->CFTypeRef? {var value:CFTypeRef?;return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value:nil}
    private static func children(_ element:AXUIElement)->[AXUIElement] {read(element,kAXChildrenAttribute) as? [AXUIElement] ?? []}
    private static func element(_ parent:AXUIElement,_ name:String)->AXUIElement? {guard let value=read(parent,name),CFGetTypeID(value)==AXUIElementGetTypeID() else {return nil};return unsafeDowncast(value,to:AXUIElement.self)}
    static func matchesCommand(_ action:PersonalMenuAction.Action,character:String,modifiers:Int,title:String,path:[String])->Bool {
        let c=character.lowercased(),semantic=title.lowercased().filter(\.isLetter)
        switch action {
        case .lock:return c=="q" && modifiers==2 && semantic=="lockscreen"
        case .reopenTab:return c=="t" && modifiers==1 && ["reopenlastclosedtab","reopentab"].contains(semantic)
        case .bookmark:return c=="d" && modifiers==0 && ["addbookmark","addbookmarkforthispage"].contains(semantic)
        case .zoomIn:return ["+","="].contains(c) && [0,1].contains(modifiers) && semantic=="zoomin"
        case .zoomOut:return c=="-" && modifiers==0 && semantic=="zoomout"
        case .zoomReset:return c=="0" && modifiers==0 && ["actualsize","resetzoom"].contains(semantic)
        default:return false
        }
    }
    static func bookmarkURL(_ text:String)->URL? {
        guard let url=URL(string:text),url.scheme=="https",let host=url.host,!host.isEmpty,url.user==nil,url.password==nil else {return nil};return url
    }
    private static func candidates(_ root:AXUIElement,_ c:PersonalMenuAction)->[AXUIElement] {
        let deadline=Date().addingTimeInterval(3)
        var queue:[(AXUIElement,Int,[String])]=[(root,0,[])],index=0,result:[AXUIElement]=[]
        while index<queue.count,index<2000 {
            guard Date()<deadline else {return []}
            let (node,depth,path)=queue[index];index+=1
            let role=read(node,kAXRoleAttribute) as? String ?? "",title=read(node,kAXTitleAttribute) as? String ?? "",next=path+[title]
            let items=children(node)
            if role==kAXMenuItemRole,read(node,kAXEnabledAttribute) as? Bool == true {
                let char=read(node,kAXMenuItemCmdCharAttribute) as? String ?? "",mods=(read(node,kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? -1
                var match=matchesCommand(c.action,character:char,modifiers:mods,title:title,path:path)
                if c.action == .openBookmark {match=title.caseInsensitiveCompare(c.query) == .orderedSame && items.isEmpty && path.contains(where:["Bookmarks","Bookmarks and Lists"].contains)}
                if c.action == .podcastSpeed {match=["1.5×","1.5x","1½×","1 1/2x"].contains(title) && path.contains(where:{$0.localizedCaseInsensitiveContains("speed")})}
                if match {result.append(node)}
            }
            if depth<6 {queue += items.map{($0,depth+1,next)}}
        }
        return index>=2000 ? []:result
    }
    private static func menuItems(_ menu:NSMenu)->[NSMenuItem] {menu.items.flatMap{[$0]+($0.submenu.map{menuItems($0)} ?? [])}}
    @MainActor private final class Flag {var inactive=false}
    private static func lock() async throws ->PersonalReceipt {
        let matches=(NSApp.mainMenu.map{menuItems($0)} ?? []).filter{$0.keyEquivalent.lowercased()=="q" && $0.keyEquivalentModifierMask.intersection([.command,.control,.option,.shift])==[.command,.control] && $0.isEnabled && !$0.isHidden}
        let invoke:()->Bool
        if matches.count==1,let item=matches.first,let action=item.action {invoke={NSApp.sendAction(action,to:item.target,from:item)}}
        else {
            // macOS may inject Apple-menu items outside the app-owned NSMenu model.
            // Read only Wesley Flow's own menu bar, never another app's content.
            guard matches.isEmpty,AXIsProcessTrusted() else {throw PersonalAgentError.unsupported}
            NSApp.activate(ignoringOtherApps:true)
            let root=AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier);AXUIElementSetMessagingTimeout(root,0.2)
            guard let menu=element(root,kAXMenuBarAttribute) else {throw PersonalAgentError.unsupported}
            let candidates=candidates(menu,try .init(action:.lock,appID:"self"))
            guard candidates.count==1,let selected=candidates.first else {throw PersonalAgentError.unsupported}
            invoke={AXUIElementPerformAction(selected,kAXPressAction as CFString) == .success}
        }
        let observed=Flag(),center=NSWorkspace.shared.notificationCenter
        let token=center.addObserver(forName:NSWorkspace.sessionDidResignActiveNotification,object:nil,queue:.main) {_ in Task {@MainActor in observed.inactive=true}}
        defer {center.removeObserver(token)}
        guard invoke() else {throw PersonalAgentError.verificationFailed}
        for _ in 0..<30 {if observed.inactive {return .init(identifier:UUID().uuidString,evidence:"Native Lock Screen menu accepted; session became inactive. No synthetic key or privileged process used.")};try await Task.sleep(for:.milliseconds(100))}
        throw PersonalAgentError.verificationFailed
    }
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .menuAction {
            var c=try PersonalMenuAction.decode(steps[i].text)
            if c.action != .lock {
                _=try NativePersonalApps.target(c.appID)
                let running=NSRunningApplication.runningApplications(withBundleIdentifier:c.appID).filter{!$0.isTerminated}
                guard running.count==1,let app=running.first else {throw PersonalAgentError.unsupported};c.processID=app.processIdentifier
            }
            steps[i] = .init(id:steps[i].id,tool:.menuAction,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let c=try PersonalMenuAction.decode(step.text)
        if c.action == .lock {return try await lock()}
        guard AXIsProcessTrusted() else {throw PersonalAgentError.permissionDenied}
        guard let pid=c.processID,let app=NSRunningApplication(processIdentifier:pid),app.bundleIdentifier==c.appID,!app.isTerminated else {throw PersonalAgentError.verificationFailed}
        app.activate(options:[])
        let root=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(root,0.2)
        guard let menu=element(root,kAXMenuBarAttribute) else {throw PersonalAgentError.unsupported}
        let items=candidates(menu,c)
        guard items.count==1,let selected=items.first else {throw PersonalAgentError.unsupported}
        if c.action == .openBookmark {
            let metadata=read(selected,kAXURLAttribute)
            let address=(metadata as? URL)?.absoluteString ?? (metadata as? String)
            guard let address,let url=bookmarkURL(address) else {throw PersonalAgentError.unsupported}
            // Open the exact native HTTPS metadata instead of pressing a potentially changed bookmarklet.
            let target=try NativePersonalApps.target(c.appID),configuration=NSWorkspace.OpenConfiguration();configuration.activates=true
            let opened=try await NSWorkspace.shared.open([url],withApplicationAt:target,configuration:configuration)
            guard opened.bundleIdentifier==c.appID,!opened.isTerminated else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:url.absoluteString,evidence:"Unique bookmark HTTPS metadata handed to Brave. Website loading and final page are unverified; no bookmarklet or page script was invoked.",verified:false)
        }
        guard AXUIElementPerformAction(selected,kAXPressAction as CFString) == .success else {throw PersonalAgentError.unsupported}
        if c.action == .podcastSpeed {
            for _ in 0..<10 {if let mark=read(selected,kAXMenuItemMarkCharAttribute) as? String,!mark.isEmpty {return .init(identifier:c.appID,evidence:"Native 1.5× playback-speed menu item is checked; audio rate itself not measured.")};try await Task.sleep(for:.milliseconds(100))};throw PersonalAgentError.verificationFailed
        }
        let detail=c.action == .bookmark ? "Safari Add Bookmark was requested through its exact native menu command. Choose the folder and confirm in Safari; no bookmark creation claimed.":"The unique native menu command was accepted. Final browser state/zoom/page is unverified; inspect the app before any retry."
        return .init(identifier:c.appID,evidence:detail,verified:false)
    }
}
