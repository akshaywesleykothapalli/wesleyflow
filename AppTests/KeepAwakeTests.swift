import AppKit
import Foundation
import Testing
@testable import WesleyFlow

struct KeepAwakeCommandTests {
    @Test func recognizesWholeCommandsAndRejectsAmbiguousConditions() {
        #expect(KeepAwakeCommand.parse("Make my screen active until I say, turn it off.", active: false) == .untilStopped)
        #expect(KeepAwakeCommand.parse("Keep my screen awake for one hour", active: false) == .timed(3600))
        #expect(KeepAwakeCommand.parse("Keep my screen awake for twenty-five minutes", active: false) == .timed(1500))
        #expect(KeepAwakeCommand.parse("Keep my screen awake for 25 hours", active: false) == .unsupported)
        #expect(KeepAwakeCommand.parse("Keep my screen awake until Visual Studio Code quits", active: false) == .application("Visual Studio Code"))
        #expect(KeepAwakeCommand.parse("Keep my screen awake while this app is running", active: false) == .application("this app"))
        #expect(KeepAwakeCommand.parse("Keep my screen awake until Report.zip is downloaded.", active: false) == .download("Report.zip"))
        #expect(KeepAwakeCommand.parse("Keep my screen awake until the download finishes", active: false) == .download(nil))
        #expect(KeepAwakeCommand.parse("Keep my screen awake until Safari finishes downloading", active: false) == .unsupported)
        #expect(KeepAwakeCommand.parse("Tell Bob to keep my screen awake", active: true) == nil)
        #expect(KeepAwakeCommand.parse("Turn it off", active: false) == nil)
        #expect(KeepAwakeCommand.parse("Turn it off", active: true) == .stop)
        #expect(KeepAwakeCommand.parse("Lock the screen by making it active", active: false) == .curtain)
        #expect(KeepAwakeCommand.parse("Lock my screen and keep it awake.", active: true) == .curtain)
        #expect(KeepAwakeCommand.parse("Keep my screen awake for an hour and cover the screen.", active: false) == .timedCurtain(3600))
        #expect(KeepAwakeCommand.parse("Cover the screen by making it awake for 1 hour.", active: false) == .timedCurtain(3600))
        #expect(KeepAwakeCommand.parse("Cover my screen by keeping it awake for two minutes", active: true) == .timedCurtain(120))
        #expect(KeepAwakeCommand.parse("Cover the screen by making it awake for 25 hours", active: false) == .unsupported)
        #expect(KeepAwakeCommand.parse("Show the privacy curtain.", active: false) == .curtain)
        #expect(KeepAwakeCommand.parse("Tell me how to lock the screen and keep it awake", active: true) == nil)
    }

    @Test func watchesNewFilesAndWaitsForPartialRemovalAndStability() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let partial = root.appendingPathComponent("report.zip.crdownload")
        let final = root.appendingPathComponent("report.zip")
        try Data([1]).write(to: partial)
        var download = try DownloadCompletion(directory: root, filename: nil)
        #expect(download.filename == "report.zip")
        try Data([1]).write(to: final)
        #expect(try !download.finished())
        try FileManager.default.removeItem(at: partial)
        #expect(try !download.finished())
        try Data([1, 2]).write(to: final)
        #expect(try !download.finished())
        #expect(try !download.finished())
        #expect(try download.finished())
        #expect(throws: DownloadCompletion.SetupFailure.alreadyExists) {
            try DownloadCompletion(directory: root, filename: "report.zip")
        }
        #expect(throws: DownloadCompletion.SetupFailure.invalidName) {
            try DownloadCompletion(directory: root, filename: "../report.zip")
        }
        try Data([1]).write(to: partial)
        try Data([2]).write(to: root.appendingPathComponent("other.zip.part"))
        #expect(throws: DownloadCompletion.SetupFailure.ambiguous) {
            try DownloadCompletion(directory: root, filename: nil)
        }
    }
}

