import Domain
import Foundation
import Speech
import AVFoundation

public enum ModernSpeechEngine: String, Sendable, Equatable, CaseIterable {
    case speechTranscriber, dictationTranscriber
    public var label: String { self == .speechTranscriber ? "Apple SpeechTranscriber (modern)" : "Apple DictationTranscriber (modern)" }
}
public enum SpeechAssetState: String, Sendable, Equatable {
    case deviceUnavailable, unsupported, missing, downloading, installed, unconfirmed
    public var label: String {
        switch self {
        case .deviceUnavailable: "Unavailable on this device"
        case .unsupported: "Selected language unsupported"
        case .missing: "Supported — resources not installed"
        case .downloading: "macOS reports downloading"
        case .installed: "Installed (inventory and locale list verified)"
        case .unconfirmed: "Inventory installed; locale list not confirmed — inspect again"
        }
    }
}
public struct SpeechEngineResources: Sendable, Equatable {
    public let engine: ModernSpeechEngine
    public let deviceAvailable: Bool
    public let resolvedLocale: String?
    public let supportedLocales: [String]
    public let installedLocales: [String]
    public let inventoryStatus: String
    public let state: SpeechAssetState
    public var canInstall: Bool { state == .missing || state == .downloading }
    public init(engine: ModernSpeechEngine, deviceAvailable: Bool, resolvedLocale: String?, supportedLocales: [String], installedLocales: [String], inventoryStatus: String) {
        self.engine = engine; self.deviceAvailable = deviceAvailable; self.resolvedLocale = resolvedLocale
        self.supportedLocales = supportedLocales; self.installedLocales = installedLocales; self.inventoryStatus = inventoryStatus
        let supported = resolvedLocale.map { locale in supportedLocales.contains { Self.sameLocale($0,locale) } } ?? false
        let installed = resolvedLocale.map { locale in installedLocales.contains { Self.sameLocale($0,locale) } } ?? false
        if !deviceAvailable { state = .deviceUnavailable }
        else if !supported || inventoryStatus == "unsupported" { state = .unsupported }
        else if inventoryStatus == "installed" { state = installed ? .installed : .unconfirmed }
        else if inventoryStatus == "downloading" { state = .downloading }
        else if inventoryStatus == "supported" { state = .missing }
        else { state = .unconfirmed }
    }
    public static func sameLocale(_ a: String, _ b: String) -> Bool {
        Locale(identifier:a).identifier(.bcp47).lowercased() == Locale(identifier:b).identifier(.bcp47).lowercased()
    }
    public var summary: String {
        let localePresent = resolvedLocale.map { locale in installedLocales.contains { Self.sameLocale($0,locale) } } ?? false
        let label = state == .missing && localePresent ? "Locale present; required module resources not ready" : state.label
        return label + " · inventory " + inventoryStatus + (resolvedLocale.map { " · Apple locale " + $0 } ?? "")
    }
}
public struct AppleSpeechConfiguration: Sendable, Equatable {
    public let locale: String
    public let speech: SpeechEngineResources
    public let dictation: SpeechEngineResources
    public let legacyOnDeviceAvailable: Bool
    public let microphone: String
    public let speechPermission: String
    public let reservedLocales: [String]
    public var speechAssets: String { speech.summary }
    public var dictationAssets: String { dictation.summary }
    public var readyModernEngine: ModernSpeechEngine? {
        if speech.state == .installed { return .speechTranscriber }
        if dictation.state == .installed { return .dictationTranscriber }
        return nil
    }
    public var installCandidate: ModernSpeechEngine? {
        if speech.canInstall { return .speechTranscriber }
        if dictation.canInstall { return .dictationTranscriber }
        return nil
    }
    public var recommendedEngineLabel: String {
        readyModernEngine?.label ?? (legacyOnDeviceAvailable ? "Legacy Apple Speech compatibility — about one-minute provider limit" : "No on-device speech engine ready")
    }
    public func resources(for engine: ModernSpeechEngine) -> SpeechEngineResources { engine == .speechTranscriber ? speech : dictation }
    public init(locale: String, speech: SpeechEngineResources, dictation: SpeechEngineResources, legacyOnDeviceAvailable: Bool, microphone: String, speechPermission: String, reservedLocales: [String] = []) {
        self.locale = locale; self.speech = speech; self.dictation = dictation; self.legacyOnDeviceAvailable = legacyOnDeviceAvailable
        self.microphone = microphone; self.speechPermission = speechPermission; self.reservedLocales = reservedLocales
    }
    public static func permissionSummary() -> (microphone:String,speech:String) {
        let mic: String
        switch AVCaptureDevice.authorizationStatus(for:.audio) {
        case .authorized: mic = "Allowed"
        case .denied,.restricted: mic = "Denied"
        default: mic = "Not requested"
        }
        let speech: String
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = "Allowed"
        case .denied,.restricted: speech = "Denied"
        default: speech = "Not requested"
        }
        return (mic,speech)
    }
    /// Read-only: never requests installation, reserves a locale or prepares a model.
    @MainActor public static func inspect(localeIdentifier: String) async -> AppleSpeechConfiguration {
        let locale = Locale(identifier:localeIdentifier)
        guard #available(macOS 26.0, *) else {
            let legacy = SFSpeechRecognizer(locale: locale)
            let permissions = permissionSummary()
            func unavailable(_ engine: ModernSpeechEngine) -> SpeechEngineResources {
                .init(engine: engine, deviceAvailable: false, resolvedLocale: nil,
                      supportedLocales: [], installedLocales: [], inventoryStatus: "requiresMacOS26")
            }
            return .init(locale: localeIdentifier, speech: unavailable(.speechTranscriber),
                         dictation: unavailable(.dictationTranscriber),
                         legacyOnDeviceAvailable: legacy?.isAvailable == true && legacy?.supportsOnDeviceRecognition == true,
                         microphone: permissions.microphone, speechPermission: permissions.speech)
        }
        let speechSupported = await SpeechTranscriber.supportedLocales
        let speechInstalled = await SpeechTranscriber.installedLocales
        let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo:locale)
        let speechAvailable = SpeechTranscriber.isAvailable
        var speechStatus = "unsupported"
        if speechAvailable, let selected = speechLocale {
            speechStatus = statusName(await AssetInventory.status(forModules:[AppleSpeechModules.speech(selected)]))
        }
        let dictationSupported = await DictationTranscriber.supportedLocales
        let dictationInstalled = await DictationTranscriber.installedLocales
        let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo:locale)
        var dictationStatus = "unsupported"
        if let selected = dictationLocale {
            dictationStatus = statusName(await AssetInventory.status(forModules:[AppleSpeechModules.dictation(selected)]))
        }
        let legacy = SFSpeechRecognizer(locale:locale), permissions = permissionSummary()
        let reservations = await AssetInventory.reservedLocales
        return .init(locale:localeIdentifier,
                     speech:.init(engine:.speechTranscriber,deviceAvailable:speechAvailable,resolvedLocale:speechLocale?.identifier,supportedLocales:speechSupported.map(\.identifier).sorted(),installedLocales:speechInstalled.map(\.identifier).sorted(),inventoryStatus:speechStatus),
                     dictation:.init(engine:.dictationTranscriber,deviceAvailable:true,resolvedLocale:dictationLocale?.identifier,supportedLocales:dictationSupported.map(\.identifier).sorted(),installedLocales:dictationInstalled.map(\.identifier).sorted(),inventoryStatus:dictationStatus),
                     legacyOnDeviceAvailable:legacy?.isAvailable == true && legacy?.supportsOnDeviceRecognition == true,
                     microphone:permissions.microphone,speechPermission:permissions.speech,reservedLocales:reservations.map(\.identifier).sorted())
    }
    @available(macOS 26.0, *)
    private static func statusName(_ value: AssetInventory.Status) -> String {
        switch value {
        case .unsupported: "unsupported"
        case .supported: "supported"
        case .downloading: "downloading"
        case .installed: "installed"
        @unknown default: "unknown"
        }
    }
}

