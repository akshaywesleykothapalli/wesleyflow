import Foundation
import AppKit
import SystemOperations
import Domain
import SwiftUI
import ServiceManagement

enum DictationPage: String, CaseIterable, Identifiable {
    case dictation = "Dictation", insights = "Insights", dictionary = "Dictionary"
    case commands = "Command Mode", smartFormatting = "Smart Formatting", privacy = "Privacy", general = "General"
    case history = "History"
    static let sidebar: [Self] = [.dictation, .insights, .dictionary, .commands, .smartFormatting, .privacy, .general]
    // The earlier UI had no disk-backed page selection. Accept legacy restoration
    // input here without retaining an obsolete Workspace case.
    static func restoring(_ rawValue: String?) -> Self { rawValue.flatMap(Self.init(rawValue:)) ?? .dictation }
    var sidebarSelection: Self { self == .history ? .dictation : self }
    func moving(_ offset: Int) -> Self {
        let index = Self.sidebar.firstIndex(of:sidebarSelection) ?? 0
        return Self.sidebar[min(max(index + offset,0),Self.sidebar.count - 1)]
    }
    var id: String { rawValue }
    var symbol: String { switch self {
        case .dictation: "mic"
        case .history: "clock"
        case .commands: "terminal"
        case .insights: "waveform.path.ecg"
        case .dictionary: "text.book.closed"
        case .smartFormatting: "textformat"
        case .privacy: "shield"
        case .general: "slider.horizontal.3"
    } }
}
enum DictationAppearance: String, Codable, CaseIterable {
    case system, light, dark
    var colorScheme: ColorScheme? { switch self { case .system:nil; case .light:.light; case .dark:.dark } }
}
struct DictationPreferences: Codable, Equatable {
    var languageMode: DictationLanguageMode = .english
    var teluguRecognitionLanguage: TeluguRecognitionLanguage = .automatic
    var version = 1
    var keepHistory = true
    var spacingCleanup = true
    var showPill = true
    var appearance: DictationAppearance = .system
    var holdFnEnabled = true
    var formatting = DictationFormattingOptions()
    var activationKey: DictationActivationKey = .fn
    var agentKey: DictationActivationKey = .rightControl
    var agentHotkeyEnabled = true
    var idlePillEnabled = false
    var blockNetworkRequests = false
    var polishTone: OfflineRewriteTone = .natural
    var promptEngineeringEnabled = false
    var inPlaceAIRewrite = false
    var useFocusedTextWhenUnselected = false
    var previewShortcutsEnabled = false
    var offlineAIRewriting = false
    init() {}
    private enum CodingKeys: String, CodingKey { case languageMode, teluguRecognitionLanguage, agentKey, agentHotkeyEnabled, inPlaceAIRewrite, useFocusedTextWhenUnselected, version, keepHistory, spacingCleanup, showPill, appearance, holdFnEnabled, formatting, activationKey, idlePillEnabled, offlineAIRewriting, blockNetworkRequests, polishTone, promptEngineeringEnabled, previewShortcutsEnabled }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        languageMode = try c.decodeIfPresent(DictationLanguageMode.self,forKey:.languageMode) ?? .english
        teluguRecognitionLanguage = try c.decodeIfPresent(TeluguRecognitionLanguage.self,forKey:.teluguRecognitionLanguage) ?? .automatic
        version = try c.decode(Int.self,forKey:.version)
        keepHistory = try c.decode(Bool.self,forKey:.keepHistory)
        spacingCleanup = try c.decode(Bool.self,forKey:.spacingCleanup)
        showPill = try c.decode(Bool.self,forKey:.showPill)
        appearance = try c.decode(DictationAppearance.self,forKey:.appearance)
        formatting = try c.decodeIfPresent(DictationFormattingOptions.self,forKey:.formatting) ?? .init()
        activationKey = try c.decodeIfPresent(DictationActivationKey.self,forKey:.activationKey) ?? .fn
        agentKey = try c.decodeIfPresent(DictationActivationKey.self,forKey:.agentKey) ?? .rightControl
        agentHotkeyEnabled = try c.decodeIfPresent(Bool.self,forKey:.agentHotkeyEnabled) ?? true
        idlePillEnabled = try c.decodeIfPresent(Bool.self,forKey:.idlePillEnabled) ?? false
        promptEngineeringEnabled = try c.decodeIfPresent(Bool.self,forKey:.promptEngineeringEnabled) ?? false
        inPlaceAIRewrite = try c.decodeIfPresent(Bool.self,forKey:.inPlaceAIRewrite) ?? false
        useFocusedTextWhenUnselected = try c.decodeIfPresent(Bool.self,forKey:.useFocusedTextWhenUnselected) ?? false
        previewShortcutsEnabled = try c.decodeIfPresent(Bool.self,forKey:.previewShortcutsEnabled) ?? false
        blockNetworkRequests = try c.decodeIfPresent(Bool.self,forKey:.blockNetworkRequests) ?? false
        polishTone = try c.decodeIfPresent(OfflineRewriteTone.self,forKey:.polishTone) ?? .natural
        offlineAIRewriting = try c.decodeIfPresent(Bool.self,forKey:.offlineAIRewriting) ?? false
        holdFnEnabled = try c.decodeIfPresent(Bool.self,forKey:.holdFnEnabled) ?? true
    }
}
@MainActor final class DictationPreferenceStore {
    private let defaults: UserDefaults
    private let key = "dictation.preferences.v1"
    private(set) var error: String?
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> DictationPreferences {
        guard let data = defaults.data(forKey:key) else { return .init() }
        guard data.count <= 65_536, let value = try? JSONDecoder().decode(DictationPreferences.self,from:data), value.version == 1, value.formatting.isValid else {
            error = "Saved settings are unreadable or from another version. They were preserved; changes will not overwrite them."
            return .init()
        }
        return value
    }
    func save(_ value: DictationPreferences) {
        guard error == nil, value.version == 1, value.formatting.isValid, let data = try? JSONEncoder().encode(value) else { return }
        guard data.count <= 65_536 else { return }
        defaults.set(data,forKey:key)
    }
}

