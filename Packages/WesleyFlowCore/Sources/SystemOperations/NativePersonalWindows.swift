import AppKit
import ApplicationServices
import Domain

/// Closed native window operations; no generated script, arbitrary AX action or text access.
@MainActor public enum NativePersonalWindows {
    static func chooseWindow<E>(focused:E?,main:E?,windows:[E]) throws -> E {
        if let focused { return focused };if let main { return main }
        guard windows.count==1,let only=windows.first else { throw PersonalAgentError.unsupported }
        return only
    }
    private static func read(_ element:AXUIElement,_ name:String)->CFTypeRef? {
        var value:CFTypeRef?
        return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value:nil
    }
    private static func element(_ root:AXUIElement,_ name:String)->AXUIElement? {
        guard let value=read(root,name),CFGetTypeID(value)==AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value,to:AXUIElement.self)
    }
    private static func writable(_ e:AXUIElement,_ name:String)->Bool {
        var value=DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(e,name as CFString,&value) == .success && value.boolValue
    }
    private static func setBool(_ e:AXUIElement,_ name:String,_ value:Bool) throws {
        guard writable(e,name),AXUIElementSetAttributeValue(e,name as CFString,value ? kCFBooleanTrue:kCFBooleanFalse) == .success else { throw PersonalAgentError.unsupported }
    }
    private static func poll(_ app:NSRunningApplication,_ window:AXUIElement,_ matches:()->Bool) async throws {
        for _ in 0..<50 {
            try Task.checkCancellation()
            guard !app.isTerminated,AXIsProcessTrusted() else { throw PersonalAgentError.verificationFailed }
            if matches() { return }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw PersonalAgentError.verificationFailed
    }
    public static func perform(_ step:PersonalStep) async throws -> PersonalReceipt {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw PersonalAgentError.permissionDenied }
        _=try NativePersonalApps.target(step.text)
        let apps=NSRunningApplication.runningApplications(withBundleIdentifier:step.text).filter { !$0.isTerminated }
        guard apps.count==1,let app=apps.first else { throw PersonalAgentError.unsupported }
        let root=AXUIElementCreateApplication(app.processIdentifier);AXUIElementSetMessagingTimeout(root,0.2)
        let windows=read(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
        let window=try chooseWindow(focused:element(root,kAXFocusedWindowAttribute),main:element(root,kAXMainWindowAttribute),windows:windows)
        var owner:pid_t=0
        guard AXUIElementGetPid(window,&owner) == .success,owner==app.processIdentifier else { throw PersonalAgentError.verificationFailed }
        AXUIElementSetMessagingTimeout(window,0.2)
        switch step.tool {
        case .minimizeApp,.restoreApp:
            let value=step.tool == .minimizeApp
            if (read(window,kAXMinimizedAttribute) as? Bool) != value { try setBool(window,kAXMinimizedAttribute,value) }
            try await poll(app,window) { (read(window,kAXMinimizedAttribute) as? Bool)==value }
            if !value { app.activate(options:[]) }
        case .fullScreenApp,.exitFullScreenApp:
            let value=step.tool == .fullScreenApp
            if value,(read(window,kAXMinimizedAttribute) as? Bool)==true { try setBool(window,kAXMinimizedAttribute,false) }
            if (read(window,"AXFullScreen") as? Bool) != value { try setBool(window,"AXFullScreen",value) }
            app.activate(options:[])
            try await poll(app,window) { (read(window,"AXFullScreen") as? Bool)==value }
        case .maximizeApp:
            if (read(window,"AXFullScreen") as? Bool)==true {
                try setBool(window,"AXFullScreen",false)
                try await poll(app,window) { (read(window,"AXFullScreen") as? Bool)==false }
            }
            if (read(window,kAXMinimizedAttribute) as? Bool)==true { try setBool(window,kAXMinimizedAttribute,false) }
            guard writable(window,kAXPositionAttribute),writable(window,kAXSizeAttribute),let first=NSScreen.screens.first else { throw PersonalAgentError.unsupported }
            var origin=CGPoint.zero,size=CGSize.zero
            if let p=read(window,kAXPositionAttribute),CFGetTypeID(p)==AXValueGetTypeID() { _=AXValueGetValue(unsafeDowncast(p,to:AXValue.self),.cgPoint,&origin) }
            if let p=read(window,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID() { _=AXValueGetValue(unsafeDowncast(p,to:AXValue.self),.cgSize,&size) }
            let top=first.frame.maxY,center=NSPoint(x:origin.x+size.width/2,y:top-origin.y-size.height/2)
            guard let screen=NSScreen.screens.first(where:{$0.frame.contains(center)}) ?? NSScreen.main else { throw PersonalAgentError.unsupported }
            let frame=screen.visibleFrame
            origin=CGPoint(x:frame.minX,y:top-frame.maxY);size=CGSize(width:frame.width,height:frame.height)
            guard let position=AXValueCreate(.cgPoint,&origin),let extent=AXValueCreate(.cgSize,&size),AXUIElementSetAttributeValue(window,kAXPositionAttribute as CFString,position) == .success,AXUIElementSetAttributeValue(window,kAXSizeAttribute as CFString,extent) == .success else { throw PersonalAgentError.verificationFailed }
            app.activate(options:[])
            try await poll(app,window) {
                guard let p=read(window,kAXPositionAttribute),let z=read(window,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(z)==AXValueGetTypeID() else { return false }
                var observed=CGPoint.zero,observedSize=CGSize.zero
                guard AXValueGetValue(unsafeDowncast(p,to:AXValue.self),.cgPoint,&observed),AXValueGetValue(unsafeDowncast(z,to:AXValue.self),.cgSize,&observedSize) else { return false }
                return abs(observed.x-origin.x)<=2 && abs(observed.y-origin.y)<=2 && abs(observedSize.width-size.width)<=2 && abs(observedSize.height-size.height)<=2
            }
        default: throw PersonalAgentError.unsupported
        }
        return .init(identifier:step.id.uuidString,evidence:"Native window state read back after requested action; no force termination")
    }
}
