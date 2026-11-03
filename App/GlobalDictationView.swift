import SwiftUI
import AppKit
import Domain
import VoiceInput

@MainActor struct GlobalDictationView: View {
    @ObservedObject var coordinator: SystemWideDictationCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: DictationPage = .dictation
    @State private var selectedEntry: DictationHistoryEntry?
    @State private var vocabularyInput = ""
    @State private var phraseInput = ""
    @State private var replacementInput = ""
    @State private var confirmClear = false
    @State private var observedAgentSteps:Set<UUID>=[]
    @State private var commandLibraryExpanded = false
    @State private var deletingEntry: DictationHistoryEntry?
    @State private var copyError: String?
    @StateObject private var copyFeedback = HistoryCopyFeedback()
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @State private var confirmRestore = false
    @State private var recoveryID: String?
    @State private var speechExpanded = false
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
                    if page == .history { Button("Back to Dictation") { page = .dictation } }
                    if page == .dictation || page == .history { HistoryHeaderSearch(text:$coordinator.search) }
                }.padding(.horizontal,22).frame(minHeight:56).layoutPriority(1)
                if page == .dictation || page == .history || page == .dictionary { Divider().overlay(FlowSurface.border) }
                Group {
                    switch page {
                    case .dictation: dictationPage
                    case .history: historyPage
                    case .commands: commandsPage
                    case .insights: insightsPage
                    case .dictionary: dictionaryPage
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
            commandLibraryExpanded = coordinator.agentHUD == "Agent help"
            if NSClassFromString("XCTestCase") == nil { openWindow(id:"foundation"); NSApplication.shared.activate() }
        }
        .onChange(of:coordinator.flowPageRequestID) { _,_ in
            if let destination = coordinator.flowPageRequest { page = destination }
            if NSClassFromString("XCTestCase") == nil { openWindow(id:"foundation"); NSApplication.shared.activate() }
        }
        .onChange(of:page) { _,_ in copyFeedback.cancelAll(); copyError = nil }
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
            if coordinator.preferences.previewShortcutsEnabled && coordinator.preferences.formattingShortcutAction == .lastInsertion {
                VStack(alignment:.leading,spacing:6) {
                    Text("⌥1  Polish last dictation     ⌥2  Turn it into a prompt").font(.callout.weight(.semibold))
                    Text("Hold Fn, speak and release. After your text appears, press Option+1 or Option+2 without moving the cursor. The result replaces that dictation in the same editor.").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal,22).padding(.vertical,12)
            }
            if coordinator.preferences.previewShortcutsEnabled && coordinator.preferences.formattingShortcutAction == .nextRecording {
                VStack(alignment:.leading,spacing:6) {
                    Text("⌥1  Smart Polish     ⌥2  Structured prompt").font(.callout.weight(.semibold))
                    Text("Press a shortcut in your target app, then hold Fn and speak English. Local formatting happens before insertion.").font(.caption).foregroundStyle(.secondary)
                    if !coordinator.beforeFormattingNotice.isEmpty { Text(coordinator.beforeFormattingNotice).font(.caption).textSelection(.enabled) }
                    if coordinator.armedFormattingKind != nil { Button("Cancel armed shortcut") { coordinator.cancelArmedFormatting() } }
                }.padding(.horizontal,22).padding(.vertical,12)
            }
            if let result = coordinator.lastAIShortcutResult, coordinator.lastAIShortcutFailure == nil, !coordinator.busy {
                VStack(alignment:.leading,spacing:6) {
                    Text("Last formatting result").font(.callout.weight(.semibold))
                    Text(result).font(.callout).textSelection(.enabled)
                    Button("Copy dictation & AI diagnostics") { _ = coordinator.copyReviewedText(coordinator.combinedDictationDiagnostics) }.disabled(!coordinator.historyCopyAllowed)
                }.padding(.horizontal,22).padding(.vertical,12)
            }
            if coordinator.busy || coordinator.phase == .error || coordinator.clipboardPending || coordinator.historyError != nil || copyError != nil || coordinator.lastAIShortcutFailure != nil {
                VStack(alignment:.leading,spacing:8) {
                    if coordinator.busy { HStack { Text(coordinator.message).font(.callout); Spacer(); Button("Cancel dictation") { coordinator.cancel() } } }
                    if let failure = coordinator.lastAIShortcutFailure, !coordinator.busy {
                        Text(failure).font(.callout).foregroundStyle(.orange)
                        Button("Shortcut status & requirements") { page = .smartFormatting }
                        Button("Copy dictation & AI diagnostics") { _ = coordinator.copyReviewedText(coordinator.combinedDictationDiagnostics) }.disabled(!coordinator.historyCopyAllowed)
                    }
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
            ScrollView {
                LazyVStack(alignment:.leading,spacing:0,pinnedViews:[.sectionHeaders]) {
                    ForEach(DictationHistoryQuery.groups(coordinator.filteredHistory,calendar:localCalendar),id:\.date) { group in
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
                    if coordinator.filteredHistory.isEmpty { Text(coordinator.search.isEmpty ? "No saved dictations yet." : "No matching dictations.").foregroundStyle(.secondary).padding(22).frame(maxWidth:.infinity,alignment:.leading) }
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
                FlowSettingsRow(coordinator.preferences.agentKey.label,description:coordinator.agentShortcutStatus) {
                    Toggle("Enable command key",isOn:Binding(get:{coordinator.preferences.agentHotkeyEnabled},set:{ if $0 {coordinator.enableAgentShortcut()} else {coordinator.disableAgentShortcut()} })).disabled(coordinator.busy)
                }
            }
            Text(coordinator.agentNotice).font(.callout).foregroundStyle(coordinator.phase == .error ? .orange : .secondary)
            FlowSettingsGroup("Dictation controls") {
                FlowSettingsRow("Current dictation language") { Text(coordinator.preferences.languageMode == .english ? "English" : (coordinator.preferences.teluguRecognitionLanguage == .teluguOnly ? "Telugu only" : "Telugu + English")).foregroundStyle(.secondary) }
                ForEach(FlowVoiceControl.examples,id:\.self) { example in
                    FlowCommandHelpRow(command:example,explanation:FlowVoiceControl.parse(example)?.helpDescription ?? "")
                }
            }
            FlowSettingsGroup("Everyday Mac actions") {
                ForEach(["Open Notes","Set volume to thirty percent","Turn volume up","Mute audio","Show battery status","Move Safari to the left half"],id:\.self) { example in
                    FlowCommandHelpRow(command:example,explanation:Self.macCommandHelp[example] ?? "")
                }
            }
            Text("Hold the command key, say one command, then release. Commands are listed for reference; Mac actions use existing permissions.").font(.caption).foregroundStyle(.secondary)
            Text("Speak normally with the separate Agent key. Installed apps can be opened or normally quit. Google/YouTube searches open in your default browser. Music controls the existing player. Messages require a final recipient and text confirmation.").font(FlowTypography.secondary).foregroundStyle(.secondary)
            Text(coordinator.agentShortcutStatus).font(.caption).foregroundStyle(.secondary)
            if let failure=coordinator.lastAgentFailure {
                Text(failure).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                Button("Copy command speech diagnostics") { _ = coordinator.copyReviewedText(coordinator.speechDiagnosticSummary) }.disabled(!coordinator.historyCopyAllowed)
            }
            Text("Hold the Agent key, speak, then release. Routine requests run directly. Ambiguous requests stop for clarification; messages require confirmation. Dictation always inserts text.").font(.caption).foregroundStyle(.secondary)
            Divider()
            DisclosureGroup("Type a command instead") {
                TextField("Command",text:$coordinator.agentCommandText).disabled(coordinator.agentQuestion != nil)
                Button("Run text request") { coordinator.reviewAgentCommand() }.disabled(coordinator.busy)
            }
            DisclosureGroup("Command library",isExpanded:$commandLibraryExpanded) {
                ForEach(PersonalCommandLibrary.examples,id:\.self) { example in Text(example).font(.caption).textSelection(.enabled) }
                Text("Natural requests: Hey, open WhatsApp · Go open Google · Open Gmail in Safari · Open YouTube and search for piano music").font(.caption).textSelection(.enabled)
                Text("Known website names: "+PersonalWebsiteNames.sites.map(\.name).joined(separator:", ")).font(.caption).foregroundStyle(.secondary)
                Text("Command understanding is local. Loading online websites still needs an internet connection. Unknown website names require an exact address.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("100-command expansion").font(.headline)
                ForEach(PersonalRoadmapCatalog.commands) { command in
                    VStack(alignment:.leading,spacing:2) {
                        Text(String(format:"%03d",command.id)+" · "+command.example).font(.caption).textSelection(.enabled)
                        Text(command.mode.label+" · "+command.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Folder commands use Documents, Desktop or Downloads. Delete moves to Trash only after review; it never permanently erases. Finder controls and protected folders may need macOS consent. Browser searches use the named installed browser.").font(.caption).foregroundStyle(.secondary)
            if !coordinator.agentHeard.isEmpty {
                FlowSettingsGroup("Latest spoken request") {
                    FlowCommandHelpRow(command:"Heard",explanation:coordinator.agentHeard)
                    if !coordinator.agentInterpretation.isEmpty { FlowCommandHelpRow(command:"Understood",explanation:coordinator.agentInterpretation) }
                }
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
            if !coordinator.agentScheduledDrafts.isEmpty {
                Text("Scheduled local message drafts").font(.headline)
                Text("These drafts never send automatically. At the due time, Review opens a fresh exact-send approval. Notification delivery depends on macOS settings.").font(.caption).foregroundStyle(.secondary)
                ForEach(coordinator.agentScheduledDrafts) { draft in
                    VStack(alignment:.leading,spacing:4) {
                        Text(verbatim:[draft.message.recipient,draft.date.formatted(),draft.state.rawValue].joined(separator:" · ")).font(.caption)
                        Text(draft.message.body).font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Review due message") {coordinator.reviewScheduledDraft(draft.id)}.disabled(coordinator.busy || draft.state != .pending)
                            if draft.state != .pending {Button("Delete local draft record") {coordinator.deleteScheduledDraft(draft.id)}.disabled(coordinator.busy)}
                        }
                    }
                }
                Button("Refresh scheduled drafts") {coordinator.loadScheduledDrafts()}.disabled(coordinator.busy)
            }
            if let name=coordinator.agentEditingRoutine {
                Text("Edit routine: "+name).font(.headline)
                ForEach(Array(coordinator.agentRoutineExistingSteps.enumerated()),id:\.offset) { _,summary in Text(summary).font(.caption) }
                Text("Enter one complete replacement command per line, up to eight steps. Saving does not run them.").font(.caption)
                TextEditor(text:$coordinator.agentRoutineEditText).frame(minHeight:80)
                HStack {Button("Review revised routine") {coordinator.saveAgentRoutineEdits()};Button("Cancel editing") {coordinator.cancelAgentRoutineEdits()}}
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
                        if record.state == .awaitingApproval { Button("Review") { coordinator.reviewQueuedAgent(record.id) } }
                        if record.state == .running {Button("Pause after current step") {coordinator.pauseAgentTask(record.id)}}
                        if [PersonalTaskState.paused,.cancelled,.needsReview].contains(record.state),record.supersededBy==nil {Button("Continue with review") {coordinator.continueAgentTask(record.id)}.disabled(coordinator.busy)}
                        if record.state == .running || record.state == .awaitingApproval { Button("Cancel remaining steps") { coordinator.cancelAgentTask(record.id) } }
                        Button("Delete task record") { coordinator.deleteAgentTask(record.id) }.disabled(coordinator.busy)
                    }
                }
            }
            Divider()
            Toggle("Explicit local memory (off each launch)",isOn:Binding(get:{coordinator.agentMemoryEnabled},set:{coordinator.setAgentMemory($0)}))
            Text("Only text you save here is remembered for 30 days. No passive activity or sensitive capture. Task receipts are separate and can be deleted above.").font(.caption).foregroundStyle(.secondary)
            TextField("Memory text, search, or correction",text:$coordinator.agentMemoryText)
            HStack {
                Button("Remember") { coordinator.rememberAgentText() }.disabled(!coordinator.agentMemoryEnabled)
                Button("Search") { coordinator.searchAgentMemory() }.disabled(!coordinator.agentMemoryEnabled)
                Button("Delete all memory") { coordinator.deleteAgentMemory() }
            }
            ForEach(coordinator.agentMemories) { memory in
                HStack {
                    Text(memory.text).font(.caption)
                    Button("Replace with entered text") { coordinator.correctAgentMemory(memory.id) }
                    Button("Delete") { coordinator.deleteAgentMemory(memory.id) }
                }
            }

        }
    }
    private var historyPage: some View { dictationPage }
    private func historyRow(_ entry: DictationHistoryEntry) -> some View {
        HStack(alignment:.center,spacing:12) {
            Text(DictationHistoryPresentation.time(entry.timestamp,calendar:localCalendar)).font(.body.weight(.medium)).monospacedDigit().foregroundStyle(.secondary).frame(width:DictationHistoryPresentation.timeColumnWidth,alignment:.leading).fixedSize(horizontal:false,vertical:true)
            Button { selectedEntry = entry } label: {
                Text(entry.cleaned).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
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
                    Text("Where you write").font(.headline)
                    VStack(alignment:.leading,spacing:12) {
                        if summary.appUsage.isEmpty {
                            Text("No verified inserted words with a saved application name yet.").foregroundStyle(.secondary)
                        } else {
                            ForEach(summary.appUsage) { app in
                                VStack(alignment:.leading,spacing:5) {
                                    HStack { Text(app.name); Spacer(); Text("\(app.words) words").foregroundStyle(.secondary) }
                                    ProgressView(value:Double(app.words),total:Double(max(1,summary.appUsage.first?.words ?? 1)))
                                        .accessibilityLabel("\(app.name), \(app.words) verified inserted words")
                                }
                            }
                        }
                        Text(summary.usageNote).font(.caption).foregroundStyle(.secondary)
                    }
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
    private var dictionaryPage: some View {
        FlowPage {
            FlowSection("Protected vocabulary") {
                Text("These terms are preserved during local cleanup and spelling checks. They do not train the speech recognizer.").font(.caption)
                HStack { TextField("Term or phrase",text:$vocabularyInput)
                    Button("Add") { var options = coordinator.preferences.formatting; options.vocabulary.append(vocabularyInput); if options.isValid { coordinator.preferences.formatting = options; vocabularyInput = "" } }
                        .disabled(vocabularyInput.isEmpty || vocabularyInput.utf8.count > 128 || vocabularyInput.contains(where:{ $0.isNewline }) || coordinator.preferences.formatting.vocabulary.count >= 128)
                }
                ForEach(Array(coordinator.preferences.formatting.vocabulary.enumerated()),id:\.offset) { item in
                    HStack { Text(item.element); Spacer(); Button("Remove") { coordinator.preferences.formatting.vocabulary.remove(at:item.offset) } }
                }
            }
            FlowSection("Exact phrase replacements") {
                Text("Only explicit phrases are expanded. Protected technical spans take priority. Replacement output is not rewritten.").font(.caption)
                TextField("Spoken phrase",text:$phraseInput); TextField("Replace with",text:$replacementInput)
                Button("Add replacement") { var options = coordinator.preferences.formatting; options.replacements.append(.init(phrase:phraseInput,replacement:replacementInput)); if options.isValid { coordinator.preferences.formatting = options; phraseInput = ""; replacementInput = "" } }
                    .disabled(phraseInput.isEmpty || phraseInput.utf8.count > 128 || replacementInput.utf8.count > 512 || coordinator.preferences.formatting.replacements.count >= 64)
                ForEach(Array(coordinator.preferences.formatting.replacements.enumerated()),id:\.offset) { item in
                    HStack { Text(item.element.phrase + " → " + item.element.replacement); Spacer(); Button("Remove") { coordinator.preferences.formatting.replacements.remove(at:item.offset) } }
                }
            }
        }
    }
    private var formattingPage: some View {
        FlowPage {
            FlowSettingsGroup("Formatting shortcuts") {
                Text("Dictate with Fn, then use Option+1 to polish your text or Option+2 to turn it into a prompt. Nothing is submitted.").font(.callout).foregroundStyle(.secondary).padding(14)
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
                FlowSettingsRow("Fix spelling and common typos",description:"Protected dictionary terms are preserved.") { Toggle("Fix spelling and common typos",isOn:$coordinator.preferences.formatting.correctSpelling) }
                FlowSettingsRow("Smart typography",description:"Recognize spoken quotes and em dashes.") { Toggle("Smart typography",isOn:$coordinator.preferences.formatting.smartTypography) }
                FlowSettingsRow("Spoken punctuation") { Toggle("Spoken punctuation",isOn:$coordinator.preferences.formatting.spokenPunctuation) }
                FlowSettingsRow("Capitalize sentence starts") { Toggle("Capitalize sentence starts",isOn:$coordinator.preferences.formatting.sentenceCapitalization) }
                FlowSettingsRow("Remove filler words",description:"Removes isolated um, uh and erm.") { Toggle("Remove filler words",isOn:$coordinator.preferences.formatting.removeFillers) }
                FlowSettingsRow("Collapse repeated fillers") { Toggle("Collapse repeated fillers",isOn:$coordinator.preferences.formatting.removeRepeatedFillers).disabled(coordinator.preferences.formatting.removeFillers) }
                FlowSettingsRow("Explicit self corrections",description:"Recognize phrases such as ‘scratch that’; ambiguous wording is preserved.") { Toggle("Handle explicit self corrections",isOn:$coordinator.preferences.formatting.handleSelfCorrections) }
            }
            DisclosureGroup("Troubleshooting") {
                FlowSettingsRow("Shortcut registration",description:coordinator.previewShortcutStatus) { Button("Retry") { coordinator.configurePreviewShortcuts() }.disabled(!coordinator.preferences.previewShortcutsEnabled) }
                FlowSettingsRow("Diagnostics",description:"Copies status and error codes without your dictated text or audio.") { Button("Copy diagnostics") { _ = coordinator.copyReviewedText(coordinator.combinedDictationDiagnostics) }.disabled(!coordinator.historyCopyAllowed) }
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
                FlowSettingsRow("Hold to talk",description:"Native modifier choices; chords cancel rather than steal typing.") { Picker("Hold-to-talk key",selection:Binding(get:{ coordinator.preferences.activationKey },set:{ coordinator.changeActivationKey($0) })) { ForEach(DictationActivationKey.allCases,id:\.self) { Text($0.label).tag($0) } }.pickerStyle(.menu).disabled(coordinator.busy) }
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
                if coordinator.preferences.languageMode == .english {
                    FlowSettingsRow("Speech recognition",description:coordinator.speechStatus) { Button("Open Settings") { openPrivacy("Privacy_SpeechRecognition") } }
                }
            }
            FlowSettingsGroup("History") {
                FlowSettingsRow("Save dictation history on this Mac") { Toggle("Save dictation history on this Mac",isOn:$coordinator.preferences.keepHistory) }
                FlowSettingsRow("Saved dictations",description:"Raw/cleaned text, app name, duration and outcome. Up to 2,000 entries /100 MiB; disabling does not delete saved entries.") { Button("Clear all history…",role:.destructive) { confirmClear = true }.disabled(coordinator.busy || coordinator.entries.isEmpty) }
            }
            FlowSettingsGroup("Command Mode") {
                FlowSettingsRow("Enable Agent shortcut",description:coordinator.agentShortcutStatus) { Toggle("Enable Agent shortcut",isOn:Binding(get:{ coordinator.preferences.agentHotkeyEnabled },set:{ if $0 { coordinator.enableAgentShortcut() } else { coordinator.disableAgentShortcut() } })).disabled(coordinator.busy) }
                FlowSettingsRow("Agent key",description:"Separate from the dictation key.") {
                    Picker("Agent key",selection:Binding(get:{ coordinator.preferences.agentKey },set:{ coordinator.changeAgentKey($0) })) { ForEach(DictationActivationKey.allCases,id:\.self) { Text($0.label).tag($0) } }.pickerStyle(.menu).disabled(coordinator.busy)
                }
            }
            DisclosureGroup("Troubleshooting") { advancedSpeechSettings.padding(.top,12) }
            FlowSettingsGroup("About") {
                FlowSettingsRow("Wesley Flow") { Text(AppRelease.version).foregroundStyle(.secondary) }
                FlowSettingsRow("Source code") { Link("View on GitHub",destination:URL(string:"https://github.com/akshaywesleykothapalli/wesleyflow")!) }
            }
            if let error = coordinator.settingsError { Text(error).foregroundStyle(.orange) }
        }.onAppear { loginItem.refresh(); coordinator.refreshPermissions() }
    }
    private var advancedSpeechSettings: some View {
        FlowSettingsGroup("Dictation support") {
            if coordinator.preferences.languageMode == .teluguRomanised {
                FlowSettingsRow("Offline Telugu files",description:"Setup instructions are included in the GitHub documentation.") { Text(FileManager.default.fileExists(atPath:WhisperTeluguSmallModel.installedURL.path) ? "Installed" : "Setup required").foregroundStyle(.secondary) }
            } else {
                FlowSettingsRow("English speech setup",description:coordinator.speechResourceStatus) {
                    Button("Check availability") { Task { await coordinator.inspectSpeech() } }.disabled(coordinator.busy || coordinator.speechResourceWorking)
                }
                if coordinator.speechConfiguration?.installCandidate != nil {
                    FlowSettingsRow("Speech resources",description:"Install the on-device English resources supplied by macOS.") { Button("Set up English dictation") { coordinator.installSpeechResources() }.disabled(!coordinator.canInstallSpeechResources) }
                }
            }
            if coordinator.speechResourceWorking {
                FlowSettingsRow("Setup progress") {
                    if let fraction = coordinator.speechDownloadProgress?.fraction { ProgressView(value:fraction).frame(width:90) } else { ProgressView().controlSize(.small) }
                    Button("Stop waiting") { coordinator.stopWaitingForSpeechResources() }
                }
            }
            FlowSettingsRow("Diagnostics",description:"Status and error codes only; no dictated text or audio.") { Button("Copy diagnostics") { _ = coordinator.copyReviewedText(coordinator.combinedDictationDiagnostics) }.disabled(!coordinator.historyCopyAllowed) }
            Text("If Fn opens macOS emoji or Dictation, set Keyboard → Press Globe key to → Do Nothing.").font(.caption).foregroundStyle(.secondary).padding(14)
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
@MainActor private struct FlowSection<Content:View>: View {
    let title: String
    let content: Content
    init(_ title:String,@ViewBuilder content:() -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title.uppercased()).font(.system(size:12,weight:.semibold)).tracking(0.6).foregroundStyle(.secondary).padding(.leading,4)
            VStack(alignment:.leading,spacing:10) { content }
                .frame(maxWidth:.infinity,alignment:.leading).padding(14)
                .background(FlowSurface.card,in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(FlowSurface.border,lineWidth:1))
        }
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
                        if Self.hasSeparator(index:index,count:rows.count) { Divider().padding(.leading,14) }
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
