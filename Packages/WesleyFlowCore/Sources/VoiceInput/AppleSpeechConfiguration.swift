import Domain
import Foundation
import Speech
import AVFoundation

public struct AppleSpeechConfiguration: Sendable {
    public let locale: String
    public let speechAssets: String
    public let dictationAssets: String
    public let legacyOnDeviceAvailable: Bool
    public let microphone: String
    public let speechPermission: String
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
    @MainActor public static func inspect(localeIdentifier: String) async -> AppleSpeechConfiguration {
        let locale = Locale(identifier:localeIdentifier)
        var speechAssets = "Unsupported", dictationAssets = "Unsupported"
        if SpeechTranscriber.isAvailable, let selected = await SpeechTranscriber.supportedLocale(equivalentTo:locale) {
            speechAssets = String(describing:await AssetInventory.status(forModules:[SpeechTranscriber(locale:selected,preset:.progressiveTranscription)]))
        }
        if let selected = await DictationTranscriber.supportedLocale(equivalentTo:locale) {
            dictationAssets = String(describing:await AssetInventory.status(forModules:[DictationTranscriber(locale:selected,preset:.progressiveShortDictation)]))
        }
        let legacy = SFSpeechRecognizer(locale:locale), permissions = permissionSummary()
        return .init(locale:localeIdentifier,speechAssets:speechAssets,dictationAssets:dictationAssets,
                     legacyOnDeviceAvailable:legacy?.isAvailable == true && legacy?.supportsOnDeviceRecognition == true,
                     microphone:permissions.microphone,speechPermission:permissions.speech)
    }
}
