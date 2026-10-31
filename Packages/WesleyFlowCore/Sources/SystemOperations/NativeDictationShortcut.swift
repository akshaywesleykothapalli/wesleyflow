import Domain
import AppKit
import ApplicationServices
import Synchronization
import Carbon

// Only public process identity crosses the C callback; no AppKit/AX work there.
final class DictationActivationIdentityMailbox: Sendable {
    private let state:Mutex<(application:DictationApplicationIdentity?,epoch:UUID,since:Double)>
    init(_ application:DictationApplicationIdentity?) { state=Mutex((application,UUID(),ProcessInfo.processInfo.systemUptime)) }
    func update(_ application:DictationApplicationIdentity?) { state.withLock { $0=(application,UUID(),ProcessInfo.processInfo.systemUptime) } }
    func snapshot()->(application:DictationApplicationIdentity?,epoch:UUID,since:Double) { state.withLock { $0 } }
}
private struct DictationNativeSignal:Sendable {
    let event:DictationShortcutEvent
    let application:DictationApplicationIdentity?
    let epoch:UUID
    let time:Double
    let source:String
    let eventTime:Double
    let activationSince:Double
}
private final class ShortcutCallback: Sendable {
    let key: DictationActivationKey
    private struct Counts: Sendable { var selectedEvents = 0; var downs = 0; var ups = 0; var cancellations = 0; var last = "none" }
    private let counts = Mutex(Counts())
    var summary: String { counts.withLock { "selectedEvents=\($0.selectedEvents) down=\($0.downs) up=\($0.ups) cancelled=\($0.cancellations) last=\($0.last)" } }
    func accept(type:CGEventType,code:Int64,flags:CGEventFlags,source:String,time:Double) {
        let signal = ModifierShortcutDecoder.decode(key:key,type:type,code:code,flags:flags).signal
        counts.withLock {
            if type == .flagsChanged && code == Int64(ModifierShortcutDecoder.code(key)) { $0.selectedEvents = min(1_000_000,$0.selectedEvents+1) }
            if let signal {
                switch signal { case .pressed: $0.downs = min(1_000_000,$0.downs+1); case .released: $0.ups = min(1_000_000,$0.ups+1); case .cancelled: $0.cancellations = min(1_000_000,$0.cancellations+1); case .unavailable: break }
                $0.last = source + ":" + String(describing:signal)
            }
        }
        if let signal { send(signal,source,time) }
    }
    let send: @Sendable (DictationShortcutEvent,String,Double) -> Void
    init(key: DictationActivationKey, send: @escaping @Sendable (DictationShortcutEvent,String,Double) -> Void) { self.key = key; self.send = send }
}
// The C callback has no actor isolation. Only small Sendable signals cross into UI state.
private let shortcutCallback: CGEventTapCallBack = { _, type, event, pointer in
    guard let pointer else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<ShortcutCallback>.fromOpaque(pointer).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        context.send(.unavailable,"eventTap",Double(event.timestamp)/1_000_000_000); return Unmanaged.passUnretained(event)
    }
    context.accept(type:type,code:event.getIntegerValueField(.keyboardEventKeycode),flags:event.flags,source:"eventTap",time:Double(event.timestamp)/1_000_000_000)
    return Unmanaged.passUnretained(event)
}

enum FnShortcutDecoder {
    nonisolated static func decode(type: CGEventType,code: Int64,flags: CGEventFlags) -> (signal: DictationShortcutEvent?, consume: Bool) {
        if type == .flagsChanged && code == 63 {
            if !flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]).isEmpty { return (.cancelled,false) }
            return (flags.contains(.maskSecondaryFn) ? .pressed : .released,false)
        }
        if (type == .keyDown && (code == 53 || flags.contains(.maskSecondaryFn))) ||
            (type == .flagsChanged && flags.contains(.maskSecondaryFn)) { return (.cancelled,false) }
        return (nil,false)
    }
}

