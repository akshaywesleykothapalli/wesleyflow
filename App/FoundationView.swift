import SwiftUI

@MainActor
struct FoundationView: View {
    let state: FoundationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(state.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(state.phase)
                .font(.headline)
            Text(state.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(minWidth: 480, idealWidth: 640, minHeight: 300, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityIdentifier("foundation-content")
    }
}
