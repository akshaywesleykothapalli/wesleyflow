import Foundation

public struct DictationAudioLevel: Sendable, Equatable {
    public let sequence: UInt32
    public let rms: Float
    public init(sequence: UInt32 = 0, rms: Float = 0) { self.sequence = sequence; self.rms = rms.isFinite ? min(1,max(0,rms)) : 0 }
}
@MainActor public protocol DictationAudioMetering: AnyObject { func audioLevel() -> DictationAudioLevel }

/// Seven recent energy observations, never a repeating/rand function. No audio retained.
public struct DictationAudioEnvelope: Sendable {
    public private(set) var bars = [Double](repeating:0,count:7)
    private var envelope = 0.0
    private var sequence: UInt32 = 0
    private var staleTicks = 0
    public init() {}
    public mutating func reset() { self = .init() }
    public mutating func update(_ sample: DictationAudioLevel) {
        if sample.sequence == sequence { staleTicks += 1 } else { staleTicks = 0; sequence = sample.sequence }
        let rms = staleTicks >= 3 ? 0 : Double(sample.rms)
        let target = rms <= 0.00056 ? 0 : min(1,max(0,(20*log10(rms)+60)/48))
        envelope += (target-envelope) * (target > envelope ? 0.7 : 0.25)
        if envelope < 0.002 { envelope = 0 }
        bars.removeFirst(); bars.append(envelope)
    }
}

/// Ephemeral authority derived only after a verified insertion, never from history or AI output.
@MainActor public protocol DictationRewriteAnchor: AnyObject {
    var sessionID: String { get }
    var originalText: String { get }
    var processID: Int32 { get }
    var verificationDiagnostics: [DictationVerificationDiagnostic] { get }
    var lastValidationFailure: DictationRewriteValidationFailure? { get }
    func validate() throws
    func replaceValidatedSpan(_ text: String) -> TextInsertionReceipt
}
@MainActor public protocol DictationRewriteAnchorProviding: InsertionTarget {
    var rewriteVerificationDiagnostics: [DictationVerificationDiagnostic] { get }
    func verifiedRewriteAnchor(insertedText: String) throws -> any DictationRewriteAnchor
}

public extension DictationRewriteAnchor {
    var verificationDiagnostics: [DictationVerificationDiagnostic] { [] }
    var lastValidationFailure: DictationRewriteValidationFailure? { nil }
}
public extension DictationRewriteAnchorProviding { var rewriteVerificationDiagnostics: [DictationVerificationDiagnostic] { [] } }
