import AppKit
import ScreenCaptureKit
import Domain
@MainActor public enum NativeScreenCapture {
    private final class SelectionPanel:NSPanel {override var canBecomeKey:Bool {true}}
    private final class SelectionView:NSView {
        override var isFlipped:Bool {true}
        var start:CGPoint?
        var selection:CGRect?
        var completion:((CGRect?)->Void)?
        override var acceptsFirstResponder:Bool {true}
        override func draw(_ rect:NSRect) {
            NSColor.black.withAlphaComponent(0.25).setFill();bounds.fill()
            if let selection {NSColor.white.setStroke();let path=NSBezierPath(rect:selection);path.lineWidth=2;path.stroke()}
        }
        override func mouseDown(with event:NSEvent) {start=convert(event.locationInWindow,from:nil)}
        override func mouseDragged(with event:NSEvent) {guard let start else {return};let end=convert(event.locationInWindow,from:nil);selection=CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(end.x-start.x),height:abs(end.y-start.y)).intersection(bounds);needsDisplay=true}
        override func mouseUp(with event:NSEvent) {mouseDragged(with:event);finish(selection.flatMap{$0.width>=4 && $0.height>=4 ? $0:nil})}
        override func keyDown(with event:NSEvent) {if event.keyCode==53 {finish(nil)} else {super.keyDown(with:event)}}
        func finish(_ rect:CGRect?) {let done=completion;completion=nil;done?(rect)}
    }
    private static var selectionView:SelectionView?
    private static func pick(_ screen:NSScreen) async throws ->CGRect {
        try await withTaskCancellationHandler(operation:{
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation {continuation in
                let panel=SelectionPanel(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
                panel.isReleasedWhenClosed=false;panel.level = .screenSaver;panel.backgroundColor = .clear;panel.isOpaque=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
                let view=SelectionView(frame:CGRect(origin:.zero,size:screen.frame.size));selectionView=view;panel.contentView=view
                view.completion={rect in panel.orderOut(nil);panel.close();selectionView=nil;if let rect {continuation.resume(returning:rect)} else {continuation.resume(throwing:CancellationError())}}
                panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(view)
            }
        },onCancel:{Task {@MainActor in selectionView?.finish(nil)}})
    }
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .screenCapture {
            var c=try PersonalScreenCapture.decode(steps[i].text)
            guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main,let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {throw PersonalAgentError.unsupported}
            c.displayID=number.uint32Value
            c.originPID=NSWorkspace.shared.frontmostApplication?.processIdentifier;c.originBundleID=NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            c.visibleOwnWindows=NSApp.windows.filter(\.isVisible).prefix(100).map(\.windowNumber)
            steps[i] = .init(id:steps[i].id,tool:.screenCapture,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let c=try PersonalScreenCapture.decode(step.text)
        guard let id=c.displayID,let screen=NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==id}) else {throw PersonalAgentError.approvalRequired}
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {throw PersonalAgentError.permissionDenied}
        let ownPID=ProcessInfo.processInfo.processIdentifier
        let external=c.originPID != nil && c.originPID != ownPID
        if external,let pid=c.originPID,let app=NSRunningApplication(processIdentifier:pid),app.bundleIdentifier==c.originBundleID,!app.isTerminated {
            let originalWindows=Set(c.visibleOwnWindows ?? [])
            for window in NSApp.windows where window.isVisible && window.canBecomeMain && !originalWindows.contains(window.windowNumber) {window.orderOut(nil)}
            app.activate(options:[])
            for _ in 0..<10 {if NSWorkspace.shared.frontmostApplication?.processIdentifier==pid {break};try await Task.sleep(for:.milliseconds(100))}
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else {throw PersonalAgentError.verificationFailed}
        } else if external {throw PersonalAgentError.verificationFailed}
        let rect=c.region ? try await pick(screen):CGRect(origin:.zero,size:screen.frame.size)
        try Task.checkCancellation()
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        guard let display=content.displays.first(where:{$0.displayID==id}) else {throw PersonalAgentError.verificationFailed}
        let config=SCStreamConfiguration();config.sourceRect=rect;config.width=Int(rect.width*screen.backingScaleFactor);config.height=Int(rect.height*screen.backingScaleFactor);config.showsCursor=false
        guard config.width>0,config.height>0,config.width<=16384,config.height<=16384,config.width*config.height<=40000000 else {throw PersonalAgentError.unsupported}
        let filter:SCContentFilter
        if external {filter=SCContentFilter(display:display,excludingApplications:content.applications.filter{$0.processID==ownPID},exceptingWindows:[])}
        else {filter=SCContentFilter(display:display,excludingWindows:content.windows.filter{$0.owningApplication?.processID==ownPID && $0.frame.width<=150 && $0.frame.height<=60})}
        let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
        guard image.width==config.width,image.height==config.height else {throw PersonalAgentError.verificationFailed}
        try Task.checkCancellation()
        guard let data=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else {throw PersonalAgentError.verificationFailed}
        let path=try NativeFileActions.writeExclusive(data,name:"Screenshot-"+step.id.uuidString+".png",rootURL:NativePersonalFolders.rootURL(.documents),subfolder:"Wesley Flow Screenshots")
        return .init(identifier:path.path,evidence:"User-requested screenshot saved and bytes verified: "+path.path+". No upload or clipboard operation.")
    }
}
