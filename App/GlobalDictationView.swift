import SwiftUI
import Charts
import AppKit
import Domain
import VoiceInput

@MainActor struct GlobalDictationView: View {
    @ObservedObject var coordinator: SystemWideDictationCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: DictationPage = .dictation
    @State private var speakerFilter = "all"
    @State private var selectedEntry: DictationHistoryEntry?
    @State private var confirmClear = false
    @State private var observedAgentSteps:Set<UUID>=[]
    @State private var showingCommandActivity = false
    @State private var deletingEntry: DictationHistoryEntry?
    @State private var copyError: String?
    @StateObject private var copyFeedback = HistoryCopyFeedback()
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @State private var confirmRestore = false
    @State private var recoveryID: String?
    @State private var showingSpeechSetup = false
    @StateObject private var loginItem = LoginItemControl()
    @ScaledMetric(relativeTo:.title2) private var headingSize = FlowTypography.pageTitle
    @ScaledMetric(relativeTo:.body) private var bodySize = FlowTypography.body
    @ScaledMetric(relativeTo:.body) private var navigationSize = FlowTypography.sidebar
    init(coordinator: SystemWideDictationCoordinator, initialPage: DictationPage? = nil, restoredSelection: String? = nil) {
        self.coordinator = coordinator; _page = State(initialValue:initialPage ?? DictationPage.restoring(restoredSelection))
    }
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:8) {
                    Image(systemName:"waveform.circle.fill").font(.system(size:19)).foregroundStyle(FlowSurface.accent)
                    Text("Wesley Flow").font(.system(size:15,weight:.semibold))
                }.padding(.horizontal,18).frame(minHeight:52)
                Divider().overlay(FlowSurface.border)
                ScrollView {
                VStack(spacing:3) {
                    ForEach(DictationPage.sidebar) { destination in
                        Button { page = destination } label: {
                            HStack(spacing:11) {
                                Image(systemName:destination.symbol).imageScale(.large).frame(width:22).accessibilityHidden(true)
                                Text(destination.rawValue).foregroundStyle(FlowSurface.text).font(.system(size:navigationSize,weight:page.sidebarSelection == destination ? .semibold : .regular))
                                Spacer(minLength:0)
                            }.frame(minHeight:42).padding(.leading,16).padding(.trailing,10)
                        }
                        .buttonStyle(FlowSidebarStyle(selected:page.sidebarSelection == destination))
                        .accessibilityAddTraits(page.sidebarSelection == destination ? .isSelected : [])
                    }
                }.padding(10)
                }.scrollIndicators(.hidden)
                .onMoveCommand { direction in
                    switch direction {
                    case .up: page = page.moving(-1)
                    case .down: page = page.moving(1)
                    default: break
                    }
                }
            }
            .frame(width:CompactWindowLayout.sidebarWidth).frame(maxHeight:.infinity)
            .background(FlowSurface.sidebar)
            .accessibilityElement(children:.contain).accessibilityIdentifier("wesley.permanentSidebar")
            Rectangle().fill(FlowSurface.border).frame(width:1)
            VStack(spacing:0) {
                HStack {
                    Text(page.rawValue).font(.system(size:headingSize,weight:.semibold))
                    Spacer()
                    if page == .speechRecognition {
                        Button("Apple Speech setup…") { showingSpeechSetup = true }
                            .popover(isPresented: $showingSpeechSetup) {
                                FlowPage { appleSpeechSettings }.frame(width: 450, height: 340)
                            }
                    }
                    if page == .history { Button("Back to Dictation") { page = .dictation } }
                    if page == .dictation || page == .history { HistoryHeaderSearch(text:$coordinator.search) }
                }.padding(.horizontal,22).frame(minHeight:56).layoutPriority(1)
                if page == .dictation || page == .history { Divider().overlay(FlowSurface.border) }
                Group {
                    switch page {
                    case .dictation: dictationPage
                    case .speechRecognition:
                        FlowPage {
                            if let speakers = coordinator.speakers {
                                SpeakerSettingsView(settings: speakers, dictationBusy: coordinator.busy || coordinator.speechResourceWorking)
                            } else {
                                Text("Voice profiles are unavailable in this session.").foregroundStyle(.secondary)
                            }
                        }
                    case .history: historyPage
                    case .commands: commandsPage
                    case .insights: insightsPage
                    case .smartFormatting: formattingPage
                    case .privacy: privacyPage
                    case .general: generalPage
                    }
                }.frame(maxWidth:.infinity,minHeight:0,maxHeight:.infinity).id(page).transition(.opacity)
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(FlowSurface.canvas)
        }
        .foregroundStyle(FlowSurface.text)
        .font(.system(size:bodySize))
        .tint(FlowSurface.accent)
        .toggleStyle(.switch)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.18),value:page)
        .frame(minWidth:CompactWindowLayout.minimumSize.width,minHeight:CompactWindowLayout.minimumSize.height)
        .preferredColorScheme(coordinator.preferences.appearance.colorScheme)
        .sheet(item:$selectedEntry) { entry in
            VStack(alignment:.leading,spacing:0) {
                if entry.id == coordinator.unmergedSpeechRecoveryEntry?.id {
                    Text("Unmerged recognition candidate: may overlap earlier speech. Review separately before copying. Kept in memory until the next dictation or quit; never inserted automatically.")
                        .font(.callout).foregroundStyle(.orange).padding(.horizontal,24).padding(.top,16).frame(width:640)
                }
                DictationEntryDetail(entry:entry,canCopy:coordinator.historyCopyAllowed,copyText:coordinator.copyReviewedText,feedback:copyFeedback)
            }
        }
        .confirmationDialog("Delete this dictation?",isPresented:Binding(get:{ deletingEntry != nil },set:{ if !$0 { deletingEntry = nil } }),presenting:deletingEntry) { entry in
            Button("Delete",role:.destructive) { let id = entry.id; Task { await coordinator.deleteHistory(id:id) } }
        } message: { _ in Text("This permanently removes this entry from local history. Other entries are preserved.") }
        .onDisappear { copyFeedback.cancelAll() }
        .onChange(of:coordinator.agentReviewRequest) { _,_ in
            page = .commands
            showingCommandActivity = false
            if NSClassFromString("XCTestCase") == nil { openWindow(id:"foundation"); NSApplication.shared.activate() }
        }
        .onChange(of:coordinator.flowPageRequestID) { _,_ in
            if let destination = coordinator.flowPageRequest { page = destination }
            if NSClassFromString("XCTestCase") == nil { openWindow(id:"foundation"); NSApplication.shared.activate() }
        }
        .onChange(of:page) { _, destination in
            copyFeedback.cancelAll()
            copyError = nil
            if destination != .speechRecognition { showingSpeechSetup = false }
        }
        .onChange(of:coordinator.entries.map(\.id)) { _,ids in copyFeedback.retain(ids:Set(ids)) }
        .confirmationDialog("Clear all local dictation history?",isPresented:$confirmClear) {
            Button("Clear all history",role:.destructive) { Task { await coordinator.clearHistory() } }
        } message: { Text("This removes saved transcripts from this app. Backups and clipboard managers may retain copies.") }
        .confirmationDialog("Have you confirmed the pending paste has completed?",isPresented:$confirmRestore) {
            let expectedRecoveryID = recoveryID
            Button("I confirmed it — restore saved clipboard") { coordinator.restoreClipboardAfterConfirmation(expectedRecoveryID:expectedRecoveryID) }
        } message: { Text("The app could not verify paste completion. Restoration is attempted only while this app still owns the clipboard; newer clipboard contents are preserved. Restoring the clipboard does not paste or retry this dictation. Your recording remains in History; use a fresh Fn recording to try again.") }
        .onReceive(Timer.publish(every:2,on:.main,in:.common).autoconnect()) { _ in
            if NSClassFromString("XCTestCase") == nil { coordinator.refreshPermissions() }
        }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in if NSClassFromString("XCTestCase") == nil { loginItem.refresh(); coordinator.resumeShortcutIfAuthorized() } }
    }
    private var dictationPage: some View {
        VStack(alignment:.leading,spacing:0) {
            if coordinator.busy || (coordinator.phase == .error && coordinator.lastAIShortcutFailure == nil) || coordinator.clipboardPending || coordinator.historyError != nil || copyError != nil {
                VStack(alignment:.leading,spacing:8) {
                    if coordinator.busy { HStack { Text(coordinator.message).font(.callout); Spacer(); Button("Cancel dictation") { coordinator.cancel() } } }
                    if coordinator.phase == .error && !coordinator.clipboardPending && coordinator.lastAIShortcutFailure == nil {
                        Text(coordinator.message).font(.callout).foregroundStyle(.orange)
                        HStack {
                            Button("Language & microphone settings") { page = .general }
                            Button("Copy dictation & AI diagnostics") { _ = coordinator.copyReviewedText(coordinator.combinedDictationDiagnostics) }.disabled(!coordinator.historyCopyAllowed)
                        }
                    }
                    if coordinator.clipboardPending {
                        Text("A paste remains unverified. Its clipboard backup is retained.").font(.callout).foregroundStyle(.orange)
                        Button("Review clipboard restoration…") { recoveryID = coordinator.clipboardRecoveryID; confirmRestore = recoveryID != nil }.disabled(coordinator.busy)
                    }
                    if let latest = coordinator.latest, !coordinator.busy {
                        Button(latest.insertion.reason == .speechFailed ? "Copy partial recognized text" : "Copy latest dictation") {
                            if coordinator.copyReviewedText(latest.cleaned) { copyError = nil }
                            else { copyError = "Resolve clipboard recovery before copying. Your latest transcript remains available for review." }
                        }.disabled(!coordinator.historyCopyAllowed)
                        .help("Explicit copy only. Pending clipboard recovery must be resolved first.")
                    }
                    if let candidate = coordinator.unmergedSpeechRecoveryEntry, !coordinator.busy {
                        Button("Review unmerged speech candidate") { selectedEntry = candidate }
                            .help("May overlap earlier recognized speech. Review separately; never inserted automatically.")
                    }
                    if let error = coordinator.historyError { Text(error).font(.callout).foregroundStyle(.orange); Button("Retry history") { Task { await coordinator.loadHistory() } } }
                    if let copyError { Text(copyError).font(.callout).foregroundStyle(.orange) }
                }.padding(.horizontal,22).padding(.vertical,12)
                Divider()
            }
            if let latest = coordinator.latest, !coordinator.entries.contains(where:{ $0.id == latest.id }) {
                Button(latest.insertion.reason == .speechFailed ? "Review partial recognized text" : "Review latest unsaved dictation") { selectedEntry = latest }.padding(.horizontal,22).padding(.vertical,8)
            }
            if !speakerCategories.isEmpty {
                Picker("Speaker", selection: $speakerFilter) {
                    Text("All speakers").tag("all")
                    ForEach(speakerCategories, id: \.key) { category in
                        Text(category.name).tag(category.key)
                    }
                }.padding(.horizontal,22).padding(.vertical,8)
                .onChange(of:speakerCategories.map(\.key)) { _,keys in
                    if speakerFilter != "all", !keys.contains(speakerFilter) { speakerFilter = "all" }
                }
            }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:0,pinnedViews:[.sectionHeaders]) {
                    ForEach(DictationHistoryQuery.groups(speakerFilteredHistory,calendar:localCalendar),id:\.date) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                historyRow(entry).transition(.opacity)
                                Divider().padding(.horizontal,20)
                            }
                        } header: {
                            Text(DictationHistoryPresentation.sectionHeading(group.date,now:Date(),calendar:localCalendar))
                                .font(.system(size:12,weight:.semibold)).tracking(1.1).foregroundStyle(.secondary)
                                .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,28).padding(.vertical,11)
                                .background(FlowSurface.canvas)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    if speakerFilteredHistory.isEmpty { Text(coordinator.entries.isEmpty ? "No saved dictations yet." : "No matching dictations.").foregroundStyle(.secondary).padding(22).frame(maxWidth:.infinity,alignment:.leading) }
                }.animation(reduceMotion ? nil : .easeInOut(duration:0.16),value:coordinator.entries.map(\.id))
            }.scrollIndicators(.hidden)

        }
    }
    private var permissionsSummary: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Permissions").font(.headline)
            LabeledContent("Microphone",value:coordinator.microphoneStatus)
            LabeledContent("Apple Speech",value:coordinator.speechStatus)
            LabeledContent("Text insertion",value:coordinator.accessibilityAllowed ? "Accessibility allowed" : "Accessibility needed")
            if !coordinator.accessibilityAllowed { Button("Allow text insertion…") { coordinator.requestAccessibility() } }
            Text("If access is denied, you can still dictate here and copy the text manually.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private static let macCommandHelp = ["Open Notes":"Open the Notes app.","Set volume to thirty percent":"Set system output volume to 30%.","Turn volume up":"Increase system output volume.","Mute audio":"Mute system output audio.","Show battery status":"Read the current battery level.","Move Safari to the left half":"Place Safari's window on the left half of its display."]
    private var commandsPage: some View {
        FlowPage {
            Text("Hold \(coordinator.preferences.agentKey.label) for Agent commands; hold \(coordinator.preferences.activationKey.label) for dictation. Speak Agent commands in English. Language commands change your next dictation.").foregroundStyle(.secondary)
            FlowSettingsGroup("Command key") {
                FlowSettingsRow("Enable command key",description:coordinator.agentShortcutStatus) {
                    Toggle("Enable command key",isOn:Binding(get:{coordinator.preferences.agentHotkeyEnabled},set:{ if $0 {coordinator.enableAgentShortcut()} else {coordinator.disableAgentShortcut()} })).disabled(coordinator.busy)
                }
                FlowSettingsRow("Agent key",description:"Choose a key separate from dictation.") {
                    Picker("Agent key",selection:Binding(get:{ coordinator.preferences.agentKey },set:{ coordinator.changeAgentKey($0) })) {
                        ForEach(DictationActivationKey.allCases,id:\.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu).disabled(coordinator.busy)
                }
            }
            Text(coordinator.agentNotice).font(.callout).foregroundStyle(coordinator.phase == .error ? .orange : .secondary)
            if let failure=coordinator.lastAgentFailure {
                Text(failure).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                Button("Copy command speech diagnostics") { _ = coordinator.copyReviewedText(coordinator.speechDiagnosticSummary) }.disabled(!coordinator.historyCopyAllowed)
            }
            if let question=coordinator.agentQuestion {
                VStack(alignment:.leading,spacing:8) {
                    Text(question.prompt).font(.headline)
                    Text("Reply with the Agent key or type below. Cancel starts over. This question expires after two minutes.").font(.caption).foregroundStyle(.secondary)
                    ForEach(question.options) { option in
                        Button(option.label) { coordinator.submitAgentReply(option.answer,questionID:question.id) }.disabled(coordinator.busy)
                    }
                    TextField("Your reply…",text:$coordinator.agentReplyText).onSubmit { coordinator.submitAgentReply(questionID:question.id) }
                    HStack {
                        Button("Continue") { coordinator.submitAgentReply(questionID:question.id) }.disabled(coordinator.busy || coordinator.agentReplyText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        Button("Cancel request") { coordinator.cancelAgentConversation() }.disabled(coordinator.busy)
                    }
                }.padding(12).background(FlowSurface.card,in:RoundedRectangle(cornerRadius:12))
            }
            if let plan = coordinator.agentPlan {
                ForEach(plan.steps) { step in
                    Text(step.userSummary(apps:[]))
                }
                if plan.steps.count==1,plan.steps.first?.tool == .message {
                    Text("Say ‘change the message to …’ or ‘change the recipient to …’ to replace this draft. Voice ‘yes’ never sends it.").font(.caption).foregroundStyle(.secondary)
                    TextField("New message text…",text:$coordinator.agentReplyText).onSubmit { coordinator.applyAgentMessageEdit() }
                    HStack {
                        Button("Apply message change") { coordinator.applyAgentMessageEdit() }.disabled(coordinator.busy || coordinator.agentReplyText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        Button("Clear edit") { coordinator.agentReplyText="" }.disabled(coordinator.busy || coordinator.agentReplyText.isEmpty)
                    }
                    if !coordinator.agentReplyText.isEmpty { Text("Apply or clear this edit before sending.").font(.caption).foregroundStyle(.secondary) }
                }
                Button(plan.steps.contains(where:{$0.tool == .mailAction && (try? PersonalMailCommand.decode($0.text).action) == .send}) ? "Send this reviewed email" : plan.steps.contains(where:{$0.tool == .message}) ? "Send this reviewed message" : plan.steps.contains(where:{$0.tool == .trashFolder}) ? "Move reviewed folder to Trash" : "Approve these actions and run") { coordinator.approveAgentPlan(expectedPlan:plan) }.disabled(coordinator.busy || (plan.steps.contains(where:{$0.tool == .message}) && !coordinator.agentReplyText.isEmpty))
                Button("Reject plan") { coordinator.cancelAgentTask(plan.id) }.disabled(coordinator.busy)
            }
            if let name=coordinator.agentEditingRoutine {
                Text("Edit routine: "+name).font(.headline)
                ForEach(Array(coordinator.agentRoutineExistingSteps.enumerated()),id:\.offset) { _,summary in Text(summary).font(.caption) }
                Text("Enter one complete replacement command per line, up to eight steps. Saving does not run them.").font(.caption)
                TextEditor(text:$coordinator.agentRoutineEditText).frame(minHeight:80)
                HStack {Button("Review revised routine") {coordinator.saveAgentRoutineEdits()};Button("Cancel editing") {coordinator.cancelAgentRoutineEdits()}}
            }
            if !coordinator.agentRecords.isEmpty || !coordinator.agentScheduledDrafts.isEmpty {
                Button("Review saved command activity…") { showingCommandActivity = true }
            }
            FlowSettingsGroup("Dictation controls") {
                FlowSettingsRow("Current dictation language") { Text(coordinator.preferences.languageMode == .english ? "English" : (coordinator.preferences.teluguRecognitionLanguage == .teluguOnly ? "Telugu only" : "Telugu + English")).foregroundStyle(.secondary) }
                ForEach(FlowVoiceControl.examples,id:\.self) { example in
                    FlowCommandHelpRow(command:example,explanation:FlowVoiceControl.parse(example)?.helpDescription ?? "")
                }
            }
            FlowSettingsGroup("Keep awake by voice") {
                Text(coordinator.keepAwakeStatus).font(.callout).foregroundStyle(.secondary).padding(12)
                FlowCommandHelpRow(command: "Make my screen active until I say, turn it off", explanation: "Keep the display awake until a stop command.")
                FlowCommandHelpRow(command: "Keep my screen awake for one hour", explanation: "Set a timer of up to 24 hours.")
                FlowCommandHelpRow(command: "Keep my screen awake until Xcode quits", explanation: "Watch one currently running app.")
                FlowCommandHelpRow(command: "Keep my screen awake until report.zip is downloaded", explanation: "Watch for a new file with that name in Downloads.")
                FlowCommandHelpRow(command: "Cover the screen", explanation: "Keep work running behind the privacy curtain. Use Touch ID to reveal it.")
                FlowCommandHelpRow(command: "Cover the screen by making it awake for one hour", explanation: "The timer ends keep awake. The curtain stays until Touch ID.")
                Text("The curtain temporarily turns off Swipe between spaces and restores your previous Trackpad choice. Other system controls can still bypass it.")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
                FlowCommandHelpRow(command: "Turn it off", explanation: "End the active keep-awake session.")
            }
            FlowSettingsGroup("Everyday Mac actions") {
                ForEach(["Open Notes","Set volume to thirty percent","Turn volume up","Mute audio","Show battery status","Move Safari to the left half"],id:\.self) { example in
                    FlowCommandHelpRow(command:example,explanation:Self.macCommandHelp[example] ?? "")
                }
            }
        }
        .sheet(isPresented:$showingCommandActivity) {
            commandActivitySheet
        }
    }
    private var commandActivitySheet: some View {
        FlowPage {
            HStack {
                Text("Command activity").font(.headline)
                Spacer()
                Button("Done") { showingCommandActivity = false }.keyboardShortcut(.cancelAction)
            }
            if !coordinator.agentScheduledDrafts.isEmpty {
                Text("Scheduled local message drafts").font(.headline)
                Text("These drafts never send automatically. At the due time, Review opens a fresh exact-send approval. Notification delivery depends on macOS settings.").font(.caption).foregroundStyle(.secondary)
                ForEach(coordinator.agentScheduledDrafts) { draft in
                    VStack(alignment:.leading,spacing:4) {
                        Text(verbatim:[draft.message.recipient,draft.date.formatted(),draft.state.rawValue].joined(separator:" · ")).font(.caption)
                        Text(draft.message.body).font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Review due message") {showingCommandActivity = false; coordinator.reviewScheduledDraft(draft.id)}.disabled(coordinator.busy || draft.state != .pending)
                            if draft.state != .pending {Button("Delete local draft record") {coordinator.deleteScheduledDraft(draft.id)}.disabled(coordinator.busy)}
                        }
                    }
                }
                Button("Refresh scheduled drafts") {coordinator.loadScheduledDrafts()}.disabled(coordinator.busy)
            }
            ForEach(coordinator.agentRecords.reversed()) { record in
                VStack(alignment:.leading,spacing:4) {
                    Text(verbatim:agentTaskHeading(record)).font(.caption)
                    ForEach(Array(record.plan.steps.enumerated()),id:\.element.id) { index, step in
                        Text(step.displayText + " · " + record.steps[index].rawValue + " · " + (record.receipts[index]?.evidence ?? "No verified receipt")).font(.caption)
                        if record.state == .needsReview,record.steps[index] == .uncertain,record.supersededBy==nil {
                            Toggle("I checked this exact action’s outcome in the native app",isOn:Binding(get:{observedAgentSteps.contains(step.id)},set:{if $0 {observedAgentSteps.insert(step.id)} else {observedAgentSteps.remove(step.id)}})).toggleStyle(.checkbox).font(.caption)
                            Button("Record my observation; do not replay") {coordinator.confirmObservedAgentStep(record.id,expectedStep:step);observedAgentSteps.remove(step.id)}.disabled(coordinator.busy || !observedAgentSteps.contains(step.id))
                            Text("Use only after actually checking. This does not prove message delivery, undo an effect or grant another send attempt.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        if record.state == .awaitingApproval { Button("Review") { showingCommandActivity = false; coordinator.reviewQueuedAgent(record.id) } }
                        if record.state == .running {Button("Pause after current step") {coordinator.pauseAgentTask(record.id)}}
                        if [PersonalTaskState.paused,.cancelled,.needsReview].contains(record.state),record.supersededBy==nil {Button("Continue with review") {showingCommandActivity = false; coordinator.continueAgentTask(record.id)}.disabled(coordinator.busy)}
                        if record.state == .running || record.state == .awaitingApproval { Button("Cancel remaining steps") { coordinator.cancelAgentTask(record.id) } }
                        Button("Delete task record") { coordinator.deleteAgentTask(record.id) }.disabled(coordinator.busy)
                    }
                }
            }
        }.frame(width:600,height:440)
    }
    private var historyPage: some View { dictationPage }
    private func speakerKey(_ entry: DictationHistoryEntry) -> String {
        entry.speaker.map { $0.profileID?.uuidString ?? "unknown" } ?? "unlabeled"
    }
    private var speakerFilteredHistory: [DictationHistoryEntry] {
        coordinator.filteredHistory.filter { speakerFilter == "all" || speakerKey($0) == speakerFilter }
    }
    private var speakerCategories: [(key: String, name: String)] {
        guard coordinator.entries.contains(where: { $0.speaker != nil }) else { return [] }
        var names: [String: String] = [:]
        for entry in coordinator.entries where names[speakerKey(entry)] == nil {
            names[speakerKey(entry)] = entry.speaker?.name ?? "Unlabeled"
        }
        return names.map { (key: $0.key, name: $0.value) }.sorted { ($0.name, $0.key) < ($1.name, $1.key) }
    }
    private func historyRow(_ entry: DictationHistoryEntry) -> some View {
        HStack(alignment:.center,spacing:12) {
            Text(DictationHistoryPresentation.time(entry.timestamp,calendar:localCalendar)).font(.body.weight(.medium)).monospacedDigit().foregroundStyle(.secondary).frame(width:DictationHistoryPresentation.timeColumnWidth,alignment:.leading).fixedSize(horizontal:false,vertical:true)
            Button { selectedEntry = entry } label: {
                VStack(alignment: .leading, spacing: 3) {
                    if let speaker = entry.speaker { Text(speaker.name).font(.caption).foregroundStyle(.secondary) }
                    Text(entry.cleaned).lineLimit(3)
                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Review full dictation")
            Button {
                if coordinator.copyHistory(id:entry.id) {
                    copyError = nil; copyFeedback.show(id:entry.id)
                    NSAccessibility.post(element:NSApplication.shared,notification:.announcementRequested,userInfo:[.announcement:"Dictation copied",.priority:NSAccessibilityPriorityLevel.low.rawValue])
                } else { copyError = "Copy is unavailable. Finish dictation or review the pending clipboard recovery first." }
            } label: { Image(systemName:copyFeedback.copied.contains(entry.id) ? "checkmark" : "doc.on.doc").font(.system(size:15)).frame(width:36,height:26) }
            .buttonStyle(.plain).foregroundStyle(copyFeedback.copied.contains(entry.id) ? FlowSurface.accent : Color.secondary)
            .accessibilityLabel(copyFeedback.copied.contains(entry.id) ? "Copied dictation" : "Copy dictation")
            .help(coordinator.historyCopyAllowed ? "Copy dictation" : "Finish dictation and resolve clipboard recovery before copying")
            .disabled(!coordinator.historyCopyAllowed)
            Button { deletingEntry = entry } label: { Image(systemName:"trash").font(.system(size:15)).frame(width:36,height:26) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Delete dictation").help("Delete this dictation…").disabled(coordinator.busy)
        }.padding(.horizontal,44).padding(.vertical,10).frame(minHeight:46)
    }
    private var localCalendar: Calendar { var value = calendar; value.timeZone = timeZone; return value }
    private var insightsPage: some View {
        FlowPage {
            TimelineView(.periodic(from:.now,by:60)) { context in
                let activity = DictationActivity(entries:coordinator.entries,now:context.date,calendar:localCalendar)
                let summary = SketchInsightsSummary(entries:coordinator.entries,activity:activity)
                VStack(alignment:.leading,spacing:18) {
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:10) { insightCards(summary) }
                        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) { insightCards(summary) }
                    }
                    Text(summary.timingNote).font(.caption).foregroundStyle(.secondary)
                    Text("Activity").font(.headline)
                    VStack(alignment:.leading,spacing:14) {
                        HStack(alignment:.firstTextBaseline) {
                            Text(activity.currentStreak == 1 ? "1 day in a row" : "\(activity.currentStreak) days in a row").font(.headline)
                            Spacer(minLength:12)
                            Text("Longest streak: \(activity.longestStreak) \(activity.longestStreak == 1 ? "day" : "days")").font(.caption).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal) {
                            DictationActivityHeatmap(activity:activity).frame(minWidth:680)
                        }.scrollIndicators(.hidden)
                    }.padding(14).background(FlowSurface.card,in:RoundedRectangle(cornerRadius:12))
                        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(FlowSurface.border,lineWidth:1))
                    AppWritingChart(entries:coordinator.entries,now:context.date,calendar:localCalendar)
                }
            }
        }
    }
    @ViewBuilder private func insightCards(_ summary:SketchInsightsSummary) -> some View {
        ForEach(summary.values) { item in
            VStack(alignment:.leading,spacing:5) {
                Text(item.value).font(.system(size:22,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(minWidth:112,maxWidth:.infinity,minHeight:68,maxHeight:68,alignment:.leading)
                .padding(10).background(FlowSurface.card,in:RoundedRectangle(cornerRadius:10))
                .accessibilityElement(children:.combine)
        }
    }
    private var formattingPage: some View {
        FlowPage {
            FlowSettingsGroup("Formatting shortcuts") {
                if coordinator.preferences.formattingShortcutAction == .nextRecording {
                    Text("Press Option+1 for Smart Polish or Option+2 for a structured prompt, then hold Fn and dictate in English.").font(.callout).foregroundStyle(.secondary).padding(14)
                    if !coordinator.beforeFormattingNotice.isEmpty {
                        Text(coordinator.beforeFormattingNotice).font(.caption).textSelection(.enabled).padding(14)
                    }
                    if coordinator.armedFormattingKind != nil {
                        Button("Cancel armed shortcut") { coordinator.cancelArmedFormatting() }.padding(14)
                    }
                } else {
                    Text("Dictate with Fn, then use Option+1 to polish your text or Option+2 to turn it into a prompt. Keep the cursor in the original field.").font(.callout).foregroundStyle(.secondary).padding(14)
                }
                if let result = coordinator.lastAIShortcutResult, coordinator.lastAIShortcutFailure == nil {
                    FlowSettingsRow("Last formatting result",description:result) { EmptyView() }
                }
                FlowSettingsRow("Enable formatting shortcuts",description:"Allow Option+1 and Option+2 to update the last dictation in its original text field.") {
                    Toggle("Enable formatting shortcuts",isOn:Binding(get:{ coordinator.preferences.previewShortcutsEnabled && (coordinator.preferences.inPlaceAIRewrite || coordinator.preferences.formattingShortcutAction == .nextRecording) },set:{ enabled in
                        var value = coordinator.preferences
                        value.previewShortcutsEnabled = enabled; value.inPlaceAIRewrite = enabled
                        coordinator.preferences = value
                    }))
                }
                if coordinator.preferences.formattingShortcutAction == .nextRecording {
                    FlowSettingsRow("Shortcut behavior",description:"Your saved setting formats the next recording. Use the current workflow to change the last dictation instead.") {
                        Button("Use last dictation") { coordinator.preferences.formattingShortcutAction = .lastInsertion }.disabled(coordinator.busy || coordinator.inPlaceRunning)
                    }
                }
                FlowSettingsRow("Smart Polish · Option+1",description:"Improve English grammar and wording while preserving your intended meaning.") { Toggle("Enable Smart Polish",isOn:$coordinator.preferences.offlineAIRewriting) }
                FlowSettingsRow("Create a prompt · Option+2",description:"Clarify and structure an English request while retaining supplied constraints.") { Toggle("Enable Prompt Engineering",isOn:$coordinator.preferences.promptEngineeringEnabled) }
                FlowSettingsRow("Polish style") {
                    Picker("Polish style",selection:$coordinator.preferences.polishStyle) { ForEach(PolishStyle.allCases,id:\.self) { Text($0.label).tag($0) } }.pickerStyle(.menu).disabled(coordinator.busy || coordinator.inPlaceRunning)
                }
                FlowSettingsRow("Tone") {
                    Picker("Tone",selection:$coordinator.preferences.polishTone) { ForEach(OfflineRewriteTone.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.menu).disabled(!coordinator.preferences.offlineAIRewriting || coordinator.busy || coordinator.inPlaceRunning)
                }
                if let failure = coordinator.lastAIShortcutFailure { Text(failure).font(.callout).foregroundStyle(.orange).textSelection(.enabled).padding(14) }
            }
            FlowSettingsGroup("Text cleanup") {
                FlowSettingsRow("Clean up spacing") { Toggle("Clean up spacing",isOn:$coordinator.preferences.spacingCleanup) }
                FlowSettingsRow("Fix spelling and common typos") { Toggle("Fix spelling and common typos",isOn:$coordinator.preferences.formatting.correctSpelling) }
                FlowSettingsRow("Smart typography",description:"Recognize spoken quotes and em dashes.") { Toggle("Smart typography",isOn:$coordinator.preferences.formatting.smartTypography) }
                FlowSettingsRow("Spoken punctuation") { Toggle("Spoken punctuation",isOn:$coordinator.preferences.formatting.spokenPunctuation) }
                FlowSettingsRow("Capitalize sentence starts") { Toggle("Capitalize sentence starts",isOn:$coordinator.preferences.formatting.sentenceCapitalization) }
                FlowSettingsRow("Remove filler words",description:"Removes isolated um, uh and erm.") { Toggle("Remove filler words",isOn:$coordinator.preferences.formatting.removeFillers) }
                if !coordinator.preferences.formatting.removeFillers {
                    FlowSettingsRow("Collapse repeated fillers") { Toggle("Collapse repeated fillers",isOn:$coordinator.preferences.formatting.removeRepeatedFillers) }
                }
                FlowSettingsRow("Explicit self corrections",description:"Recognize phrases such as ‘scratch that’; ambiguous wording is preserved.") { Toggle("Handle explicit self corrections",isOn:$coordinator.preferences.formatting.handleSelfCorrections) }
            }
            DisclosureGroup("Troubleshooting") {
                FlowSettingsRow("Shortcut registration",description:coordinator.previewShortcutStatus) { Button("Retry") { coordinator.configurePreviewShortcuts() }.disabled(!coordinator.preferences.previewShortcutsEnabled) }
            }
        }
    }
    private var privacyPage: some View {
        FlowPage {
            FlowSettingsGroup("On-device processing") {
                Text("Speech recognition uses installed on-device engines. Telugu uses local model files. No cloud transcription fallback is configured.").font(.callout).foregroundStyle(.secondary).padding(14)
                FlowSettingsRow("Text formatting",description:"Smart Polish and prompt rewriting use Apple's on-device AI when available. Protected sentences can be formatted locally.") { Text("On this Mac").foregroundStyle(.secondary) }
                FlowSettingsRow("Audio recordings",description:"Wesley Flow does not save your microphone recordings.") { Text("Not saved").foregroundStyle(.secondary) }
            }
            FlowSettingsGroup("Network access") {
                FlowSettingsRow("Block app network requests",description:"Blocks connections made directly by Wesley Flow. macOS manages its speech and AI services separately.") { Toggle("Block app network requests",isOn:$coordinator.preferences.blockNetworkRequests) }
            }
            FlowSettingsGroup("History and clipboard") {
                Text("Dictation history stays on this Mac when enabled. You can manage it in General. Saved history is protected by your user account and may appear in backups.").font(.callout).foregroundStyle(.secondary).padding(14)
                Text("Supported editors can use clipboard paste. Wesley Flow preserves the existing clipboard and checks delivery. If delivery is uncertain, review clipboard recovery before recording again.").font(.callout).foregroundStyle(.secondary).padding(14)
            }
        }
    }
    private var languageSettings: some View {
        FlowSettingsGroup("Dictation") {
            FlowSettingsRow("Language",description:"Choose the language you want to dictate.") {
                Picker("Dictation language",selection:$coordinator.preferences.languageMode) {
                    Text("English").tag(DictationLanguageMode.english)
                    Text("Telugu (Romanised)").tag(DictationLanguageMode.teluguRomanised)
                }.pickerStyle(.menu).disabled(coordinator.busy).accessibilityIdentifier("wesley.dictationLanguage")
            }
            if coordinator.preferences.languageMode == .teluguRomanised {
                FlowSettingsRow("Recognise",description:"Use Telugu only for Telugu speech, or Auto for Telugu and English. " + coordinator.languagePreparationStatus) {
                    Picker("Recognition language",selection:$coordinator.preferences.teluguRecognitionLanguage) {
                        ForEach(TeluguRecognitionLanguage.allCases,id:\.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu).disabled(coordinator.busy)
                }
            }
                FlowSettingsRow("Hold to talk",description:"Choose the key to hold while dictating.") { Picker("Hold-to-talk key",selection:Binding(get:{ coordinator.preferences.activationKey },set:{ coordinator.changeActivationKey($0) })) { ForEach(DictationActivationKey.allCases,id:\.self) { Text($0.label).tag($0) } }.pickerStyle(.menu).disabled(coordinator.busy) }
                FlowSettingsRow("Hold-to-talk dictation") { Button(coordinator.shortcutEnabled ? "Disable" : "Enable") { if coordinator.shortcutEnabled { coordinator.disableShortcut() } else { coordinator.enableShortcut() } }.accessibilityLabel(coordinator.shortcutEnabled ? "Disable hold-to-talk dictation" : "Enable hold-to-talk dictation") }
        }.task(id:[coordinator.preferences.languageMode.rawValue,coordinator.preferences.teluguRecognitionLanguage.rawValue]) {
            await coordinator.prepareSelectedLanguage()
        }
    }
    private var generalPage: some View {
        FlowPage {
            languageSettings
            FlowSettingsGroup("Appearance & startup") {
                FlowSettingsRow("Launch at login",description:loginItem.message.isEmpty ? loginItem.summary : loginItem.message) { Toggle("Launch at login",isOn:Binding(get:{loginItem.enabled},set:{loginItem.setEnabled($0)})).disabled(loginItem.updating || loginItem.status == .notFound) }
                if loginItem.status == .requiresApproval { FlowSettingsRow("Login approval") { Button("Open Login Items") { loginItem.openSettings() } } }
                FlowSettingsRow("Appearance") { Picker("Appearance",selection:$coordinator.preferences.appearance) { ForEach(DictationAppearance.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.menu) }
                FlowSettingsRow("Show dictation pill") { Toggle("Show dictation pill",isOn:$coordinator.preferences.showPill) }
                FlowSettingsRow("Show clickable pill while idle") { Toggle("Show clickable pill while idle",isOn:$coordinator.preferences.idlePillEnabled) }
            }
            FlowSettingsGroup("Permissions") {
                FlowSettingsRow("Microphone",description:coordinator.microphoneStatus) { Button("Open Settings") { openPrivacy("Privacy_Microphone") } }
                FlowSettingsRow("Accessibility",description:coordinator.accessibilityAllowed ? "Allowed" : "Needed for inserting text") { Button("Open Settings") { openPrivacy("Privacy_Accessibility") } }
            }
            FlowSettingsGroup("History") {
                FlowSettingsRow("Save dictation history on this Mac") { Toggle("Save dictation history on this Mac",isOn:$coordinator.preferences.keepHistory) }
                FlowSettingsRow("Saved dictations",description:"Turning off history keeps existing entries.") { Button("Clear all history…",role:.destructive) { confirmClear = true }.disabled(coordinator.busy || coordinator.entries.isEmpty) }
            }
            DisclosureGroup("Troubleshooting") { dictationTroubleshooting.padding(.top,12) }
            FlowSettingsGroup("About") {
                FlowSettingsRow("Wesley Flow") { Text(AppRelease.version).foregroundStyle(.secondary) }
                FlowSettingsRow("Source code") { Link("View on GitHub",destination:URL(string:"https://github.com/akshaywesleykothapalli/wesleyflow")!) }
            }
            if let error = coordinator.settingsError { Text(error).foregroundStyle(.orange) }
        }.onAppear { loginItem.refresh(); coordinator.refreshPermissions() }
    }
    private var dictationTroubleshooting: some View {
        FlowSettingsGroup("Dictation support") {
            if coordinator.preferences.languageMode == .teluguRomanised {
                FlowSettingsRow("Offline Telugu files",description:"Setup instructions are included in the GitHub documentation.") { Text(FileManager.default.fileExists(atPath:WhisperTeluguSmallModel.installedURL.path) ? "Installed" : "Setup required").foregroundStyle(.secondary) }
            }
            FlowSettingsRow("Diagnostics",description:"Status and error codes only; no dictated text or audio.") { Button("Copy diagnostics") { _ = coordinator.copyReviewedText(coordinator.combinedDictationDiagnostics) }.disabled(!coordinator.historyCopyAllowed) }
            Text("If Fn opens macOS emoji or Dictation, set Keyboard → Press Globe key to → Do Nothing.").font(.caption).foregroundStyle(.secondary).padding(14)
        }
    }
    @ViewBuilder private var appleSpeechSettings: some View {
        FlowSettingsGroup("Apple Speech") {
            FlowSettingsRow("Speech Recognition permission", description: coordinator.speechStatus) {
                Button("Open Settings") { openPrivacy("Privacy_SpeechRecognition") }
            }
            FlowSettingsRow("Microphone permission", description: coordinator.microphoneStatus) {
                Button("Open Settings") { openPrivacy("Privacy_Microphone") }
            }
        }
        FlowSettingsGroup("English dictation resources") {
            FlowSettingsRow("English speech setup",description:coordinator.speechResourceStatus) {
                Button("Check availability") { Task { await coordinator.inspectSpeech() } }.disabled(coordinator.busy || coordinator.speechResourceWorking)
            }
            if coordinator.speechConfiguration?.installCandidate != nil {
                FlowSettingsRow("Speech resources",description:"Install the on-device English resources supplied by macOS.") { Button("Set up English dictation") { coordinator.installSpeechResources() }.disabled(!coordinator.canInstallSpeechResources) }
            }
            if coordinator.speechResourceWorking {
                FlowSettingsRow("Setup progress") {
                    if let fraction = coordinator.speechDownloadProgress?.fraction { ProgressView(value:fraction).frame(width:90) } else { ProgressView().controlSize(.small) }
                    Button("Stop waiting") { coordinator.stopWaitingForSpeechResources() }
                }
            }
        }
    }
    private func openPrivacy(_ pane: String) { if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?"+pane) { NSWorkspace.shared.open(url) } }
}
@MainActor private struct DictationEntryDetail: View {
    let entry: DictationHistoryEntry
    let canCopy: Bool
    let copyText: @MainActor (String) -> Bool
    @ObservedObject var feedback: HistoryCopyFeedback
    @Environment(\.dismiss) private var dismiss
    @State private var rawVisible = false
    @State private var edited = ""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Dictation details").font(.title2); Spacer(); Button("Done") { dismiss() } }
            LabeledContent("Recorded",value:entry.timestamp.formatted())
            LabeledContent("Insertion",value:entry.insertion.status.rawValue)
            Text(SystemWideDictationCoordinator.insertionExplanation(entry.insertion)).font(.callout).foregroundStyle(.secondary)
            if let source = entry.sourceApplication { LabeledContent("Source app",value:source) }
            TextEditor(text:$edited).scrollIndicators(.hidden).font(.body).frame(minHeight:160)
            HStack { Button(feedback.copied.contains(entry.id) ? "Copied" : "Copy edited text") { if copyText(edited) { feedback.show(id:entry.id) } }.disabled(!canCopy); Toggle("Compare raw",isOn:$rawVisible).toggleStyle(.switch); Spacer(); Text("\(entry.wordCount) words · \(entry.characterCount) characters").foregroundStyle(.secondary) }
            if rawVisible { ScrollView { Text(entry.raw).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.scrollIndicators(.hidden).frame(height:110) }
            Text("Edits are a local review draft. Copy your edited text here; the saved history entry stays unchanged.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:640).onAppear { edited = entry.cleaned }
    }
}

// Original native surfaces; each semantic role has an explicit light-mode counterpart.
private enum FlowSurface {
    static func color(dark:Double, light:Double) -> Color {
        Color(nsColor:NSColor(name:nil) { appearance in
            NSColor(white:appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark : light,alpha:1)
        })
    }
    static let canvas = color(dark:0.095,light:0.98)
    static let sidebar = color(dark:0.075,light:0.945)
    static let card = color(dark:0.14,light:1)
    static let border = color(dark:0.205,light:0.85)
    static let selection = color(dark:0.175,light:0.875)
    static let text = Color(nsColor:.labelColor)
    static let accent = Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.30,green:0.39,blue:0.96,alpha:1)
            : NSColor(srgbRed:0.18,green:0.27,blue:0.81,alpha:1)
    })
}
@MainActor private struct FlowPage<Content:View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) { content }
                .frame(maxWidth:.infinity,alignment:.leading).padding(22)
        }.scrollIndicators(.hidden).scrollContentBackground(.hidden)
    }
}

@MainActor private struct FlowSidebarStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration:Configuration) -> some View { Row(configuration:configuration,selected:selected) }
    private struct Row: View {
        let configuration:ButtonStyleConfiguration
        let selected:Bool
        @State private var hovered = false
        @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @ScaledMetric(relativeTo:.body) private var symbolSize = 14
        private var presentation: SidebarPresentation { .init(selected:selected,hovered:hovered,pressed:configuration.isPressed) }
        private var iconColor: Color {
            switch presentation.foreground {
            case .accent: FlowSurface.accent
            case .emphasized: FlowSurface.text
            case .muted: Color(nsColor:.secondaryLabelColor)
            }
        }
        var body: some View {
            configuration.label
                .font(.system(size:symbolSize,weight:presentation.iconWeight))
                .foregroundStyle(iconColor)
                .background(FlowSurface.selection.opacity(presentation.backgroundOpacity),in:RoundedRectangle(cornerRadius:9))
                .overlay(alignment:.leading) {
                    if selected { RoundedRectangle(cornerRadius:2).fill(FlowSurface.accent).frame(width:3,height:22).padding(.leading,3).transition(.opacity) }
                }
                .contentShape(RoundedRectangle(cornerRadius:9))
                .onHover { hovered = $0 }
                .onDisappear { hovered = false }
                .animation(reduceMotion ? nil : .easeInOut(duration:0.14),value:hovered)
                .animation(reduceMotion ? nil : .easeInOut(duration:0.18),value:selected)
        }
    }
}

@MainActor private struct DictationActivityHeatmap: View {
    let activity: DictationActivity
    @FocusState private var focusedDay: Date?
    private func color(_ level:Int) -> Color {
        level == 0 ? FlowSurface.border.opacity(0.5) : FlowSurface.accent.opacity([0,0.25,0.45,0.7,1][min(4,max(0,level))])
    }
    private func description(_ day:DictationActivity.Day) -> String {
        var style = Date.FormatStyle(date:.complete,time:.omitted); style.calendar = activity.calendar; style.timeZone = activity.calendar.timeZone
        return "\(style.format(day.date)): \(day.count) \(day.count == 1 ? "dictation" : "dictations")" + (day.future ? " (future date)" : "")
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            GeometryReader { geometry in
                let side: CGFloat = 10
                HStack(alignment:.top,spacing:2) {
                    VStack(spacing:2) {
                        Color.clear.frame(width:26,height:18)
                        ForEach(0..<7,id:\.self) { row in
                            let weekday = (activity.calendar.firstWeekday - 1 + row) % 7
                            Text(side >= 8 && [1,3,5].contains(row) ? activity.calendar.veryShortWeekdaySymbols[weekday] : " ")
                                .font(.system(size:9)).foregroundStyle(.secondary).frame(width:26,height:side)
                        }
                    }
                    ForEach(0..<53,id:\.self) { column in
                        VStack(alignment:.leading,spacing:2) {
                            Group {
                                if let date = activity.monthLabelDate(column:column) { Text(date,format:.dateTime.month(.abbreviated)).fixedSize() }
                                else { Text(" ") }
                            }.font(.system(size:9)).foregroundStyle(.secondary).frame(width:side,height:18,alignment:.leading)
                            ForEach(Array(activity.days.dropFirst(column*7).prefix(7))) { day in
                                RoundedRectangle(cornerRadius:2).fill(color(day.level)).frame(width:side,height:side).opacity(day.future ? 0.25 : 1)
                                    .help(description(day)).accessibilityLabel(description(day))
                                    .focusable(!day.future).focused($focusedDay,equals:day.date)
                            }
                        }
                    }
                }
            }.frame(height:108)
            HStack(spacing:4) { Spacer(); Text("Less"); ForEach(0..<5,id:\.self) { level in RoundedRectangle(cornerRadius:2).fill(color(level)).frame(width:10,height:10).accessibilityLabel("Activity level \(level)") }; Text("More") }.font(.caption2).foregroundStyle(.secondary)
        }
        .onMoveCommand { direction in
            let current = focusedDay.flatMap { date in activity.days.firstIndex(where:{ $0.date == date }) } ?? 0
            let offset: Int
            switch direction { case .left: offset = -7; case .right: offset = 7; case .up: offset = -1; case .down: offset = 1; default: return }
            let next = min(max(0,current+offset),activity.days.count-1)
            if activity.days.indices.contains(next), !activity.days[next].future { focusedDay = activity.days[next].date }
        }
    }
}

/// A single aligned setting; the control retains its native behavior and binding.
@MainActor struct FlowSettingsRow<Control:View>: View {
    let title: String
    let description: String?
    let control: Control
    init(_ title:String,description:String? = nil,@ViewBuilder control:() -> Control) {
        self.title = title; self.description = description; self.control = control()
    }
    var body: some View {
        HStack(alignment:.center,spacing:16) {
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(FlowTypography.setting)
                if let description { Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            }.frame(maxWidth:.infinity,alignment:.leading)
            control.labelsHidden()
                .frame(width:180,alignment:.trailing)
        }.frame(minHeight:28).padding(.horizontal,14).padding(.vertical,10).accessibilityElement(children:.contain)
    }
}
@MainActor struct FlowSettingsGroup<Content:View>: View {
    let title: String
    let content: Content
    let headingColor: Color
    init(_ title:String,headingColor:Color = .secondary,@ViewBuilder content:() -> Content) { self.title = title; self.headingColor = headingColor; self.content = content() }
    static func hasSeparator(index:Int,count:Int) -> Bool { index >= 0 && index < count - 1 }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if !title.isEmpty { Text(title.uppercased()).font(FlowTypography.section).tracking(0.6).foregroundStyle(headingColor).padding(.leading,4) }
            VStack(spacing:0) {
                Group(subviews:content) { rows in
                    ForEach(Array(rows.enumerated()),id:\.element.id) { index,row in
                        row
                        if Self.hasSeparator(index:index,count:rows.count) { Divider() }
                    }
                }
            }.background(FlowSurface.card,in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(FlowSurface.border,lineWidth:1))
        }
    }
}


