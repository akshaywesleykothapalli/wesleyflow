import Foundation

/// Exact, local app-opening intents. Text never becomes a shell command or URL.
public enum AppOpeningCommand: String, CaseIterable, Sendable {
    case whatsapp = "WhatsApp", browser = "Browser", settings = "Settings", finder = "Finder", notes = "Notes", music = "Music"
    public static func parse(_ text: String) -> Self? {
        guard text.utf8.count <= 128 else { return nil }
        let normalized = text.lowercased().trimmingCharacters(in:.whitespacesAndNewlines.union(CharacterSet(charactersIn:".!?")))
        let names: [String:Self] = ["whatsapp":.whatsapp,"whats app":.whatsapp,"browser":.browser,"default browser":.browser,"settings":.settings,"system settings":.settings,"finder":.finder,"notes":.notes,"music":.music]
        guard normalized.hasPrefix("open ") else { return nil }
        return names[String(normalized.dropFirst(5))]
    }
}
