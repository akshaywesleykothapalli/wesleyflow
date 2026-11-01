import Foundation

/// Explicit app-local commands. Whole utterances only; never parsed from dictated text,
/// pending message bodies, model-generated output or saved executable plans.
public enum FlowControlDestination: String, Sendable { case settings, dictation, history, dictionary, formatting, commands }
public enum FlowVoiceControl: Equatable, Sendable {
    case language(DictationLanguageMode, TeluguRecognitionLanguage?)
    case navigate(FlowControlDestination)
    case saveHistory(Bool)
    case spacing(Bool)
    public static let examples = ["Switch dictation to English", "Switch dictation to Telugu only", "Use automatic Telugu and English", "Open dictation settings", "Show dictation history", "Open my dictionary", "Open smart formatting", "Stop saving dictation history", "Save dictation history", "Turn on spacing cleanup"]
    public static func parse(_ original:String) -> Self? {
        guard original.utf8.count <= 512, !original.contains("\n"), !original.contains("\r") else { return nil }
        let text = PersonalAgentDialogue.canonical(original).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ").lowercased()
        let commands:[(Self,[String])] = [
            (.language(.english,nil),["switch dictation to english","switch language to english","switch the language to english","change dictation language to english","set dictation language to english","switch to english","use english dictation"]),
            (.language(.teluguRomanised,.teluguOnly),["switch dictation to telugu","switch dictation to telugu only","switch language to telugu","switch the language to telugu","switch language to telugu only","change dictation language to telugu","set dictation language to telugu","switch to telugu","switch to telugu only","use telugu only"]),
            (.language(.teluguRomanised,.automatic),["use automatic telugu and english","switch dictation to automatic","switch recognition to automatic","use telugu and english"]),
            (.navigate(.settings),["open dictation settings","show dictation settings","open language settings"]),
            (.navigate(.dictation),["show dictation","open dictation"]),
            (.navigate(.history),["show dictation history","open dictation history","show my dictation history"]),
            (.navigate(.dictionary),["open my dictionary","open dictation dictionary","show my dictionary"]),
            (.navigate(.formatting),["open smart formatting","show smart formatting","open shortcut settings"]),
            (.navigate(.commands),["show agent commands","open command mode"]),
            (.saveHistory(false),["stop saving dictation history","disable dictation history","turn off dictation history"]),
            (.saveHistory(true),["save dictation history","enable dictation history","turn on dictation history"]),
            (.spacing(true),["turn on spacing cleanup","enable spacing cleanup"]),
            (.spacing(false),["turn off spacing cleanup","disable spacing cleanup"])
        ]
        return commands.first(where:{$0.1.contains(text)})?.0
    }
    public var confirmation:String {
        switch self {
        case .language(.english,_): "English selected for the next Fn dictation."
        case .language(.teluguRomanised,.automatic): "Automatic Telugu and English selected for the next Fn dictation."
        case .language(.teluguRomanised,_): "Telugu-only selected for the next Fn dictation."
        case .navigate(.settings): "Opened dictation settings."
        case .navigate(.dictation): "Opened Dictation."
        case .navigate(.history): "Opened dictation history."
        case .navigate(.dictionary): "Opened your dictionary."
        case .navigate(.formatting): "Opened Smart Formatting and shortcut status."
        case .navigate(.commands): "Opened Agent commands."
        case .saveHistory(true): "New dictations will be saved on this Mac."
        case .saveHistory(false): "New dictations will not be saved. Existing history is retained."
        case .spacing(true): "Spacing cleanup is enabled for the next dictation."
        case .spacing(false): "Spacing cleanup is disabled for the next dictation."
        }
    }
}
