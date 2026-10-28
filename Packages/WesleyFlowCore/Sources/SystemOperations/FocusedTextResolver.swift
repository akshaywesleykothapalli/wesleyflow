import AppKit
import ApplicationServices
import Carbon
import Synchronization

public enum FocusedTextSource: String, Sendable { case selection = "Selected text", draft = "Focused draft", paragraph = "Current paragraph", manual = "Manual input" }
public enum FocusedTextStatus: String, Sendable, CaseIterable {
    case captured, disabled, permissionRequired, secure, unsupported, empty, sizeLimit, sourceChanged, cancelled, timedOut, busy
    public var explanation: String {
        switch self {
        case .captured: "Review the captured text before generating."
        case .disabled: "Focused-text capture is disabled. Enable it in Smart Formatting, select text, or enter text here."
        case .permissionRequired: "Accessibility permission is required to read the focused editor. You can enter text here."
        case .secure: "Secure or composing input is excluded. Enter non-sensitive text here instead."
        case .unsupported: "This editor does not expose supported readable text. Enter text here instead."
        case .empty: "No text exists in the focused field. Enter text here."
        case .sizeLimit: "Input exceeds the permitted size or paragraph boundary. Select a shorter passage or enter text here."
        case .sourceChanged: "The source application or focused field changed during capture. Enter text here or invoke the shortcut again."
        case .cancelled: "Text capture was cancelled."
        case .timedOut: "The editor did not respond within the capture deadline. Enter text here."
        case .busy: "Another text capture is still settling. Enter text here."
        }
    }
}
public enum FocusedTextStage: String, Sendable { case authorization, focus, attributes, classification, selection, parameterList, rangeRead, valueRead, selectedRead, consistency, finished }
public struct FocusedTextResolution: Sendable, Equatable {
    public let text: String
    public let source: FocusedTextSource
    public let status: FocusedTextStatus
    public let stage: FocusedTextStage
    public init(text: String = "", source: FocusedTextSource = .manual, status: FocusedTextStatus? = nil, stage: FocusedTextStage = .finished) {
        self.text = text; self.source = source; self.status = status ?? (text.isEmpty ? .unsupported : .captured); self.stage = stage
    }
}
@MainActor public protocol FocusedTextResolving: AnyObject {
    func resolve(processID: Int32, allowUnselected: Bool) async -> FocusedTextResolution
}

