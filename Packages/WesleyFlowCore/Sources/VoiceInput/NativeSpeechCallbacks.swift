import Domain
import Foundation
import AVFoundation
import Speech

/// ObjC/audio callbacks may arrive on arbitrary queues. Construct them outside actor
/// isolation, resume Sendable continuations there, and hop explicitly for app state.
enum NativeSpeechCallbacks {
    nonisolated static func authorization(
        using register: @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            let callback: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = { status in
                continuation.resume(returning: status)
            }
            register(callback)
        }
    }
    nonisolated static func recognition(
        deliver: @escaping @MainActor @Sendable (String?, Bool, Bool) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in deliver(text, final, failed) }
        }
    }
    nonisolated static func tap(_ ingress: AudioIngress, meter: AudioLevelMailbox? = nil) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in meter?.append(buffer); ingress.append(buffer) }
    }
}
