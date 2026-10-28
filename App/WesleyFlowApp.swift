import AppKit
import SwiftUI
import Combine
import Domain

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var dictation: DictationModel?
    private var pill: ClickableDictationPill?
    private var aiPreview: ShortcutPreviewPanel?
    private weak var global: SystemWideDictationCoordinator?
    func connect(_ model: DictationModel) { dictation = model }
    func connectGlobal(_ coordinator: SystemWideDictationCoordinator) { global = coordinator; if pill == nil { pill = ClickableDictationPill(coordinator:coordinator) }; if aiPreview == nil { aiPreview = ShortcutPreviewPanel(coordinator:coordinator) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { if let global, global.preferences.holdFnEnabled || global.preferences.idlePillEnabled || global.preferences.previewShortcutsEnabled || global.busy { return false }; return !(dictation?.shortcutEnabled ?? false) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { (global?.canTerminateSafely() ?? true) ? .terminateNow : .terminateCancel }
    func applicationWillTerminate(_ notification: Notification) { dictation?.disableShortcut(); dictation?.close(); global?.close(); pill?.close(); aiPreview?.close() }
}

@main
@MainActor
struct WesleyFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let composition = AppComposition()
    @StateObject private var global = AppComposition().makeSystemWideCoordinator()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Wesley Flow", id: "foundation") {
            FoundationView(state:composition.makeShellState(),coordinator:global)
                .onAppear { if NSClassFromString("XCTestCase") == nil { appDelegate.connectGlobal(global); global.resumeShortcutIfAuthorized() } }
                .task {
                    // Hosted unit tests use only injected stores, never the user’s transcript history.
                    if NSClassFromString("XCTestCase") == nil { await global.loadHistory() }
                }
        }
        .defaultSize(width:CompactWindowLayout.defaultSize.width,height:CompactWindowLayout.defaultSize.height)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            Text(global.message)
            Text(global.previewNotice)
            if global.isPreviewingRewrite || global.inPlaceRunning { Button("Cancel AI") { global.cancelRewritePreview(); global.cancelInPlaceRewrite() } }
            Button("Open Wesley Flow") { openWindow(id:"foundation"); NSApplication.shared.activate() }
            if global.busy { Button("Cancel dictation") { global.cancel() } }
            Button(global.shortcutEnabled ? "Disable hold-to-talk dictation" : "Enable hold-to-talk dictation…") {
                if global.shortcutEnabled { global.disableShortcut() } else { global.enableShortcut() }
            }
            if !global.accessibilityAllowed && !global.busy { Button("Dictate for manual copy") { global.startManual() } }
            Divider()
            Button("Quit Wesley Flow") { NSApplication.shared.terminate(nil) }
        } label: { Image(systemName:global.phase == .recording ? "mic.fill" : "waveform") }
    }
}


/// Explicit Settings preview only; an explicit Edit input action
/// allows this panel to receive keyboard focus. Capture stays read-only.
@MainActor final class ShortcutPreviewPanel: NSObject, NSWindowDelegate {
    private final class Panel: NSPanel {
        var editing = false
        override var canBecomeKey: Bool { editing }
        override var canBecomeMain: Bool { false }
    }
    private var panel: Panel?
    private weak var coordinator: SystemWideDictationCoordinator?
    private var observation: AnyCancellable?
    init(coordinator: SystemWideDictationCoordinator) {
        self.coordinator = coordinator
        super.init()
        observation = coordinator.$previewPresented.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    private func makePanel(coordinator:SystemWideDictationCoordinator) -> Panel {
        if let panel { return panel }
        let panel = Panel(contentRect:NSRect(x:0,y:0,width:480,height:380),styleMask:[.titled,.closable,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title = "Wesley Flow · AI Preview · 37"; panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:ShortcutPreviewContents(coordinator:coordinator,beginEditing:{ [weak self] in self?.beginEditing() }))
        panel.delegate = self; panel.center(); self.panel = panel
        return panel
    }
    private func beginEditing() {
        guard let panel, panel.isVisible else { return }; panel.editing = true; panel.makeKey()
    }
    private func refresh() {
        if let coordinator, coordinator.previewPresented {
            let panel = makePanel(coordinator:coordinator)
            panel.orderFrontRegardless()
            coordinator.recordPreviewDiagnostic(panel.isVisible ? .presented : .hidden)
        } else { panel?.editing = false; panel?.orderOut(nil); coordinator?.recordPreviewDiagnostic(.hidden) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        coordinator?.dismissShortcutPreview(); panel?.orderOut(nil); return false
    }
    func close() { observation?.cancel(); observation = nil; panel?.orderOut(nil); panel?.delegate = nil; panel?.close(); panel = nil }
    // No native preview window is allocated until an explicit presentation request.
    var hasCreatedPanel: Bool { panel != nil }
    var isVisible: Bool { panel?.isVisible ?? false }
    var canBecomeKey: Bool { panel?.canBecomeKey ?? false }

}
@MainActor private struct ShortcutPreviewContents: View {
    @ObservedObject var coordinator: SystemWideDictationCoordinator
    let beginEditing: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(coordinator.previewKind == .polish ? "Smart Polish" : "Prompt Engineering").font(.headline)
            Text("Preview only · Edit input takes keyboard focus only when clicked").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    Text(coordinator.shortcutSource.rawValue).font(.caption).foregroundStyle(.secondary)
                    if coordinator.isResolvingShortcutText { ProgressView("Reading focused text…") }
                    TextEditor(text:$coordinator.shortcutInputText).frame(minHeight:80).accessibilityLabel("Preview input")
                        .disabled(coordinator.isResolvingShortcutText || coordinator.isPreviewingRewrite)
                    Button("Edit input",action:beginEditing).disabled(coordinator.isResolvingShortcutText || coordinator.isPreviewingRewrite)
                    Button("Generate preview") { coordinator.generateShortcutPreview() }
                        .disabled(coordinator.shortcutInputText.isEmpty || coordinator.shortcutInputText.utf8.count > 2048 || coordinator.isResolvingShortcutText || coordinator.isPreviewingRewrite)
                    Text("Original").font(.caption).foregroundStyle(.secondary)
                    Text(coordinator.previewOriginalText)
                    Text(coordinator.previewNotice).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Capture details") { Text(coordinator.previewCaptureDiagnostic).font(.caption).textSelection(.enabled) }
                    if let result = coordinator.previewKind == .polish ? coordinator.rewritePreview : coordinator.promptPreview {
                        Text(coordinator.rewritePreviewMessage).font(.caption)
                        Text(result.text)
                        Button("Copy reviewed preview") { _ = coordinator.copyReviewedText(result.text) }.disabled(!coordinator.historyCopyAllowed)
                        Button("Reject preview") { coordinator.rejectRewritePreview() }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack {
                if coordinator.isPreviewingRewrite || coordinator.isResolvingShortcutText { ProgressView().controlSize(.small); Button("Cancel") { coordinator.cancelTextCapture(); coordinator.cancelRewritePreview() } }
                Spacer()
                Button("Close") { coordinator.dismissShortcutPreview() }
            }
        }.padding(18).frame(width:480,height:380).background(Color(nsColor:.windowBackgroundColor))
    }
}
