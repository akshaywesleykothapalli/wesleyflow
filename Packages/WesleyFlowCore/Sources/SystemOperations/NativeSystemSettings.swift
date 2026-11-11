import AppKit
import ApplicationServices
import Domain
@MainActor public enum NativeSystemSettings {
    private static func read(_ e:AXUIElement,_ name:String)->CFTypeRef? {var value:CFTypeRef?;return AXUIElementCopyAttributeValue(e,name as CFString,&value) == .success ? value:nil}
    private static func normalized(_ value:String)->String {value.lowercased().filter(\.isLetter)}
    private static func label(_ e:AXUIElement)->String {
        var labels=[kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap{read(e,$0) as? String}
        if let raw=read(e,kAXTitleUIElementAttribute),CFGetTypeID(raw)==AXUIElementGetTypeID() {let title=unsafeDowncast(raw,to:AXUIElement.self);if (read(title,kAXRoleAttribute) as? String)==kAXStaticTextRole,let value=read(title,kAXValueAttribute) as? String {labels.append(value)}}
        return normalized(labels.joined(separator:" "))
    }
    private static func controls(_ root:AXUIElement,term:String,roles:[String]) throws ->[AXUIElement] {
        let deadline=Date().addingTimeInterval(1)
        var queue=[root],index=0,result:[AXUIElement]=[]
        while index<queue.count,index<2000 {
            guard Date()<deadline else {throw PersonalAgentError.unsupported}
            let e=queue[index];index+=1
            if let role=read(e,kAXRoleAttribute) as? String,roles.contains(role),label(e).contains(term) {result.append(e)}
            queue += read(e,kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        guard index<2000 else {throw PersonalAgentError.unsupported};return result
    }
    private static func control(pane:String,term:String,roles:[String]) async throws ->AXUIElement {
        guard AXIsProcessTrusted() else {throw PersonalAgentError.permissionDenied}
        _=try await NativePersonalApps.open("com.apple.systempreferences")
        // A routing hint only. The exact semantic control must still be found and validated.
        if let url=URL(string:"x-apple.systempreferences:"+pane) {_=NSWorkspace.shared.open(url)}
        let apps=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.systempreferences").filter{!$0.isTerminated}
        guard apps.count==1,let app=apps.first else {throw PersonalAgentError.unsupported}
        let root=AXUIElementCreateApplication(app.processIdentifier);AXUIElementSetMessagingTimeout(root,0.2)
        for _ in 0..<25 {
            try Task.checkCancellation();guard !app.isTerminated else {throw PersonalAgentError.verificationFailed}
            let windows=read(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
            let matches=try windows.flatMap{try controls($0,term:term,roles:roles)}
            if matches.count==1,let match=matches.first {return match}
            if matches.count>1 {throw PersonalAgentError.unsupported}
            try await Task.sleep(for:.milliseconds(150))
        }
        throw PersonalAgentError.unsupported
    }
    public static func brightness(_ request:PersonalMacControl) async throws ->PersonalReceipt {
        guard NSScreen.screens.count==1 else {throw PersonalAgentError.unsupported}
        let slider=try await control(pane:"com.apple.Displays-Settings.extension",term:"brightness",roles:[kAXSliderRole])
        guard let value=read(slider,kAXValueAttribute) as? NSNumber,let minimum=read(slider,kAXMinValueAttribute) as? NSNumber,let maximum=read(slider,kAXMaxValueAttribute) as? NSNumber else {throw PersonalAgentError.unsupported}
        let low=minimum.doubleValue,high=maximum.doubleValue,old=value.doubleValue
        guard low.isFinite,high.isFinite,old.isFinite,high>low,high-low<=10000,old>=low,old<=high else {throw PersonalAgentError.unsupported}
        let prior=(old-low)/(high-low),fraction:Double
        switch request.action {case .brightnessSet:guard let n=Int(request.value),(0...100).contains(n) else {throw PersonalAgentError.invalidCommand};fraction=Double(n)/100;case .brightnessUp:fraction=min(1,prior+0.1);case .brightnessDown:fraction=max(0,prior-0.1);default:throw PersonalAgentError.unsupported}
        let wanted=low+fraction*(high-low);var settable=DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(slider,kAXValueAttribute as CFString,&settable) == .success,settable.boolValue,AXUIElementSetAttributeValue(slider,kAXValueAttribute as CFString,NSNumber(value:wanted)) == .success else {throw PersonalAgentError.unsupported}
        for _ in 0..<10 {if let observed=read(slider,kAXValueAttribute) as? NSNumber,abs(observed.doubleValue-wanted)<=0.02*(high-low) {return .init(identifier:"system-settings.brightness",evidence:"Native single-display brightness slider read back at \(Int(fraction*100))%. No private display API or synthetic key used.")};try await Task.sleep(for:.milliseconds(100))}
        throw PersonalAgentError.verificationFailed
    }
    public static func lowPower() async throws ->PersonalReceipt {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {return .init(identifier:"low-power-mode",evidence:"Low Power Mode was already enabled; native ProcessInfo readback.")}
        let control=try await control(pane:"com.apple.Battery-Settings.extension",term:"lowpowermode",roles:[kAXCheckBoxRole,kAXPopUpButtonRole])
        if (read(control,kAXRoleAttribute) as? String)==kAXCheckBoxRole {
            guard let value=read(control,kAXValueAttribute) as? NSNumber else {throw PersonalAgentError.unsupported}
            if value.intValue==0 {guard AXUIElementPerformAction(control,kAXPressAction as CFString) == .success else {throw PersonalAgentError.unsupported}}
            else if value.intValue != 1 {throw PersonalAgentError.unsupported}
        } else {
            if normalized(read(control,kAXValueAttribute) as? String ?? "") != "always" {
                guard AXUIElementPerformAction(control,kAXPressAction as CFString) == .success else {throw PersonalAgentError.unsupported}
                var queue=read(control,kAXChildrenAttribute) as? [AXUIElement] ?? [],index=0,choices:[AXUIElement]=[]
                while index<queue.count,index<100 {let e=queue[index];index+=1;if (read(e,kAXRoleAttribute) as? String)==kAXMenuItemRole,normalized(read(e,kAXTitleAttribute) as? String ?? "")=="always" {choices.append(e)};queue += read(e,kAXChildrenAttribute) as? [AXUIElement] ?? []}
                guard choices.count==1,let chosen=choices.first,AXUIElementPerformAction(chosen,kAXPressAction as CFString) == .success else {throw PersonalAgentError.unsupported}
            }
        }
        for _ in 0..<20 {if ProcessInfo.processInfo.isLowPowerModeEnabled {return .init(identifier:"low-power-mode",evidence:"Native Low Power Mode control selected; ProcessInfo confirms Low Power Mode enabled. No sudo or privileged helper used.")};try await Task.sleep(for:.milliseconds(100))}
        throw PersonalAgentError.verificationFailed
    }

    public enum SpacesSwipe: String, Codable, Sendable {
        case off = "Off"
        case threeFingers = "Swipe Left or Right with Three Fingers"
        case fourFingers = "Swipe Left or Right with Four Fingers"
    }

    public static func spacesSwipe() async throws -> SpacesSwipe {
        let foreground = NSWorkspace.shared.frontmostApplication
        let settingsWasVisible = runningTrackpadSettings()?.isHidden == false
        defer { restoreForegroundAfterTrackpadSettings(foreground, settingsWasVisible: settingsWasVisible) }
        let root = try await trackpadGestures()
        return try swipeChoice(try swipePopup(in: root))
    }

    public static func replaceSpacesSwipe(_ expected: SpacesSwipe, with wanted: SpacesSwipe,
                                          beforeChange: () throws -> Void) async throws {
        let foreground = NSWorkspace.shared.frontmostApplication
        let settingsWasVisible = runningTrackpadSettings()?.isHidden == false
        defer { restoreForegroundAfterTrackpadSettings(foreground, settingsWasVisible: settingsWasVisible) }
        let root = try await trackpadGestures()
        let popup = try swipePopup(in: root)
        let current = try swipeChoice(popup)
        guard current == expected else { throw PersonalAgentError.verificationFailed }
        try Task.checkCancellation()
        guard AXUIElementPerformAction(popup, kAXPressAction as CFString) == .success else {
            throw PersonalAgentError.unsupported
        }
        for _ in 0..<12 {
            let items = try matchingElements(in: popup) { element in
                (read(element, kAXRoleAttribute) as? String) == kAXMenuItemRole
                    && (read(element, kAXTitleAttribute) as? String) == wanted.rawValue
            }
            if items.count == 1, let item = items.first {
                try Task.checkCancellation()
                try beforeChange()
                guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
                    throw PersonalAgentError.verificationFailed
                }
                for _ in 0..<15 {
                    if let control = try? swipePopup(in: root), (try? swipeChoice(control)) == wanted { return }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw PersonalAgentError.verificationFailed
            }
            guard items.isEmpty else { throw PersonalAgentError.unsupported }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PersonalAgentError.unsupported
    }

    private static func trackpadGestures() async throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw PersonalAgentError.permissionDenied }
        let workspace = NSWorkspace.shared
        let identifier = "com.apple.systempreferences"
        if let app = runningTrackpadSettings() {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.2)
            if (try? swipePopup(in: root)) != nil { return root }
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"),
              let appURL = workspace.urlForApplication(withBundleIdentifier: identifier) else {
            throw PersonalAgentError.unsupported
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let app = try await workspace.open([url], withApplicationAt: appURL, configuration: configuration)
        guard app.bundleIdentifier == identifier else { throw PersonalAgentError.unsupported }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        for _ in 0..<30 {
            try Task.checkCancellation()
            guard !app.isTerminated else { throw PersonalAgentError.verificationFailed }
            if (try? swipePopup(in: root)) != nil { return root }
            let tabs = try windowElements(in: root) { element in
                let role = read(element, kAXRoleAttribute) as? String
                return [kAXCheckBoxRole, kAXRadioButtonRole].contains(role ?? "")
                    && (read(element, kAXDescriptionAttribute) as? String) == "More Gestures"
            }
            if tabs.count == 1, let tab = tabs.first,
               (read(tab, kAXValueAttribute) as? NSNumber)?.intValue == 0 {
                guard AXUIElementPerformAction(tab, kAXPressAction as CFString) == .success else {
                    throw PersonalAgentError.unsupported
                }
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw PersonalAgentError.unsupported
    }

    private static func runningTrackpadSettings() -> NSRunningApplication? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .filter { !$0.isTerminated }
        return apps.count == 1 ? apps.first : nil
    }

    private static func restoreForegroundAfterTrackpadSettings(_ previous: NSRunningApplication?, settingsWasVisible: Bool) {
        // A popup action can bring Settings forward even when it opened in the background.
        guard let settings = runningTrackpadSettings(),
              previous?.processIdentifier != settings.processIdentifier else { return }
        let becameForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier == settings.processIdentifier
        if becameForeground || !settingsWasVisible { _ = settings.hide() }
        if becameForeground, let previous, !previous.isTerminated { _ = previous.activate(options: []) }
    }

    private static func swipePopup(in root: AXUIElement) throws -> AXUIElement {
        let matches = try windowElements(in: root) { element in
            (read(element, kAXRoleAttribute) as? String) == kAXPopUpButtonRole
                && (read(element, kAXIdentifierAttribute) as? String) == "GNAME_DASHBOARD"
        }
        guard matches.count == 1, let popup = matches.first else { throw PersonalAgentError.unsupported }
        return popup
    }

    private static func swipeChoice(_ popup: AXUIElement) throws -> SpacesSwipe {
        guard let text = read(popup, kAXValueAttribute) as? String, let choice = SpacesSwipe(rawValue: text) else {
            throw PersonalAgentError.unsupported
        }
        return choice
    }

    private static func windowElements(in root: AXUIElement, where matches: (AXUIElement) -> Bool) throws -> [AXUIElement] {
        let windows = read(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard windows.count <= 4 else { throw PersonalAgentError.unsupported }
        return try windows.flatMap { try matchingElements(in: $0, where: matches) }
    }

    private static func matchingElements(in root: AXUIElement, where matches: (AXUIElement) -> Bool) throws -> [AXUIElement] {
        let deadline = ContinuousClock.now + .seconds(1)
        var queue = [root], index = 0, result: [AXUIElement] = []
        while index < queue.count {
            guard index < 500, ContinuousClock.now < deadline else { throw PersonalAgentError.unsupported }
            let item = queue[index]
            index += 1
            if matches(item) { result.append(item) }
            queue += read(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return result
    }

}
