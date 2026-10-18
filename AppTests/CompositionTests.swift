import AppKit
import Domain
import Testing
@testable import WesleyFlow

@Suite("Native shell composition")
@MainActor
struct CompositionTests {
    @Test func productionCompositionConstructsHonestShell() {
        let composition = AppComposition()
        let state = composition.makeShellState()
        #expect(state.title == "Wesley Flow")
        #expect(state.phase == "Phase 0B · Native foundation")
        #expect(state.message.contains("separately approved phases"))
        #expect(composition.makeRootView().state == state)
    }

    @Test func compositionUsesInjectedProvider() {
        let expected = FoundationStatus(title: "Fixture", phase: "Composition test", message: "Injected value")
        let composition = AppComposition(statusProvider: FixedStatus(value: expected))
        #expect(composition.makeShellState() == expected)
        #expect(composition.makeRootView().state == expected)
    }

    @Test func localDomainProductLinksIntoApplicationTests() {
        let task = TaskLifecycle(id: .init(rawValue: "composition-test"), verification: .required)
        #expect(task.state == .queued)
        #expect(task.retryOf == nil)
        #expect(TaskState.Kind.allCases.count == 9)
    }

    @Test func appKitLifecycleClosesApplicationAfterLastWindow() {
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}

@MainActor
private struct FixedStatus: FoundationStatusProviding {
    let value: FoundationStatus
    func status() -> FoundationStatus { value }
}
