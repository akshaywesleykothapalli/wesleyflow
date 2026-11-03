import Foundation

public enum TextInsertionOutcome: String, Codable, Sendable, CaseIterable {
    case inserted = "INSERTED", denied = "DENIED", unsupportedTarget = "UNSUPPORTED_TARGET"
    case targetChanged = "TARGET_CHANGED", cancelled = "CANCELLED", timedOut = "TIMED_OUT", uncertain = "UNCERTAIN"
}
/// Display/inspection vocabulary; legacy persisted outcomes remain decodable without migration.
public enum TextInsertionStatus: String, Sendable, CaseIterable {
    case insertedVerified = "INSERTED_VERIFIED", dispatchedUnverified = "DISPATCHED_UNVERIFIED"
    case targetChanged = "TARGET_CHANGED", unsupportedTarget = "UNSUPPORTED_TARGET", permissionDenied = "PERMISSION_DENIED"
    case cancelled = "CANCELLED", failed = "FAILED", uncertain = "UNCERTAIN"
}
public enum InsertionReason: String, Codable, Sendable {
    case verified, manualOnly, permission, secureField, unsupported, changed, clipboardUnsupported
    case clipboardChanged, clipboardPending, verificationUnavailable, cancelled, deadline, speechFailed
}
public struct TextInsertionReceipt: Codable, Equatable, Sendable {
    public let outcome: TextInsertionOutcome
    public let reason: InsertionReason
    public let attempted: Bool
    public let clipboardPending: Bool
    public init(_ outcome: TextInsertionOutcome, _ reason: InsertionReason, attempted: Bool = false, clipboardPending: Bool = false) {
        self.outcome = outcome; self.reason = reason; self.attempted = attempted; self.clipboardPending = clipboardPending
    }
}
public extension TextInsertionReceipt {
    var status: TextInsertionStatus {
        // Legacy speech failures occurred before delivery; retain their stored payload.
        if outcome == .uncertain && reason == .speechFailed && !attempted { return .failed }
        return switch outcome {
        case .inserted: attempted && reason == .verified ? .insertedVerified : .uncertain
        case .uncertain: attempted && [.deadline,.verificationUnavailable].contains(reason) ? .dispatchedUnverified : .uncertain
        case .denied: reason == .permission ? .permissionDenied : .failed
        case .targetChanged: attempted ? .uncertain : .targetChanged
        case .unsupportedTarget: attempted ? .uncertain : .unsupportedTarget
        case .cancelled: attempted ? .uncertain : .cancelled
        case .timedOut: attempted ? .uncertain : .failed
        }
    }
}
/// Correlation metadata only. Its presence is not user approval to restore a clipboard.
public struct ClipboardRecovery: Sendable, Equatable, Identifiable {
    public let id: String
    public let session: String
    public let dispatched: Bool
    public init(id: String, session: String, dispatched: Bool) { self.id = id; self.session = session; self.dispatched = dispatched }
}
public struct TextSelection: Codable, Equatable, Sendable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
    public func replacing(in text: String, with inserted: String) -> String? {
        let utf16 = text.utf16
        guard location >= 0, length >= 0, location <= utf16.count, length <= utf16.count - location,
              let a = utf16.index(utf16.startIndex,offsetBy:location,limitedBy:utf16.endIndex)?.samePosition(in:text),
              let b = utf16.index(utf16.startIndex,offsetBy:location+length,limitedBy:utf16.endIndex)?.samePosition(in:text) else { return nil }
        var result = text; result.replaceSubrange(a..<b,with:inserted); return result
    }
}
public struct InsertionTargetInfo: Sendable, Equatable {
    public let session: String
    public let bundleIdentifier:String?
    public let applicationName: String
    public let processID: Int32
    public let windowIdentity: String
    public let elementIdentity: String
    public let role: String
    public init(session: String, applicationName: String, processID: Int32, windowIdentity: String, elementIdentity: String, role: String, bundleIdentifier:String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.session = session; self.applicationName = applicationName; self.processID = processID
        self.windowIdentity = windowIdentity; self.elementIdentity = elementIdentity; self.role = role
    }
}
public struct TargetTextState: Sendable, Equatable {
    public let text: String
    public let selection: TextSelection
    public init(text: String, selection: TextSelection) { self.text = text; self.selection = selection }
}
public enum TextTargetError: Error, Sendable { case denied, secure, unsupported, changed, clipboardChanged }
/// Advertised precise-edit API capability only; never replacement authority.
public enum EditorReplacementCapability:String, Sendable { case available, unavailable, unknown }
@MainActor public protocol InsertionTarget: AnyObject {
    var replacementCapability:EditorReplacementCapability { get }
    var info: InsertionTargetInfo { get }
    /// Nil means delivery may be possible but exact readback/replacement cannot
    /// be proven. Never substitute an empty document or a made-up caret.
    var original: TargetTextState? { get }
    func validate() throws
    func canReplaceSelection() -> Bool
    func replaceSelection(_ text: String) throws
    /// Throw only before dispatch; a posted event has no delivery acknowledgement.
    func postPaste(whileClipboardOwned: () -> Bool) throws
    func observedText() -> String?
    /// Post-effect read of the original bound editor. Native implementations
    /// revalidate identity without requiring the pre-insertion text/selection.
    func readbackText() throws -> String
    var insertionDiagnostics: [InsertionVerificationDiagnostic] { get }
    /// false guarantees no native input was posted; true includes partial/uncertain delivery.
    /// Must retain the bound editor and never send controls or Return. Service verifies outcome.
    func postText(_ text: String, budgetMilliseconds: Int64) -> Bool
}
public extension InsertionTarget {
    var replacementCapability:EditorReplacementCapability { .unknown }
    var insertionDiagnostics:[InsertionVerificationDiagnostic] { [] }
    func readbackText() throws -> String { guard let text = observedText() else { throw InsertionReadbackFailure.temporarilyUnavailable }; return text }
    func postText(_ text: String, budgetMilliseconds: Int64) -> Bool { false } }
