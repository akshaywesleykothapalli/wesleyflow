/// A physical hold gesture authorizes one text insertion, never a task or command.
public enum DictationShortcutEvent: Sendable, Equatable { case pressed, released, cancelled, unavailable }
public enum DictationShortcutFailure: Error, Sendable { case permissionRequired, monitoringUnavailable, unsupportedField, destinationChanged, insertionFailed }
@MainActor public protocol DictationShortcutMonitoring: AnyObject {
    var authorizationReady: Bool { get }
    var activationContext:DictationActivationContext? { get }
    var diagnosticSummary: String { get }
    func enable(receive: @escaping @MainActor @Sendable (DictationShortcutEvent) -> Void) throws
    func configure(key: DictationActivationKey)
    func disable()
}
@MainActor public protocol DictationTextDestination: AnyObject {
    func insert(_ text: String) throws
}
@MainActor public protocol DictationDestinationCapturing: AnyObject {
    func capture() throws -> any DictationTextDestination
}

public extension DictationShortcutMonitoring {
    var diagnosticSummary: String { "Injected shortcut monitor" }
    var authorizationReady: Bool { true }
    var activationContext:DictationActivationContext? { nil }
}

public enum DictationActivationKey: String, Codable, CaseIterable, Sendable {
    case fn, rightOption, rightCommand, rightControl
    public var label: String { switch self { case .fn: "Fn / Globe"; case .rightOption: "Right Option"; case .rightCommand: "Right Command"; case .rightControl: "Right Control" } }
}
public extension DictationShortcutMonitoring { func configure(key: DictationActivationKey) {} }


/// Public process metadata only; never editor labels, values, titles or clipboard data.
public struct DictationApplicationIdentity: Sendable, Equatable {
    public let processID: Int32
    public let launchTime: Double
    public let bundleIdentifier: String?
    public init(processID:Int32,launchTime:Double,bundleIdentifier:String?) { self.processID=processID;self.launchTime=launchTime;self.bundleIdentifier=bundleIdentifier }
    public var valid:Bool { processID>0 && launchTime.isFinite }
    public func matches(_ other:Self?) -> Bool { valid && other?.valid == true && self == other }
    public var summary:String {
        let bundle=bundleIdentifier.flatMap { value in value.utf8.count<=255 && value.utf8.allSatisfy({(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,95].contains($0)}) ? value : nil } ?? "unknown"
        return "pid=\(processID),launch=\(launchTime),bundle=\(bundle)"
    }
}
public struct DictationActivationContext: Sendable, Equatable {
    public let application:DictationApplicationIdentity?
    public let pressUptime:Double
    public var eventUptime:Double?
    public var activationObservedUptime:Double?
    public let source:String
    public let activationUnchanged:Bool
    public init(application:DictationApplicationIdentity?,pressUptime:Double,source:String,activationUnchanged:Bool=true) { self.application=application;self.pressUptime=pressUptime;self.source=source;self.activationUnchanged=activationUnchanged }
    public func permits(_ current:DictationApplicationIdentity?) -> Bool { activationUnchanged && pressUptime.isFinite && pressUptime>=0 && application?.matches(current)==true }
    public var summary:String { "source=\(source),pressUptime=\(pressUptime),eventUptime=\(eventUptime.map(String.init(describing:)) ?? "none"),activationObservedUptime=\(activationObservedUptime.map(String.init(describing:)) ?? "none"),activationUnchanged=\(activationUnchanged),"+(application?.summary ?? "identity=unavailable") }
}

public enum DictationActivationTiming {
    /// NSEvent seconds / CGEvent nanoseconds and systemUptime share startup time.
    /// A delayed event predating the current activation cannot select that app.
    public static func accepts(event:Double,observed:Double,activation:Double)->Bool {
        event.isFinite && observed.isFinite && activation.isFinite && event>0 && activation>=0 && event>=activation && observed>=event
    }
}
