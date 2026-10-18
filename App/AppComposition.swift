import SwiftUI

struct FoundationStatus: Equatable, Sendable {
    let title: String
    let phase: String
    let message: String
}

@MainActor
protocol FoundationStatusProviding {
    func status() -> FoundationStatus
}

@MainActor
struct NativeFoundationStatus: FoundationStatusProviding {
    func status() -> FoundationStatus {
        FoundationStatus(
            title: "Wesley Flow",
            phase: "Phase 0B · Native foundation",
            message: "The native shell and task lifecycle foundation are ready for verification. Feature workflows belong to separately approved phases."
        )
    }
}

@MainActor
struct AppComposition {
    private let statusProvider: any FoundationStatusProviding

    init(statusProvider: any FoundationStatusProviding = NativeFoundationStatus()) {
        self.statusProvider = statusProvider
    }

    func makeShellState() -> FoundationStatus { statusProvider.status() }
    func makeRootView() -> FoundationView { FoundationView(state: makeShellState()) }
}