@MainActor public protocol InsertionTargetCapturing: AnyObject {
    /// Sanitized capability failure only; never include target text or selection contents.
    var failureExplanation: String? { get }
    var captureBundleIdentifier:String? { get }
    var captureDiagnostics:[InsertionVerificationDiagnostic] { get }
    func capture(session: String) throws -> any InsertionTarget
    func capture(session:String,activation:DictationActivationContext) throws -> any InsertionTarget
    var observedApplicationIdentity:DictationApplicationIdentity? { get }
}
public extension InsertionTargetCapturing {
    // Capturers must explicitly support binding; never silently discard an origin.
    func capture(session:String,activation:DictationActivationContext) throws -> any InsertionTarget { throw TextTargetError.changed }
    var observedApplicationIdentity:DictationApplicationIdentity? { nil }
    var captureBundleIdentifier:String? { nil }; var captureDiagnostics:[InsertionVerificationDiagnostic] { [] }; var failureExplanation: String? { nil } }
public struct ClipboardSnapshot: Sendable {
    public let changeCount: Int
    public let items: [[String:[UInt8]]]
    public init(changeCount: Int, items: [[String:[UInt8]]]) { self.changeCount = changeCount; self.items = items }
}
public struct ClipboardOwnership: Sendable, Equatable {
    public let changeCount: Int
    public let token: String
    public init(changeCount: Int, token: String) { self.changeCount = changeCount; self.token = token }
}
/// Publication failed after clearing our clipboard revision; the backup still needs restoration.
public struct ClipboardPublicationFailure: Error, Sendable {
    public let ownership: ClipboardOwnership
    public init(ownership: ClipboardOwnership) { self.ownership = ownership }
}
public enum ClipboardRestoration: String, Sendable { case restored, preservedNewer, unavailable }
@MainActor public protocol DictationPasteboard: AnyObject {
    /// Sanitized capability metadata only; never clipboard payload.
    var snapshotFailureExplanation: String? { get }
    func snapshot() throws -> ClipboardSnapshot
    func install(_ text: String, replacing snapshot: ClipboardSnapshot) throws -> ClipboardOwnership
    func owns(_ ownership: ClipboardOwnership) -> Bool
    /// Positive revision evidence only. A failed ownership read does not prove a newer copy.
    func isSuperseded(_ ownership: ClipboardOwnership) -> Bool
    func restore(_ snapshot: ClipboardSnapshot, ifOwned ownership: ClipboardOwnership) -> ClipboardRestoration
}
public extension DictationPasteboard {
    var snapshotFailureExplanation: String? { nil }
    func isSuperseded(_ ownership: ClipboardOwnership) -> Bool { false }
}
@MainActor public protocol DictationTextInserting: AnyObject {
    var failureExplanation: String? { get }
    var verificationDiagnostics:[InsertionVerificationDiagnostic] { get }
    /// Diagnostic correlation only; never authorization or evidence of delivery.
    var verificationSession:String? { get }
    var hasPendingClipboard: Bool { get }
    func insert(_ text: String, target: any InsertionTarget, session: String) async -> TextInsertionReceipt
    var pendingClipboardRecovery: ClipboardRecovery? { get }
    /// Retires only a superseded lease; never writes the clipboard or retries insertion.
    @discardableResult func reconcileClipboardState() -> ClipboardRestoration?
    /// Identity must be captured when the user opens recovery, not when they confirm later.
    func restoreAfterUserConfirmation(expectedRecoveryID: String) -> ClipboardRestoration
}
public extension DictationTextInserting { var verificationSession:String? { nil }; var verificationDiagnostics:[InsertionVerificationDiagnostic] { [] }; var failureExplanation: String? { nil } }
public struct DictationHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let raw: String
    public let cleaned: String
    public let sourceApplication: String?
    public let durationMilliseconds: Int64
    public let insertion: TextInsertionReceipt
    public var wordCount: Int { cleaned.split(whereSeparator: { $0.isWhitespace }).count }
    public var characterCount: Int { cleaned.count }
    public init(id: String, timestamp: Date, raw: String, cleaned: String, sourceApplication: String?, durationMilliseconds: Int64, insertion: TextInsertionReceipt) {
        self.id = id; self.timestamp = timestamp; self.raw = raw; self.cleaned = cleaned
        self.sourceApplication = sourceApplication; self.durationMilliseconds = durationMilliseconds; self.insertion = insertion
    }
    public func validate() throws {
        guard UUID(uuidString:id) != nil, timestamp.timeIntervalSince1970.isFinite, raw.utf8.count <= DictationText.maximumBytes,
              cleaned.utf8.count <= DictationText.maximumBytes, (sourceApplication?.utf8.count ?? 0) <= 256,
              (0...DictationText.maximumDurationMilliseconds).contains(durationMilliseconds) else { throw DictationHistoryFailure.invalidEntry }
        if insertion.outcome == .inserted && (!insertion.attempted || insertion.reason != .verified) { throw DictationHistoryFailure.invalidEntry }
    }
}
public enum DictationHistoryFailure: Error, Sendable { case unavailable, incompatibleSchema, corrupt, alreadyOpen, full, invalidEntry, closed }
public protocol DictationHistoryStore: Sendable {
    func load() async throws -> [DictationHistoryEntry]
    func append(_ entry: DictationHistoryEntry) async throws
    func delete(id: String) async throws
    func clear() async throws
    func close() async
}
public enum DictationHistoryQuery {
    public static func filter(_ entries: [DictationHistoryEntry], search: String) -> [DictationHistoryEntry] {
        entries.filter { search.isEmpty || $0.cleaned.localizedCaseInsensitiveContains(search) || $0.raw.localizedCaseInsensitiveContains(search) || ($0.sourceApplication?.localizedCaseInsensitiveContains(search) ?? false) }
            .sorted { ($0.timestamp,$0.id) > ($1.timestamp,$1.id) }
    }
    public static func groups(_ entries: [DictationHistoryEntry], calendar: Calendar) -> [(date: Date, entries: [DictationHistoryEntry])] {
        Dictionary(grouping:entries) { calendar.startOfDay(for:$0.timestamp) }.map { (date:$0.key, entries:filter($0.value,search:"")) }.sorted { $0.date > $1.date }
    }
}