@MainActor struct KeepAwakeSessionTests {
    @Test func curtainPanelCanJoinOtherAppsWithoutActivatingWesleyFlow() {
        let panel = FrostedScreenCurtain.makePanel(frame: NSRect(x: 20, y: 30, width: 640, height: 480))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.canBecomeKey)
        #expect(panel.isOpaque)
    }

    @Test func replacesAndReleasesExactlyOneAssertionPerSession() {
        var next: UInt32 = 0
        var released: [UInt32] = []
        let session = KeepAwakeSession(acquire: { next += 1; return next }, release: { released.append($0) })
        #expect(session.run(.untilStopped, origin: nil))
        #expect(!session.run(.unsupported, origin: nil))
        #expect(session.isActive)
        #expect(released.isEmpty)
        #expect(session.run(.untilStopped, origin: nil))
        #expect(released == [1])
        #expect(session.run(.stop, origin: nil))
        #expect(!session.isActive)
        session.stop()
        #expect(released == [1, 2])
    }

    @Test func curtainRequiresTouchIDToShowAndToReveal() async {
        let curtain = CurtainFixture()
        var decisions = [false, true, false, true]
        let session = KeepAwakeSession(acquire: { 7 }, release: { _ in },
                                       authenticate: { _ in decisions.removeFirst() }, curtain: curtain)
        await withCheckedContinuation { continuation in
            session.onStatus = { if $0.hasPrefix("Touch ID did not confirm") { continuation.resume() } }
            #expect(session.run(.curtain, origin: nil))
        }
        #expect(!curtain.visible)
        #expect(!session.isActive)
        await withCheckedContinuation { continuation in
            session.onStatus = { if $0.hasPrefix("Privacy curtain is on") { continuation.resume() } }
            #expect(session.run(.curtain, origin: nil))
        }
        #expect(curtain.visible)
        #expect(session.isActive)
        await withCheckedContinuation { continuation in
            curtain.onFailure = { continuation.resume() }
            curtain.unlock?()
        }
        #expect(curtain.visible)
        await withCheckedContinuation { continuation in
            session.onStatus = { if $0.hasPrefix("Privacy curtain removed") { continuation.resume() } }
            curtain.unlock?()
        }
        #expect(!curtain.visible)
        #expect(session.isActive)
        session.stop()
    }

    @Test func curtainCoversTheDisplayDuringBothTrackpadChanges() async {
        let curtain = CurtainFixture()
        let receipt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: receipt) }
        var selected: CurtainSwipeSetting.Choice = .threeFingers
        let swipeSetting = CurtainSwipeSetting(receipt: receipt, read: { selected }, replace: { _, choice, prepare in
            #expect(curtain.visible)
            #expect(curtain.updatingSettings)
            try prepare()
            selected = choice
        })
        let session = KeepAwakeSession(acquire: { 7 }, release: { _ in },
                                       authenticate: { _ in true }, curtain: curtain, swipeSetting: swipeSetting)
        await withCheckedContinuation { continuation in
            session.onStatus = { if $0.hasPrefix("Privacy curtain is on") { continuation.resume() } }
            #expect(session.run(.curtain, origin: nil))
        }
        #expect(selected == .off)
        #expect(!curtain.updatingSettings)
        await withCheckedContinuation { continuation in
            session.onStatus = { if $0.hasPrefix("Privacy curtain removed") { continuation.resume() } }
            curtain.unlock?()
        }
        #expect(selected == .threeFingers)
        #expect(!curtain.visible)
        session.stop()
    }

    @Test func keepAwakeTimerEndsWithoutRevealingTheDesktop() async {
        let curtain = CurtainFixture()
        var released: [UInt32] = []
        var requested: Duration?
        let session = KeepAwakeSession(acquire: { 7 }, release: { released.append($0) }, wait: { requested = $0 },
                                       authenticate: { _ in true }, curtain: curtain)
        await withCheckedContinuation { continuation in
            session.onStatus = { if $0.contains("timer finished") { continuation.resume() } }
            #expect(session.run(.timedCurtain(60), origin: nil))
        }
        #expect(requested == .seconds(60))
        #expect(released == [7])
        #expect(!session.isActive)
        #expect(session.isCurtainVisible)
        #expect(curtain.visible)
        await withCheckedContinuation { continuation in
            session.onStatus = { if $0.hasPrefix("Privacy curtain removed") { continuation.resume() } }
            curtain.unlock?()
        }
        #expect(!curtain.visible)
    }

    @Test func timerReleasesTheAssertionAndPublishesTheEnd() async {
        var released: [UInt32] = []
        var requested: Duration?
        let session = KeepAwakeSession(acquire: { 7 }, release: { released.append($0) }, wait: { requested = $0 })
        await withCheckedContinuation { continuation in
            session.onStatus = { message in
                if message.contains("timer finished") { continuation.resume() }
            }
            #expect(session.run(.timed(60), origin: nil))
        }
        #expect(requested == .seconds(60))
        #expect(released == [7])
        #expect(!session.isActive)
    }
}


@MainActor private final class CurtainFixture: ScreenCurtain {
    var visible = false
    var unlock: (() -> Void)?
    var onFailure: (() -> Void)?
    var updatingSettings = false

    func show(onUnlock: @escaping () -> Void) -> Bool {
        unlock = onUnlock
        visible = true
        return true
    }

    func setUnlocking(_ unlocking: Bool) {}
    func setUpdatingSettings(_ updating: Bool) { updatingSettings = updating }
    func showUnlockFailure() { onFailure?() }
    func hide() { visible = false; updatingSettings = false; unlock = nil }
}


@MainActor struct CurtainSwipeSettingTests {
    @Test(arguments: [false, true])
    func restoresTheExactPreviousSwipeChoiceAfterRelaunch(_ fourFingers: Bool) async throws {
        let original: CurtainSwipeSetting.Choice = fourFingers ? .fourFingers : .threeFingers
        var selected = original
        let receipt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: receipt) }
        let replace: CurtainSwipeSetting.Replace = { expected, newValue, beforeChange in
            #expect(selected == expected)
            try beforeChange()
            if newValue == .off { #expect(FileManager.default.fileExists(atPath: receipt.path)) }
            selected = newValue
        }
        let firstLaunch = CurtainSwipeSetting(receipt: receipt, read: { selected }, replace: replace)
        try await firstLaunch.suspend()
        #expect(selected == .off)
        #expect(firstLaunch.hasPendingRestore)
        let nextLaunch = CurtainSwipeSetting(receipt: receipt, read: { selected }, replace: replace)
        try await nextLaunch.restore()
        #expect(selected == original)
        #expect(!nextLaunch.hasPendingRestore)
    }

    @Test func leavesAnAlreadyOffGestureAloneAndPreservesAnExternalEnabledChoice() async throws {
        var selected: CurtainSwipeSetting.Choice = .off
        var writes = 0
        let receipt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: receipt) }
        let lease = CurtainSwipeSetting(receipt: receipt, read: { selected }, replace: { _, newValue, beforeChange in
            writes += 1
            try beforeChange()
            selected = newValue
        })
        try await lease.suspend()
        #expect(writes == 0)
        #expect(!lease.hasPendingRestore)
        selected = .fourFingers
        try await lease.suspend()
        selected = .threeFingers
        try await lease.restore()
        #expect(selected == .threeFingers)
        #expect(writes == 1)
        #expect(!lease.hasPendingRestore)
    }
}
