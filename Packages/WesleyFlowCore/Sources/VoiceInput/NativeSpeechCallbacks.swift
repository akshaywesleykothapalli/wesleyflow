import Domain
import Foundation
import AVFoundation
import Speech
import os

/// ObjC/audio callbacks may arrive on arbitrary queues. Construct them outside actor
/// isolation, resume Sendable continuations there, and hop explicitly for app state.
struct NativeLegacyObservation: Sendable {
    let text: String?
    let start: Double?, end: Double?
    let isFinal: Bool
    let failure: SpeechNativeError?
    let observedAt: Double
    let metadataStart: Double?, metadataDuration: Double?
    var sequence: UInt64
}


/// One bounded FIFO per recognition request. A single actor task drains it, so
/// independently scheduled actor hops cannot drop an earlier passage or final.
final class NativeLegacyDelivery: Sendable {
    private struct State: Sendable {
        var queue: [NativeLegacyObservation] = []
        var scheduled = false
        var failed = false
        var sequence: UInt64 = 0
    }
    private let state = OSAllocatedUnfairLock(initialState:State())
    private let deliver: @MainActor @Sendable (NativeLegacyObservation) -> Void
    init(deliver: @escaping @MainActor @Sendable (NativeLegacyObservation) -> Void) { self.deliver = deliver }
    func enqueue(_ observation: NativeLegacyObservation) {
        let schedule = state.withLock { value -> Bool in
            guard !value.failed else { return false }
            value.sequence += 1
            var item = observation; item.sequence = value.sequence
            if value.queue.count >= 32 || (item.text?.utf8.count ?? 0) > DictationText.maximumBytes {
                // Do not silently drop callbacks and later claim complete insertion.
                value.failed = true
                if value.queue.count >= 32 { value.queue.removeLast() }
                value.queue.append(.init(text:nil,start:nil,end:nil,isFinal:false,
                    failure:.init(primary:.init(domain:"WesleyFlowSpeechDeliveryError",code:1)),
                    observedAt:item.observedAt,metadataStart:nil,metadataDuration:nil,sequence:item.sequence))
            } else { value.queue.append(item) }
            guard !value.scheduled else { return false }; value.scheduled = true; return true
        }
        if schedule { Task { @MainActor in
            while let item = self.next() { self.deliver(item) }
        } }
    }
    private func next() -> NativeLegacyObservation? {
        state.withLock { value in
            guard !value.queue.isEmpty else { value.scheduled = false; return nil }
            return value.queue.removeFirst()
        }
    }
}

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
    /// Copy time ranges as values before crossing actors. Legacy providers can return
    /// a new passage after silence instead of the entire task's previous text.
    nonisolated static func recognitionPassages(
        deliver: @escaping @MainActor @Sendable (NativeLegacyObservation) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        let delivery = NativeLegacyDelivery(deliver:deliver)
        return { result, error in
            let observedAt = ProcessInfo.processInfo.systemUptime
            let transcription = result?.bestTranscription
            delivery.enqueue(NativeLegacyObservation(text:transcription?.formattedString,
                start:transcription?.segments.first?.timestamp,
                end:transcription?.segments.last.map { $0.timestamp + $0.duration },
                isFinal:result?.isFinal == true,failure:errorMetadata(error),observedAt:observedAt,
                metadataStart:result?.speechRecognitionMetadata?.speechStartTimestamp,
                metadataDuration:result?.speechRecognitionMetadata?.speechDuration,sequence:0))
        }
    }
    /// Copy only structural error metadata. Never serialize NSError.userInfo or descriptions.
    nonisolated static func errorMetadata(_ error: (any Error)?) -> SpeechNativeError? {
        guard let error else { return nil }
        let root = error as NSError
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(root)], underlying: [SpeechErrorCode] = []
        var current = root
        for _ in 0..<4 {
            guard let child = current.userInfo[NSUnderlyingErrorKey] as? NSError,
                  seen.insert(ObjectIdentifier(child)).inserted else { break }
            underlying.append(.init(domain:child.domain,code:child.code)); current = child
        }
        return .init(primary:.init(domain:root.domain,code:root.code),underlying:underlying)
    }
    nonisolated static func tap(_ ingress: AudioIngress, meter: AudioLevelMailbox? = nil) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, time in meter?.append(buffer); ingress.append(buffer,at:time) }
    }
}
