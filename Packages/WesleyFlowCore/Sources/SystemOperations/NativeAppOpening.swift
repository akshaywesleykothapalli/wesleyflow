import AppKit
import Domain

private extension AppOpeningCommand {
    var bundleIdentifier: String? {
        switch self { case .whatsapp:"net.whatsapp.WhatsApp"; case .browser:nil; case .settings:"com.apple.systempreferences"; case .finder:"com.apple.finder"; case .notes:"com.apple.Notes"; case .music:"com.apple.Music" }
    }
}

@MainActor public enum NativeAppOpening {
    public static func open(_ command: AppOpeningCommand) async throws {
        let workspace = NSWorkspace.shared
        let url: URL?
        if let id = command.bundleIdentifier { url = workspace.urlForApplication(withBundleIdentifier:id) }
        else { url = workspace.urlForApplication(toOpen:URL(string:"https://example.invalid")!) }
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        // Resolve the handler only; no URL, document, message, or command is sent to it.
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        _ = try await workspace.openApplication(at:url,configuration:configuration)
    }
}
