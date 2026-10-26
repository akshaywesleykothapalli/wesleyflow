import Domain
import AppKit
import Carbon

private final class PreviewHotkeyContext: Sendable {
    let send: @Sendable (PreviewShortcutSignal,Bool) -> Void
    init(send:@escaping @Sendable (PreviewShortcutSignal,Bool) -> Void) { self.send = send }
}
// C entry point constructed outside actor isolation. No AppKit state, text or clipboard access.
private let previewHotkeyCallback: EventHandlerUPP = { _, event, pointer in
    guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id) == noErr,
          id.signature == 0x57465052, id.id == 1 || id.id == 2 else { return OSStatus(eventNotHandledErr) }
    let kind: OfflinePreviewKind = id.id == 1 ? .polish : .promptEngineering
    let signal: PreviewShortcutSignal = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .pressed(kind) : .released(kind)
    Unmanaged<PreviewHotkeyContext>.fromOpaque(pointer).takeUnretainedValue().send(signal,IsSecureEventInputEnabled())
    return noErr
}

/// Exclusive Carbon registration extends the existing native hotkey layer; it never monitors text.
@MainActor public final class NativePreviewShortcuts: PreviewShortcutRegistering {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var context: PreviewHotkeyContext?
    private var delivery: Task<Void,Never>?
    private var finish: (@Sendable () -> Void)?
    private var wake: NSObjectProtocol?
    public init() {}
    public static func secureInputEnabled() -> Bool { IsSecureEventInputEnabled() }
    public static func numericLayoutSupported() -> Bool {
        guard let copied = TISCopyCurrentKeyboardLayoutInputSource() else { return false }
        let source = copied.takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else { return false }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard CFDataGetLength(data) >= MemoryLayout<UCKeyboardLayout>.size, let bytes = CFDataGetBytePtr(data) else { return false }
        return bytes.withMemoryRebound(to:UCKeyboardLayout.self,capacity:1) { layout in
            for (code,expected) in [(18,"1"),(19,"2")] {
                var dead: UInt32 = 0, length = 0
                var characters = [UniChar](repeating:0,count:4)
                let status = UCKeyTranslate(layout,UInt16(code),UInt16(kUCKeyActionDown),0,UInt32(LMGetKbdType()),OptionBits(kUCKeyTranslateNoDeadKeysMask),&dead,4,&length,&characters)
                guard status == noErr, String(utf16CodeUnits:characters,count:length) == expected else { return false }
            }
            return true
        }
    }
    public static func conflictsWithSystem(kinds:Set<OfflinePreviewKind>) throws -> Bool {
        var array: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&array)
        guard status == noErr, let array else { throw PreviewShortcutFailure.registration(status) }
        let keys = array.takeRetainedValue() as NSArray
        for case let dictionary as NSDictionary in keys {
            guard (dictionary[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let code = (dictionary[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                  let flags = (dictionary[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value else { continue }
            if flags == UInt32(optionKey), (code == 18 && kinds.contains(.polish) || code == 19 && kinds.contains(.promptEngineering)) { return true }
        }
        return false
    }
    public func enable(kinds:Set<OfflinePreviewKind>,receive:@escaping @MainActor @Sendable (PreviewShortcutNotification) -> Void) throws {
        disable(); guard !kinds.isEmpty else { return }
        guard !IsSecureEventInputEnabled() else { throw PreviewShortcutFailure.secureInput }
        guard Self.numericLayoutSupported() else { throw PreviewShortcutFailure.layoutUnsupported }
        guard try !Self.conflictsWithSystem(kinds:kinds) else { throw PreviewShortcutFailure.systemConflict }
        let pair = AsyncThrowingStream<(PreviewShortcutSignal,Bool),any Error>.makeStream(bufferingPolicy:.bufferingOldest(16))
        let context = PreviewHotkeyContext { signal,secure in
            if case .dropped = pair.continuation.yield((signal,secure)) { pair.continuation.finish(throwing:PreviewShortcutFailure.registration(-1)) }
        }
        var types = [EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        self.context = context
        let status = InstallEventHandler(GetApplicationEventTarget(),previewHotkeyCallback,2,&types,Unmanaged.passUnretained(context).toOpaque(),&handler)
        guard status == noErr else { disable(); throw PreviewShortcutFailure.registration(status) }
        for kind in OfflinePreviewKind.allCases where kinds.contains(kind) {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(kind == .polish ? 18 : 19,UInt32(optionKey),EventHotKeyID(signature:0x57465052,id:kind == .polish ? 1 : 2),GetApplicationEventTarget(),OptionBits(kEventHotKeyExclusive),&ref)
            guard result == noErr, let ref else { disable(); throw PreviewShortcutFailure.registration(result) }
            refs.append(ref)
        }
        finish = { pair.continuation.finish() }
        delivery = Task { [weak self] in
            var gesture = PreviewShortcutGesture()
            do {
                for try await (signal,secure) in pair.stream {
                    guard let self, !Task.isCancelled else { return }
                    guard Self.numericLayoutSupported() else { receive(.unavailable); self.disable(); return }
                    let flags = CGEventSource.flagsState(.combinedSessionState)
                    let invalidModifiers = !flags.intersection([.maskCommand,.maskControl,.maskShift,.maskSecondaryFn]).isEmpty
                    let blocked = secure || IsSecureEventInputEnabled() || invalidModifiers
                    let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
                    let action = gesture.accept(signal,secureInput:blocked,focus:focus)
                    if secure || IsSecureEventInputEnabled() { receive(.secureInput) }
                    if let action, kinds.contains(action) { receive(.invoke(action)) }
                }
            } catch { if !Task.isCancelled { receive(.unavailable); self?.disable() } }
        }
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { _ in context.send(.cancelled,false) }
    }
    public func disable() {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
        if let handler { RemoveEventHandler(handler) }; handler = nil
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }; wake = nil
        finish?(); finish = nil; delivery?.cancel(); delivery = nil; context = nil
    }
}
