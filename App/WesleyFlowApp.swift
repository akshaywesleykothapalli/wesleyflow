import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
@MainActor
struct WesleyFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let composition = AppComposition()

    var body: some Scene {
        Window("Wesley Flow", id: "foundation") {
            composition.makeRootView()
        }
        .defaultSize(width: 640, height: 360)
        .windowResizability(.contentMinSize)
    }
}