/// Inspection, installation, preparation and capture must describe the same modules.
@available(macOS 26.0, *)
@MainActor enum AppleSpeechModules {
    static func speech(_ locale: Locale) -> SpeechTranscriber { SpeechTranscriber(locale:locale,preset:.timeIndexedProgressiveTranscription) }
    static func dictation(_ locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale:locale,contentHints:[],transcriptionOptions:[.punctuation],reportingOptions:[.volatileResults,.frequentFinalization],attributeOptions:[.audioTimeRange])
    }
    static func canonicalLocale(_ engine: ModernSpeechEngine, locale: String) async throws -> Locale {
        let requested = Locale(identifier:locale)
        let selected: Locale?
        switch engine {
        case .speechTranscriber: selected = await SpeechTranscriber.supportedLocale(equivalentTo:requested)
        case .dictationTranscriber: selected = await DictationTranscriber.supportedLocale(equivalentTo:requested)
        }
        guard let selected, SpeechEngineResources.sameLocale(selected.identifier,locale) else { throw SpeechResourceFailure.unsupported }
        return selected
    }
    static func modules(_ engine: ModernSpeechEngine, locale: String) async throws -> [any SpeechModule] {
        let selected = try await canonicalLocale(engine,locale:locale)
        return engine == .speechTranscriber ? [speech(selected)] : [dictation(selected)]
    }
}
public struct SpeechDownloadProgress: Sendable, Equatable {
    public let completedUnits: Int64
    public let totalUnits: Int64
    public init(completedUnits: Int64, totalUnits: Int64) { self.completedUnits = max(0,completedUnits); self.totalUnits = max(0,totalUnits) }
    public var fraction: Double? { totalUnits > 0 ? min(1,Double(completedUnits)/Double(totalUnits)) : nil }
}
public struct SpeechEnginePreparation: Sendable, Equatable {
    public let engine: ModernSpeechEngine
    public let requestedLocale: String
    public let resolvedLocale: String
    public let sampleRate: Double
    public let channels: UInt32
    public init(engine: ModernSpeechEngine, requestedLocale: String, resolvedLocale: String, sampleRate: Double, channels: UInt32) {
        self.engine = engine; self.requestedLocale = requestedLocale; self.resolvedLocale = resolvedLocale; self.sampleRate = sampleRate; self.channels = channels
    }
}
public enum SpeechResourceFailure: Error, Equatable, Sendable { case busy, unsupported, notInstalled, installationIncomplete, preparationMismatch }
@MainActor public protocol SpeechResourceInstallation: AnyObject {
    var progress: SpeechDownloadProgress { get }
    func downloadAndInstall() async throws
}
@MainActor public protocol SpeechResourceBackend: AnyObject {
    func inspect(localeIdentifier: String) async -> AppleSpeechConfiguration
    func installation(engine: ModernSpeechEngine, locale: String) async throws -> (any SpeechResourceInstallation)?
    func prepare(engine: ModernSpeechEngine, requestedLocale: String, resolvedLocale: String) async throws -> SpeechEnginePreparation
}
@MainActor public final class AppleSpeechResourceService {
    private let backend: any SpeechResourceBackend
    private var active = false
    public init(backend: any SpeechResourceBackend = NativeSpeechResourceBackend()) { self.backend = backend }
    public func inspect(localeIdentifier: String) async -> AppleSpeechConfiguration { await backend.inspect(localeIdentifier:localeIdentifier) }
    /// Only the explicit Settings action calls this method. Nil requests are not proof of success.
    public func install(localeIdentifier: String, engine: ModernSpeechEngine, progress: @escaping @MainActor @Sendable (SpeechDownloadProgress) -> Void) async throws -> AppleSpeechConfiguration {
        guard !active else { throw SpeechResourceFailure.busy }; active = true; defer { active = false }
        let before = await backend.inspect(localeIdentifier:localeIdentifier); try Task.checkCancellation()
        let resource = before.resources(for:engine)
        guard before.locale == localeIdentifier, let resolved = resource.resolvedLocale else { throw SpeechResourceFailure.unsupported }
        if resource.state == .installed { return before }
        guard resource.canInstall else { throw SpeechResourceFailure.unsupported }
        let request = try await backend.installation(engine:engine,locale:resolved); try Task.checkCancellation()
        if let request {
            progress(request.progress)
            let monitor = Task { @MainActor in
                while !Task.isCancelled {
                    progress(request.progress)
                    do { try await Task.sleep(for:.milliseconds(250)) } catch { return }
                }
            }
            defer { monitor.cancel() }
            try await request.downloadAndInstall(); try Task.checkCancellation()
            progress(request.progress)
        }
        let after = await backend.inspect(localeIdentifier:localeIdentifier); try Task.checkCancellation()
        guard after.locale == localeIdentifier, after.resources(for:engine).state == .installed,
              after.resources(for:engine).resolvedLocale.map({ SpeechEngineResources.sameLocale($0,resolved) }) == true else { throw SpeechResourceFailure.installationIncomplete }
        return after
    }
    /// Physically calls SpeechAnalyzer.prepareToAnalyze, without starting the microphone.
    public func prepare(localeIdentifier: String, engine: ModernSpeechEngine) async throws -> SpeechEnginePreparation {
        guard !active else { throw SpeechResourceFailure.busy }; active = true; defer { active = false }
        let before = await backend.inspect(localeIdentifier:localeIdentifier); try Task.checkCancellation()
        let resource = before.resources(for:engine)
        guard before.locale == localeIdentifier, resource.state == .installed, let resolved = resource.resolvedLocale else { throw SpeechResourceFailure.notInstalled }
        let result = try await backend.prepare(engine:engine,requestedLocale:localeIdentifier,resolvedLocale:resolved); try Task.checkCancellation()
        let after = await backend.inspect(localeIdentifier:localeIdentifier); try Task.checkCancellation()
        guard result.engine == engine, result.requestedLocale == localeIdentifier, SpeechEngineResources.sameLocale(result.resolvedLocale,resolved),
              result.sampleRate.isFinite, (8000...192000).contains(result.sampleRate), result.channels == 1,
              after.locale == localeIdentifier, after.resources(for:engine).state == .installed,
              after.resources(for:engine).resolvedLocale.map({ SpeechEngineResources.sameLocale($0,resolved) }) == true else { throw SpeechResourceFailure.preparationMismatch }
        return result
    }
}
@MainActor public final class NativeSpeechResourceBackend: SpeechResourceBackend {
    public init() {}
    public func inspect(localeIdentifier: String) async -> AppleSpeechConfiguration { await AppleSpeechConfiguration.inspect(localeIdentifier:localeIdentifier) }
    public func installation(engine: ModernSpeechEngine, locale: String) async throws -> (any SpeechResourceInstallation)? {
        guard #available(macOS 26.0, *) else { throw SpeechResourceFailure.unsupported }
        // This call may reserve the requested locale. It is never reached from inspect/capture.
        guard let request = try await AssetInventory.assetInstallationRequest(supporting:try await AppleSpeechModules.modules(engine,locale:locale)) else { return nil }
        return NativeSpeechResourceInstallation(request)
    }
    public func prepare(engine: ModernSpeechEngine, requestedLocale: String, resolvedLocale: String) async throws -> SpeechEnginePreparation {
        guard #available(macOS 26.0, *) else { throw SpeechResourceFailure.unsupported }
        let modules = try await AppleSpeechModules.modules(engine,locale:resolvedLocale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:modules), format.commonFormat == .pcmFormatInt16 else { throw DictationFailure.audioUnavailable }
        let analyzer = SpeechAnalyzer(modules:modules,options:.init(priority:.userInitiated,modelRetention:.whileInUse))
        do {
            try Task.checkCancellation(); try await analyzer.prepareToAnalyze(in:format); try Task.checkCancellation()
            await analyzer.cancelAndFinishNow()
            return .init(engine:engine,requestedLocale:requestedLocale,resolvedLocale:resolvedLocale,sampleRate:format.sampleRate,channels:format.channelCount)
        } catch { await analyzer.cancelAndFinishNow(); throw error }
    }
}
@available(macOS 26.0, *)
@MainActor private final class NativeSpeechResourceInstallation: SpeechResourceInstallation {
    private let request: AssetInstallationRequest
    init(_ request: AssetInstallationRequest) { self.request = request }
    var progress: SpeechDownloadProgress { .init(completedUnits:request.progress.completedUnitCount,totalUnits:request.progress.totalUnitCount) }
    func downloadAndInstall() async throws {
        let nativeProgress = request.progress
        try await withTaskCancellationHandler {
            try Task.checkCancellation(); try await request.downloadAndInstall(); try Task.checkCancellation()
        } onCancel: { if nativeProgress.isCancellable { nativeProgress.cancel() } }
    }
}
