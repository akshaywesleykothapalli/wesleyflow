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
        observation = Publishers.CombineLatest4(coordinator.$phase,coordinator.$preferences,coordinator.$inPlaceHUD,coordinator.$hudFeedbackVisible).sink { [weak self] _,_,_,_ in Task { @MainActor [weak self] in self?.refresh() } }
        refresh()
    }
    private func refresh() {
        guard let coordinator else { return }
        hitView.updateAccessibility()
        if coordinator.pillVisible && coordinator.pillContent != .hidden { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
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
        let menu = NSMenu(), item = NSMenuItem(title:coordinator?.agentHUD == nil ? "Cancel dictation" : "Cancel Agent",action:#selector(cancelDictation),keyEquivalent:"")
        item.target = self; item.isEnabled = coordinator?.busy == true || coordinator?.inPlaceRunning == true || (coordinator?.agentPlan != nil || coordinator?.agentQuestion != nil); menu.addItem(item)
        NSMenu.popUpContextMenu(menu,with:event,for:self)
    }
    @objc private func cancelDictation() { if coordinator?.agentQuestion != nil { coordinator?.cancelAgentConversation() } else if let id = coordinator?.agentPlan?.id { coordinator?.cancelAgentTask(id) } else { coordinator?.cancel() } }
    override func accessibilityPerformPress() -> Bool { coordinator?.pillClicked(); return coordinator != nil }
    func updateAccessibility() { setAccessibilityLabel(coordinator?.agentHUD == nil ? "Dictation status" : "Agent status"); setAccessibilityHelp(coordinator?.message); toolTip = (coordinator?.agentPlan != nil || coordinator?.agentQuestion != nil) ? "Click to review or reply; right-click to cancel." : "Hold the Dictation key to insert, or the separate Agent key for commands. Right-click to cancel." }
}
enum DictationHUDContent: Equatable {
    case waveform, label(String), idle, hidden
    static func resolve(phase:SystemWideDictationCoordinator.Phase,ai:SystemWideDictationCoordinator.InPlaceHUD,verified:Bool) -> Self {
        switch ai {
        case .polishing: return .label("Polishing…")
        case .structuring: return .label("Structuring…")
        case .success: return .hidden
        case .error: return .label("Check dictation")
        case .idle: break
        }
        switch phase {
        case .recording: return .waveform
        case .preparing: return .hidden
        case .finalizing: return .label("Transcribing…")
        case .inserting: return .label("Transcribing…")
        case .success: return .hidden
        case .error: return .label("Check dictation")
        case .idle: return .idle
        }
    }
}
@MainActor extension SystemWideDictationCoordinator {
    var pillContent:DictationHUDContent {
        // Keep actionable AI status as text; ordinary errors stay in Dictation.
        if let agentHUD { return .label(agentHUD) }
        if hideCompletedDictationPill { return .hidden }
        if isPreparingTelugu { return .label("Preparing Telugu…") }
        return inPlaceHUD == .error ? .label(compactAIStatus) : phase == .error ? .label(compactDictationStatus) : DictationHUDContent.resolve(phase:phase,ai:inPlaceHUD,verified:latest?.insertion.status == .insertedVerified)
    }
}
@MainActor private struct GlobalDictationWaveform: View {
    @ObservedObject var coordinator: SystemWideDictationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let content = coordinator.pillContent
        Group {
            switch content {
            case .idle: Image(systemName:"mic.fill").foregroundStyle(.secondary)
            case .hidden: EmptyView()
            case .label(let text): Text(text).overlay(alignment:.bottom) { if text == "Agent listening" { HStack(spacing:2) { ForEach(0..<7) { i in Capsule().fill(Color.teal).frame(width:3,height:CGFloat(1+coordinator.audioBars[i]*3)) } }.offset(y:5) } }.font(.system(size:10)).lineLimit(2).multilineTextAlignment(.center).padding(.horizontal,3)
            case .waveform:
                HStack(spacing:3) {
                    ForEach(0..<7) { index in Capsule().fill(Color.teal).frame(width:3,height:CGFloat(5+coordinator.audioBars[index]*15)) }
                }.animation(reduceMotion ? nil : .linear(duration:0.05),value:coordinator.audioBars)
            }
        }.frame(width:84,height:32).background(.ultraThinMaterial,in:Capsule())
    }
}
