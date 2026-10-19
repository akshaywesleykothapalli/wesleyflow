import Domain
import Foundation
import CryptoKit

/// Versioned length-prefix encoding, independent of JSON key/operation order and process hash seeds.
public enum ProposalHashing {
    public static func content(_ text: String) -> String { digest(Array(text.utf8)) }
    static func digest(_ bytes: [UInt8]) -> String { SHA256.hash(data:Data(bytes)).map { String(format:"%02x",$0) }.joined() }
    static func sorted(_ entries: [WorkspaceSnapshot.Entry]) -> [WorkspaceSnapshot.Entry] { entries.sorted { $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8) } }
    public static func snapshotDigest(projectID: ProjectIdentifier, entries: [WorkspaceSnapshot.Entry]) throws -> String {
        try ProposalStructure.checkEntries(entries)
        var writer = Writer(); writer.integer(1); writer.string(projectID.rawValue); writer.integer(UInt64(entries.count))
        for entry in sorted(entries) { writer.string(entry.relativePath); writer.revision(entry.fileRevision) }
        return digest(writer.bytes)
    }
    public static func snapshot(projectID: ProjectIdentifier, entries: [WorkspaceSnapshot.Entry]) throws -> WorkspaceSnapshot {
        .init(projectID:projectID, snapshotDigest:try snapshotDigest(projectID:projectID, entries:entries), entries:entries)
    }
    public static func proposalDigest(_ proposal: CodingProposal) throws -> String {
        try ProposalStructure.check(proposal)
        var writer = Writer(); writer.integer(UInt64(proposal.schemaVersion)); writer.string(proposal.proposalID.rawValue); writer.string(proposal.projectID.rawValue); writer.string(proposal.baseSnapshotDigest); writer.integer(UInt64(proposal.changes.count))
        for change in proposal.changes.sorted(by: { $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8) }) { writer.change(change) }
        return digest(writer.bytes)
    }
    public static func operationDigest(_ change: ProposedFileChange) throws -> String {
        try ProposalStructure.checkChange(change)
        var writer = Writer(); writer.integer(1); writer.change(change); return digest(writer.bytes)
    }
    private struct Writer {
        var bytes: [UInt8] = []
        mutating func integer(_ value: UInt64) { bytes += (0..<8).reversed().map { UInt8(truncatingIfNeeded:value >> ($0*8)) } }
        mutating func string(_ value: String) { integer(UInt64(value.utf8.count)); bytes += value.utf8 }
        mutating func revision(_ revision: ExpectedFileRevision) { switch revision { case .absent: string("absent"); case .sha256(let value): string("sha256"); string(value) } }
        mutating func change(_ change: ProposedFileChange) { string(change.kind); string(change.relativePath); revision(change.expectedRevision); string(change.utf8Content) }
    }
}