/// Readback failures describe observation, never grant authority or prove delivery.
public enum InsertionReadbackFailure: String, Error, Sendable, CaseIterable {
    case unsupported, denied, temporarilyUnavailable, rangeUnavailable, rangeInvalid, targetChanged, secure
}
/// Fixed-vocabulary development metadata. Cannot carry document/clipboard text or hashes.
public struct InsertionVerificationDiagnostic: Sendable, Equatable {
    public enum Stage:String, Sendable { case target, selection, formatted, clipboard, dispatch, readback, span, receipt, shortcut }
    public enum Status:String, Sendable { case success, failure, unsupported, pending }
    public enum Timing:String, Sendable { case initial, settling, terminal }
    public enum Code:String, Sendable {
        case identityOnly = "IDENTITY_BOUND_PASTE_ONLY", initialReadbackUnavailable = "INITIAL_READBACK_UNAVAILABLE"
        case clipboardRestored = "CLIPBOARD_RESTORED", clipboardSuperseded = "NEWER_CLIPBOARD_PRESERVED", clipboardRetained = "CLIPBOARD_RECOVERY_RETAINED"
        case applicationFocus = "APPLICATION_FOCUSED_ELEMENT", systemFocus = "SYSTEM_FOCUSED_ELEMENT"
        case focusedWindow = "FOCUSED_WINDOW", focusCandidateRole = "FOCUS_CANDIDATE_IS_EDITOR"
        case focusedSearch = "FOCUSED_EDITOR_SEARCH", focusSearchLimit = "FOCUS_SEARCH_LIMIT", focusSearchDeadline = "FOCUS_SEARCH_DEADLINE"
        case captureFailed = "TARGET_CAPTURE_FAILED", roleSupported = "EDITABLE_ROLE_SUPPORTED", subroleKnown = "SUBROLE_EXPOSED"
        case selectedTextWritable = "SELECTED_TEXT_WRITABLE", selectionWritable = "SELECTION_RANGE_WRITABLE"
        case replacementCapability = "PRECISE_REPLACEMENT_CAPABILITY"
        case editorFocusWritable = "EDITOR_FOCUS_WRITABLE", editorFocusRequested = "EDITOR_FOCUS_REQUESTED", editorFocusConfirmed = "EDITOR_FOCUS_CONFIRMED"
        case applicationRole = "APPLICATION_ROLE", windowFromEditor = "WINDOW_FROM_FOCUSED_EDITOR"
        case targetAcquired = "TARGET_ACQUIRED", originalElement = "ORIGINAL_ELEMENT_RETAINED", selectionCaptured = "SELECTION_CAPTURED"
        case formatted = "FORMATTED_TEXT_FINALIZED", clipboardAcquired = "CLIPBOARD_LEASE_ACQUIRED"
        case directDispatched = "DIRECT_UPDATE_DISPATCHED", pasteDispatched = "PASTE_DISPATCHED", typingDispatched = "TYPING_DISPATCHED"
        case axValue = "AX_VALUE", axCharacterCount = "AX_CHARACTER_COUNT", axSelectedRange = "AX_SELECTED_RANGE"
        case axStringRange = "AX_STRING_FOR_RANGE", axAttributedRange = "AX_ATTRIBUTED_STRING_FOR_RANGE"
        case readbackSupported = "TARGET_READBACK_SUPPORTED", readbackUnsupported = "TARGET_READBACK_UNSUPPORTED"
        case readbackDenied = "TARGET_READBACK_DENIED", readbackTemporary = "TARGET_READBACK_TEMPORARILY_UNAVAILABLE"
        case readbackTimeout = "TARGET_READBACK_TIMEOUT", targetChanged = "TARGET_IDENTITY_CHANGED"
        case rangeUnavailable = "INSERTION_RANGE_UNAVAILABLE", rangeInvalid = "INSERTION_RANGE_INVALID"
        case textMismatch = "INSERTED_TEXT_MISMATCH", contextMismatch = "INSERTION_CONTEXT_MISMATCH"
        case preInsertionText = "PRE_INSERTION_TEXT", verified = "INSERTION_VERIFIED"
        case receiptCreated = "INSERTION_RECEIPT_CREATED", uncertain = "INSERTION_UNCERTAIN"
        case cancelled = "SESSION_CANCELLED", shortcutLookup = "SHORTCUT_RECEIPT_LOOKUP"
    }
    public let stage:Stage, code:Code, status:Status, timing:Timing
    public let elapsedMilliseconds:Int64?
    public let axError:Int32?, expectedUTF16:Int?, observedUTF16:Int?, rangeLocation:Int?, rangeLength:Int?
    public init(_ stage:Stage,_ code:Code,_ status:Status, timing:Timing = .initial, axError:Int32? = nil, expected:Int? = nil, observed:Int? = nil, range:TextSelection? = nil, elapsedMilliseconds:Int64? = nil) {
        self.stage = stage; self.code = code; self.status = status; self.timing = timing; self.axError = axError; self.elapsedMilliseconds = elapsedMilliseconds
        expectedUTF16 = expected; observedUTF16 = observed; rangeLocation = range?.location; rangeLength = range?.length
    }
}

/// Native clipboard-free route, with an explicit guarded-paste exception for a verified target.
@MainActor public protocol ClipboardFreeInsertionTarget:InsertionTarget {
    var requiresGuardedPaste:Bool { get }
    func supportsClipboardFreeText(_ text:String)->Bool
    func prepareForGuardedPaste() throws
}
public extension ClipboardFreeInsertionTarget {
    var requiresGuardedPaste:Bool { false }
    func prepareForGuardedPaste() throws { try validate() }
}
