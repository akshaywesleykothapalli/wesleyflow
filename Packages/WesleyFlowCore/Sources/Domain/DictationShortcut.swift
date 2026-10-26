/// A physical hold gesture authorizes one text insertion, never a task or command.
public enum DictationShortcutEvent: Sendable, Equatable { case pressed, released, cancelled, unavailable }
public enum DictationShortcutFailure: Error, Sendable { case permissionRequired, monitoringUnavailable, unsupportedField, destinationChanged, insertionFailed }
@MainActor public protocol DictationShortcutMonitoring: AnyObject {
    var authorizationReady: Bool { get }
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

public extension DictationShortcutMonitoring { var authorizationReady: Bool { true } }

public enum DictationActivationKey: String, Codable, CaseIterable, Sendable {
    case fn, rightOption, rightCommand
    public var label: String { switch self { case .fn: "Fn / Globe"; case .rightOption: "Right Option"; case .rightCommand: "Right Command" } }
}
public extension DictationShortcutMonitoring { func configure(key: DictationActivationKey) {} }
