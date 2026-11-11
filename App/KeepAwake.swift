import AppKit
import Domain
import Foundation
import IOKit.pwr_mgt
import LocalAuthentication
import SystemOperations

enum KeepAwakeCommand: Equatable {
    case untilStopped, timed(Int), application(String), download(String?), curtain, timedCurtain(Int), stop, unsupported

    static func parse(_ utterance: String, active: Bool) -> Self? {
        guard utterance.utf8.count <= 512, !utterance.contains(where: \.isNewline) else { return nil }
        let text = PersonalAgentDialogue.canonical(utterance).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let lower = text.lowercased()
        if ["cover the screen", "cover my screen", "show frosted glass", "show the privacy curtain",
            "lock the screen by making it active", "lock my screen by making it active",
            "lock the screen and keep it awake", "lock my screen and keep it awake",
            "lock the screen and keep my mac awake"].contains(lower) { return .curtain }
        let timedCoverPrefixes = ["cover the screen by making it awake for ", "cover my screen by making it awake for ",
                                  "cover the screen by keeping it awake for ", "cover my screen by keeping it awake for "]
        if let prefix = timedCoverPrefixes.first(where: { lower.hasPrefix($0) }) {
            return durationSeconds(lower.dropFirst(prefix.count)).map(Self.timedCurtain) ?? .unsupported
        }
        let coverEnding = " and cover the screen"
        if lower.hasSuffix(coverEnding),
           case .timed(let seconds) = parse(String(text.dropLast(coverEnding.count)), active: active) {
            return .timedCurtain(seconds)
        }
        if ["stop keeping my screen awake", "stop keeping the screen awake", "end keep awake"].contains(lower)
            || (active && ["turn it off", "turn off keep awake"].contains(lower)) { return .stop }

        let prefixes = ["make my screen active", "keep my screen awake", "keep the screen awake",
                        "keep my mac awake", "keep my laptop awake"]
        guard let prefix = prefixes.first(where: { lower == $0 || lower.hasPrefix($0 + " ") }) else { return nil }
        let suffix = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        let rule = suffix.lowercased()
        if ["", "until i say stop", "until i say turn it off", "until i say, turn it off", "until i turn it off"].contains(rule) {
            return .untilStopped
        }
        if rule.hasPrefix("for ") {
            return durationSeconds(rule.dropFirst(4)).map(Self.timed) ?? .unsupported
        }
        if rule.hasPrefix("while "), rule.hasSuffix(" is running") {
            let name = String(suffix.dropFirst(6).dropLast(" is running".count))
            return name.isEmpty ? .unsupported : .application(name)
        }
        guard rule.hasPrefix("until ") else { return .unsupported }
        let condition = String(suffix.dropFirst(6))
        let conditionLower = condition.lowercased()
        if ["the download finishes", "the download completes", "the file is downloaded", "the download is complete"].contains(conditionLower) {
            return .download(nil)
        }
        for ending in [" quits", " closes", " stops running", " exits"] where conditionLower.hasSuffix(ending) {
            let name = String(condition.dropLast(ending.count))
            return name.isEmpty ? .unsupported : .application(name)
        }
        for ending in [" is downloaded", " finishes downloading", " downloads"] where conditionLower.hasSuffix(ending) {
            let name = String(condition.dropLast(ending.count))
            return name.contains(".") ? .download(name) : .unsupported
        }
        return .unsupported
    }

    private static func durationSeconds(_ text: Substring) -> Int? {
        let words = text.split(separator: " ")
        guard let unit = words.last, let value = number(words.dropLast().joined(separator: " ")),
              let multiplier = ["second": 1, "seconds": 1, "minute": 60, "minutes": 60, "hour": 3600, "hours": 3600][String(unit)],
              (1...(86_400 / multiplier)).contains(value) else { return nil }
        return value * multiplier
    }

    private static func number(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let small = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                     "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        if ["a", "an"].contains(text) { return 1 }
        if let value = small.firstIndex(of: text) { return value }
        let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        let words = text.split(whereSeparator: { $0 == " " || $0 == "-" })
        guard (1...2).contains(words.count), let first = tens.firstIndex(of: String(words[0])) else { return nil }
        let base = (first + 2) * 10
        guard words.count == 2 else { return base }
        guard let rest = small.prefix(10).firstIndex(of: String(words[1])), rest > 0 else { return nil }
        return base + rest
    }
}

struct DownloadCompletion {
    enum SetupFailure: Error, Equatable { case invalidName, alreadyExists, ambiguous }
    private struct Stamp: Equatable {
        let size: Int
        let modified: Date
        let identity: String
    }