enum ModifierShortcutDecoder {
    nonisolated static func code(_ key: DictationActivationKey) -> CGKeyCode { switch key { case .fn:63; case .rightOption:61; case .rightCommand:54; case .rightControl:62 } }
    // Read the immutable flags attached to THIS event. CGEventSource.keyState is a
    // separately sampled global state and may describe before/after this transition.
    // Device-dependent side bits are public NX_DEVICE* constants in IOLLEvent.h.
    nonisolated static func sideMasks(_ key:DictationActivationKey)->(right:UInt64,left:UInt64) {
        switch key { case .rightControl:(0x2000,0x1); case .rightCommand:(0x10,0x8); case .rightOption:(0x40,0x20); case .fn:(0,0) }
    }
    nonisolated static func decode(event:NSEvent,key:DictationActivationKey)->(signal:DictationShortcutEvent?,consume:Bool) {
        decode(key:key,type:event.type == .flagsChanged ? .flagsChanged : .keyDown,code:Int64(event.keyCode),flags:CGEventFlags(rawValue:UInt64(event.modifierFlags.rawValue)))
    }
    nonisolated static func decode(key: DictationActivationKey,type: CGEventType,code: Int64,flags: CGEventFlags) -> (signal:DictationShortcutEvent?,consume:Bool) {
        if key == .fn { return FnShortcutDecoder.decode(type:type,code:code,flags:flags) }
        let selectedFlag: CGEventFlags = key == .rightOption ? .maskAlternate : key == .rightControl ? .maskControl : .maskCommand
        let masks = sideMasks(key), sides = flags.rawValue & (sideMasks(key).right | sideMasks(key).left)
        let down = flags.contains(selectedFlag) && (sides == 0 || flags.rawValue & masks.right != 0)
        if type == .flagsChanged && code == Int64(Self.code(key)) {
            // Right-up while the left sibling stays held still needs to clear the
            // coordinator latch. Never mistake that aggregate group flag for right-down.
            if !down { return (.released,false) }
            guard flags.rawValue & masks.left == 0,
                  flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift,.maskSecondaryFn]).subtracting(selectedFlag).isEmpty else { return (.cancelled,false) }
            return (.pressed,false)
        }
        if type == .keyDown && (code == 53 || down) { return (.cancelled,false) }
        if type == .flagsChanged && down { return (.cancelled,false) }
        return (nil,false)
    }
}

