import Domain
import AppKit
import ApplicationServices

private final class ShortcutCallback: Sendable {
    let key: DictationActivationKey
    let send: @Sendable (DictationShortcutEvent) -> Void
    init(key: DictationActivationKey, send: @escaping @Sendable (DictationShortcutEvent) -> Void) { self.key = key; self.send = send }
}
// The C callback has no actor isolation. Only small Sendable signals cross into UI state.
private let shortcutCallback: CGEventTapCallBack = { _, type, event, pointer in
    guard let pointer else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<ShortcutCallback>.fromOpaque(pointer).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        context.send(.unavailable); return Unmanaged.passUnretained(event)
    }
    let decoded = ModifierShortcutDecoder.decode(key:context.key,type:type,code:event.getIntegerValueField(.keyboardEventKeycode),flags:event.flags,selectedDown:CGEventSource.keyState(.combinedSessionState,key:ModifierShortcutDecoder.code(context.key)))
    if let signal = decoded.signal { context.send(signal) }
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
    nonisolated static func code(_ key: DictationActivationKey) -> CGKeyCode { switch key { case .fn:63; case .rightOption:61; case .rightCommand:54 } }
    nonisolated static func decode(key: DictationActivationKey,type: CGEventType,code: Int64,flags: CGEventFlags,selectedDown: Bool) -> (signal:DictationShortcutEvent?,consume:Bool) {
        if key == .fn { return FnShortcutDecoder.decode(type:type,code:code,flags:flags) }
        let selectedFlag: CGEventFlags = key == .rightOption ? .maskAlternate : .maskCommand
        if type == .flagsChanged && code == Int64(Self.code(key)) {
            guard flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift,.maskSecondaryFn]).subtracting(selectedFlag).isEmpty else { return (.cancelled,false) }
            return (selectedDown ? .pressed : .released,false)
        }
        if (type == .keyDown && (code == 53 || selectedDown)) || (type == .flagsChanged && selectedDown) { return (.cancelled,false) }
        return (nil,false)
    }
}

@MainActor public final class NativeDictationShortcut: DictationShortcutMonitoring {
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
    public var authorizationReady: Bool { AXIsProcessTrusted() }
    public init() {}
    public func enable(receive: @escaping @MainActor @Sendable (DictationShortcutEvent) -> Void) throws {
        disable()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw DictationShortcutFailure.permissionRequired }
        let pair = AsyncThrowingStream<DictationShortcutEvent, any Error>.makeStream(bufferingPolicy: .bufferingOldest(16))
        let context = ShortcutCallback(key:key) { signal in
            if case .dropped = pair.continuation.yield(signal) { pair.continuation.finish(throwing: DictationShortcutFailure.monitoringUnavailable) }
        }
        // All three sources feed one bounded FIFO. The coordinator fences generations and
        // accepts only one down/up pair, so redundant notifications cannot create duplicate work.
        let forward: @Sendable (NSEvent) -> Void = { event in
            let type: CGEventType = event.type == .flagsChanged ? .flagsChanged : .keyDown
            var flags: CGEventFlags = []
            if event.modifierFlags.contains(.function) { flags.insert(.maskSecondaryFn) }
            if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
            if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
            if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
            if event.modifierFlags.contains(.shift) { flags.insert(.maskShift) }
            if let signal = ModifierShortcutDecoder.decode(key:context.key,type:type,code:Int64(event.keyCode),flags:flags,selectedDown:CGEventSource.keyState(.combinedSessionState,key:ModifierShortcutDecoder.code(context.key))).signal { context.send(signal) }
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged,.keyDown],handler: forward)
        let localHandler: @Sendable (NSEvent) -> NSEvent? = { event in forward(event); return event }
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
                for try await signal in pair.stream {
                    guard !Task.isCancelled else { return }
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
        let onWake: @Sendable (Notification) -> Void = { [weak self] _ in
            context.send(.cancelled)
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.authorizationReady, let tap = self.tap, CFMachPortIsValid(tap) else { context.send(.unavailable); return }
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