    private static let partialExtensions = ["download", "crdownload", "part"]
    private let directory: URL
    let filename: String
    private var previous: Stamp?
    private var unchanged = 0

    init(directory: URL, filename: String?) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let resolved: String
        if let filename {
            resolved = filename
        } else {
            let candidates = names.compactMap { name -> String? in
                guard let dot = name.lastIndex(of: "."), Self.partialExtensions.contains(String(name[name.index(after: dot)...]).lowercased()) else { return nil }
                return String(name[..<dot])
            }
            guard candidates.count == 1, let name = candidates.first else { throw SetupFailure.ambiguous }
            resolved = name
        }
        guard !resolved.isEmpty, resolved.utf8.count <= 255, !resolved.hasPrefix("."),
              !resolved.contains("/"), !resolved.contains("\\"), !resolved.contains(where: \.isNewline),
              !Self.partialExtensions.contains((resolved as NSString).pathExtension.lowercased()) else { throw SetupFailure.invalidName }
        guard !names.contains(where: { $0.caseInsensitiveCompare(resolved) == .orderedSame }) else { throw SetupFailure.alreadyExists }
        self.directory = directory
        self.filename = resolved
    }

    mutating func finished() throws -> Bool {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let partials = Self.partialExtensions.map { "\(filename).\($0)".lowercased() }
        guard !names.contains(where: { partials.contains($0.lowercased()) }),
              let name = names.first(where: { $0.caseInsensitiveCompare(filename) == .orderedSame }) else {
            previous = nil; unchanged = 0
            return false
        }
        let url = directory.appendingPathComponent(name)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false,
              let size = values.fileSize, size > 0, let modified = values.contentModificationDate,
              let identity = values.fileResourceIdentifier else {
            previous = nil; unchanged = 0
            return false
        }
        let stamp = Stamp(size: size, modified: modified, identity: String(describing: identity))
        unchanged = previous == stamp ? unchanged + 1 : 0
        previous = stamp
        return unchanged >= 2
    }
}

@MainActor final class CurtainSwipeSetting {
    typealias Choice = NativeSystemSettings.SpacesSwipe
    private let receipt: URL
    private let read: @MainActor () async throws -> Choice
    typealias Replace = @MainActor (Choice, Choice, () throws -> Void) async throws -> Void
    private let replace: Replace

    init(receipt: URL,
         read: @escaping @MainActor () async throws -> Choice = NativeSystemSettings.spacesSwipe,
         replace: @escaping Replace = NativeSystemSettings.replaceSpacesSwipe) {
        self.receipt = receipt
        self.read = read
        self.replace = replace
    }

    var hasPendingRestore: Bool { FileManager.default.fileExists(atPath: receipt.path) }

    func suspend() async throws {
        try await restore()
        let original = try await read()
        guard original != .off else { return }
        try FileManager.default.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await replace(original, .off) {
            // Save the exact choice before pressing Off so a relaunch can restore it.
            try Data(original.rawValue.utf8).write(to: receipt, options: .atomic)
        }
    }

    func restore() async throws {
        guard hasPendingRestore else { return }
        guard let original = Choice(rawValue: try String(contentsOf: receipt, encoding: .utf8)), original != .off else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let current = try await read()
        if current == .off { try await replace(.off, original, {}) }
        // An enabled choice may have been changed deliberately outside Wesley Flow.
        try FileManager.default.removeItem(at: receipt)
    }
}

@MainActor final class KeepAwakeSession {
    typealias Acquire = () -> IOPMAssertionID?
    typealias Wait = @MainActor (Duration) async throws -> Void
    private let acquire: Acquire
    private let release: (IOPMAssertionID) -> Void
    private let wait: Wait
    private let authenticate: @MainActor (String) async throws -> Bool
    private let curtain: any ScreenCurtain
    private let swipeSetting: CurtainSwipeSetting?
    private var authenticationTask: Task<Void, Never>?
    private var authenticationID: UUID?
    private var assertion: IOPMAssertionID?
    private var task: Task<Void, Never>?
    private var sessionID: UUID?
    var isActive: Bool { assertion != nil }
    var canStop: Bool { isActive || authenticationID != nil }
    private(set) var isCurtainVisible = false
    var isUpdatingCurtain: Bool { authenticationID != nil || isRecoveringSwipe }
    private var isRecoveringSwipe = false
    var onStatus: ((String) -> Void)?

