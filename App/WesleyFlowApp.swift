import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var dictation: DictationModel?
    private var pill: ClickableDictationPill?
    private weak var global: SystemWideDictationCoordinator?
    func connect(_ model: DictationModel) { dictation = model }
    func connectGlobal(_ coordinator: SystemWideDictationCoordinator) { global = coordinator; if pill == nil { pill = ClickableDictationPill(coordinator:coordinator) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { if let global, global.preferences.holdFnEnabled || global.preferences.idlePillEnabled || global.busy { return false }; return !(dictation?.shortcutEnabled ?? false) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { (global?.canTerminateSafely() ?? true) ? .terminateNow : .terminateCancel }
    func applicationWillTerminate(_ notification: Notification) { dictation?.disableShortcut(); dictation?.close(); global?.close(); pill?.close() }
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
            if global.isPreviewingRewrite { Button("Cancel AI preview") { global.cancelRewritePreview() } }
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