/// Pure bounded policy shared by native retrieval and deterministic tests. AX offsets are UTF-16.
enum FocusedTextPolicy {
    static let maximumBytes = 2048
    static let windowCharacters = 1024
    static func eligible(role: String, subrole: String?, enabled: Bool?, editable: Bool?, writable: Bool, marked: Bool) -> Bool {
        guard [kAXTextAreaRole,kAXTextFieldRole,kAXComboBoxRole].contains(role),
              let subrole, !subrole.lowercased().contains("secure"), !subrole.lowercased().contains("password"),
              enabled == true, editable != false, !marked else { return false }
        return editable == true || writable
    }
    static func permitsValueFallback(rangeStatus: AXError, selectionLength: Int, count: Int) -> Bool {
        selectionLength == 0 && count > 0 && count <= windowCharacters &&
            [.attributeUnsupported,.parameterizedAttributeUnsupported,.notImplemented,.noValue].contains(rangeStatus)
    }
    static func readBounded(rangeStatus: AXError, rangeText: String?, selectionLength: Int, count: Int,
                            selected: () -> String?, value: () -> String?) -> (text: String?, stage: FocusedTextStage) {
        if rangeStatus == .success { return (rangeText,.rangeRead) }
        guard [.attributeUnsupported,.parameterizedAttributeUnsupported,.notImplemented,.noValue].contains(rangeStatus) else { return (nil,.rangeRead) }
        if selectionLength > 0 {
            guard selectionLength <= windowCharacters else { return (nil,.selectedRead) }
            return (selected(),.selectedRead)
        }
        guard permitsValueFallback(rangeStatus:rangeStatus,selectionLength:selectionLength,count:count) else { return (nil,.valueRead) }
        return (value(),.valueRead)
    }
    static func select(count: Int, selection: NSRange, allowUnselected: Bool) -> NSRange? {
        guard count >= 0, selection.location >= 0, selection.length >= 0,
              selection.location <= count, selection.length <= count - selection.location else { return nil }
        if selection.length > 0 { return selection.length <= windowCharacters ? selection : nil }
        guard allowUnselected, count > 0 else { return nil }
        if count <= windowCharacters { return NSRange(location:0,length:count) }
        let start = max(0,min(selection.location-windowCharacters/2,count-windowCharacters))
        return NSRange(location:start,length:windowCharacters)
    }
    static func resolve(text: String, count: Int, selection: NSRange, retrieved: NSRange) -> FocusedTextResolution {
        guard text.utf16.count == retrieved.length else { return .init() }
        let value: String, source: FocusedTextSource
        if selection.length > 0 { value = text; source = .selection }
        else if count <= windowCharacters { value = text; source = .draft }
        else {
            let local = selection.location - retrieved.location
            guard local >= 0, local <= text.utf16.count else { return .init() }
            let ns = text as NSString
            let range = ns.paragraphRange(for:NSRange(location:local,length:0))
            // Never accept a paragraph clipped by either edge of a bounded observation.
            guard (range.location > 0 || retrieved.location == 0),
                  (NSMaxRange(range) < ns.length || NSMaxRange(retrieved) == count) else { return .init() }
            value = ns.substring(with:range); source = .paragraph
        }
        guard !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumBytes else { return .init() }
        return .init(text:value,source:source)
    }
}

// NotificationCenter owns only a counter closure, not the resolver. No window/text inspection.
final class TextFocusEpoch: @unchecked Sendable {
    private final class Counter: Sendable { let value = Mutex<UInt64>(0) }
    private let counter = Counter()
    private let center: NotificationCenter
    private var token: NSObjectProtocol?
    init(center: NotificationCenter) {
        self.center = center
        let counter = self.counter
        token = center.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { _ in counter.value.withLock { $0 &+= 1 } }
    }
    deinit { if let token { center.removeObserver(token) } }
    var current: UInt64 { counter.value.withLock { $0 } }
}

