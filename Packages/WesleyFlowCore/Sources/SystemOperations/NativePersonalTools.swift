import AppKit
import EventKit
import UserNotifications
import Domain

/// Native APIs only, closed templates. No subprocess, shell, JS or accessibility control.
@MainActor public final class NativePersonalTools: PersonalToolRunning {
    private let events = EKEventStore()
    private let routineURL:URL?
    public init(routineURL:URL?=nil) {self.routineURL=routineURL}
    private func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")
            .replacingOccurrences(of:"\r",with:"\\r").replacingOccurrences(of:"\n",with:"\\n") + "\""
    }
    private func script(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source:source) else { throw PersonalAgentError.invalidCommand }
        let result = script.executeAndReturnError(&error)
        guard error == nil, let text = result.stringValue else {
            if error?[NSAppleScript.errorNumber] as? Int == -1743 { throw PersonalAgentError.permissionDenied }
            throw PersonalAgentError.verificationFailed
        }
        return text
    }
    private func grant(_ type: EKEntityType) async throws {
        let status = EKEventStore.authorizationStatus(for:type)
        if status == .fullAccess { return }
        guard status == .notDetermined else { throw PersonalAgentError.permissionDenied }
        let store = events
        let allowed: Bool = try await withCheckedThrowingContinuation { completion in
            let callback: @Sendable (Bool, (any Error)?) -> Void = { allowed, error in
                if let error { completion.resume(throwing:error) } else { completion.resume(returning:allowed) }
            }
            if type == .reminder { store.requestFullAccessToReminders(completion:callback) }
            else { store.requestFullAccessToEvents(completion:callback) }
        }
        guard allowed else { throw PersonalAgentError.permissionDenied }
    }
    public func perform(_ step: PersonalStep) async throws -> PersonalReceipt {
        guard !step.text.isEmpty, step.text.utf8.count <= step.maximumPayloadBytes,
              !step.text.unicodeScalars.contains(where: { $0.value < 32 && $0 != "\n" && $0 != "\r" && $0 != "\t" }) else { throw PersonalAgentError.invalidCommand }
        try Task.checkCancellation()
        switch step.tool {
        case .website: return try await NativeWebsiteOpening.perform(step)
        case .openInstalledApp: return try await NativePersonalApps.open(step.text)
        case .closeApp: return try await NativePersonalApps.close(step.text)
        case .createFolder,.openFolder,.closeFolder,.findFolder,.trashFolder: return try await NativePersonalFolders.perform(step)
        case .searchBrowser: return try await NativePersonalFolders.searchBrowser(step.text)
        case .messageSchedule: return try await NativeScheduledMessages.perform(step)
        case .menuAction: return try await NativeMenuActions.perform(step)
        case .mailAction: return try NativeMailActions.perform(step)
        case .routineSave: return try PersonalRoutineStore(url:routineURL ?? PersonalRoutineStore.defaultURL).save(PersonalRoutineSave.decode(step.text))
        case .browserExtra: return try NativeBrowserExtra.perform(step)
        case .screenCapture: return try await NativeScreenCapture.perform(step)
        case .fileAction: return try await NativeFileActions.perform(step)
        case .notesAction: return try NativeNotesActions.perform(step)
        case .mediaAction: return try await NativeMediaActions.perform(step)
        case .contactAction: return try await NativeContactActions.perform(step)
        case .recordAction: return try await NativeRecordTools.perform(step)
        case .ownedTimers: return try await NativeOwnedTimers.perform(step)
        case .macControl: return try await NativeMacControl.perform(step)
        case .systemAudio,.browserControl: return try NativePersonalControls.perform(step)
        case .minimizeApp,.restoreApp,.fullScreenApp,.exitFullScreenApp,.maximizeApp,.layoutApp: return try await NativePersonalWindows.perform(step)
        case .searchGoogle, .searchYouTube: return try await NativePersonalApps.search(step.text,youtube:step.tool == .searchYouTube)
        case .message:
            let message=try PersonalMessage.decode(step.text)
            guard let address=message.address,PersonalMessage.validAddress(address) else { throw PersonalAgentError.invalidCommand }
            _ = try script("""
            with timeout of 10 seconds
              tell application id "com.apple.MobileSMS"
                set targetService to first service whose service type is iMessage
                set targetBuddy to buddy \(literal(address)) of targetService
                send \(literal(message.body)) to targetBuddy
                return "dispatch-returned"
              end tell
            end timeout
            """)
            return PersonalReceipt(identifier:step.id.uuidString,evidence:"Messages send call returned; delivery unverified. Inspect Messages before any retry.",verified:false)
        case .openApp:
            guard let command = AppOpeningCommand(rawValue:step.text) else { throw PersonalAgentError.unsupported }
            try await NativeAppOpening.open(command)
            return PersonalReceipt(identifier:step.id.uuidString,evidence:"NSWorkspace openApplication completion; app launch only")
        case .note:
            let marker = "Wesley Flow " + step.id.uuidString
            let html = step.text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;")
                .replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\n",with:"<br>")
            let identifier = try script("""
            with timeout of 10 seconds
              tell application id "com.apple.Notes"
                set matches to notes whose name is \(literal(marker))
                if (count of matches) is 0 then
                  set createdNote to make new note at default account with properties {name:\(literal(marker)), body:\(literal("<h1>" + marker + "</h1><div>" + html + "</div>"))}
                else
                  set createdNote to item 1 of matches
                end if
                if not ((body of createdNote) contains \(literal(marker))) then error "verification failed"
                return id of createdNote
              end tell
            end timeout
            """)
            guard !identifier.isEmpty else { throw PersonalAgentError.verificationFailed }
            return PersonalReceipt(identifier:identifier,evidence:"Notes returned note ID and marker readback; content fidelity requires physical check")
        case .reminder:
            guard let date = step.date, date > Date() else { throw PersonalAgentError.invalidCommand }
            try await grant(.reminder); try Task.checkCancellation()
            guard let calendar = events.defaultCalendarForNewReminders() else { throw PersonalAgentError.unsupported }
            let reminder = EKReminder(eventStore:events); reminder.calendar = calendar; reminder.title = step.text
            reminder.url = URL(string:"wesleyflow-task://step/" + step.id.uuidString)
            reminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone],from:date)
            reminder.addAlarm(EKAlarm(absoluteDate:date))
            try events.save(reminder,commit:true)
            guard let saved = events.calendarItem(withIdentifier:reminder.calendarItemIdentifier) as? EKReminder,
                  saved.title == step.text, saved.dueDateComponents == reminder.dueDateComponents else { throw PersonalAgentError.verificationFailed }
            return PersonalReceipt(identifier:reminder.calendarItemIdentifier,evidence:"EventKit saved reminder title and due components read back")
        case .calendar:
            guard let date = step.date, date > Date() else { throw PersonalAgentError.invalidCommand }
            try await grant(.event); try Task.checkCancellation()
            guard let calendar = events.defaultCalendarForNewEvents else { throw PersonalAgentError.unsupported }
            let event = EKEvent(eventStore:events); event.calendar = calendar; event.title = step.text
            event.startDate = date; event.endDate = date.addingTimeInterval(1800)
            event.url = URL(string:"wesleyflow-task://step/" + step.id.uuidString)
            try events.save(event,span:.thisEvent,commit:true)
            guard let id = event.eventIdentifier, let saved = events.event(withIdentifier:id), saved.title == step.text,
                  saved.startDate == date else { throw PersonalAgentError.verificationFailed }
            return PersonalReceipt(identifier:id,evidence:"EventKit read back title/start; 30 minute event without attendees")
        case .timer:
            guard let date = step.date, date.timeIntervalSinceNow >= 1 else { throw PersonalAgentError.invalidCommand }
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options:[.alert,.sound]) else { throw PersonalAgentError.permissionDenied }
            try Task.checkCancellation()
            let content = UNMutableNotificationContent(); content.title = "Wesley Flow timer"; content.body = step.text; content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching:Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone],from:date),repeats:false)
            try await center.add(UNNotificationRequest(identifier:"wesleyflow.timer."+step.id.uuidString,content:content,trigger:trigger))
            guard await center.pendingNotificationRequests().contains(where: { $0.identifier == "wesleyflow.timer."+step.id.uuidString }) else { throw PersonalAgentError.verificationFailed }
            return PersonalReceipt(identifier:step.id.uuidString,evidence:"Notification pending request verified; delivery depends on sleep/Focus/system settings")
        case .safari:
            guard let url = URL(string:step.text), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw PersonalAgentError.invalidCommand }
            let readback = try script("""
            with timeout of 10 seconds
              tell application id "com.apple.Safari"
                make new document with properties {URL:\(literal(url.absoluteString))}
                return URL of front document
              end tell
            end timeout
            """)
            guard readback == url.absoluteString else { throw PersonalAgentError.verificationFailed }
            return PersonalReceipt(identifier:readback,evidence:"Safari URL readback; loading and website access require connectivity")
        case .music, .spotify:
            guard ["play","pause","next","previous"].contains(step.text) else { throw PersonalAgentError.unsupported }
            let app = step.tool == .music ? "com.apple.Music" : "com.spotify.client"
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:app) != nil else { throw PersonalAgentError.unsupported }
            if ["next","previous"].contains(step.text) { return try await NativePersonalControls.changeTrack(step) }
            let state = try script("""
            with timeout of 10 seconds
              tell application id "\(app)"
                \(step.text)
                return player state as text
              end tell
            end timeout
            """)
            guard state == (step.text == "play" ? "playing" : "paused") else { throw PersonalAgentError.verificationFailed }
            return PersonalReceipt(identifier:app,evidence:"Player state readback: " + state + "; streaming may require connectivity")
        }
    }
}