// Presentation values are shared by the actual view and focused interaction tests.
enum CompactWindowLayout {
    static let defaultSize = CGSize(width:960,height:620)
    static let minimumSize = CGSize(width:800,height:520)
    static let sidebarWidth: CGFloat = 230
}
struct SidebarPresentation: Equatable {
    enum Foreground: Equatable { case muted, emphasized, accent }
    var selected: Bool
    var hovered = false
    var pressed = false
    var iconWeight: Font.Weight { selected ? .semibold : .regular }
    var foreground: Foreground { selected ? .accent : hovered ? .emphasized : .muted }
    var backgroundOpacity: Double { selected ? 1 : pressed ? 0.75 : hovered ? 0.5 : 0 }
}

/// Pure presentation aggregation. Calendar arithmetic, never 86,400-second day steps.
struct DictationActivity: Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let count: Int
        let future: Bool
        var id: Date { date }
        var level: Int { Self.intensity(count) }
        static func intensity(_ count:Int) -> Int { count <= 0 ? 0 : count == 1 ? 1 : count <= 3 ? 2 : count <= 7 ? 3 : 4 }
    }
    let days: [Day]
    let calendar: Calendar
    let currentStreak: Int
    let longestStreak: Int
    let eligibleCount: Int
    static func includes(_ entry:DictationHistoryEntry) -> Bool {
        guard entry.cleaned.contains(where:{ !$0.isWhitespace }) else { return false }
        switch entry.insertion.reason {
        case .speechFailed: return false
        case .cancelled,.deadline: return entry.insertion.attempted
        default: return true
        }
    }
    init(entries:[DictationHistoryEntry], now:Date, calendar:Calendar) {
        self.calendar = calendar
        let today = calendar.startOfDay(for:now)
        var seen = Set<String>(), counts: [Date:Int] = [:]
        for entry in entries where entry.timestamp.timeIntervalSince1970.isFinite && entry.timestamp <= now && Self.includes(entry) {
            guard seen.insert(entry.id).inserted else { continue }
            counts[calendar.startOfDay(for:entry.timestamp),default:0] += 1
        }
        eligibleCount = counts.values.reduce(0,+)
        let week = calendar.dateInterval(of:.weekOfYear,for:today)?.start ?? today
        let start = calendar.date(byAdding:.weekOfYear,value:-52,to:week) ?? today
        days = (0..<371).compactMap { index in
            guard let day = calendar.date(byAdding:.day,value:index,to:start) else { return nil }
            return Day(date:day,count:day > today ? 0 : counts[day,default:0],future:day > today)
        }
        var current = 0, cursor = today
        while counts[cursor,default:0] > 0 {
            current += 1
            guard let previous = calendar.date(byAdding:.day,value:-1,to:cursor) else { break }
            cursor = previous
        }
        currentStreak = current
        var longest = 0, run = 0, previous:Date?
        for date in counts.keys.sorted() {
            run = previous.flatMap { calendar.date(byAdding:.day,value:1,to:$0) } == date ? run + 1 : 1
            longest = max(longest,run); previous = date
        }
        longestStreak = longest
    }
    func monthLabelDate(column:Int) -> Date? {
        let slice = days.dropFirst(column*7).prefix(7)
        if let first = slice.first(where:{ calendar.component(.day,from:$0.date) == 1 }) { return first.date }
        guard column == 0, !days.dropFirst(7).prefix(21).contains(where:{ calendar.component(.day,from:$0.date) == 1 }) else { return nil }
        return slice.first?.date
    }
}

