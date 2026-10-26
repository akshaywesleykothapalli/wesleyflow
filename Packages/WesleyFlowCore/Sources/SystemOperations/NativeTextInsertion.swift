import Domain
import AppKit
import ApplicationServices
import Carbon

/// Read-only application/system observations must identify the same bound process.
@MainActor enum NativeFocusedElementResolver {
    static func resolve<Element>(processID: Int32, application: () -> Element?, system: () -> Element?, window: () -> Element? = { nil }, owner: (Element) -> Int32?) throws -> Element {
        if let element = application() {
            guard owner(element) == processID else { throw TextTargetError.changed }; return element
        }
        guard let element = system() ?? window() else { throw TextTargetError.unsupported }
        guard owner(element) == processID else { throw TextTargetError.changed }; return element
    }
}

/// Read existing focus metadata only, with explicit node/depth limits. Never guess a field.
@MainActor enum FocusedDescendantSearch {
    static func find<Element>(root: Element, limit: Int = 64, maximumDepth: Int = 8,
                             permitted: () -> Bool = { true }, focusedEditor: (Element) -> Bool,
                             children: (Element,Int) -> [Element]) -> Element? {
        guard limit > 0, limit <= 64, maximumDepth >= 0, maximumDepth <= 8 else { return nil }
        var queue: [(Element,Int)] = [(root,0)], index = 0
        while index < queue.count, permitted() {
            let (element,depth) = queue[index]; index += 1
            if focusedEditor(element) { return element }
            let remaining = limit-queue.count
            if depth < maximumDepth, remaining > 0 {
                queue.append(contentsOf:children(element,remaining).prefix(remaining).map { ($0,depth+1) })
            }
        }
        return nil
    }
}

/// Alternate read-only text representations; never substitute a partial/truncated field.
@MainActor enum NativeFieldTextReader {
    static func read(maximumBytes: Int, value: () -> String?, characterCount: () -> Int?, range: (Int) -> String?, attributedRange: (Int) -> String? = { _ in nil }, failure: (String) -> Void = { _ in }) -> String? {
        func reject(_ message: String) -> String? { failure(message); return nil }
        guard maximumBytes >= 0 else { return reject("Text inspection has an invalid size limit. No paste was attempted.") }
        if let text = value() {
            return text.utf8.count <= maximumBytes ? text : reject("The editor's text exceeds the supported size limit. No paste was attempted.")
        }
        guard let count = characterCount() else { return reject("The editor exposes neither a readable text value nor its character count. No paste was attempted. Copy from History.") }
        guard count >= 0, count <= maximumBytes else { return reject("The editor reports an invalid or oversized character count. No paste was attempted.") }
        // A successfully reported zero character count proves emptiness. Missing data does not.
        if count == 0 { return "" }
        guard let text = range(count) ?? attributedRange(count) else { return reject("The editor provides no text through either supported range reader. No paste was attempted. Copy from History.") }
        guard text.utf16.count == count, text.utf8.count <= maximumBytes else { return reject("The editor returned incomplete or oversized text. No paste was attempted. Copy from History.") }
        return text
    }
    static func plainAttributedText(_ value: CFTypeRef?) -> String? {
        guard let value, CFGetTypeID(value) == CFAttributedStringGetTypeID() else { return nil }
        return CFAttributedStringGetString(unsafeDowncast(value,to:CFAttributedString.self)) as String
    }
    static func characterCount(_ value: CFTypeRef?) -> Int? {
        guard let value, CFGetTypeID(value) == CFNumberGetTypeID(),
              let number = value as? NSNumber else { return nil }
        return Int(exactly:number.doubleValue)
    }
}

