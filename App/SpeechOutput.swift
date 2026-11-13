import AVFoundation
import Combine
import CryptoKit
import Domain
import Foundation
import NaturalLanguage
import PhononTTS

@MainActor protocol TTSEngine {
    /// Returns after audio has played. didStart marks the point after which replay would repeat audio.
    func speak(_ text: String, voice: String, didStart: @escaping @MainActor () -> Void) async throws
    func stop()
}

enum SpeechOutputError: LocalizedError {
    case networkBlocked, download, verification, installation, model, voice, audio, noAudio

    var errorDescription: String? {
        switch self {
        case .networkBlocked: "Allow app network requests in Privacy to download Phonon."
        case .download: "Couldn’t download Phonon. Check your connection and try again."
        case .verification: "The Phonon download failed verification. Try downloading it again."
        case .installation: "Couldn’t install Phonon. Check available disk space and try again."
        case .model: "Couldn’t load the Phonon model. Try downloading it again in Speech Output."
        case .voice: "The selected voice couldn’t be loaded. Choose another voice and try again."
        case .audio: "Couldn’t play speech. Check your Mac’s audio output."
        case .noAudio: "The speech engine produced no audio."
        }
    }
}

struct PhononModelStore: Sendable {
    private static let release = "0.7.0"
    private static let archiveURL = URL(string: "https://github.com/gradium-ai/xn-ptts/releases/download/v\(release)/phonon-31m-en-coreml.zip")!
    private static let archiveSHA = "058cde756a5e67bcdb986e7c45fe431d41a1a9073e68aabae314c80631a34b76"
    private static let manifestSHA = "8c4cc8ba9619695ef231c7770938286073d3e6ea04863d4efe821c36bd9e4007"
    private static let archiveSize = 137_300_950
    let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "WesleyFlow/SpeechOutput/Phonon-\(Self.release)")) {
        self.directory = directory
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: "bundle.json").path)
    }

    func install(policy: ApplicationNetworkPolicy) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = try policy.begin(Self.archiveURL) { session.invalidateAndCancel() }
        defer { policy.finish(request) }

        let archive: URL
        do {
            let (url, response) = try await session.download(from: Self.archiveURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https" else {
                try? FileManager.default.removeItem(at: url)
                throw SpeechOutputError.download
            }
            archive = url
        } catch {
            try Task.checkCancellation()
            if policy.snapshot().blocked { throw SpeechOutputError.networkBlocked }
            throw SpeechOutputError.download
        }
        defer { try? FileManager.default.removeItem(at: archive) }
        try Task.checkCancellation()

        let work = Task.detached(priority: .utility) {
            do { try stageArchive(archive, policy: policy) }
            catch is CancellationError { throw CancellationError() }
            catch let error as SpeechOutputError { throw error }
            catch { throw SpeechOutputError.installation }
        }
        try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func stageArchive(_ archive: URL, policy: ApplicationNetworkPolicy) throws {
        let fm = FileManager.default
        guard try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize == Self.archiveSize,
              try Self.sha256(of: archive) == Self.archiveSHA else {
            throw SpeechOutputError.verification
        }
        try Task.checkCancellation()
        let parent = directory.deletingLastPathComponent()
        let staging = parent.appending(path: ".install-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        // Only extract the byte-for-byte verified Gradium release with the system ZIP tool.
        let extract = Process()
        extract.executableURL = URL(filePath: "/usr/bin/ditto")
        extract.arguments = ["-x", "-k", archive.path, staging.path]
        extract.standardOutput = FileHandle.nullDevice
        extract.standardError = FileHandle.nullDevice
        try extract.run()
        extract.waitUntilExit()
        guard extract.terminationStatus == 0 else { throw SpeechOutputError.installation }
        var model = staging.appending(path: "phonon-31m-en")
        try Self.validate(model)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? model.setResourceValues(values)
        try Task.checkCancellation()
        guard !policy.snapshot().blocked else { throw SpeechOutputError.networkBlocked }
        if fm.fileExists(atPath: directory.path) {
            _ = try fm.replaceItemAt(directory, withItemAt: model)
        } else {
            try fm.moveItem(at: model, to: directory)
        }
    }

    func validateInstalled() async throws {
        let work = Task.detached(priority: .utility) { try Self.validate(directory) }
        try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private struct Manifest: Decodable {
        struct Entry: Decodable {
            let path: String
            let size: Int
            let sha256: String
        }
        let files: [Entry]
    }

    private static func validate(_ directory: URL) throws {
        let url = directory.appending(path: "bundle.json")
        guard let manifestSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              manifestSize < 128_000,
              try sha256(of: url) == manifestSHA else { throw SpeechOutputError.verification }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        for entry in manifest.files {
            let file = directory.appending(path: entry.path)
            guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == entry.size,
                  try sha256(of: file) == entry.sha256 else { throw SpeechOutputError.verification }
        }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor final class PhononTTSEngine: TTSEngine {
    private let store: PhononModelStore
    private var model: Phonon?
    private var player: SpeechPCMPlayer?
    private var expiry: Task<Void, Never>?

    init(store: PhononModelStore) { self.store = store }

    func speak(_ text: String, voice: String, didStart: @escaping @MainActor () -> Void) async throws {
        expiry?.cancel()
        defer { if model != nil { scheduleUnload() } }
        let loaded = try await loadModel()
        try Task.checkCancellation()
        if loaded.voice != voice {
            do { try await loaded.setVoice(voice) }
            catch { throw SpeechOutputError.voice }
        }
        try Task.checkCancellation()
        let player = try SpeechPCMPlayer()
        self.player = player
        defer {
            player.stop()
            self.player = nil
        }
        // Limit the upstream stream's backlog to a short passage, even when synthesis outruns playback.
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var spoke = false
        for sentence in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
            var remainder = text[sentence]
            while !remainder.isEmpty {
                let prefix = remainder.prefix(240)
                let count = prefix.count < remainder.count
                    ? (prefix.lastIndex(where: \.isWhitespace).map { prefix.distance(from: prefix.startIndex, to: $0) + 1 } ?? prefix.count)
                    : prefix.count
                let passage = String(remainder.prefix(count)).trimmingCharacters(in: .whitespacesAndNewlines)
                remainder = remainder.dropFirst(count)
                guard !passage.isEmpty else { continue }
                try Task.checkCancellation()
                let (stream, continuation) = AsyncThrowingStream<[Float], any Error>.makeStream()
                let producer = Task {
                    do {
                        try await loaded.speak(passage) { continuation.yield($0) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                do {
                    for try await chunk in stream {
                        try await player.enqueue(chunk)
                        if !spoke {
                            spoke = true
                            didStart()
                        }
                    }
                    try Task.checkCancellation()
                    try await player.waitUntilDrained()
                } catch {
                    producer.cancel()
                    await producer.value
                    throw error
                }
            }
        }
        guard spoke else { throw SpeechOutputError.noAudio }
    }

    private func loadModel() async throws -> Phonon {
        if let model { return model }
        do {
            try await store.validateInstalled()
            try Task.checkCancellation()
            let loaded = try await Phonon.load(models: store.directory, language: .english)
            try Task.checkCancellation()
            model = loaded
            return loaded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechOutputError.model
        }
    }

    func stop() { player?.stop() }

    func unload() {
        expiry?.cancel()
        expiry = nil
        model = nil
    }

    private func scheduleUnload() {
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) }
            catch { return }
            self?.model = nil
            self?.expiry = nil
        }
    }
}

@MainActor private final class SpeechPCMPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var pending = 0
    private var stopped = false
    private var outputFailed = false
    private var waiter: CheckedContinuation<Void, Never>?

    init() throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Phonon.sampleRate, channels: 1) else {
            throw SpeechOutputError.audio
        }
        self.format = format
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do { try engine.start() }
        catch { throw SpeechOutputError.audio }
    }

    func enqueue(_ samples: [Float]) async throws {
        guard !samples.isEmpty else { throw SpeechOutputError.noAudio }
        while pending >= 8, !stopped { await waitForBuffer() }
        try Task.checkCancellation()
        if outputFailed { throw SpeechOutputError.audio }
        guard !stopped else { throw CancellationError() }
        guard engine.isRunning,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw SpeechOutputError.audio }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        pending += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.bufferPlayed() }
        }
        if !node.isPlaying { node.play() }
    }

    func waitUntilDrained() async throws {
        while pending > 0, !stopped { await waitForBuffer() }
        try Task.checkCancellation()
        if outputFailed { throw SpeechOutputError.audio }
        guard !stopped else { throw CancellationError() }
        guard engine.isRunning else { throw SpeechOutputError.audio }
    }

    private func waitForBuffer() async {
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            self?.outputFailed = true
            self?.stop()
        }
        defer { timeout.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    private func bufferPlayed() {
        guard !stopped else { return }
        pending -= 1
        waiter?.resume()
        waiter = nil
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        node.stop()
        engine.stop()
        waiter?.resume()
        waiter = nil
    }
}