@MainActor private struct HistoryHeaderSearch: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing:6) {
            Image(systemName:"magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search dictations",text:$text).textFieldStyle(.plain).focused($focused)
                .accessibilityLabel("Search dictations")
            if !text.isEmpty {
                Button { text = ""; focused = true } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear dictation search")
            }
        }.padding(.horizontal,10).padding(.vertical,6).frame(width:180)
            .background(FlowSurface.card,in:Capsule())
            .overlay(Capsule().strokeBorder(focused ? FlowSurface.accent : FlowSurface.border,lineWidth:1))
            .animation(reduceMotion ? nil : .easeInOut(duration:0.12),value:focused)
    }
}

private func agentTaskHeading(_ record:PersonalTaskRecord)->String {
    let shortID=String(record.id.uuidString.prefix(8))
    let status:String=agentTaskStatusLabel(record)
    return shortID+" · "+status
}

func agentTaskStatusLabel(_ record:PersonalTaskRecord)->String {
    guard record.state == .needsReview,let close=record.receipts.values.first(where:{!$0.verified && $0.appClose != nil})?.appClose else {return record.state.rawValue}
    return switch close.outcome {case .pending:"Quit pending";case .refused:"Quit refused";case .reopened:"App reopened";case .unavailable:"Can't check app";case .unconfirmed,.closed:"Check app"}
}