/// AX text mutation and caret selection are distinct capabilities. A paste-only
/// editor must still provide complete text/range observations for verification.
enum NativeEditorCapability {
    static func accepts(enabled: Bool?, editable: Bool?, writableText: Bool, writableSelection: Bool, console: Bool) -> Bool {
        guard enabled != false, editable != false else { return false }
        if editable == true || writableText { return true }
        return !console && writableSelection
    }
    /// Installed ChatGPT-branded app identity, verified from its bundle metadata.
    /// Choose paste before any attempt; never retry an uncertain direct update.
    static func allowsDirectTextReplacement(_ bundleIdentifier: String?) -> Bool { bundleIdentifier != "com.openai.codex" }
    static func allowsAutomaticInsertion(_ bundleIdentifier: String?) -> Bool { bundleIdentifier != "com.apple.Terminal" }
    static func isConsole(_ bundleIdentifier: String?) -> Bool {
        ["com.apple.Terminal","com.googlecode.iterm2"].contains(bundleIdentifier ?? "")
    }
}

@MainActor public enum DictationAccess {
    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    public static func requestAccessibility() -> Bool { AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary) }
}
@MainActor public final class NativeInsertionTargetCapture: InsertionTargetCapturing {
    public private(set) var failureExplanation: String?
    public init() {}
    public func capture(session: String) throws -> any InsertionTarget {
        failureExplanation = nil
        let target = try NativeInsertionTarget(session:session,reportStage:{ self.failureExplanation = $0 })
        failureExplanation = nil; return target
    }
}
@MainActor private final class NativeInsertionTarget: InsertionTarget {
    let info: InsertionTargetInfo
    let original: TargetTextState
    private let application: NSRunningApplication
    private let launch: Date
    private let window: AXUIElement
    private let element: AXUIElement
    private let created = ContinuousClock.now
    init(session: String, reportStage: (String) -> Void) throws {
        reportStage("Accessibility access is required for insertion. Your transcript remains available for copy.")
        guard AXIsProcessTrusted() else { throw TextTargetError.denied }
        reportStage("Secure input is excluded. Nothing was inserted.")
        guard !IsSecureEventInputEnabled() else { throw TextTargetError.secure }
        reportStage("The original application could not be identified safely. Copy the transcript from History.")
        guard let application = NSWorkspace.shared.frontmostApplication, let launch = application.launchDate else { throw TextTargetError.unsupported }
        if !NativeEditorCapability.allowsAutomaticInsertion(application.bundleIdentifier) {
            reportStage("Apple Terminal is set to manual-copy only. Your transcript will be available in History; no input is sent to Terminal.")
            throw TextTargetError.unsupported
        }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.2)
        reportStage("The app does not expose a focused window. Copy the transcript from History.")
        guard let window = Self.elementAttribute(root,kAXFocusedWindowAttribute) else { throw TextTargetError.unsupported }
        reportStage("The app does not expose a focused text field. Copy the transcript from History.")
        let element = try Self.focusedElement(root,processID:application.processIdentifier)
        AXUIElementSetMessagingTimeout(element,0.2)
        let role = Self.attribute(element,kAXRoleAttribute) as? String ?? ""
        let subrole = Self.attribute(element,kAXSubroleAttribute) as? String ?? ""
        guard subrole != kAXSecureTextFieldSubrole, !subrole.lowercased().contains("secure") else { throw TextTargetError.secure }
        reportStage("The focused control is not a supported text field. Click inside the editor before holding Fn. Copy this transcript from History.")
        guard [kAXTextAreaRole,kAXTextFieldRole,kAXComboBoxRole].contains(role) else { throw TextTargetError.unsupported }
        let console = NativeEditorCapability.isConsole(application.bundleIdentifier)
        let capability = Self.editable(element,console:console)
        reportStage(console ? "The terminal exposes its screen rather than a verified editable field. Automatic insertion was skipped; your transcript is available in History." : "The focused area reports read-only, disabled, or no writable text/caret interface. Automatic insertion was skipped; copy from History.")
        guard capability else { throw TextTargetError.unsupported }
        reportStage("The field does not expose readable text within the supported size limit. Copy the transcript from History.")
        guard let text = Self.readText(element,maximumBytes:65_536,failure:reportStage) else { throw TextTargetError.unsupported }
        reportStage("The field does not expose a readable caret or selection. Copy the transcript from History.")
        guard let rawRange = Self.attribute(element,kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else { throw TextTargetError.unsupported }
        let value = unsafeDowncast(rawRange,to:AXValue.self)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value,.cfRange,&range) else { throw TextTargetError.unsupported }
        let selection = TextSelection(location:range.location,length:range.length)
        guard selection.replacing(in:text,with:"") != nil else { throw TextTargetError.unsupported }
        self.application = application; self.launch = launch; self.window = window; self.element = element
        original = .init(text:text,selection:selection)
        info = .init(session:session,applicationName:String((application.localizedName ?? "Application").prefix(64)),processID:application.processIdentifier,
                     windowIdentity:UUID().uuidString,elementIdentity:UUID().uuidString,role:role)
    }
    private static func attribute(_ element: AXUIElement,_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value : nil
    }
    private static func elementAttribute(_ element: AXUIElement,_ name: String) -> AXUIElement? {
        guard let value = attribute(element,name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value,to:AXUIElement.self)
    }
    private static func readText(_ element: AXUIElement, maximumBytes: Int, failure: (String) -> Void = { _ in }) -> String? {
        NativeFieldTextReader.read(maximumBytes:maximumBytes,value:{ attribute(element,kAXValueAttribute) as? String },characterCount:{
            NativeFieldTextReader.characterCount(attribute(element,kAXNumberOfCharactersAttribute))
        },range:{ count in
            var range = CFRange(location:0,length:count), result: CFTypeRef?
            guard let parameter = AXValueCreate(.cfRange,&range),
                  AXUIElementCopyParameterizedAttributeValue(element,kAXStringForRangeParameterizedAttribute as CFString,parameter,&result) == .success else { return nil }
            return result as? String
        },attributedRange:{ count in
            var range = CFRange(location:0,length:count), result: CFTypeRef?
            guard let parameter = AXValueCreate(.cfRange,&range),
                  AXUIElementCopyParameterizedAttributeValue(element,kAXAttributedStringForRangeParameterizedAttribute as CFString,parameter,&result) == .success,
                  let result else { return nil }
            return NativeFieldTextReader.plainAttributedText(result)
        },failure:failure)
    }
    private static func focusedElement(_ root: AXUIElement, processID: Int32) throws -> AXUIElement {
        try NativeFocusedElementResolver.resolve(processID:processID,application:{ elementAttribute(root,kAXFocusedUIElementAttribute) },system:{
            let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system,0.2)
            return elementAttribute(system,kAXFocusedUIElementAttribute)
        },window:{
            guard let window = elementAttribute(root,kAXFocusedWindowAttribute) else { return nil }
            let deadline = ContinuousClock.now.advanced(by:.milliseconds(250))
            return FocusedDescendantSearch.find(root:window,permitted:{ ContinuousClock.now < deadline && AXIsProcessTrusted() },focusedEditor:{ element in
                AXUIElementSetMessagingTimeout(element,0.05)
                guard (attribute(element,kAXFocusedAttribute) as? Bool) == true,
                      let role = attribute(element,kAXRoleAttribute) as? String else { return false }
                return [kAXTextAreaRole,kAXTextFieldRole,kAXComboBoxRole].contains(role)
            },children:{ element,remaining in
                var count: CFIndex = 0, values: CFArray?
                guard AXUIElementGetAttributeValueCount(element,kAXChildrenAttribute as CFString,&count) == .success,
                      count > 0,
                      AXUIElementCopyAttributeValues(element,kAXChildrenAttribute as CFString,0,min(count,remaining),&values) == .success,
                      let values = values as? [AXUIElement] else { return [] }
                return values
            })
        },owner:{ element in
            var pid: pid_t = 0
            return AXUIElementGetPid(element,&pid) == .success ? pid : nil
        })
    }
    private static func editable(_ element: AXUIElement, console: Bool) -> Bool {
        func settable(_ name: String) -> Bool {
            var value = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element,name as CFString,&value) == .success && value.boolValue
        }
        return NativeEditorCapability.accepts(enabled:attribute(element,kAXEnabledAttribute) as? Bool,
            editable:attribute(element,"AXEditable") as? Bool,
            writableText:settable(kAXSelectedTextAttribute) || settable(kAXValueAttribute),
            writableSelection:settable(kAXSelectedTextRangeAttribute),console:console)
    }
    private func validateIdentity() throws {
        guard AXIsProcessTrusted() else { throw TextTargetError.denied }
        guard !IsSecureEventInputEnabled(), (Self.attribute(element,kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole else { throw TextTargetError.secure }
        guard NativeEditorCapability.allowsAutomaticInsertion(application.bundleIdentifier), Self.editable(element,console:NativeEditorCapability.isConsole(application.bundleIdentifier)) else { throw TextTargetError.unsupported }
        guard created.duration(to:.now) < .seconds(120), !application.isTerminated,
              let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == application.processIdentifier, front.launchDate == launch else { throw TextTargetError.changed }
        let root = AXUIElementCreateApplication(application.processIdentifier); AXUIElementSetMessagingTimeout(root,0.2)
        guard let focusedWindow = Self.elementAttribute(root,kAXFocusedWindowAttribute), CFEqual(focusedWindow,window),
              let focused = try? Self.focusedElement(root,processID:application.processIdentifier), CFEqual(focused,element) else { throw TextTargetError.changed }
    }
    func validate() throws {
        try validateIdentity()
        guard observedText() == original.text,
              let raw = Self.attribute(element,kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { throw TextTargetError.changed }
        var range = CFRange(); let value = unsafeDowncast(raw,to:AXValue.self)
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value,.cfRange,&range),
              range.location == original.selection.location, range.length == original.selection.length else { throw TextTargetError.changed }
    }
    func postText(_ text: String, budgetMilliseconds: Int64) -> Bool {
        guard !NativeEditorCapability.isConsole(application.bundleIdentifier), budgetMilliseconds > 0, budgetMilliseconds <= 1500 else { return false }
        let deadline = ContinuousClock.now.advanced(by:.milliseconds(budgetMilliseconds))
        guard let events = NativeUnicodeKeystrokes.make(text), !Task.isCancelled,
              (try? validate()) != nil, ContinuousClock.now < deadline else { return false }
        return NativeBoundTextDelivery.dispatch(count:events.count,permitted:{
            !Task.isCancelled && ContinuousClock.now < deadline && (try? self.validateIdentity()) != nil && ContinuousClock.now < deadline
        },send:{ index in
            events[index].0.postToPid(self.application.processIdentifier)
            events[index].1.postToPid(self.application.processIdentifier)
        })
    }
    func canReplaceSelection() -> Bool {
        guard NativeEditorCapability.allowsDirectTextReplacement(application.bundleIdentifier) else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element,kAXSelectedTextAttribute as CFString,&settable) == .success && settable.boolValue
    }
    func replaceSelection(_ text: String) throws {
        try validate()
        guard canReplaceSelection(), AXUIElementSetAttributeValue(element,kAXSelectedTextAttribute as CFString,text as CFString) == .success else { throw TextTargetError.unsupported }
    }
    func observedText() -> String? {
        guard AXIsProcessTrusted(), !application.isTerminated,
              (Self.attribute(element,kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole,
              let value = Self.readText(element,maximumBytes:98_304) else { return nil }
        return value
    }
    func postPaste(whileClipboardOwned: () -> Bool) throws {
        try validate()
        let events = try NativePasteKeystrokes.make()
        guard whileClipboardOwned() else { throw TextTargetError.clipboardChanged }
        events.forEach { $0.postToPid(application.processIdentifier) }
    }
}
/// Testable dispatch fence: no input before validation; balanced pairs stop on loss.
@MainActor enum NativeBoundTextDelivery {
    static func dispatch(count: Int, permitted: () -> Bool, send: (Int) -> Void) -> Bool {
        guard count > 0, count <= 256 else { return false }
        var attempted = false
        for index in 0..<count {
            guard permitted() else { return attempted }
            attempted = true; send(index)
        }
        return attempted
    }
}
/// Bounded plain-text events for verified editors only; tests construct but never post.
enum NativeUnicodeKeystrokes {
    static func make(_ text: String) -> [(CGEvent,CGEvent)]? {
        guard !text.isEmpty, text.utf8.count <= 4096,
              text.unicodeScalars.allSatisfy({ ![Unicode.GeneralCategory.control,.lineSeparator,.paragraphSeparator].contains($0.properties.generalCategory) }),
              let source = CGEventSource(stateID:.privateState) else { return nil }
        var chunks: [[UniChar]] = [], current: [UniChar] = []
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if current.count+units.count > 16 { chunks.append(current); current = [] }
            current.append(contentsOf:units)
        }
        if !current.isEmpty { chunks.append(current) }
        var result: [(CGEvent,CGEvent)] = []
        for units in chunks {
            guard let down = CGEvent(keyboardEventSource:source,virtualKey:0,keyDown:true),
                  let up = CGEvent(keyboardEventSource:source,virtualKey:0,keyDown:false) else { return nil }
            down.flags = []; up.flags = []
            down.setIntegerValueField(.keyboardEventAutorepeat,value:0)
            up.setIntegerValueField(.keyboardEventAutorepeat,value:0)
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
            }
            result.append((down,up))
        }
        return result
    }
}
/// Construction is independently testable without posting any event. No Return/Enter exists.
enum NativePasteKeystrokes {
    static func make() throws -> [CGEvent] {
        guard let down = CGEvent(keyboardEventSource:nil,virtualKey:9,keyDown:true),
              let up = CGEvent(keyboardEventSource:nil,virtualKey:9,keyDown:false) else { throw TextTargetError.unsupported }
        down.flags = .maskCommand; up.flags = .maskCommand; return [down,up]
    }
}
@MainActor public final class NativeDictationPasteboard: DictationPasteboard {
    public private(set) var snapshotFailureExplanation: String?
    private let pasteboard: NSPasteboard
    private let publish: @MainActor ([NSPasteboardItem]) -> Bool
    private var emptyLease: (ownership:ClipboardOwnership,count:Int)?
    private static let marker = NSPasteboard.PasteboardType("local.wesleyflow.dictation-owner")
    private static let supported: Set<String> = [NSPasteboard.PasteboardType.string.rawValue,NSPasteboard.PasteboardType.html.rawValue,NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.png.rawValue,NSPasteboard.PasteboardType.tiff.rawValue,NSPasteboard.PasteboardType.URL.rawValue,NSPasteboard.PasteboardType.fileURL.rawValue,
        "public.utf16-external-plain-text","public.utf16-plain-text","public.jpeg",marker.rawValue]
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard; publish = { pasteboard.writeObjects($0) } }
    init(pasteboard: NSPasteboard, publication: @escaping @MainActor ([NSPasteboardItem]) -> Bool) {
        self.pasteboard = pasteboard; publish = publication
    }
    public func snapshot() throws -> ClipboardSnapshot {
        snapshotFailureExplanation = nil
        func reject(_ explanation: String) throws -> Never {
            snapshotFailureExplanation = explanation; throw TextTargetError.unsupported
        }
        let count = pasteboard.changeCount, source = pasteboard.pasteboardItems ?? []
        guard source.count <= 16 else { try reject("The clipboard has more than16 items. It was preserved; copy ordinary text before retrying dictation.") }
        var bytes = 0; var items: [[String:[UInt8]]] = []
        for item in source {
            guard item.types.count <= 16 else { try reject("The clipboard has too many representations. It was preserved; copy ordinary text before retrying dictation.") }
            var representations: [String:[UInt8]] = [:]
            for type in item.types {
                guard Self.supported.contains(type.rawValue) else {
                    // A format name is diagnostic metadata, not its potentially private payload.
                    let name = String(type.rawValue.unicodeScalars.filter { CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"._-")).contains($0) }.prefix(96))
                    try reject("Clipboard format ‘\(name)’ cannot be safely backed up. No paste was attempted and the clipboard was preserved. Copy ordinary text before retrying.")
                }
                guard let data = item.data(forType:type) else { try reject("A clipboard representation is unavailable. The clipboard was preserved; copy ordinary text before retrying.") }
                guard data.count <= 1_048_576 - bytes else { try reject("The clipboard exceeds the1 MiB backup limit. It was preserved; copy a short ordinary text item before retrying.") }
                if type == Self.marker {
                    guard data.count <= 64, let token = String(data:data,encoding:.utf8), UUID(uuidString:token) != nil else {
                        try reject("The clipboard has an invalid Wesley Flow marker. It was preserved; copy ordinary text before retrying.")
                    }
                }
                bytes += data.count; representations[type.rawValue] = Array(data)
            }
            items.append(representations)
        }
        guard pasteboard.changeCount == count else { throw TextTargetError.changed }
        return .init(changeCount:count,items:items)
    }
    public func owns(_ ownership: ClipboardOwnership) -> Bool {
        if let lease = emptyLease, lease.ownership == ownership, pasteboard.changeCount == lease.count, (pasteboard.pasteboardItems ?? []).isEmpty { return true }
        return pasteboard.changeCount == ownership.changeCount && pasteboard.string(forType:Self.marker) == ownership.token
    }
    public func isSuperseded(_ ownership: ClipboardOwnership) -> Bool {
        let expectedCount = emptyLease.flatMap { $0.ownership == ownership ? $0.count : nil } ?? ownership.changeCount
        return pasteboard.changeCount != expectedCount
    }
    public func install(_ text: String, replacing snapshot: ClipboardSnapshot) throws -> ClipboardOwnership {
        let token = UUID().uuidString, item = NSPasteboardItem()
        item.setString(text,forType:.string); item.setString(token,forType:Self.marker)
        guard pasteboard.changeCount == snapshot.changeCount else { throw TextTargetError.changed }
        let cleared = pasteboard.clearContents()
        guard pasteboard.changeCount == cleared else { throw TextTargetError.changed }
        guard publish([item]) else {
            let lease = ClipboardOwnership(changeCount:cleared,token:token)
            if pasteboard.changeCount == cleared { emptyLease = (lease,cleared) }
            throw ClipboardPublicationFailure(ownership:lease)
        }
        emptyLease = nil
        let ownership = ClipboardOwnership(changeCount:pasteboard.changeCount,token:token)
        guard owns(ownership) else { throw TextTargetError.changed }; return ownership
    }
    public func restore(_ snapshot: ClipboardSnapshot, ifOwned ownership: ClipboardOwnership) -> ClipboardRestoration {
        let items = snapshot.items.map { source in
            let item = NSPasteboardItem(); for (type,bytes) in source { item.setData(Data(bytes),forType:.init(type)) }; return item
        }
        guard owns(ownership) else { return isSuperseded(ownership) ? .preservedNewer : .unavailable }
        let cleared = pasteboard.clearContents()
        guard pasteboard.changeCount == cleared else { return .preservedNewer }
        if items.isEmpty { emptyLease = nil; return .restored }
        if publish(items) { emptyLease = nil; return .restored }
        if pasteboard.changeCount == cleared { emptyLease = (ownership,cleared); return .unavailable }
        emptyLease = nil; return .preservedNewer
    }
}
