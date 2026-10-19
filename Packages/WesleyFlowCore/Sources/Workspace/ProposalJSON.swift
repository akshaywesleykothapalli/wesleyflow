import Domain
import Foundation

public enum ProposalLimits {
    public static let inputBytes = 1_048_576
    public static let contentBytes = 262_144
    public static let operations = 20
    public static let pathBytes = 1_024
    public static let pathComponents = 32
    public static let depth = 16
    public static let syntaxNodes = 512
    public static let objectKeys = 32
    public static let keyBytes = 128
    public static let snapshotEntries = 100
}
/// Preflight syntax scanner: bounded recursion/counts, strict Unicode and decoded duplicate-key detection.
/// It does not execute content, repair paths, or read any external resource.
struct ProposalJSONScanner {
    let bytes: [UInt8]
    var index = 0
    var nodes = 0
    mutating func scan() throws {
        guard bytes.count <= ProposalLimits.inputBytes else { throw ProposalRejectionReason.oversized }
        guard String(bytes:bytes, encoding:.utf8) != nil else { throw ProposalRejectionReason.invalidEncoding }
        try value(depth:1); space()
        guard index == bytes.count else { throw ProposalRejectionReason.malformed }
    }
    mutating func space() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ byte: UInt8) -> Bool { space(); if index < bytes.count, bytes[index] == byte { index += 1; return true }; return false }
    mutating func value(depth: Int) throws {
        guard depth <= ProposalLimits.depth else { throw ProposalRejectionReason.oversized }
        nodes += 1; guard nodes <= ProposalLimits.syntaxNodes else { throw ProposalRejectionReason.oversized }
        space(); guard index < bytes.count else { throw ProposalRejectionReason.malformed }
        switch bytes[index] {
        case 123:
            index += 1; var keys = Set<String>()
            if take(125) { return }
            while true {
                let key = try string(isKey:true)
                guard keys.insert(key).inserted else { throw ProposalRejectionReason.duplicateKey }
                guard keys.count <= ProposalLimits.objectKeys else { throw ProposalRejectionReason.oversized }
                guard take(58) else { throw ProposalRejectionReason.malformed }
                try value(depth:depth+1)
                if take(125) { return }
                guard take(44) else { throw ProposalRejectionReason.malformed }
            }
        case 91:
            index += 1; var count = 0
            if take(93) { return }
            while true {
                count += 1; guard count <= ProposalLimits.operations else { throw ProposalRejectionReason.oversized }
                try value(depth:depth+1)
                if take(93) { return }
                guard take(44) else { throw ProposalRejectionReason.malformed }
            }
        case 34: _ = try string(isKey:false)
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        case 45,48...57:
            // The proposal schema has only integer numeric fields. Decimal/exponent spellings reject.
            let start = index
            if bytes[index] == 45 { index += 1 }
            guard index < bytes.count, (48...57).contains(bytes[index]) else { throw ProposalRejectionReason.malformed }
            if bytes[index] == 48 { index += 1 }
            else { while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 } }
            guard index-start <= 20 else { throw ProposalRejectionReason.malformed }
        default: throw ProposalRejectionReason.malformed
        }
    }
    mutating func literal(_ text: String) throws {
        let expected = Array(text.utf8)
        guard index + expected.count <= bytes.count, bytes[index..<index+expected.count].elementsEqual(expected) else { throw ProposalRejectionReason.malformed }
        index += expected.count
    }
    func hex(_ start: Int) throws -> UInt16 {
        guard start+4 <= bytes.count else { throw ProposalRejectionReason.malformed }
        var result: UInt16 = 0
        for byte in bytes[start..<start+4] {
            let value: UInt16
            switch byte { case 48...57: value = UInt16(byte-48); case 65...70: value = UInt16(byte-55); case 97...102: value = UInt16(byte-87); default: throw ProposalRejectionReason.malformed }
            result = result*16+value
        }
        return result
    }
    mutating func string(isKey: Bool) throws -> String {
        space(); let start = index
        guard index < bytes.count, bytes[index] == 34 else { throw ProposalRejectionReason.malformed }
        index += 1
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 {
                let text: String
                do { text = try JSONDecoder().decode(String.self, from:Data(bytes[start..<index])) }
                catch { throw ProposalRejectionReason.invalidEncoding }
                if isKey, text.utf8.count > ProposalLimits.keyBytes { throw ProposalRejectionReason.oversized }
                return text
            }
            guard byte >= 32 else { throw ProposalRejectionReason.malformed }
            if byte == 92 {
                guard index < bytes.count else { throw ProposalRejectionReason.malformed }
                let escaped = bytes[index]; index += 1
                if escaped == 117 {
                    let scalar = try hex(index); index += 4
                    if (0xD800...0xDBFF).contains(scalar) {
                        guard index+6 <= bytes.count, bytes[index] == 92, bytes[index+1] == 117 else { throw ProposalRejectionReason.invalidEncoding }
                        let low = try hex(index+2); guard (0xDC00...0xDFFF).contains(low) else { throw ProposalRejectionReason.invalidEncoding }; index += 6
                    } else if (0xDC00...0xDFFF).contains(scalar) { throw ProposalRejectionReason.invalidEncoding }
                } else if ![34,47,92,98,102,110,114,116].contains(escaped) { throw ProposalRejectionReason.malformed }
            }
        }
        throw ProposalRejectionReason.malformed
    }
}
public enum CodingProposalCodec {
    /// Sole supported boundary for untrusted serialized proposals. Generic Codable decoders lack raw-key checks.
    public static func decode(_ bytes: [UInt8]) throws -> CodingProposal {
        var scanner = ProposalJSONScanner(bytes:bytes); try scanner.scan()
        do {
            let proposal = try JSONDecoder().decode(CodingProposal.self, from:Data(bytes))
            try ProposalStructure.check(proposal)
            return proposal
        } catch let reason as ProposalRejectionReason { throw reason }
        catch { throw ProposalRejectionReason.malformed }
    }
    public static func encode(_ proposal: CodingProposal) throws -> [UInt8] {
        try ProposalStructure.check(proposal)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = Array(try encoder.encode(proposal))
        guard bytes.count <= ProposalLimits.inputBytes else { throw ProposalRejectionReason.oversized }
        return bytes
    }
}