/// Read-only, user-gesture-scoped AX capture. No enumeration, text writes, key injection or pasteboard access.
@MainActor public final class NativeFocusedTextResolver: FocusedTextResolving {
    private let focusEpoch = TextFocusEpoch(center:NSWorkspace.shared.notificationCenter)
    private var reading = false
    public init() {}
    public func resolve(processID: Int32, allowUnselected: Bool) async -> FocusedTextResolution {
        guard !reading else { return .init(status:.busy,stage:.authorization) }
        guard AXIsProcessTrusted() else { return .init(status:.permissionRequired,stage:.authorization) }
        guard !IsSecureEventInputEnabled() else { return .init(status:.secure,stage:.authorization) }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == processID,
              let launch = app.launchDate else { return .init(status:.sourceChanged,stage:.focus) }
        guard !NativeEditorCapability.isConsole(app.bundleIdentifier) else { return .init(status:.unsupported,stage:.classification) }
        reading = true; defer { reading = false }
        let epoch = focusEpoch.current
        let worker = Task.detached(priority:.userInitiated) { Self.read(processID:processID,allowUnselected:allowUnselected) }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return .init(status:.cancelled,stage:.finished) }
        guard AXIsProcessTrusted() else { return .init(status:.permissionRequired,stage:.authorization) }
        guard !IsSecureEventInputEnabled() else { return .init(status:.secure,stage:.authorization) }
        guard focusEpoch.current == epoch, let current = NSWorkspace.shared.frontmostApplication,
              current.processIdentifier == processID, current.launchDate == launch else { return .init(status:.sourceChanged,stage:.focus) }
        return result
    }
    nonisolated private static func read(processID: Int32, allowUnselected: Bool) -> FocusedTextResolution {
        let deadline = ContinuousClock.now.advanced(by:.milliseconds(700))
        func unavailable(_ status: FocusedTextStatus = .unsupported, _ stage: FocusedTextStage) -> FocusedTextResolution {
            if Task.isCancelled { return .init(status:.cancelled,stage:stage) }
            if ContinuousClock.now >= deadline { return .init(status:.timedOut,stage:stage) }
            if !AXIsProcessTrusted() { return .init(status:.permissionRequired,stage:stage) }
            if IsSecureEventInputEnabled() { return .init(status:.secure,stage:stage) }
            return .init(status:status,stage:stage)
        }
        func permitted() -> Bool { !Task.isCancelled && ContinuousClock.now < deadline && AXIsProcessTrusted() && !IsSecureEventInputEnabled() }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard permitted() else { return nil }
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value : nil
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(value,to:AXUIElement.self)
        }
        func owner(_ e: AXUIElement) -> Bool { var pid: pid_t = 0; return AXUIElementGetPid(e,&pid) == .success && pid == processID }
        func range(_ raw: CFTypeRef?) -> CFRange? {
            guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            let value = unsafeDowncast(raw,to:AXValue.self)
            guard AXValueGetType(value) == .cfRange else { return nil }
            var result = CFRange(); return AXValueGetValue(value,.cfRange,&result) ? result : nil
        }
        let root = AXUIElementCreateApplication(processID)
        guard AXUIElementSetMessagingTimeout(root,0.08) == .success else { return unavailable(.unsupported,.focus) }
        guard let field = element(attribute(root,kAXFocusedUIElementAttribute)) else { return unavailable(.unsupported,.focus) }
        guard owner(field) else { return unavailable(.sourceChanged,.focus) }
        guard AXUIElementSetMessagingTimeout(field,0.08) == .success else { return unavailable(.unsupported,.focus) }
        var names: CFArray?
        guard permitted(), AXUIElementCopyAttributeNames(field,&names) == .success, let supported = names as? [String],
              supported.contains(kAXRoleAttribute), supported.contains(kAXSubroleAttribute),
              supported.contains(kAXSelectedTextRangeAttribute), supported.contains(kAXNumberOfCharactersAttribute) else { return unavailable(.unsupported,.attributes) }
        let role = attribute(field,kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(field,kAXSubroleAttribute) as? String
        let enabled = attribute(field,kAXEnabledAttribute) as? Bool
        let editable = supported.contains("AXEditable") ? attribute(field,"AXEditable") as? Bool : nil
        var writable: DarwinBoolean = false
        let writableValue = AXUIElementIsAttributeSettable(field,kAXValueAttribute as CFString,&writable) == .success && writable.boolValue
        writable = false
        let writableSelection = AXUIElementIsAttributeSettable(field,kAXSelectedTextAttribute as CFString,&writable) == .success && writable.boolValue
        let marked = range(attribute(field,"AXMarkedTextRange"))
        guard FocusedTextPolicy.eligible(role:role,subrole:subrole,enabled:enabled,editable:editable,writable:writableValue || writableSelection,marked:(marked?.length ?? 0) > 0),
              !supported.contains("AXEditable") || editable != nil else {
            return unavailable((subrole?.lowercased().contains("secure") == true || subrole?.lowercased().contains("password") == true || (marked?.length ?? 0) > 0) ? .secure : .unsupported,.classification)
        }
        // IME state is not uniformly exposed by AX: fail closed for non-ASCII-capable input sources.
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ascii = TISGetInputSourceProperty(source,kTISPropertyInputSourceIsASCIICapable),
              CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ascii).takeUnretainedValue()) else { return unavailable(.unsupported,.classification) }
        guard let count = focusedCharacterCount(attribute(field,kAXNumberOfCharactersAttribute)),
              let selected = range(attribute(field,kAXSelectedTextRangeAttribute)), selected.location >= 0, selected.length >= 0 else { return unavailable(.unsupported,.selection) }
        guard count > 0 else { return unavailable(.empty,.selection) }
        if selected.length == 0 && !allowUnselected { return unavailable(.disabled,.selection) }
        guard let requested = FocusedTextPolicy.select(count:count,selection:NSRange(location:selected.location,length:selected.length),allowUnselected:allowUnselected) else { return unavailable(.sizeLimit,.selection) }
        var parameterNames: CFArray?
        guard permitted() else { return unavailable(.timedOut,.attributes) }
        let parameterStatus = AXUIElementCopyParameterizedAttributeNames(field,&parameterNames)
        guard [.success,.attributeUnsupported,.parameterizedAttributeUnsupported,.notImplemented,.noValue].contains(parameterStatus) else { return unavailable(.unsupported,.parameterList) }
        let parameters = parameterNames as? [String] ?? []
        var readStage: FocusedTextStage = .rangeRead
        func readText() -> String? {
            var value: CFTypeRef?
            var rangeStatus: AXError = .attributeUnsupported
            if parameters.contains(kAXStringForRangeParameterizedAttribute) {
                var requestedRange = CFRange(location:requested.location,length:requested.length)
                guard let parameter = AXValueCreate(.cfRange,&requestedRange), permitted() else { return nil }
                readStage = .rangeRead
                rangeStatus = AXUIElementCopyParameterizedAttributeValue(field,kAXStringForRangeParameterizedAttribute as CFString,parameter,&value)
                if rangeStatus == .success { return value as? String }
            }
            let resolved = FocusedTextPolicy.readBounded(rangeStatus:rangeStatus,rangeText:nil,selectionLength:selected.length,count:count,selected:{
                permitted() && supported.contains(kAXSelectedTextAttribute) ? attribute(field,kAXSelectedTextAttribute) as? String : nil
            },value:{
                permitted() && supported.contains(kAXValueAttribute) ? attribute(field,kAXValueAttribute) as? String : nil
            })
            readStage = resolved.stage
            return resolved.text
        }

        let result = readText()
        guard let result else { return unavailable(.unsupported,readStage) }
        guard result.utf8.count <= 4096 else { return unavailable(.sizeLimit,readStage) }
        guard permitted(), readText() == result, owner(field),
              let current = element(attribute(root,kAXFocusedUIElementAttribute)), CFEqual(current,field),
              focusedCharacterCount(attribute(field,kAXNumberOfCharactersAttribute)) == count,
              let finalRange = range(attribute(field,kAXSelectedTextRangeAttribute)), finalRange.location == selected.location, finalRange.length == selected.length else { return unavailable(.sourceChanged,.consistency) }
        guard permitted(), let finalSubrole = attribute(field,kAXSubroleAttribute) as? String else { return unavailable(.sourceChanged,.consistency) }
        guard !finalSubrole.lowercased().contains("secure"), !finalSubrole.lowercased().contains("password"),
              (range(attribute(field,"AXMarkedTextRange"))?.length ?? 0) == 0 else { return unavailable(.secure,.consistency) }
        guard result.utf16.count == requested.length else { return unavailable(.unsupported,.consistency) }
        let resolved = FocusedTextPolicy.resolve(text:result,count:count,selection:NSRange(location:selected.location,length:selected.length),retrieved:requested)
        return resolved.text.isEmpty ? unavailable(result.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? .empty : .sizeLimit,readStage) : .init(text:resolved.text,source:resolved.source,stage:readStage)
    }
}

// Avoid bridging bools/NaN/fractional values as character counts.
nonisolated private func focusedCharacterCount(_ raw: CFTypeRef?) -> Int? {
    guard let raw, CFGetTypeID(raw) == CFNumberGetTypeID(), let number = raw as? NSNumber,
          let count = Int(exactly:number.doubleValue), count >= 0 else { return nil }
    return count
}