    init(acquire: @escaping Acquire = KeepAwakeSession.acquireDisplay,
         release: @escaping (IOPMAssertionID) -> Void = { IOPMAssertionRelease($0) },
         wait: @escaping Wait = { try await Task.sleep(for: $0) },
         authenticate: @escaping @MainActor (String) async throws -> Bool = KeepAwakeSession.confirmWithTouchID,
         curtain: any ScreenCurtain = FrostedScreenCurtain(),
         swipeSetting: CurtainSwipeSetting? = nil) {
        self.acquire = acquire
        self.release = release
        self.wait = wait
        self.authenticate = authenticate
        self.curtain = curtain
        self.swipeSetting = swipeSetting
    }

    @discardableResult
    func run(_ command: KeepAwakeCommand, origin: DictationApplicationIdentity?) -> Bool {
        switch command {
        case .stop:
            stop(message: "Keep awake is off. Normal display sleep can resume.")
            return true
        case .curtain:
            return requestCurtain(duration: nil)
        case .timedCurtain(let seconds):
            return requestCurtain(duration: seconds)
        case .untilStopped:
            return start("Keeping the screen awake until you say “turn it off”.")
        case .timed(let seconds):
            return startTimer(seconds)
        case .application(let name):
            let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
            let matches = apps.filter { app in
                if ["this app", "this application", "the current app"].contains(name.lowercased()) {
                    guard let launch = app.launchDate else { return false }
                    return origin?.matches(.init(processID: app.processIdentifier,
                                                 launchTime: launch.timeIntervalSinceReferenceDate,
                                                 bundleIdentifier: app.bundleIdentifier)) == true
                }
                return [app.localizedName, app.bundleIdentifier, app.bundleURL?.deletingPathExtension().lastPathComponent]
                    .compactMap { $0 }.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
            guard matches.count == 1, let app = matches.first else {
                onStatus?("Name one running app, or say “until this app quits” with it in front.")
                return false
            }
            let label = app.localizedName ?? name
            return start("Keeping the screen awake until \(label) quits.") { wait in
                while !app.isTerminated { try await wait(.seconds(2)) }
                return "Keep awake ended when \(label) quit."
            }
        case .download(let filename):
            do {
                let directory = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                var download = try DownloadCompletion(directory: directory, filename: filename)
                let label = download.filename
                return start("Keeping the screen awake until \(label) appears and settles in Downloads.") { wait in
                    while true {
                        try await wait(.seconds(2))
                        if try download.finished() { return "Keep awake ended after \(label) settled in Downloads." }
                    }
                }
            } catch DownloadCompletion.SetupFailure.alreadyExists {
                onStatus?("That file is already in Downloads. Name the new download’s filename.")
            } catch is DownloadCompletion.SetupFailure {
                onStatus?("Name the final filename in Downloads, or start one identifiable download first.")
            } catch {
                onStatus?("Wesley Flow could not read the Downloads folder.")
            }
            return false
        case .unsupported:
            onStatus?("Say how long, name a running app and say “quits”, or name a file and say “is downloaded”.")
            return false
        }
    }

    func stop(message: String? = nil) {
        authenticationID = nil
        authenticationTask?.cancel()
        authenticationTask = nil
        if isCurtainVisible { curtain.setUnlocking(false) }
        clearAssertion()
        if let message { onStatus?(message) }
    }

    private func clearAssertion() {
        sessionID = nil
        task?.cancel()
        task = nil
        if let assertion { release(assertion) }
        assertion = nil
    }

    private func start(_ message: String, watch: (@MainActor (Wait) async throws -> String)? = nil) -> Bool {
        guard let id = acquire() else {
            onStatus?("macOS could not start keep awake.")
            return false
        }
        clearAssertion()
        assertion = id
        let session = UUID()
        sessionID = session
        onStatus?(message)
        if let watch {
            task = Task { [weak self, wait] in
                let status: String
                do { status = try await watch(wait) }
                catch { status = "Keep awake ended because the condition could no longer be checked." }
                guard !Task.isCancelled, let self, self.sessionID == session else { return }
                self.clearAssertion()
                self.onStatus?(status)
            }
        }
        return true
    }

    private func startTimer(_ seconds: Int) -> Bool {
        start("Keeping the screen awake for \(Duration.seconds(seconds).formatted()).") { wait in
            try await wait(.seconds(seconds))
            return "Keep awake ended when the timer finished."
        }
    }

    private func requestCurtain(duration: Int?) -> Bool {
        guard !isCurtainVisible else { return true }
        guard !isUpdatingCurtain else { return true }
        onStatus?("Confirm with Touch ID to cover the screen.")
        authorize("Confirm showing the privacy curtain.") { [weak self] approved in
            guard let self else { return }
            guard approved else {
                self.onStatus?("Touch ID did not confirm the privacy curtain.")
                return
            }
            self.curtain.setUpdatingSettings(true)
            guard self.curtain.show(onUnlock: { [weak self] in self?.unlockCurtain() }) else {
                self.curtain.setUpdatingSettings(false)
                self.onStatus?("The privacy curtain could not cover the displays.")
                return
            }
            self.isCurtainVisible = true
            do {
                try await self.swipeSetting?.suspend()
            } catch {
                await self.finishCurtainSetupFailure("Wesley Flow could not verify that Swipe between spaces is off.")
                return
            }
            let awake: Bool
            if let duration { awake = self.startTimer(duration) }
            else if self.isActive { awake = true }
            else { awake = self.start("Keeping the screen awake until you say “turn it off”.") }
            if awake {
                self.curtain.setUpdatingSettings(false)
                self.onStatus?("Privacy curtain is on. Touch ID reveals the desktop.")
            } else {
                await self.finishCurtainSetupFailure("The privacy curtain could not start because keep awake was unavailable.")
            }
        }
        return true
    }

    private func finishCurtainSetupFailure(_ message: String) async {
        let status: String
        do {
            try await swipeSetting?.restore()
            status = message
        } catch {
            status = message + " The original Trackpad choice is saved for recovery on next launch."
        }
        curtain.hide()
        isCurtainVisible = false
        onStatus?(status)
    }

    func recoverCurtainSwipe() async {
        guard swipeSetting?.hasPendingRestore == true, !isUpdatingCurtain, !isCurtainVisible else { return }
        isRecoveringSwipe = true
        defer { isRecoveringSwipe = false }
        do {
            try await swipeSetting?.restore()
            onStatus?("Recovered the Trackpad setting from the previous curtain session.")
        } catch {
            onStatus?("Trackpad restore is pending. Check Accessibility access and relaunch Wesley Flow.")
        }
    }

    private func unlockCurtain() {
        guard isCurtainVisible, !isUpdatingCurtain else { return }
        curtain.setUnlocking(true)
        authorize("Use Touch ID to reveal your desktop.") { [weak self] approved in
            guard let self else { return }
            guard approved else {
                self.curtain.setUnlocking(false)
                self.curtain.showUnlockFailure()
                return
            }
            self.curtain.setUpdatingSettings(true)
            var restored = true
            do { try await self.swipeSetting?.restore() }
            catch { restored = false }
            self.curtain.hide()
            self.isCurtainVisible = false
            if restored {
                self.onStatus?(self.isActive ? "Privacy curtain removed. Keep awake is still active." : "Privacy curtain removed.")
            } else {
                self.onStatus?("Privacy curtain removed. Trackpad restore is pending and will retry on next launch.")
            }
        }
    }

    private func authorize(_ reason: String, completion: @escaping (Bool) async -> Void) {
        let id = UUID()
        authenticationID = id
        authenticationTask = Task { [weak self, authenticate] in
            let approved = (try? await authenticate(reason)) == true
            guard !Task.isCancelled, let self, self.authenticationID == id else { return }
            defer {
                if self.authenticationID == id {
                    self.authenticationID = nil
                    self.authenticationTask = nil
                }
            }
            await completion(approved)
        }
    }

    private static func confirmWithTouchID(_ reason: String) async throws -> Bool {
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        context.localizedFallbackTitle = ""
        guard context.canEvaluatePolicy(policy, error: nil), context.biometryType == .touchID else { return false }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await context.evaluatePolicy(policy, localizedReason: reason)
        } onCancel: {
            context.invalidate()
        }
    }