@MainActor private struct FlowCommandHelpRow: View {
    let command:String, explanation:String
    var body:some View {
        HStack(alignment:.top,spacing:20) {
            Text(command).frame(maxWidth:.infinity,alignment:.leading)
            Text(explanation).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
        }.font(.callout).textSelection(.enabled).padding(14).accessibilityElement(children:.combine)
    }
}

@MainActor private struct SpeakerSettingsView: View {
    @ObservedObject var settings: SpeakerSettings
    let dictationBusy: Bool
    @State private var name = ""
    @State private var consent = false
    @State private var showingEnrollment = false
    @State private var pendingDeletion: UUID?

    var body: some View {
        FlowSettingsGroup("Voice profiles") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add your voice so Wesley Flow can label new saved dictations. Voices it can’t confidently match appear as Unknown speaker.")
                    .foregroundStyle(.secondary)
                TextField("Your name", text: $name)
                    .accessibilityIdentifier("wesley.speakerName")
                Button("Add My Voice") {
                    consent = false
                    showingEnrollment = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!SpeakerProfile.validName(name) || dictationBusy || settings.working || settings.enrolling)
                Toggle("Label saved dictations by voice", isOn: Binding(get: { settings.enabled }, set: settings.setEnabled))
                    .disabled(dictationBusy || settings.enrolling || settings.working || settings.profiles.isEmpty)
                ForEach(settings.profiles, id: \.id) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Button("Delete profile…", role: .destructive) { pendingDeletion = profile.id }
                            .disabled(dictationBusy || settings.working || settings.enrolling)
                    }
                }
                Text(settings.status).font(.caption).foregroundStyle(.secondary)
            }.padding(14)
        }
        .task { await settings.refresh() }
        .sheet(isPresented: $showingEnrollment) { enrollment }
        .confirmationDialog("Delete this voice profile?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { id in
            Button("Delete voice profile", role: .destructive) { Task { await settings.delete(id: id) } }
        } message: { _ in Text("Future dictations will no longer match this profile. Saved history keeps its labels.") }
    }

    private var enrollment: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add My Voice").font(.title2.bold())
            Text(name).font(.headline)
            Text("Read three passages in your normal voice. Your voice profile stays on this Mac, and Wesley Flow discards the sample recordings.")
                .foregroundStyle(.secondary)
            if !settings.enrolling || settings.sample < SpeakerSettings.passages.count {
                let sample = settings.enrolling ? settings.sample : 0
                Text("Passage \(sample + 1) of \(SpeakerSettings.passages.count)").font(.headline)
                Text(SpeakerSettings.passages[sample]).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Label("All three samples are ready", systemImage: "checkmark.circle")
            }
            if !settings.enrolling {
                Toggle("I consent to storing my voice profile on this Mac", isOn: $consent).toggleStyle(.checkbox)
            }
            Text(settings.status).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") {
                    Task {
                        if settings.enrolling { await settings.cancel() }
                        showingEnrollment = false
                    }
                }.keyboardShortcut(.cancelAction).disabled(settings.working)
                Spacer()
                if !settings.enrolling {
                    Button("Continue") { Task { await settings.begin(name: name) } }
                        .disabled(!consent || dictationBusy || settings.working)
                } else if settings.sample == SpeakerSettings.passages.count {
                    Button("Save voice profile") {
                        Task {
                            await settings.save()
                            if !settings.enrolling { name = ""; showingEnrollment = false }
                        }
                    }.disabled(settings.working)
                } else if settings.recording {
                    Button("Finish sample") { Task { await settings.finishSample() } }
                } else {
                    Button("Record sample") { Task { await settings.startSample() } }.disabled(settings.working || dictationBusy)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .interactiveDismissDisabled(settings.enrolling || settings.working)
        .onDisappear {
            if settings.enrolling && !settings.working { Task { await settings.cancel() } }
        }
    }
}