@MainActor public final class NativeDictationShortcut: DictationShortcutMonitoring {
    public private(set) var activationContext:DictationActivationContext?
    private var activationObserver:NSObjectProtocol?
    private static func identity(_ application:NSRunningApplication?)->DictationApplicationIdentity? {
        application.flatMap { app in app.launchDate.map { DictationApplicationIdentity(processID:app.processIdentifier,launchTime:$0.timeIntervalSinceReferenceDate,bundleIdentifier:app.bundleIdentifier) } }
    }
    private var key: DictationActivationKey = .fn
    public func configure(key: DictationActivationKey) { if self.key != key { disable(); self.key = key } }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var context: ShortcutCallback?
    private var global: Any?
    private var local: Any?
    private var wake: NSObjectProtocol?
    private var delivery: Task<Void, Never>?
    private var finish: (@Sendable () -> Void)?
    public var diagnosticSummary: String {
        "key=\(key.label) tap=\(tap != nil) global=\(global != nil) local=\(local != nil) " + (context?.summary ?? "monitor=disabled")
    }
    public var authorizationReady: Bool { AXIsProcessTrusted() }
    public init() {}
    /// Reads security metadata only: never a field value or clipboard contents.
    public static func validateAgentActivation(_ context: DictationActivationContext) throws {
        guard context.permits(identity(NSWorkspace.shared.frontmostApplication)) else { throw TextTargetError.changed }
    }
    // A global Agent gesture needs security metadata, not an insertion destination.
    // No focused element is normal on a desktop/full-screen canvas; unknown AX failures still fail closed.
    static func validateAgentSecurity(trusted:Bool,secureInput:Bool,focusStatus:AXError,elementPresent:Bool,subroleStatus:AXError = .attributeUnsupported,subrole:String?=nil,roleStatus:AXError = .attributeUnsupported,role:String?=nil) throws {
        guard trusted else { throw TextTargetError.denied }
        guard !secureInput else { throw TextTargetError.secure }
        if [.noValue,.attributeUnsupported,.notImplemented].contains(focusStatus),!elementPresent { return }
        guard focusStatus == .success,elementPresent else { throw focusStatus == .apiDisabled ? TextTargetError.denied:TextTargetError.unsupported }
        for (status,value) in [(subroleStatus,subrole),(roleStatus,role)] {
            guard [.success,.attributeUnsupported,.noValue,.notImplemented].contains(status) else { throw status == .apiDisabled ? TextTargetError.denied:TextTargetError.unsupported }
            guard status != .success || value != nil else { throw TextTargetError.unsupported }
            let label=(value ?? "").lowercased()
            guard !label.contains("secure"),!label.contains("password") else { throw TextTargetError.secure }
        }
    }
    public static func validateAgentCapture() throws {
        guard AXIsProcessTrusted() else { throw TextTargetError.denied }
        guard !IsSecureEventInputEnabled() else { throw TextTargetError.secure }
        guard let front=NSWorkspace.shared.frontmostApplication,!front.isTerminated else { throw TextTargetError.changed }
        let application=AXUIElementCreateApplication(front.processIdentifier)
        // Scope the timeout to this application/element, never to system-wide AX defaults.
        AXUIElementSetMessagingTimeout(application,0.1)
        var focused:CFTypeRef?
        let status=AXUIElementCopyAttributeValue(application,kAXFocusedUIElementAttribute as CFString,&focused)
        guard status == .success,let focused,CFGetTypeID(focused)==AXUIElementGetTypeID() else {
            try validateAgentSecurity(trusted:AXIsProcessTrusted(),secureInput:IsSecureEventInputEnabled(),focusStatus:status,elementPresent:false)
            return
        }
        let element=unsafeDowncast(focused,to:AXUIElement.self)
        AXUIElementSetMessagingTimeout(element,0.1)
        var subrole:CFTypeRef?,role:CFTypeRef?
        let subroleStatus=AXUIElementCopyAttributeValue(element,kAXSubroleAttribute as CFString,&subrole)
        let roleStatus=AXUIElementCopyAttributeValue(element,kAXRoleAttribute as CFString,&role)
        try validateAgentSecurity(trusted:AXIsProcessTrusted(),secureInput:IsSecureEventInputEnabled(),focusStatus:status,elementPresent:true,subroleStatus:subroleStatus,subrole:subrole as? String,roleStatus:roleStatus,role:role as? String)
    }
    public static func conflictsWithSystem(key: DictationActivationKey) throws -> Bool {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr, let array else { throw DictationShortcutFailure.monitoringUnavailable }
        for case let item as NSDictionary in array.takeRetainedValue() as NSArray {
            if (item[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
               (item[kHISymbolicHotKeyCode as String] as? NSNumber)?.intValue == Int(ModifierShortcutDecoder.code(key)) { return true }
        }
        return false
    }
    public func enable(receive: @escaping @MainActor @Sendable (DictationShortcutEvent) -> Void) throws {
        disable()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw DictationShortcutFailure.permissionRequired }
        let identity=DictationActivationIdentityMailbox(Self.identity(NSWorkspace.shared.frontmostApplication))
        let pair = AsyncThrowingStream<DictationNativeSignal, any Error>.makeStream(bufferingPolicy: .bufferingOldest(16))
        let context = ShortcutCallback(key:key) { signal,source,eventTime in
            let current=identity.snapshot()
            let sample=DictationNativeSignal(event:signal,application:current.application,epoch:current.epoch,time:ProcessInfo.processInfo.systemUptime,source:source,eventTime:eventTime,activationSince:current.since)
            if case .dropped = pair.continuation.yield(sample) { pair.continuation.finish(throwing: DictationShortcutFailure.monitoringUnavailable) }
        }
        // All three sources feed one bounded FIFO. The coordinator fences generations and
        // accepts only one down/up pair, so redundant notifications cannot create duplicate work.
        let forward: @Sendable (NSEvent,String) -> Void = { event,source in
            let type: CGEventType = event.type == .flagsChanged ? .flagsChanged : .keyDown
            context.accept(type:type,code:Int64(event.keyCode),flags:CGEventFlags(rawValue:UInt64(event.modifierFlags.rawValue)),source:source,time:event.timestamp)
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged,.keyDown],handler: { forward($0,"globalMonitor") })
        let localHandler: @Sendable (NSEvent) -> NSEvent? = { event in forward(event,"localMonitor"); return event }
        local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged,.keyDown],handler: localHandler)
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        if let created = CGEvent.tapCreate(tap: .cgSessionEventTap,place: .headInsertEventTap,options: .listenOnly,
                                          eventsOfInterest: mask,callback: shortcutCallback,
                                          userInfo: Unmanaged.passUnretained(context).toOpaque()) {
            if let runLoop = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,created,0) {
                tap = created; source = runLoop
                CFRunLoopAddSource(CFRunLoopGetMain(),runLoop,.commonModes); CGEvent.tapEnable(tap: created,enable: true)
            } else { CFMachPortInvalidate(created) }
        }
        guard global != nil || tap != nil else {
            disable(); _ = CGRequestListenEventAccess(); throw DictationShortcutFailure.monitoringUnavailable
        }
        self.context = context; finish = { pair.continuation.finish() }
        delivery = Task { [weak self] in
            do {
                for try await sample in pair.stream {
                    guard !Task.isCancelled else { return }
                    let signal=sample.event
                    if signal == .pressed {
                        var context=DictationActivationContext(application:sample.application,pressUptime:sample.time,source:sample.source,activationUnchanged:sample.epoch==identity.snapshot().epoch && DictationActivationTiming.accepts(event:sample.eventTime,observed:sample.time,activation:sample.activationSince))
                        context.eventUptime=sample.eventTime;context.activationObservedUptime=sample.activationSince
                        self?.activationContext=context
                    }
                    if signal == .unavailable {
                        // A disabled optional tap never synthesizes a key press. Cancel the
                        // current gesture and re-arm only while already authorized.
                        receive(.cancelled)
                        if let self, self.authorizationReady, let tap = self.tap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap,enable: true) }
                        else { receive(.unavailable) }
                    } else { receive(signal) }
                }
            } catch { if !Task.isCancelled { receive(.unavailable) } }
        }
        activationObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { note in
            // queue:.main is the explicit isolation guarantee; do not move this
            // AppKit read into the C callback or delay it behind the signal FIFO.
            let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { identity.update(Self.identity(app)) }
        }
        let onWake: @Sendable (Notification) -> Void = { [weak self] _ in
            identity.update(nil)
            context.send(.cancelled,"wake",ProcessInfo.processInfo.systemUptime)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.authorizationReady, let tap = self.tap, CFMachPortIsValid(tap) else { context.send(.unavailable,"wake",ProcessInfo.processInfo.systemUptime); return }
                identity.update(Self.identity(NSWorkspace.shared.frontmostApplication))
                CGEvent.tapEnable(tap: tap,enable: true)
            }
        }
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,object: nil,queue: .main,using: onWake)
    }
    public func disable() {
        if let tap { CGEvent.tapEnable(tap: tap,enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        if let global { NSEvent.removeMonitor(global) }; if let local { NSEvent.removeMonitor(local) }
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver=nil;activationContext=nil
        finish?(); finish = nil; delivery?.cancel(); delivery = nil
        source = nil; tap = nil; context = nil; global = nil; local = nil; wake = nil
    }
}

/// Compatibility port for Phase1C.1 callers: verified AX-only insertion. The new
/// coordinator uses TextInsertionService for asynchronous paste/clipboard handling.
@MainActor public final class NativeDictationDestinationCapture: DictationDestinationCapturing {
    public init() {}
    public func capture() throws -> any DictationTextDestination {
        try LegacyAXDestination(target:NativeInsertionTargetCapture().capture(session:UUID().uuidString))
    }
}
@MainActor private final class LegacyAXDestination: DictationTextDestination {
    let target: any InsertionTarget
    init(target: any InsertionTarget) { self.target = target }
    func insert(_ text: String) throws {
        let clean = DictationText.cleaned(text)
        guard !clean.isEmpty, clean.utf8.count <= DictationText.maximumBytes, let original = target.original, target.canReplaceSelection(),
              let expected = original.selection.replacing(in:original.text,with:clean) else { throw DictationShortcutFailure.insertionFailed }
        try target.validate(); try target.replaceSelection(clean)
        guard target.observedText() == expected else { throw DictationShortcutFailure.insertionFailed }
    }
}