    private nonisolated static func acquireDisplay() -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Wesley Flow voice keep awake" as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }
}


@MainActor protocol ScreenCurtain: AnyObject {
    func show(onUnlock: @escaping () -> Void) -> Bool
    func setUnlocking(_ unlocking: Bool)
    func setUpdatingSettings(_ updating: Bool)
    func showUnlockFailure()
    func hide()
}

@MainActor final class FrostedScreenCurtain: NSObject, ScreenCurtain {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private struct Cover {
        let window: NSPanel
        let button: NSButton
        let status: NSTextField
    }

    private var covers: [Cover] = []
    private var unlock: (() -> Void)?
    private var screenChanges: (any NSObjectProtocol)?
    private var spaceChanges: (any NSObjectProtocol)?
    private var inputMonitor: Any?
    private var unlocking = false
    private var updatingSettings = false

    func show(onUnlock: @escaping () -> Void) -> Bool {
        guard !NSScreen.screens.isEmpty else { return false }
        unlock = onUnlock
        screenChanges = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.coverDisplays() }
        }
        spaceChanges = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.raiseCovers() }
        }
        // A local monitor consumes input delivered to Wesley Flow. System gestures
        // and events delivered to other apps remain under macOS control.
        let blockedInput: NSEvent.EventTypeMask = [.keyDown, .keyUp, .scrollWheel, .gesture, .swipe, .magnify, .rotate, .smartMagnify]
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: blockedInput) { [weak self] event in
            guard let self, self.unlock != nil else { return event }
            if event.type == .keyDown, !event.isARepeat, [36, 49, 76].contains(event.keyCode) { self.requestUnlock() }
            return nil
        }
        coverDisplays()
        return true
    }

    func setUnlocking(_ unlocking: Bool) {
        self.unlocking = unlocking
        updateControls()
    }

    func setUpdatingSettings(_ updating: Bool) {
        updatingSettings = updating
        updateControls()
        raiseCovers()
    }

    private func updateControls() {
        for cover in covers {
            cover.window.level = updatingSettings ? .screenSaver : .statusBar
            cover.button.isEnabled = !unlocking && !updatingSettings
            cover.status.stringValue = progressMessage
        }
    }

    private var progressMessage: String {
        if updatingSettings { return "Updating Trackpad settings…" }
        return unlocking ? "Waiting for Touch ID…" : ""
    }

    func showUnlockFailure() {
        for cover in covers {
            cover.status.stringValue = "Touch ID did not confirm. Try again."
        }
    }

    func hide() {
        unlock = nil
        if let screenChanges { NotificationCenter.default.removeObserver(screenChanges) }
        if let spaceChanges { NSWorkspace.shared.notificationCenter.removeObserver(spaceChanges) }
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        screenChanges = nil
        spaceChanges = nil
        inputMonitor = nil
        unlocking = false
        updatingSettings = false
        for cover in covers { cover.window.orderOut(nil) }
        covers.removeAll()
    }

    @objc private func requestUnlock() {
        guard !unlocking, !updatingSettings else { return }
        unlock?()
    }

    private func coverDisplays() {
        guard unlock != nil, !NSScreen.screens.isEmpty else { return }
        let previous = covers
        covers = NSScreen.screens.map { makeCover(on: $0) }
        raiseCovers()
        for cover in previous { cover.window.orderOut(nil) }
    }

    private func raiseCovers() {
        for cover in covers { cover.window.orderFrontRegardless() }
        // Keep the system's Touch ID prompt in focus if a Space changes during authentication.
        guard !unlocking, !updatingSettings else { return }
        let pointer = NSEvent.mouseLocation
        (covers.first { $0.window.frame.contains(pointer) } ?? covers.first)?.window.makeKey()
    }

    static func makePanel(frame: NSRect) -> NSPanel {
        let panel = Panel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.setFrame(frame, display: false)
        panel.level = .statusBar
        // Other apps' full-screen Spaces need explicit cross-application participation.
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.hasShadow = false
        panel.isOpaque = true
        panel.backgroundColor = NSColor(srgbRed: 0.16, green: 0.22, blue: 0.30, alpha: 1)
        return panel
    }

    private func makeCover(on screen: NSScreen) -> Cover {
        let panel = Self.makePanel(frame: screen.frame)
        if updatingSettings { panel.level = .screenSaver }
        // A frosted appearance over opaque pixels keeps the desktop text unreadable.
        let background = NSView()
        background.wantsLayer = true
        let glass = CAGradientLayer()
        glass.colors = [
            NSColor(srgbRed: 0.32, green: 0.41, blue: 0.52, alpha: 1).cgColor,
            NSColor(srgbRed: 0.14, green: 0.19, blue: 0.27, alpha: 1).cgColor
        ]
        glass.startPoint = CGPoint(x: 0, y: 1)
        glass.endPoint = CGPoint(x: 1, y: 0)
        background.layer = glass

        let title = NSTextField(labelWithString: "Privacy curtain")
        title.font = .systemFont(ofSize: 32, weight: .semibold)
        title.textColor = .white
        let button = NSButton(title: "Reveal with Touch ID", target: self, action: #selector(requestUnlock))
        button.bezelStyle = .rounded
        button.isEnabled = !unlocking && !updatingSettings
        let status = NSTextField(labelWithString: progressMessage)
        status.textColor = .white
        let stack = NSStackView(views: [title, button, status])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])
        panel.contentView = background
        return Cover(window: panel, button: button, status: status)
    }
}
