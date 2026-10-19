// Data contracts only. No value here is approval, effect authority, or an observation of a real filesystem.
public enum ProposalRejectionReason: String, Error, Codable, Equatable, Sendable {
    case unsupportedSchema, unknownField, unknownOperation, malformed, oversized, invalidEncoding, duplicateKey
    case invalidIdentifier, invalidHash, invalidPath, duplicateTarget, projectMismatch, unknownProject
    case staleSnapshot, revisionMismatch, unauthorizedTarget, unsafeFileType, conflict, invalidSnapshot
    case fileAlreadyExists, cancelled, deadlineExceeded, policyChanged
}
public enum ProposalSchema { public static let version = 1 }
private func metadataIdentifier(_ text: String) -> Bool {
    !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,95,58,46].contains($0) }
}
private func validIdentifier(_ text: String) -> Bool {
    guard text.utf8.count == 36 else { return false }
    let bytes = Array(text.utf8)
    return bytes.count == 36 && bytes.enumerated().allSatisfy { index, byte in
        [8,13,18,23].contains(index) ? byte == 45 : (48...57).contains(byte) || (97...102).contains(byte)
    }
}
public struct ProposalIdentifier: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ value: String) throws { guard validIdentifier(value) else { throw ProposalRejectionReason.invalidIdentifier }; rawValue = value }
    public init(from decoder: any Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
public struct ProjectIdentifier: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ value: String) throws { guard validIdentifier(value) else { throw ProposalRejectionReason.invalidIdentifier }; rawValue = value }
    public init(from decoder: any Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
// Generic Decoder cannot detect duplicate raw keys. Hostile bytes must enter through Workspace.CodingProposalCodec.
private struct ProposalKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func requireKeys(_ decoder: any Decoder, _ expected: Set<String>) throws {
    let c = try decoder.container(keyedBy: ProposalKey.self)
    guard Set(c.allKeys.map(\.stringValue)).isSubset(of: expected) else { throw ProposalRejectionReason.unknownField }
}
public enum ExpectedFileRevision: Equatable, Sendable, Codable {
    case absent
    case sha256(String)
    private enum Keys: String, CodingKey { case kind, digest }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "absent": try requireKeys(decoder, ["kind"]); self = .absent
        case "sha256": try requireKeys(decoder, ["kind","digest"]); self = .sha256(try c.decode(String.self, forKey: .digest))
        default: throw ProposalRejectionReason.malformed
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .absent: try c.encode("absent", forKey: .kind)
        case .sha256(let digest): try c.encode("sha256", forKey: .kind); try c.encode(digest, forKey: .digest)
        }
    }
}
public enum ProposedFileChange: Equatable, Sendable, Codable {
    case create(relativePath: String, expectedRevision: ExpectedFileRevision, utf8Content: String)
    case update(relativePath: String, expectedRevision: ExpectedFileRevision, utf8Content: String)
    public static func == (lhs: ProposedFileChange, rhs: ProposedFileChange) -> Bool {
        lhs.kind == rhs.kind && lhs.relativePath.utf8.elementsEqual(rhs.relativePath.utf8)
            && lhs.expectedRevision == rhs.expectedRevision && lhs.utf8Content.utf8.elementsEqual(rhs.utf8Content.utf8)
    }
    public var relativePath: String { switch self { case .create(let p,_,_), .update(let p,_,_): p } }
    public var expectedRevision: ExpectedFileRevision { switch self { case .create(_,let r,_), .update(_,let r,_): r } }
    public var utf8Content: String { switch self { case .create(_,_,let t), .update(_,_,let t): t } }
    public var kind: String { switch self { case .create: "create"; case .update: "update" } }
    private enum Keys: String, CodingKey { case kind, relativePath, expectedRevision, utf8Content }
    public init(from decoder: any Decoder) throws {
        try requireKeys(decoder, ["kind","relativePath","expectedRevision","utf8Content"])
        let c = try decoder.container(keyedBy: Keys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        guard kind == "create" || kind == "update" else { throw ProposalRejectionReason.unknownOperation }
        let p = try c.decode(String.self, forKey: .relativePath), r = try c.decode(ExpectedFileRevision.self, forKey: .expectedRevision), t = try c.decode(String.self, forKey: .utf8Content)
        self = kind == "create" ? .create(relativePath:p, expectedRevision:r, utf8Content:t) : .update(relativePath:p, expectedRevision:r, utf8Content:t)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kind, forKey:.kind); try c.encode(relativePath, forKey:.relativePath)
        try c.encode(expectedRevision, forKey:.expectedRevision); try c.encode(utf8Content, forKey:.utf8Content)
    }
}
public struct CodingProposal: Equatable, Sendable, Codable {
    public let schemaVersion: Int
    public let proposalID: ProposalIdentifier
    public let projectID: ProjectIdentifier
    public let baseSnapshotDigest: String
    public let changes: [ProposedFileChange]
    public init(schemaVersion: Int = ProposalSchema.version, proposalID: ProposalIdentifier, projectID: ProjectIdentifier, baseSnapshotDigest: String, changes: [ProposedFileChange]) {
        self.schemaVersion = schemaVersion; self.proposalID = proposalID; self.projectID = projectID; self.baseSnapshotDigest = baseSnapshotDigest; self.changes = changes
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, proposalID, projectID, baseSnapshotDigest, changes }
    public init(from decoder: any Decoder) throws {
        try requireKeys(decoder, ["schemaVersion","proposalID","projectID","baseSnapshotDigest","changes"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey:.schemaVersion)
        guard version == ProposalSchema.version else { throw ProposalRejectionReason.unsupportedSchema }
        self.init(schemaVersion:version, proposalID:try c.decode(ProposalIdentifier.self, forKey:.proposalID), projectID:try c.decode(ProjectIdentifier.self, forKey:.projectID), baseSnapshotDigest:try c.decode(String.self, forKey:.baseSnapshotDigest), changes:try c.decode([ProposedFileChange].self, forKey:.changes))
    }
}
/// Explicit absence is required for creation; missing entries are unknown, never implicitly absent.
public struct WorkspaceSnapshot: Equatable, Sendable {
    public enum FileState: String, Sendable { case absent, regular, symlink, hardlink, directory, unknown }
    public struct Entry: Equatable, Sendable {
        public let relativePath: String
        public let fileRevision: ExpectedFileRevision
        public let fileState: FileState
        public init(relativePath: String, fileRevision: ExpectedFileRevision, fileState: FileState) { self.relativePath = relativePath; self.fileRevision = fileRevision; self.fileState = fileState }
    }
    public let schemaVersion: Int
    public let projectID: ProjectIdentifier
    public let snapshotDigest: String
    public let entries: [Entry]
    public init(schemaVersion: Int = ProposalSchema.version, projectID: ProjectIdentifier, snapshotDigest: String, entries: [Entry]) { self.schemaVersion = schemaVersion; self.projectID = projectID; self.snapshotDigest = snapshotDigest; self.entries = entries }
}
/// Structural evaluation only. These freely constructible summaries cannot be redeemed by a permission policy.
public struct ProposalValidationResult: Equatable, Sendable {
    public struct Validated: Equatable, Sendable {
        public let proposalDigest: String
        public let projectID: ProjectIdentifier
        public let baseSnapshotDigest: String
        public let expectedPostSnapshotDigest: String
        public let policyRevision: String
        public let operationDigests: [String]
        public let proposedContentHashes: [String]
        public init(proposalDigest: String, projectID: ProjectIdentifier, baseSnapshotDigest: String, expectedPostSnapshotDigest: String, policyRevision: String, operationDigests: [String], proposedContentHashes: [String]) {
            self.proposalDigest = proposalDigest; self.projectID = projectID; self.baseSnapshotDigest = baseSnapshotDigest; self.expectedPostSnapshotDigest = expectedPostSnapshotDigest; self.policyRevision = policyRevision; self.operationDigests = operationDigests; self.proposedContentHashes = proposedContentHashes
        }
    }
    public enum Disposition: Equatable, Sendable { case validated(Validated), rejected([ProposalRejectionReason]) }
    public let schemaVersion = ProposalSchema.version
    public let disposition: Disposition
    public init(_ disposition: Disposition) { self.disposition = disposition }
}
/// Inert review requirement, NOT a grant. No initializer produces OperationToken or effect capability.
public struct ApprovalRequirement: Equatable, Sendable {
    public let schemaVersion = ProposalSchema.version
    public let evaluation: ProposalValidationResult.Validated
    public let taskID: TaskIdentifier
    public let operationID: String
    public let sessionID: String
    public let generation: Int
    public let deadline: Int64
    public let maximumTTLMilliseconds: Int64
    public init(evaluation: ProposalValidationResult.Validated, taskID: TaskIdentifier, operationID: String, sessionID: String, generation: Int, deadline: Int64, maximumTTLMilliseconds: Int64) throws {
        guard metadataIdentifier(taskID.rawValue), metadataIdentifier(operationID), metadataIdentifier(sessionID), generation >= 0, deadline >= 0, maximumTTLMilliseconds > 0, maximumTTLMilliseconds <= 300_000 else { throw ProposalRejectionReason.malformed }
        self.evaluation = evaluation; self.taskID = taskID; self.operationID = operationID; self.sessionID = sessionID; self.generation = generation; self.deadline = deadline; self.maximumTTLMilliseconds = maximumTTLMilliseconds
    }
}
/// A report value, not proof of effects. Never decoded from the model-facing proposal schema.
public struct VerifiedChangeResult: Equatable, Sendable {
    public enum Scope: String, Sendable { case fileContent, containedBuildAndTests }
    public enum Outcome: String, Sendable { case verified, failed, partial, uncertain }
    public struct Receipt: Equatable, Sendable {
        public enum Disposition: Sendable { case notApplied, applied, uncertain }
        public let relativePath: String
        public let before: ExpectedFileRevision
        public let after: ExpectedFileRevision
        public let disposition: Disposition
        public let intentReference: String
        public let outcomeReference: String?
        public init(relativePath: String, before: ExpectedFileRevision, after: ExpectedFileRevision, disposition: Disposition, intentReference: String, outcomeReference: String?) { self.relativePath = relativePath; self.before = before; self.after = after; self.disposition = disposition; self.intentReference = intentReference; self.outcomeReference = outcomeReference }
    }
    public let schemaVersion = ProposalSchema.version
    public let proposalDigest: String
    public let projectID: ProjectIdentifier
    public let baseSnapshotDigest: String
    public let observedPostSnapshotDigest: String
    public let receipts: [Receipt]
    public let verificationScope: Scope
    public let evidenceDigest: String
    public let outcome: Outcome
    public init(proposalDigest: String, projectID: ProjectIdentifier, baseSnapshotDigest: String, observedPostSnapshotDigest: String, receipts: [Receipt], verificationScope: Scope, evidenceDigest: String, outcome: Outcome) {
        self.proposalDigest = proposalDigest; self.projectID = projectID; self.baseSnapshotDigest = baseSnapshotDigest; self.observedPostSnapshotDigest = observedPostSnapshotDigest; self.receipts = receipts; self.verificationScope = verificationScope; self.evidenceDigest = evidenceDigest; self.outcome = outcome
    }
}
