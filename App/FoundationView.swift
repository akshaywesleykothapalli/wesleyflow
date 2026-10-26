import SwiftUI

@MainActor struct FoundationView: View {
    let state: FoundationStatus
    @StateObject private var coordinator: SystemWideDictationCoordinator
    init(state: FoundationStatus, dictation: DictationModel) {
        self.state = state
        _coordinator = StateObject(wrappedValue:AppComposition().makeSystemWideCoordinator())
    }
    init(state: FoundationStatus, coordinator: SystemWideDictationCoordinator) {
        self.state = state; _coordinator = StateObject(wrappedValue:coordinator)
    }
    var body: some View { GlobalDictationView(coordinator:coordinator) }
}
