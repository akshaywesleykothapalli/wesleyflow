import Foundation
import FoundationModels

@main struct AvailabilityProbe {
    static func main() throws {
        let model = SystemLanguageModel.default
        let status: String
        switch model.availability {
        case .available: status = "available"
        case .unavailable(.deviceNotEligible): status = "deviceNotEligible"
        case .unavailable(.appleIntelligenceNotEnabled): status = "appleIntelligenceNotEnabled"
        case .unavailable(.modelNotReady): status = "modelNotReady"
        case .unavailable: status = "unknownUnavailableReason"
        }
        let result: [String: Any] = [
            "provider": "FoundationModels.SystemLanguageModel.default",
            "availability": status,
            "isAvailable": model.isAvailable,
            "currentLocale": Locale.current.identifier,
            "supportsCurrentLocale": model.supportsLocale(Locale.current),
            "supportsEnglishIndia": model.supportsLocale(Locale(identifier: "en_IN")),
            "supportsEnglishUS": model.supportsLocale(Locale(identifier: "en_US")),
            "supportedLanguages": model.supportedLanguages.map { String(describing: $0) }.sorted(),
            "generationAttempted": false,
            "sessionCreated": false,
            "modelDownloadRequested": false,
            "utc": ISO8601DateFormatter().string(from: Date())
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
