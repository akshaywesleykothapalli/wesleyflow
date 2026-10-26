import Domain
import AppKit
import Carbon
import Synchronization

// C callbacks cannot touch MainActor AppKit state. The small metadata bridge is
// shared across that boundary; the actor owns registration and all UI work.
private final class PreviewFocusIdentity: Sendable {
    private let value: Mutex<(process:Int32, epoch:UUID)>
    init(_ process: Int32) { value = Mutex((process, UUID())) }
    func update(_ process: Int32) { value.withLock { $0 = (process, UUID()) } }
    func snapshot() -> (process:Int32, epoch:UUID) { value.withLock { $0 } }
}
private struct PreviewHotkeySample: Sendable {
    let signal: PreviewShortcutSignal
    let secure: Bool
    let focus: Int32
    let focusEpoch: UUID
    let invalidModifiers: Bool
    let time: TimeInterval
}
/// Exercises the actual delivery state machine without native key injection.
struct PreviewHotkeyDelivery {
    private var gesture = PreviewShortcutGesture()
    mutating func accept(_ signal: PreviewShortcutSignal, originFocus: Int32, currentFocus: Int32, age: TimeInterval, blocked: Bool) -> OfflinePreviewKind? {
        guard !blocked, originFocus > 0, originFocus == currentFocus, age >= 0, age <= 1 else {
            _ = gesture.accept(.cancelled, secureInput:false, focus:currentFocus)
            return nil
        }
        return gesture.accept(signal, secureInput:false, focus:originFocus)
    }
}

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
    private var observers: [NSObjectProtocol] = []
    private var suspended = false
    private var epoch = UUID()
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
        let focusIdentity = PreviewFocusIdentity(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)
        let ticket = epoch
        let pair = AsyncThrowingStream<PreviewHotkeySample,any Error>.makeStream(bufferingPolicy:.bufferingOldest(16))
        let context = PreviewHotkeyContext { signal,secure in
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let invalid = !flags.intersection([.maskCommand,.maskControl,.maskShift,.maskSecondaryFn]).isEmpty
            let identity = focusIdentity.snapshot()
            let sample = PreviewHotkeySample(signal:signal, secure:secure, focus:identity.process, focusEpoch:identity.epoch, invalidModifiers:invalid, time:GetCurrentEventTime())
            if case .dropped = pair.continuation.yield(sample) { pair.continuation.finish(throwing:PreviewShortcutFailure.registration(-1)) }
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
            var state = PreviewHotkeyDelivery()
            do {
                for try await sample in pair.stream {
                    guard let self, self.epoch == ticket, !Task.isCancelled else { return }
                    guard Self.numericLayoutSupported() else { receive(.unavailable); self.disable(); return }
                    let flags = CGEventSource.flagsState(.combinedSessionState)
                    let invalidModifiers = !flags.intersection([.maskCommand,.maskControl,.maskShift,.maskSecondaryFn]).isEmpty
                    let secure = sample.secure || IsSecureEventInputEnabled()
                    let blocked = secure || invalidModifiers || sample.invalidModifiers || self.suspended || sample.focusEpoch != focusIdentity.snapshot().epoch
                    let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
                    let action = state.accept(sample.signal,originFocus:sample.focus,currentFocus:focus,age:GetCurrentEventTime()-sample.time,blocked:blocked)
                    if secure || IsSecureEventInputEnabled() { receive(.secureInput) }
                    if let action, kinds.contains(action) {
                        guard (try? Self.conflictsWithSystem(kinds:kinds)) == false else { receive(.unavailable); self.disable(); return }
                        receive(.invokeFrom(action,processIdentifier:sample.focus))
                    }
                }
            } catch { if let self, self.epoch == ticket, !Task.isCancelled { receive(.unavailable); self.disable() } }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in
            // Invalidate synchronously before hopping actors: queued old key
            // events cannot be rebound to the newly active app.
            focusIdentity.update(-1); context.send(.cancelled,false)
            Task { @MainActor [weak self] in
                guard let self, self.epoch == ticket else { return }
                focusIdentity.update(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)
            }
        })
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            focusIdentity.update(-1)
            Task { @MainActor [weak self] in
                guard let self, self.epoch == ticket else { return }
                self.suspended = true; context.send(.cancelled,false); receive(.suspended)
            }
        })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.epoch == ticket else { return }
                // Revalidate layout, Secure Input and conflicts before acquiring
                // fresh native refs. Old stream events are fenced by the epoch.
                do { try self.enable(kinds:kinds,receive:receive); receive(.resumed) }
                catch { self.disable(); receive(.unavailable) }
            }
        })
    }
    public func disable() {
        epoch = UUID(); suspended = false
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
        if let handler { RemoveEventHandler(handler) }; handler = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observers.removeAll()
        finish?(); finish = nil; delivery?.cancel(); delivery = nil; context = nil
    }
}