enum DictationRowPresentation {
    static func date(_ date:Date, calendar:Calendar = .autoupdatingCurrent, locale:Locale = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date:.abbreviated,time:.shortened)
        style.calendar = calendar; style.timeZone = calendar.timeZone; style.locale = locale
        return style.format(date)
    }
}

@MainActor enum HistoryClipboard {
    static func write(_ text:String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text,forType:.string)
    }
}

/// Feedback only: no clipboard authority. One cancellable generation per stable entry ID.
@MainActor final class HistoryCopyFeedback: ObservableObject {
    @Published private(set) var copied: Set<String> = []
    private var tasks: [String:Task<Void,Never>] = [:]
    private var generations: [String:UUID] = [:]
    private let clock: any TaskClock
    init(clock:any TaskClock = SystemTaskClock()) { self.clock = clock }
    func show(id:String) {
        tasks[id]?.cancel()
        let generation = UUID(); generations[id] = generation; copied.insert(id)
        tasks[id] = Task { [weak self,clock] in
            let now = await clock.now()
            guard now >= 0, now <= Int64.max - 1400 else { self?.expire(id:id,generation:generation); return }
            do { try await clock.sleep(until:now + 1400) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire(id:id,generation:generation)
        }
    }
    private func expire(id:String,generation:UUID) {
        guard generations[id] == generation else { return }
        copied.remove(id); generations[id] = nil; tasks[id] = nil
    }
    func retain(ids:Set<String>) {
        for id in Array(generations.keys) where !ids.contains(id) {
            tasks.removeValue(forKey:id)?.cancel(); generations[id] = nil; copied.remove(id)
        }
    }
    func cancelAll() { tasks.values.forEach { $0.cancel() }; tasks.removeAll(); generations.removeAll(); copied.removeAll() }
    deinit { tasks.values.forEach { $0.cancel() } }
}

/// View-only calendar labels. The stored timestamp and history query are unchanged.
enum DictationHistoryPresentation {
    static let timeColumnWidth: CGFloat = 78
    static func ordinal(_ day:Int) -> String {
        let suffix: String
        if (11...13).contains(day % 100) { suffix = "th" }
        else { switch day % 10 { case 1:suffix = "st"; case 2:suffix = "nd"; case 3:suffix = "rd"; default:suffix = "th" } }
        return "\(day)\(suffix)"
    }
    static func heading(_ date:Date, calendar:Calendar, locale:Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = locale
        if locale.language.languageCode?.identifier == "en", calendar.identifier == .gregorian {
            formatter.dateFormat = "MMMM y"
            return ordinal(calendar.component(.day,from:date)) + " " + formatter.string(from:date)
        }
        formatter.dateStyle = .long; formatter.timeStyle = .none
        return formatter.string(from:date)
    }
    static func time(_ date:Date, calendar:Calendar, locale:Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = locale
        formatter.dateStyle = .none; formatter.timeStyle = .short
        return formatter.string(from:date)
    }
}

struct DictationInsightsMetrics {
    struct Metric: Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }
    let values: [Metric]
    let durationCoverage: String
    init(entries:[DictationHistoryEntry],activity:DictationActivity) {
        // Zero is also the existing writer's missing-clock fallback; do not assert it
        // means a reliably measured zero-length recording. No storage migration.
        let reliable = entries.filter { (1...DictationText.maximumDurationMilliseconds).contains($0.durationMilliseconds) }
        let missing = entries.count - reliable.count
        let sum = reliable.reduce(Int64(0)) { value,entry in
            let addition = value.addingReportingOverflow(entry.durationMilliseconds)
            return addition.overflow ? Int64.max : addition.partialValue
        }
        let duration = entries.isEmpty ? "0:00" : reliable.isEmpty ? "Unavailable" : Duration.milliseconds(sum).formatted(.time(pattern:.minuteSecond))
        durationCoverage = missing == 0 ? "Recording time uses stored durations." : "Recording time covers \(reliable.count) of \(entries.count) saved dictations; \(missing) have unavailable timing (including ambiguous zero durations)."
        func streak(_ n:Int) -> String { "\(n) " + (n == 1 ? "day" : "days") }
        values = [
            .init(title:"Saved Dictations",value:String(entries.count)),
            .init(title:"Total Words",value:String(entries.reduce(0) { $0 + $1.wordCount })),
            .init(title:"Recording Time",value:duration),
            .init(title:"Verified Insertions",value:String(entries.filter { $0.insertion.outcome == .inserted && $0.insertion.attempted && $0.insertion.reason == .verified }.count)),
            .init(title:"Uncertain Insertions",value:String(entries.filter { $0.insertion.outcome == .uncertain && $0.insertion.status != .failed }.count)),
            .init(title:"Current Streak",value:streak(activity.currentStreak)),
            .init(title:"Longest Streak",value:streak(activity.longestStreak))
        ]
    }
    static func columns(width:CGFloat) -> Int { max(1,min(4,Int((max(0,width)+12)/142))) }
    static func gridHeight(width:CGFloat) -> CGFloat { CGFloat((7 + columns(width:width)-1)/columns(width:width))*76 + CGFloat((7-1)/columns(width:width))*12 }
}