@MainActor final class AppleTTSEngine: NSObject, TTSEngine, AVSpeechSynthesizerDelegate {
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    private var active: ObjectIdentifier?
    private var completion: CheckedContinuation<Void, any Error>?

    func speak(_ text: String, voice: String, didStart: @escaping @MainActor () -> Void) async throws {
        try Task.checkCancellation()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voice)
        active = ObjectIdentifier(utterance)
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) }
            catch { return }
            guard let self, let id = self.active else { return }
            self.finish(id, error: .audio)
            self.synthesizer.stopSpeaking(at: .immediate)
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            synthesizer.speak(utterance)
            didStart()
        }
    }

    func stop() {
        guard active != nil else { return }
        active = nil
        synthesizer.stopSpeaking(at: .immediate)
        completion?.resume(throwing: CancellationError())
        completion = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in finish(id, error: nil) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in finish(id, error: SpeechOutputError.audio) }
    }

    private func finish(_ id: ObjectIdentifier, error: SpeechOutputError?) {
        guard active == id else { return }
        active = nil
        if let error { completion?.resume(throwing: error) }
        else { completion?.resume() }
        completion = nil
    }
}

@MainActor final class SpeechOutput: ObservableObject {
    // A small set of named choices from the pinned English release, including its default.
    static let voices = ["default", "Harper", "Easton", "Maeve", "Edwin"]
    static let sample = "Hello. I’m ready when you are."