@MainActor private struct AppWritingChart: View {
    let entries: [DictationHistoryEntry]
    let now: Date
    let calendar: Calendar
    @State private var period = AppWritingActivity.Period.week
    @State private var selectedMetric = AppWritingActivity.Metric.time
    private var metric: AppWritingActivity.Metric { period.hourly ? .time : selectedMetric }
    @State private var focusedApp: String?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: [Color] {
        colorScheme == .dark
            ? [.blue, .mint, .orange, .purple, .pink]
            : [.init(red: 0.16, green: 0.40, blue: 0.78), .init(red: 0.02, green: 0.47, blue: 0.39),
               .init(red: 0.74, green: 0.33, blue: 0.05), .init(red: 0.49, green: 0.31, blue: 0.69),
               .init(red: 0.70, green: 0.21, blue: 0.42)]
    }

    var body: some View {
        let activity = AppWritingActivity(entries: entries, now: now, calendar: calendar, period: period, metric: metric)
        let selected = activity.series.first { $0.id == focusedApp }
        let colors = appColors(activity.series)
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(minLength: 16); controls }
                VStack(alignment: .leading, spacing: 10) { title; controls }
            }
            if activity.series.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No app activity in this range").font(.callout.weight(.medium))
                    Text(metric == .time && activity.missingDurations > 0
                         ? "Saved dictations in this range have unavailable recording time."
                         : "Verified insertions will appear here by app.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 10)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.label(selected?.amount ?? activity.total))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Spacer()
                    if let selected {
                        Button("Show all apps") { focusedApp = nil }
                            .buttonStyle(.borderless).help("Clear the \(selected.name) filter")
                    }
                }
                Text((selected?.name ?? "All apps") + (period.hourly ? " · Hourly totals" : " · Daily totals"))
                    .font(.caption).foregroundStyle(.secondary)
                plot(activity, selected: selected, colors: colors)
                Divider()
                VStack(spacing: 1) {
                    ForEach(activity.series) { app in
                        appRow(app, total: activity.total, color: colors[app.id] ?? .secondary)
                    }
                }
            }
            Text(coverage(activity)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(FlowSurface.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(FlowSurface.border))
        .onChange(of: period) { focusedApp = nil }
        .onChange(of: selectedMetric) { focusedApp = nil }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Where you write").font(.headline)
            Text("Dictation activity by app").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if !period.hourly {
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(AppWritingActivity.Metric.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().accessibilityLabel("Metric")
            }
            Picker("Date range", selection: $period) {
                ForEach(AppWritingActivity.Period.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Date range").fixedSize()
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func plot(_ activity: AppWritingActivity, selected: AppWritingActivity.Series?, colors: [String: Color]) -> some View {
        let visible = activity.series.filter { selected == nil || $0.id == selected?.id }
        let names = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0.name) })
        let dates = period.hourly
            ? activity.buckets.filter { calendar.component(.hour, from: $0).isMultiple(of: 4) }
            : activity.buckets.enumerated().compactMap { index, day in index.isMultiple(of: period == .week ? 1 : 7) ? day : nil }
        let hourFormat = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour()
        return Chart(activity.samples.filter { selected == nil || $0.id.series == selected?.id }) { sample in
            BarMark(
                x: .value(period.hourly ? "Hour" : "Day", sample.id.start, unit: period.hourly ? .hour : .day, calendar: calendar),
                y: .value(metric.axisTitle, metric.chartValue(sample.amount))
            )
            .foregroundStyle(by: .value("App", sample.id.series))
            .accessibilityLabel(names[sample.id.series] ?? "")
            .accessibilityValue(metric.label(sample.amount))
        }
        .chartForegroundStyleScale(domain: visible.map(\.id), range: visible.map { colors[$0.id] ?? .secondary })
        .chartLegend(.hidden)
        .chartXScale(domain: (activity.buckets.first ?? now)...activity.end)
        .chartXAxis {
            AxisMarks(values: dates) {
                AxisTick()
                if period.hourly {
                    AxisValueLabel(format: hourFormat)
                } else {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartYAxisLabel(metric.axisTitle, position: .leading)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .frame(height: 172)
        .accessibilityLabel("\(period.hourly ? "Hourly" : "Daily") \(metric.rawValue.lowercased()) by app")
    }

    private func appRow(_ app: AppWritingActivity.Series, total: Int, color: Color) -> some View {
        let selected = focusedApp == app.id
        return Button {
            focusedApp = selected ? nil : app.id
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
                Text(app.name).lineLimit(1)
                Spacer(minLength: 6)
                Text(metric.label(app.amount)).monospacedDigit().foregroundStyle(.secondary)
                Text((Double(app.amount) / Double(total)).formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 40, alignment: .trailing)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? color : .secondary).imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.callout)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(selected ? "Show all apps" : "Show only \(app.name) in the chart")
    }

    private func appColors(_ series: [AppWritingActivity.Series]) -> [String: Color] {
        var result: [String: Color] = [AppWritingActivity.other: .gray]
        var available = Set(palette.indices)
        for app in series.filter({ $0.id != AppWritingActivity.other }).sorted(by: { $0.id < $1.id }) {
            let seed = app.id.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
            if let index = (0..<palette.count).map({ (seed + $0) % palette.count }).first(where: available.contains) {
                result[app.id] = palette[index]
                available.remove(index)
            }
        }
        return result
    }

    private func coverage(_ activity: AppWritingActivity) -> String {
        var note = metric == .time ? "Time spent dictating for verified insertions, grouped by recording start."
            : "Words from verified insertions."
        if activity.missingNames > 0 { note += " Missing app name: \(activity.missingNames)." }
        if activity.missingDurations > 0 { note += " Missing recording time: \(activity.missingDurations)." }
        return note
    }
}