/// Presentation only. The previous seven-metric contract remains available unchanged.
struct SketchInsightsSummary {
    struct Usage: Identifiable, Equatable {
        let name: String
        let words: Int
        var id: String { name }
    }
    let values: [DictationInsightsMetrics.Metric]
    let appUsage: [Usage]
    let timingNote: String
    let usageNote: String
    init(entries:[DictationHistoryEntry],activity:DictationActivity) {
        var seen = Set<String>()
        let saved = entries.filter { seen.insert($0.id).inserted }
        let words = saved.reduce(0) { $0 + $1.wordCount }
        let timed = saved.filter { (1...DictationText.maximumDurationMilliseconds).contains($0.durationMilliseconds) }
        let milliseconds = timed.reduce(0.0) { $0 + Double($1.durationMilliseconds) }
        let completeTiming = !saved.isEmpty && timed.count == saved.count && milliseconds > 0
        let wpm = completeTiming ? (Double(words)*60_000/milliseconds).formatted(.number.precision(.fractionLength(0))) : "Unavailable"
        timingNote = completeTiming ? "Average WPM uses total saved words divided by total stored recording time." : "Average WPM unavailable: reliable timing covers \(timed.count) of \(saved.count) saved dictations."
        values = [
            .init(title:"Total Words",value:words.formatted()),
            .init(title:"Average WPM",value:wpm),
            .init(title:"Current Streak",value:"\(activity.currentStreak) \(activity.currentStreak == 1 ? "day" : "days")"),
            .init(title:"Longest Streak",value:"\(activity.longestStreak) \(activity.longestStreak == 1 ? "day" : "days")")
        ]
        var totals:[String:Int] = [:], missingNames = 0
        for entry in saved where entry.insertion.outcome == .inserted && entry.insertion.reason == .verified && entry.insertion.attempted {
            guard let name = entry.sourceApplication?.trimmingCharacters(in:.whitespacesAndNewlines), !name.isEmpty else { missingNames += 1; continue }
            totals[name,default:0] += entry.wordCount
        }
        appUsage = totals.filter { $0.value > 0 }.map { Usage(name:$0.key,words:$0.value) }.sorted { $0.words == $1.words ? $0.name < $1.name : $0.words > $1.words }
        usageNote = "Only verified insertion outcomes count, grouped by saved application name; failed and uncertain delivery are excluded." + (missingNames > 0 ? " \(missingNames) verified entries lack an application name." : "")
    }
}

extension DictationHistoryPresentation {
    static func sectionHeading(_ date:Date,now:Date,calendar:Calendar,locale:Locale = .autoupdatingCurrent) -> String {
        if calendar.isDate(date,inSameDayAs:now) {
            if locale.language.languageCode?.identifier == "en" { return "TODAY" }
            let formatter = DateFormatter(); formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium; formatter.timeStyle = .none; formatter.doesRelativeDateFormatting = true
            return formatter.string(from:date)
        }
        return heading(date,calendar:calendar,locale:locale)
    }
}


/// Native service status is the source of truth; no synthetic persisted login toggle.
@MainActor final class LoginItemControl: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var message = ""
    @Published private(set) var updating = false
    var enabled: Bool { status == .enabled || status == .requiresApproval }
    var summary: String {
        switch status {
        case .enabled: "Enabled"
        case .requiresApproval: "Requires approval in System Settings"
        case .notRegistered: "Not registered"
        case .notFound: "App service not found"
        @unknown default: "Unknown authorization state"
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ requested: Bool) {
        guard !updating else { return }; updating = true; message = ""
        Task {
            defer { updating = false; refresh() }
            do { if requested { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() } }
            catch { message = "Login-item change was not accepted. Check Login Items in System Settings." }
        }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

enum FlowTypography {
    static let pageTitle: CGFloat = 26
    static let body: CGFloat = 13
    static let sidebar: CGFloat = 14
    static let section = Font.system(size:12,weight:.semibold)
    static let setting = Font.body.weight(.medium)
    static let secondary = Font.caption
}
