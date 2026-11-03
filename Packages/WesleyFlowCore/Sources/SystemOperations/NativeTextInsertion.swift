import Domain
import AppKit
import ApplicationServices
import Carbon
import CryptoKit
import Synchronization

/// Read-only application/system observations must identify the same bound process.
@MainActor enum NativeFocusedElementResolver {
    static func resolve<Element>(processID:Int32,application:()throws->Element?,system:()throws->Element?,window:()throws->Element? = { nil },owner:(Element)->Int32?,isEditor:(Element)throws->Bool = { _ in true }) throws -> Element {
        // A same-process container is not necessarily the editable composer.
        // Foreign ownership/secure controls fail closed; no fallback retargeting.
        if let element = try application() {
            guard owner(element) == processID else { throw TextTargetError.changed }
            if try isEditor(element) { return element }
        }
        if let element = try system() {
            guard owner(element) == processID else { throw TextTargetError.changed }
            if try isEditor(element) { return element }
        }
        if let element = try window() {
            guard owner(element) == processID else { throw TextTargetError.changed }
            if try isEditor(element) { return element }
        }
        throw TextTargetError.unsupported
    }
}

/// Read existing focus metadata only, with explicit node/depth limits. Never guess a field.
@MainActor enum FocusedDescendantSearch {
    static func find<Element>(root: Element, limit: Int = 64, maximumDepth: Int = 8,
                             permitted: () -> Bool = { true }, focusedEditor: (Element) -> Bool,
                             children: (Element,Int) -> [Element]) -> Element? {
        guard limit > 0, limit <= 256, maximumDepth >= 0, maximumDepth <= 16 else { return nil }
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
    static func plainTextValue(_ value:CFTypeRef?) -> String? { (value as? String) ?? plainAttributedText(value) }
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

/// Pure classification of actual AX response codes; never uses app names.
enum NativeReadbackFailureClassifier {
    static func classify(_ errors:[Int32]) -> InsertionReadbackFailure {
        if errors.contains(AXError.apiDisabled.rawValue) { return .denied }
        if errors.contains(AXError.invalidUIElement.rawValue) { return .targetChanged }
        if errors.contains(AXError.cannotComplete.rawValue) || errors.contains(AXError.noValue.rawValue) { return .temporarilyUnavailable }
        if errors.contains(AXError.parameterizedAttributeUnsupported.rawValue) { return .rangeUnavailable }
        if errors.contains(AXError.attributeUnsupported.rawValue) { return .unsupported }
        return .rangeInvalid
    }
}

/// Only thrown after AX mutation was dispatched and returned a non-success
/// acknowledgement. The broker may observe; it must never resend the write.
enum DirectTextUpdateFailure: Error { case dispatchUnconfirmed }

/// AX text mutation and caret selection are distinct capabilities. A paste-only
/// editor needs complete text/range observations only for exact verification.
enum NativeEditorCapability {
    static func accepts(enabled: Bool?, editable: Bool?, writableText: Bool, writableSelection: Bool, console: Bool) -> Bool {
        guard enabled != false, editable != false else { return false }
        if editable == true || writableText { return true }
        return !console && writableSelection
    }
    static func allowsIdentityOnlyPaste(enabled:Bool?,editable:Bool?,writableText:Bool,console:Bool,secure:Bool = false) -> Bool {
        guard enabled != false, editable != false, !console, !secure else { return false }
        return editable == true || writableText
    }
    /// Ordinary initial insertion retains its existing paste-only exception.
    /// A later exact selected-span rewrite is checked independently.
    static func requiresGuardedPaste(_ bundleIdentifier:String?) -> Bool { bundleIdentifier == "com.openai.codex" }
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
    public private(set) var captureBundleIdentifier:String?
    public private(set) var captureDiagnostics:[InsertionVerificationDiagnostic] = []
    private func record(_ value:InsertionVerificationDiagnostic) {
        if captureDiagnostics.count == 24 { captureDiagnostics.removeFirst() }
        captureDiagnostics.append(value)
    }
    public private(set) var observedApplicationIdentity:DictationApplicationIdentity?
    public init() {}
    public func capture(session:String,activation:DictationActivationContext) throws -> any InsertionTarget { try captureBound(session:session,activation:activation) }
    public func capture(session: String) throws -> any InsertionTarget { try captureBound(session:session,activation:nil) }
    private func captureBound(session:String,activation:DictationActivationContext?) throws -> any InsertionTarget {
        failureExplanation = nil; captureDiagnostics = []
        let originatingApplication = NSWorkspace.shared.frontmostApplication
        observedApplicationIdentity = originatingApplication.flatMap { app in app.launchDate.map { DictationApplicationIdentity(processID:app.processIdentifier,launchTime:$0.timeIntervalSinceReferenceDate,bundleIdentifier:app.bundleIdentifier) } }
        captureBundleIdentifier = activation?.application?.bundleIdentifier ?? originatingApplication?.bundleIdentifier
        if let activation, !activation.permits(observedApplicationIdentity) {
            failureExplanation = "The app identity at the dictation press changed or could not be verified before target capture. Nothing was redirected. The transcript will remain available for explicit copy."
            record(.init(.target,.targetChanged,.failure))
            throw TextTargetError.changed
        }
        do {
            let target = try NativeInsertionTarget(session:session,application:originatingApplication,reportStage:{ self.failureExplanation = $0 },reportDiagnostic:record)
            failureExplanation = nil; return target
        } catch {
            let code:InsertionVerificationDiagnostic.Code = switch error {
            case TextTargetError.denied: .readbackDenied
            case TextTargetError.changed: .targetChanged
            default: .captureFailed
            }
            record(.init(.target,code,.failure)); throw error
        }
    }
}
@MainActor private final class NativeInsertionTarget: ClipboardFreeInsertionTarget, DictationRewriteAnchorProviding {
    let info: InsertionTargetInfo
    let original: TargetTextState?
    private let initialSelection:TextSelection?
    private let identityOnlyEditable:Bool
    private let focusEpoch = TextFocusEpoch(center:NSWorkspace.shared.notificationCenter)
    let replacementCapability:EditorReplacementCapability
    private let application: NSRunningApplication
    private let launch: Date
    private let window: AXUIElement
    private let element: AXUIElement
    private let created = ContinuousClock.now
    private(set) var insertionDiagnostics:[InsertionVerificationDiagnostic] = []
    private func recordInsertion(_ value:InsertionVerificationDiagnostic) {
        if insertionDiagnostics.count == 32 { insertionDiagnostics.remove(at:4) }
        insertionDiagnostics.append(value)
    }
    init(session: String, application:NSRunningApplication?, reportStage: (String) -> Void, reportDiagnostic:(InsertionVerificationDiagnostic)->Void) throws {
        reportStage("Accessibility access is required for insertion. Your transcript remains available for copy.")
        guard AXIsProcessTrusted() else { throw TextTargetError.denied }
        reportStage("Secure input is excluded. Nothing was inserted.")
        guard !IsSecureEventInputEnabled() else { throw TextTargetError.secure }
        reportStage("The original application could not be identified safely. Copy the transcript from History.")
        guard let application, let launch = application.launchDate else { throw TextTargetError.unsupported }
        if !NativeEditorCapability.allowsAutomaticInsertion(application.bundleIdentifier) {
            reportStage("Apple Terminal is set to manual-copy only. Your transcript will be available in History; no input is sent to Terminal.")
            throw TextTargetError.unsupported
        }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.2)
        reportStage("The app does not expose a focused window. Copy the transcript from History.")
        let window = try Self.focusElementAttribute(root,kAXFocusedWindowAttribute,code:.focusedWindow,record:reportDiagnostic)
        guard let window else { throw TextTargetError.unsupported }
        reportStage("The app does not expose a focused text field. Copy the transcript from History.")
        let element = try Self.focusedElement(root,processID:application.processIdentifier,record:reportDiagnostic)
        AXUIElementSetMessagingTimeout(element,0.2)
        let role = Self.attribute(element,kAXRoleAttribute) as? String ?? ""
        let subrole = Self.attribute(element,kAXSubroleAttribute) as? String ?? ""
        guard subrole != kAXSecureTextFieldSubrole, !subrole.lowercased().contains("secure") else { throw TextTargetError.secure }
        reportStage("The focused control is not a supported text field. Click inside the editor before holding Fn. Copy this transcript from History.")
        let supportedRole = [kAXTextAreaRole,kAXTextFieldRole,kAXComboBoxRole].contains(role)
        reportDiagnostic(.init(.target,.roleSupported,supportedRole ? .success : .unsupported))
        reportDiagnostic(.init(.target,.subroleKnown,subrole.isEmpty ? .unsupported : .success))
        guard supportedRole else { throw TextTargetError.unsupported }
        let console = NativeEditorCapability.isConsole(application.bundleIdentifier)
        let capability = Self.editable(element,console:console)
        reportStage(console ? "The terminal exposes its screen rather than a verified editable field. Automatic insertion was skipped; your transcript is available in History." : "The focused area reports read-only, disabled, or no writable text/caret interface. Automatic insertion was skipped; copy from History.")
        guard capability else { throw TextTargetError.unsupported }
        // Exact text and caret are optional for ordinary paste. They remain
        // mandatory for independently verified completion and AI authority.
        var initialReadErrors:[Int32] = []
        let text = Self.readText(element,maximumBytes:65_536,record:{ diagnostic in
            reportDiagnostic(diagnostic)
            if let error = diagnostic.axError, error != 0 { initialReadErrors.append(error) }
        })
        // Explicit denial or a dead element is not missing readback support.
        if initialReadErrors.contains(AXError.apiDisabled.rawValue) { throw TextTargetError.denied }
        if initialReadErrors.contains(AXError.invalidUIElement.rawValue) { throw TextTargetError.changed }
        var rawRange:CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(element,kAXSelectedTextRangeAttribute as CFString,&rawRange)
        reportDiagnostic(.init(.selection,.axSelectedRange,rangeError == .success ? .success : .unsupported,axError:rangeError.rawValue))
        if rangeError == .apiDisabled { throw TextTargetError.denied }
        if rangeError == .invalidUIElement { throw TextTargetError.changed }
        var selection:TextSelection?
        if rangeError == .success, let rawRange, CFGetTypeID(rawRange) == AXValueGetTypeID() {
            var range = CFRange(); let value = unsafeDowncast(rawRange,to:AXValue.self)
            guard AXValueGetType(value) == .cfRange, AXValueGetValue(value,.cfRange,&range),range.location >= 0,range.length >= 0 else { throw TextTargetError.unsupported }
            selection = .init(location:range.location,length:range.length)
        }
        if let text, let selection {
            guard selection.replacing(in:text,with:"") != nil else { reportDiagnostic(.init(.selection,.rangeInvalid,.failure,range:selection)); throw TextTargetError.unsupported }
            original = .init(text:text,selection:selection)
        } else { original = nil }
        initialSelection = selection
        // A selectable read-only conversation is not enough for an opaque target.
        // Require affirmative editability or an advertised writable text API.
        func textSettable(_ name:String) -> Bool {
            var result = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element,name as CFString,&result) == .success && result.boolValue
        }
        identityOnlyEditable = NativeEditorCapability.allowsIdentityOnlyPaste(enabled:Self.attribute(element,kAXEnabledAttribute) as? Bool,editable:Self.attribute(element,"AXEditable") as? Bool,writableText:textSettable(kAXSelectedTextAttribute) || textSettable(kAXValueAttribute),console:console)
        guard original != nil || identityOnlyEditable else {
            reportStage("This control does not affirm editable input. No automatic paste is allowed; the transcript remains for copy.")
            throw TextTargetError.unsupported
        }
        if original == nil { reportDiagnostic(.init(.target,.identityOnly,.success)); reportDiagnostic(.init(.readback,.initialReadbackUnavailable,.unsupported)) }
        func writable(_ name:String,_ code:InsertionVerificationDiagnostic.Code) -> Bool? {
            var writable = DarwinBoolean(false)
            let error = AXUIElementIsAttributeSettable(element,name as CFString,&writable)
            reportDiagnostic(.init(.selection,code,error == .success ? (writable.boolValue ? .success : .unsupported) : .failure,axError:error.rawValue))
            return error == .success ? writable.boolValue : nil
        }
        let textWritable = writable(kAXSelectedTextAttribute,.selectedTextWritable)
        let rangeWritable = writable(kAXSelectedTextRangeAttribute,.selectionWritable)
        if textWritable == false || rangeWritable == false { replacementCapability = .unavailable }
        else if textWritable == true && rangeWritable == true { replacementCapability = .available }
        else { replacementCapability = .unknown }
        reportDiagnostic(.init(.selection,.replacementCapability,replacementCapability == .available ? .success : (replacementCapability == .unavailable ? .unsupported : .pending)))
        self.application = application; self.launch = launch; self.window = window; self.element = element
        info = .init(session:session,applicationName:String((application.localizedName ?? "Application").prefix(64)),processID:application.processIdentifier,
                     windowIdentity:UUID().uuidString,elementIdentity:UUID().uuidString,role:role,bundleIdentifier:application.bundleIdentifier)
        recordInsertion(.init(.target,.targetAcquired,.success))
        recordInsertion(.init(.target,.originalElement,.success))
        recordInsertion(.init(.selection,.selectionCaptured,selection == nil ? .unsupported : .success,observed:text?.utf16.count,range:selection))
    }
    fileprivate static func attribute(_ element: AXUIElement,_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value : nil
    }
    fileprivate static func elementAttribute(_ element: AXUIElement,_ name: String) -> AXUIElement? {
        guard let value = attribute(element,name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value,to:AXUIElement.self)
    }
    fileprivate static func readText(_ element: AXUIElement, maximumBytes: Int, failure: (String) -> Void = { _ in }, record:(InsertionVerificationDiagnostic)->Void = { _ in }) -> String? {
        func attributeValue(_ name:String,_ code:InsertionVerificationDiagnostic.Code) -> CFTypeRef? {
            var value:CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element,name as CFString,&value)
            record(.init(.readback,code,status == .success ? .success : (status == .attributeUnsupported ? .unsupported : .failure),axError:status.rawValue))
            return status == .success ? value : nil
        }
        return NativeFieldTextReader.read(maximumBytes:maximumBytes,value:{
            let raw = attributeValue(kAXValueAttribute,.axValue)
            // AXValue may be plain or attributed. Preserve exact UTF-16 text.
            return NativeFieldTextReader.plainTextValue(raw)
        },characterCount:{
            NativeFieldTextReader.characterCount(attributeValue(kAXNumberOfCharactersAttribute,.axCharacterCount))
        },range:{ count in
            var range = CFRange(location:0,length:count), result:CFTypeRef?
            guard let parameter = AXValueCreate(.cfRange,&range) else { return nil }
            let status = AXUIElementCopyParameterizedAttributeValue(element,kAXStringForRangeParameterizedAttribute as CFString,parameter,&result)
            record(.init(.readback,.axStringRange,status == .success ? .success : ((status == .attributeUnsupported || status == .parameterizedAttributeUnsupported) ? .unsupported : .failure),axError:status.rawValue,expected:count,range:.init(location:0,length:count)))
            return status == .success ? result as? String : nil
        },attributedRange:{ count in
            var range = CFRange(location:0,length:count), result:CFTypeRef?
            guard let parameter = AXValueCreate(.cfRange,&range) else { return nil }
            let status = AXUIElementCopyParameterizedAttributeValue(element,kAXAttributedStringForRangeParameterizedAttribute as CFString,parameter,&result)
            record(.init(.readback,.axAttributedRange,status == .success ? .success : ((status == .attributeUnsupported || status == .parameterizedAttributeUnsupported) ? .unsupported : .failure),axError:status.rawValue,expected:count,range:.init(location:0,length:count)))
            return status == .success ? NativeFieldTextReader.plainAttributedText(result) : nil
        },failure:failure)
    }
    /// Capture only API status and fixed categories; never labels, values or text.
    private static func focusElementAttribute(_ source:AXUIElement,_ name:String,code:InsertionVerificationDiagnostic.Code,record:(InsertionVerificationDiagnostic)->Void) throws -> AXUIElement? {
        var raw:CFTypeRef?
        let error = AXUIElementCopyAttributeValue(source,name as CFString,&raw)
        let valid = error == .success && raw.map { CFGetTypeID($0) == AXUIElementGetTypeID() } == true
        record(.init(.target,code,valid ? .success : (error == .attributeUnsupported || error == .noValue ? .unsupported : .failure),axError:error.rawValue))
        if error == .apiDisabled { throw TextTargetError.denied }
        if error == .invalidUIElement { throw TextTargetError.changed }
        guard valid, let raw else { return nil }
        return unsafeDowncast(raw,to:AXUIElement.self)
    }
    fileprivate static func focusedElement(_ root: AXUIElement, processID: Int32,record:(InsertionVerificationDiagnostic)->Void = { _ in }) throws -> AXUIElement {
        try NativeFocusedElementResolver.resolve(processID:processID,application:{
            try focusElementAttribute(root,kAXFocusedUIElementAttribute,code:.applicationFocus,record:record)
        },system:{
            let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system,0.2)
            return try focusElementAttribute(system,kAXFocusedUIElementAttribute,code:.systemFocus,record:record)
        },window:{
            guard let window = try focusElementAttribute(root,kAXFocusedWindowAttribute,code:.focusedWindow,record:record) else { return nil }
            let deadline = ContinuousClock.now.advanced(by:.milliseconds(500))
            var visited = 0, deadlineReached = false
            let found = FocusedDescendantSearch.find(root:window,limit:256,maximumDepth:16,permitted:{
                if ContinuousClock.now >= deadline { deadlineReached = true; return false }
                return AXIsProcessTrusted()
            },focusedEditor:{ element in
                visited += 1
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
            record(.init(.target,.focusedSearch,found == nil ? .unsupported : .success,observed:visited))
            if found == nil && visited == 256 { record(.init(.target,.focusSearchLimit,.failure)) }
            if deadlineReached { record(.init(.target,.focusSearchDeadline,.failure)) }
            guard AXIsProcessTrusted() else { throw TextTargetError.denied }
            return found
        },owner:{ element in
            var pid: pid_t = 0
            return AXUIElementGetPid(element,&pid) == .success ? pid : nil
        },isEditor:{ element in
            let subrole = Self.attribute(element,kAXSubroleAttribute) as? String ?? ""
            guard !subrole.lowercased().contains("secure"), !subrole.lowercased().contains("password") else { throw TextTargetError.secure }
            let role = Self.attribute(element,kAXRoleAttribute) as? String ?? ""
            let supported = [kAXTextAreaRole,kAXTextFieldRole,kAXComboBoxRole].contains(role)
            record(.init(.target,.focusCandidateRole,supported ? .success : .unsupported))
            return supported
        })
    }
    fileprivate static func editable(_ element: AXUIElement, console: Bool) -> Bool {
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
        guard focusEpoch.current == 0, created.duration(to:.now) < .seconds(120), !application.isTerminated,
              (Self.attribute(window,kAXMinimizedAttribute) as? Bool) != true,
              let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == application.processIdentifier, front.launchDate == launch, front.bundleIdentifier == application.bundleIdentifier else { throw TextTargetError.changed }
        let root = AXUIElementCreateApplication(application.processIdentifier); AXUIElementSetMessagingTimeout(root,0.2)
        guard let focusedWindow = Self.elementAttribute(root,kAXFocusedWindowAttribute), CFEqual(focusedWindow,window),
              let focused = try? Self.focusedElement(root,processID:application.processIdentifier), CFEqual(focused,element) else { throw TextTargetError.changed }
    }
    func validate() throws {
        try validateIdentity()
        guard let original else {
            guard identityOnlyEditable else { throw TextTargetError.unsupported }
            if let initialSelection {
                guard let raw = Self.attribute(element,kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { throw TextTargetError.changed }
                var range = CFRange(); let value = unsafeDowncast(raw,to:AXValue.self)
                guard AXValueGetType(value) == .cfRange,AXValueGetValue(value,.cfRange,&range),range.location == initialSelection.location,range.length == initialSelection.length else { throw TextTargetError.changed }
            }
            return
        }
        guard let observed = observedText(), DictationInsertionExpectation.exact(observed,original.text),
              let raw = Self.attribute(element,kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { throw TextTargetError.changed }
        var range = CFRange(); let value = unsafeDowncast(raw,to:AXValue.self)
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value,.cfRange,&range),
              range.location == original.selection.location, range.length == original.selection.length else { throw TextTargetError.changed }
    }
    var requiresGuardedPaste:Bool { NativeEditorCapability.requiresGuardedPaste(application.bundleIdentifier) }
    func supportsClipboardFreeText(_ text:String)->Bool {
        !NativeEditorCapability.isConsole(application.bundleIdentifier) && !text.isEmpty && text.utf8.count<=4096 && text.unicodeScalars.allSatisfy { ![Unicode.GeneralCategory.control,.lineSeparator,.paragraphSeparator].contains($0.properties.generalCategory) }
    }
    func postText(_ text: String, budgetMilliseconds: Int64) -> Bool {
        guard supportsClipboardFreeText(text), !NativeEditorCapability.isConsole(application.bundleIdentifier), budgetMilliseconds > 0, budgetMilliseconds <= 1500 else { return false }
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
    private(set) var rewriteVerificationDiagnostics: [DictationVerificationDiagnostic] = []
    private func recordRewrite(_ value:DictationVerificationDiagnostic) {
        if rewriteVerificationDiagnostics.count == 32 { rewriteVerificationDiagnostics.removeFirst() }
        rewriteVerificationDiagnostics.append(value)
    }
    func verifiedRewriteAnchor(insertedText: String) throws -> any DictationRewriteAnchor {
        do { try validateIdentity(); recordRewrite(.init(.target,.matched)) }
        catch TextTargetError.denied { throw DictationRewriteValidationFailure.permission }
        catch TextTargetError.secure { throw DictationRewriteValidationFailure.secureInput }
        catch TextTargetError.unsupported { throw DictationRewriteValidationFailure.unsupportedEditor }
        catch { recordRewrite(.init(.target,.different)); throw DictationRewriteValidationFailure.targetChanged }
        guard let original else { throw DictationRewriteValidationFailure.invalidRange }
        let expectation = try DictationInsertionExpectation(original:original,insertedText:insertedText)
        let observed = try expectation.verified(observedText(),record:recordRewrite)
        // This fixed range is proven against the actual post-insertion document,
        // after the insertion receipt was verified; never derived from history.
        let actual = try DictationInsertionExpectation.readSpan(observed,range:expectation.span)
        do { return try NativeDictationRewriteAnchor(sessionID:info.session,originalText:actual,application:application,window:window,element:element,expectedDocument:observed,span:expectation.span) }
        catch let failure as AnchorCreationFailure { failure.diagnostics.forEach(recordRewrite); throw failure.reason }
    }
    func canReplaceSelection() -> Bool {
        guard original != nil, NativeEditorCapability.allowsDirectTextReplacement(application.bundleIdentifier) else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element,kAXSelectedTextAttribute as CFString,&settable) == .success && settable.boolValue
    }
    func replaceSelection(_ text: String) throws {
        try validate()
        guard canReplaceSelection() else { throw TextTargetError.unsupported }
        let status = AXUIElementSetAttributeValue(element,kAXSelectedTextAttribute as CFString,text as CFString)
        recordInsertion(.init(.dispatch,.directDispatched,status == .success ? .success : .pending,axError:status.rawValue))
        guard status == .success else { throw DirectTextUpdateFailure.dispatchUnconfirmed }
    }
    func readbackText() throws -> String {
        do { try validateIdentity() }
        catch TextTargetError.denied { throw InsertionReadbackFailure.denied }
        catch TextTargetError.secure { throw InsertionReadbackFailure.secure }
        catch TextTargetError.changed { recordInsertion(.init(.target,.targetChanged,.failure)); throw InsertionReadbackFailure.targetChanged }
        catch { throw InsertionReadbackFailure.unsupported }
        var errors:[Int32] = []
        let value = Self.readText(element,maximumBytes:98_304,record:{ diagnostic in
            self.recordInsertion(diagnostic)
            if let error = diagnostic.axError, error != 0 { errors.append(error) }
        })
        guard let value else {
            // SDK AXError.h: preserve observed native categories. No permission
            // prompt or accessibility-tree activation is performed here.
            throw NativeReadbackFailureClassifier.classify(errors)
        }
        // Correlate identity after the synchronous AX read as well.
        do { try validateIdentity() }
        catch TextTargetError.denied { throw InsertionReadbackFailure.denied }
        catch TextTargetError.secure { throw InsertionReadbackFailure.secure }
        catch { throw InsertionReadbackFailure.targetChanged }
        var raw:CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element,kAXSelectedTextRangeAttribute as CFString,&raw)
        var selected:TextSelection?
        if status == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID() {
            let ax = unsafeDowncast(raw,to:AXValue.self); var range = CFRange()
            if AXValueGetType(ax) == .cfRange, AXValueGetValue(ax,.cfRange,&range) {
                selected = .init(location:range.location,length:range.length)
            }
        }
        recordInsertion(.init(.selection,.axSelectedRange,selected == nil ? .unsupported : .success,axError:status.rawValue,observed:value.utf16.count,range:selected))
        return value
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
        try Task.checkCancellation()
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
    private var publishedLease:(ownership:ClipboardOwnership,text:String)?
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
    /// changeCount measures ownership changes, not consumption or every data
    /// mutation. Check our exact published representations as well as the nonce.
    private func publishedStateMatches(_ ownership:ClipboardOwnership) -> Bool? {
        guard let lease = publishedLease, lease.ownership == ownership else { return nil }
        guard pasteboard.changeCount == ownership.changeCount else { return false }
        guard let items = pasteboard.pasteboardItems else { return nil }
        guard !items.isEmpty else { return nil }
        guard items.count == 1 else { return false }
        let item = items[0], types = Set(item.types)
        guard !types.isEmpty else { return nil }
        guard types == Set([NSPasteboard.PasteboardType.string,Self.marker]) else { return false }
        guard let marker = item.string(forType:Self.marker), let text = item.string(forType:.string) else { return nil }
        guard pasteboard.changeCount == ownership.changeCount else { return false }
        return marker == ownership.token && text.utf16.elementsEqual(lease.text.utf16)
    }
    public func owns(_ ownership: ClipboardOwnership) -> Bool {
        if let lease = emptyLease, lease.ownership == ownership, pasteboard.changeCount == lease.count,
           let items = pasteboard.pasteboardItems, items.isEmpty { return true }
        return publishedStateMatches(ownership) == true
    }
    public func isSuperseded(_ ownership: ClipboardOwnership) -> Bool {
        let expectedCount = emptyLease.flatMap { $0.ownership == ownership ? $0.count : nil } ?? ownership.changeCount
        if pasteboard.changeCount != expectedCount { return true }
        // A readable changed payload/type set within the same ownership revision
        // is positive evidence of newer data. Unreadability alone is not.
        return publishedStateMatches(ownership) == false
    }
    public func install(_ text: String, replacing snapshot: ClipboardSnapshot) throws -> ClipboardOwnership {
        let token = UUID().uuidString, item = NSPasteboardItem()
        item.setString(text,forType:.string); item.setString(token,forType:Self.marker)
        guard pasteboard.changeCount == snapshot.changeCount else { throw TextTargetError.changed }
        let cleared = pasteboard.clearContents()
        publishedLease = nil
        guard pasteboard.changeCount == cleared else { throw TextTargetError.changed }
        guard publish([item]) else {
            let lease = ClipboardOwnership(changeCount:cleared,token:token)
            if pasteboard.changeCount == cleared { emptyLease = (lease,cleared) }
            throw ClipboardPublicationFailure(ownership:lease)
        }
        emptyLease = nil
        let ownership = ClipboardOwnership(changeCount:pasteboard.changeCount,token:token)
        publishedLease = (ownership,text)
        guard owns(ownership) else { throw ClipboardPublicationFailure(ownership:ownership) }; return ownership
    }
    public func restore(_ snapshot: ClipboardSnapshot, ifOwned ownership: ClipboardOwnership) -> ClipboardRestoration {
        let items = snapshot.items.map { source in
            let item = NSPasteboardItem(); for (type,bytes) in source { item.setData(Data(bytes),forType:.init(type)) }; return item
        }
        guard owns(ownership) else { return isSuperseded(ownership) ? .preservedNewer : .unavailable }
        let cleared = pasteboard.clearContents()
        publishedLease = nil
        guard pasteboard.changeCount == cleared else { return .preservedNewer }
        if items.isEmpty { emptyLease = nil; return .restored }
        if publish(items) { emptyLease = nil; return .restored }
        if pasteboard.changeCount == cleared { emptyLease = (ownership,cleared); return .unavailable }
        emptyLease = nil; return .preservedNewer
    }
}

private struct AnchorCreationFailure: Error {
    let reason: DictationRewriteValidationFailure
    let diagnostics: [DictationVerificationDiagnostic]
}
/// Gesture-scoped metadata only: no characters, coordinates or clipboard data.
/// Any typing/click/scroll invalidates a pending rewrite, including an edit that
/// is later undone. The two registered formatting gestures do not invalidate it.
enum NativeRewriteInputPolicy {
    static func isFormattingGesture(keyDown:Bool,keyCode:UInt16,modifiers:NSEvent.ModifierFlags) -> Bool {
        keyDown && (keyCode == 18 || keyCode == 19) && modifiers.intersection([.command,.control,.shift,.option]) == .option
    }
}
private final class NativeRewriteInputFence: @unchecked Sendable {
    private let changed = Mutex(false)
    private var monitor: Any?
    @MainActor init() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching:[.keyDown,.leftMouseDown,.rightMouseDown,.otherMouseDown,.scrollWheel]) { [weak self] event in
            if NativeRewriteInputPolicy.isFormattingGesture(keyDown:event.type == .keyDown,keyCode:event.keyCode,modifiers:event.modifierFlags) { return }
            self?.changed.withLock { $0 = true }
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    var untouched: Bool { monitor != nil && !changed.withLock { $0 } }
}

/// Owns only the dictated span and a whole-context digest, not an unrelated document copy.
@MainActor private final class NativeDictationRewriteAnchor: DictationRewriteAnchor {
    let sessionID: String, originalText: String
    var processID: Int32 { application.processIdentifier }
    private let application: NSRunningApplication, launch: Date
    private let window: AXUIElement, element: AXUIElement
    private let span: TextSelection, documentHash: String
    private let epoch = TextFocusEpoch(center:NSWorkspace.shared.notificationCenter)
    private let inputFence = NativeRewriteInputFence()
    private let keyboard = NativeDictationRewriteAnchor.standardKeyboardIdentity()
    private static func standardKeyboardIdentity() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let typePointer = TISGetInputSourceProperty(source,kTISPropertyInputSourceType),
              let idPointer = TISGetInputSourceProperty(source,kTISPropertyInputSourceID) else { return nil }
        let type = Unmanaged<CFString>.fromOpaque(typePointer).takeUnretainedValue()
        let identity = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
        guard CFEqual(type,kTISTypeKeyboardLayout), identity.hasPrefix("com.apple.keylayout.") else { return nil }
        return identity
    }
    private let born = ContinuousClock.now
    private var used = false
    init(sessionID:String,originalText:String,application:NSRunningApplication,window:AXUIElement,element:AXUIElement,expectedDocument:String,span:TextSelection) throws {
        guard let launch = application.launchDate else { throw TextTargetError.changed }
        self.sessionID = sessionID; self.originalText = originalText; self.application = application; self.launch = launch
        self.window = window; self.element = element; self.span = span
        documentHash = Self.digest(expectedDocument)
        do { try validate() }
        catch { throw AnchorCreationFailure(reason:(error as? DictationRewriteValidationFailure) ?? .editorUnavailable,diagnostics:verificationDiagnostics) }
    }
    private(set) var verificationDiagnostics: [DictationVerificationDiagnostic] = []
    private func record(_ value:DictationVerificationDiagnostic) {
        if verificationDiagnostics.count == 32 { verificationDiagnostics.removeFirst() }
        verificationDiagnostics.append(value)
    }
    private static func digest(_ text:String) -> String { SHA256.hash(data:Data(text.utf8)).map { String(format:"%02x",$0) }.joined() }
    private func selection() -> TextSelection? {
        guard let raw = NativeInsertionTarget.attribute(element,kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(raw,to:AXValue.self); var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value,.cfRange,&range), range.location >= 0, range.length >= 0 else { return nil }
        return .init(location:range.location,length:range.length)
    }
    private(set) var lastValidationFailure: DictationRewriteValidationFailure?
    private func checkedDocument(allowConsumed:Bool = false, selected:TextSelection? = nil) throws -> String {
        do { let text = try readValidatedDocument(allowConsumed:allowConsumed,selected:selected); lastValidationFailure = nil; return text }
        catch { lastValidationFailure = error as? DictationRewriteValidationFailure; throw error }
    }
    private func readValidatedDocument(allowConsumed:Bool, selected:TextSelection?) throws -> String {
        guard !used || allowConsumed else { throw DictationRewriteValidationFailure.consumed }
        guard !Task.isCancelled else { throw CancellationError() }
        guard born.duration(to:.now) < .seconds(120) else { record(.init(.freshness,.expired)); throw DictationRewriteValidationFailure.expired }
        record(.init(.freshness,.fresh))
        guard AXIsProcessTrusted() else { throw DictationRewriteValidationFailure.permission }
        guard !IsSecureEventInputEnabled() else { throw DictationRewriteValidationFailure.secureInput }
        guard !application.isTerminated, let front = NSWorkspace.shared.frontmostApplication else { record(.init(.target,.unavailable)); throw DictationRewriteValidationFailure.editorUnavailable }
        guard epoch.current == 0, front.processIdentifier == processID, front.launchDate == launch else { record(.init(.target,.different)); throw DictationRewriteValidationFailure.targetChanged }
        record(.init(.target,.matched))
        guard !NativeEditorCapability.isConsole(application.bundleIdentifier) else { throw DictationRewriteValidationFailure.unsupportedEditor }
        let root = AXUIElementCreateApplication(processID); AXUIElementSetMessagingTimeout(root,0.08); AXUIElementSetMessagingTimeout(element,0.08)
        guard let focusedWindow = NativeInsertionTarget.elementAttribute(root,kAXFocusedWindowAttribute),
              let focused = try? NativeInsertionTarget.focusedElement(root,processID:processID) else { record(.init(.element,.unavailable)); throw DictationRewriteValidationFailure.editorUnavailable }
        guard CFEqual(window,focusedWindow), CFEqual(focused,element) else { record(.init(.element,.different)); throw DictationRewriteValidationFailure.targetChanged }
        record(.init(.element,.matched))
        guard inputFence.untouched else { throw DictationRewriteValidationFailure.caretChanged }
        let role = NativeInsertionTarget.attribute(element,kAXRoleAttribute) as? String ?? ""
        guard [kAXTextAreaRole,kAXTextFieldRole,kAXComboBoxRole].contains(role) else { throw DictationRewriteValidationFailure.unsupportedEditor }
        do { try DictationRewriteCapabilities.validateEditor(subrole:NativeInsertionTarget.attribute(element,kAXSubroleAttribute) as? String,editable:NativeInsertionTarget.editable(element,console:false)) }
        catch { record(.init(.element,.unsupported)); throw error }
        var raw: CFTypeRef?
        let compositionError = AXUIElementCopyAttributeValue(element,"AXMarkedTextRange" as CFString,&raw)
        var markedLength: Int?
        if compositionError == .success {
            guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { throw DictationRewriteValidationFailure.compositionUnavailable }
            let marked = unsafeDowncast(raw,to:AXValue.self); var markedRange = CFRange()
            guard AXValueGetType(marked) == .cfRange, AXValueGetValue(marked,.cfRange,&markedRange) else { throw DictationRewriteValidationFailure.compositionUnavailable }
            markedLength = markedRange.length
        } else {
            // Timeouts, denial and invalid elements are not unsupported metadata.
            guard compositionError == .attributeUnsupported || compositionError == .noValue else { throw DictationRewriteValidationFailure.compositionUnavailable }
        }
        try DictationRewriteCapabilities.validateComposition(markedLength:markedLength,
            standardKeyboardUnchanged:keyboard != nil && keyboard == Self.standardKeyboardIdentity(),inputUntouched:inputFence.untouched)
        record(.init(.composition,markedLength == nil ? .unavailable : .valid))
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element,kAXSelectedTextAttribute as CFString,&writable) == .success, writable.boolValue,
              AXUIElementIsAttributeSettable(element,kAXSelectedTextRangeAttribute as CFString,&writable) == .success, writable.boolValue else { throw DictationRewriteValidationFailure.unsupportedEditor }
        guard let text = NativeInsertionTarget.readText(element,maximumBytes:98_304) else { record(.init(.text,.unavailable)); throw DictationRewriteValidationFailure.textUnavailable }
        try DictationInsertionExpectation.validateSpan(text,range:span,insertedText:originalText,record:record)
        guard Self.digest(text) == documentHash else { record(.init(.context,.different,current:text.utf16.count)); throw DictationRewriteValidationFailure.contextChanged }
        record(.init(.context,.matched,current:text.utf16.count))
        do { try DictationInsertionExpectation.validateCaret(selection(),span:span,selected:selected); record(.init(.caret,.valid)) }
        catch { record(.init(.caret,.invalid)); throw error }
        return text
    }
    func validate() throws { _ = try checkedDocument() }
    func replaceValidatedSpan(_ text:String) -> TextInsertionReceipt {
        guard !text.isEmpty, text.utf8.count <= 8192 else { return .init(.denied,.unsupported) }
        let document: String
        do { document = try checkedDocument() } catch { return .init(.targetChanged,.changed) }
        guard let expected = span.replacing(in:document,with:text), selection() != nil else { return .init(.unsupportedTarget,.unsupported) }
        var range = CFRange(location:span.location,length:span.length)
        guard let value = AXValueCreate(.cfRange,&range) else { return .init(.unsupportedTarget,.unsupported) }
        // Consume before the first effect: no duplicate dispatch or uncertain-write retries.
        used = true
        guard AXUIElementSetAttributeValue(element,kAXSelectedTextRangeAttribute as CFString,value) == .success else { return .init(.uncertain,.verificationUnavailable,attempted:true) }
        guard let checked = try? checkedDocument(allowConsumed:true,selected:span), DictationInsertionExpectation.exact(checked,document) else { return .init(.uncertain,.verificationUnavailable,attempted:true) }
        guard AXUIElementSetAttributeValue(element,kAXSelectedTextAttribute as CFString,text as CFString) == .success,
              NativeInsertionTarget.readText(element,maximumBytes:98_304).map({ DictationInsertionExpectation.exact($0,expected) }) == true, epoch.current == 0, inputFence.untouched, NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return .init(.uncertain,.verificationUnavailable,attempted:true) }
        return .init(.inserted,.verified,attempted:true)
    }
}
