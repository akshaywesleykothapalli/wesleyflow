import AppKit
import SwiftUI
import Combine

@MainActor final class NonActivatingDictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class ClickableDictationPill {
    let panel: NonActivatingDictationPanel
    private weak var coordinator: SystemWideDictationCoordinator?
    private let hitView: DictationPillHitView
    private var observation: AnyCancellable?
    init(coordinator: SystemWideDictationCoordinator) {
        self.coordinator = coordinator
        panel = NonActivatingDictationPanel(contentRect:NSRect(x:0,y:0,width:84,height:32),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false; panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear
        hitView = DictationPillHitView(coordinator:coordinator); panel.contentView = hitView
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.midX-42,y:screen.visibleFrame.minY+36)) }
        observation = coordinator.$phase.combineLatest(coordinator.$preferences).sink { [weak self] _,_ in Task { @MainActor [weak self] in self?.refresh() } }
        refresh()
    }
    private func refresh() {
        guard let coordinator else { return }
        hitView.updateAccessibility()
        if coordinator.pillVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
    func close() { observation?.cancel(); panel.orderOut(nil); panel.close() }
}
@MainActor final class DictationPillHitView: NSView {
    private weak var coordinator: SystemWideDictationCoordinator?
    init(coordinator: SystemWideDictationCoordinator) {
        self.coordinator = coordinator
        super.init(frame:NSRect(x:0,y:0,width:84,height:32))
        let host = NSHostingView(rootView:GlobalDictationWaveform(coordinator:coordinator).accessibilityHidden(true))
        host.frame = bounds; host.autoresizingMask = [.width,.height]; addSubview(host)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        toolTip = "Hold Fn to speak; release Fn to insert. Right-click to cancel."
        updateAccessibility()
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point,from:superview)) ? self : nil }
    override func mouseDown(with event: NSEvent) { coordinator?.pillClicked(clickCount:event.clickCount) }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(), item = NSMenuItem(title:"Cancel dictation",action:#selector(cancelDictation),keyEquivalent:"")
        item.target = self; item.isEnabled = coordinator?.busy == true; menu.addItem(item)
        NSMenu.popUpContextMenu(menu,with:event,for:self)
    }
    @objc private func cancelDictation() { coordinator?.cancel() }
    override func accessibilityPerformPress() -> Bool { coordinator?.pillClicked(); return coordinator != nil }
    func updateAccessibility() { setAccessibilityLabel("Dictation status"); setAccessibilityHelp(coordinator?.message); toolTip = "Hold the selected key to speak. Click to start/stop; right-click to cancel." }
}
@MainActor private struct GlobalDictationWaveform: View {
    @ObservedObject var coordinator: SystemWideDictationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            switch coordinator.phase {
            case .idle: Image(systemName:"mic.fill").foregroundStyle(.secondary)
            case .preparing,.finalizing: ProgressView().controlSize(.small)
            case .inserting: Image(systemName:"arrow.down.to.line").foregroundStyle(.secondary)
            case .success: Image(systemName:"checkmark").foregroundStyle(.green)
            case .error: Image(systemName:"exclamationmark").foregroundStyle(.orange)
            case .recording:
                TimelineView(.animation(minimumInterval:1.0/20,paused:reduceMotion)) { timeline in
                    HStack(spacing:3) {
                        ForEach(0..<7) { index in
                            let motion = reduceMotion ? 0.5 : (sin(timeline.date.timeIntervalSinceReferenceDate*6+Double(index)*0.9)+1)/2
                            Capsule().fill(Color.teal).frame(width:3,height:CGFloat(5+motion*15))
                        }
                    }
                }
            }
        }.frame(width:84,height:32).background(.ultraThinMaterial,in:Capsule())
    }
}