    @Published private(set) var isInstalled: Bool
    @Published private(set) var isInstalling = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var status = ""
    private let store: PhononModelStore
    private let phonon: any TTSEngine
    private let apple: any TTSEngine
    private let adapter: PhononTTSEngine
    private var speech: Task<Void, Never>?
    private var installation: Task<Void, Never>?
    private var ticket = UUID()

    init(store: PhononModelStore = .init(), phonon: (any TTSEngine)? = nil, apple: (any TTSEngine)? = nil) {
        self.store = store
        isInstalled = store.isInstalled
        let adapter = PhononTTSEngine(store: store)
        self.phonon = phonon ?? adapter
        self.apple = apple ?? AppleTTSEngine()
        self.adapter = adapter
    }

    func speak(_ value: String, voice: String) {
        let text = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
            .replacingOccurrences(of: "\0", with: "")
        guard !text.isEmpty else { return }
        let previous = speech
        stop()
        let id = ticket
        let selected = Self.voices.contains(voice) ? voice : "default"
        status = ""
        isSpeaking = true
        speech = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                if self.ticket == id {
                    self.isSpeaking = false
                    self.speech = nil
                }
            }
            guard self.ticket == id, !Task.isCancelled else { return }
            var started = false
            do {
                if self.isInstalled && !self.isInstalling {
                    do {
                        try await self.phonon.speak(text, voice: selected) { started = true }
                        return
                    } catch {
                        try Task.checkCancellation()
                        guard self.ticket == id else { return }
                        let reason = (error as? SpeechOutputError)?.errorDescription ?? "Phonon speech failed."
                        self.status = reason
                        if started { return }
                        self.status += " Using the macOS voice."
                    }
                } else {
                    self.status = "Using the macOS voice. Download Phonon for the selected voice."
                }
                try await self.apple.speak(text, voice: "en-US") {}
            } catch {
                guard !Task.isCancelled, self.ticket == id else { return }
                self.status = SpeechOutputError.audio.errorDescription!
            }
        }
    }

    func install(policy: ApplicationNetworkPolicy) {
        guard !isInstalling else { return }
        let previous = speech
        stop()
        isInstalling = true
        status = "Downloading and verifying Phonon…"
        installation = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                self.isInstalling = false
                self.installation = nil
            }
            do {
                try Task.checkCancellation()
                self.adapter.unload()
                try await self.store.install(policy: policy)
                self.isInstalled = self.store.isInstalled
                try Task.checkCancellation()
                self.status = "Phonon is ready to preview."
            } catch {
                self.isInstalled = self.store.isInstalled
                self.status = switch error {
                case is CancellationError: "Phonon setup stopped."
                case is ApplicationNetworkDenied: "Allow app network requests in Privacy to download Phonon."
                case let failure as SpeechOutputError: failure.errorDescription ?? "Phonon setup failed."
                default: "Phonon setup failed. Check available disk space and try again."
                }
            }
        }
    }

    func waitForSpeech() async { await speech?.value }

    func stopInstallation() { installation?.cancel() }

    func stop() {
        ticket = UUID()
        speech?.cancel()
        if isSpeaking {
            phonon.stop()
            apple.stop()
        }
        isSpeaking = false
    }

    func releaseModel() {
        stop()
        adapter.unload()
    }
}
