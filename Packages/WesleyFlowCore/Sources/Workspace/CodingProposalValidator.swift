import Domain
import Foundation

struct ProposalStructure {
    static func validHash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func policyIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,95,58,46].contains($0) }
    }
    static func alias(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.folding(options:.caseInsensitive, locale:Locale(identifier:"en_US_POSIX")) }
    static func checkPath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= ProposalLimits.pathBytes, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains("\\"), !path.contains(":"), !path.contains("%"),
              path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              path.utf8.elementsEqual(path.precomposedStringWithCanonicalMapping.utf8) else { throw ProposalRejectionReason.invalidPath }
        let parts = path.split(separator:"/", omittingEmptySubsequences:false)
        guard parts.count <= ProposalLimits.pathComponents else { throw ProposalRejectionReason.invalidPath }
        let reserved: Set<String> = ["build","dist","node_modules","credentials","secrets","id_rsa","id_ed25519","opencode.json","opencode.jsonc","agents.md","skill.md","package.resolved","known_hosts","authorized_keys"]
        for part in parts {
            let name = part.lowercased()
            guard !part.isEmpty, !part.hasPrefix("."), !part.hasSuffix("."), !part.hasSuffix(" "), !reserved.contains(name),
                  !name.hasPrefix("credentials."), !name.hasPrefix("secrets."),
                  ![".pem",".key",".p12",".pfx",".keystore",".mobileprovision"].contains(where:name.hasSuffix) else { throw ProposalRejectionReason.invalidPath }
        }
    }
    static func checkTargets(_ paths: [String]) throws {
        var previous: [String] = []
        for path in paths {
            try checkPath(path); let key = alias(path)
            guard !previous.contains(where: { $0 == key || $0.hasPrefix(key+"/") || key.hasPrefix($0+"/") }) else { throw ProposalRejectionReason.duplicateTarget }
            previous.append(key)
        }
    }
    static func checkRevision(_ revision: ExpectedFileRevision) throws {
        if case .sha256(let hash) = revision, !validHash(hash) { throw ProposalRejectionReason.invalidHash }
    }
    static func checkChange(_ change: ProposedFileChange) throws {
        try checkPath(change.relativePath); try checkRevision(change.expectedRevision)
        guard change.utf8Content.utf8.count <= ProposalLimits.contentBytes else { throw ProposalRejectionReason.oversized }
        // NUL-containing bodies fall outside the first regular-text-only scope.
        guard !change.utf8Content.contains("\0") else { throw ProposalRejectionReason.invalidEncoding }
        switch (change,change.expectedRevision) {
        case (.create,.absent), (.update,.sha256): break
        default: throw ProposalRejectionReason.revisionMismatch
        }
    }
    static func check(_ proposal: CodingProposal) throws {
        guard proposal.schemaVersion == ProposalSchema.version else { throw ProposalRejectionReason.unsupportedSchema }
        guard validHash(proposal.baseSnapshotDigest) else { throw ProposalRejectionReason.invalidHash }
        guard !proposal.changes.isEmpty else { throw ProposalRejectionReason.malformed }
        guard proposal.changes.count <= ProposalLimits.operations else { throw ProposalRejectionReason.oversized }
        var size = 0
        for change in proposal.changes { try checkChange(change); size += change.utf8Content.utf8.count; guard size <= ProposalLimits.inputBytes else { throw ProposalRejectionReason.oversized } }
        try checkTargets(proposal.changes.map(\.relativePath))
    }
    static func checkEntries(_ entries: [WorkspaceSnapshot.Entry]) throws {
        guard entries.count <= ProposalLimits.snapshotEntries else { throw ProposalRejectionReason.oversized }
        try checkTargets(entries.map(\.relativePath))
        for entry in entries {
            try checkRevision(entry.fileRevision)
            switch (entry.fileState,entry.fileRevision) {
            case (.absent,.absent), (.regular,.sha256): break
            case (.symlink,_), (.hardlink,_), (.directory,_), (.unknown,_): throw ProposalRejectionReason.unsafeFileType
            default: throw ProposalRejectionReason.invalidSnapshot
            }
        }
    }
}
/// Injected observations and policy DATA. This context neither reads a project nor grants access to one.
public struct ProposalValidationContext: Equatable, Sendable {
    public let expectedProposalID: ProposalIdentifier
    public let generation: Int
    public let expectedGeneration: Int
    public let expectedProjectID: ProjectIdentifier
    public let expectedSnapshotDigest: String
    public let snapshot: WorkspaceSnapshot
    public let editableTargets: Set<String>
    public let policyRevision: String
    public let expectedPolicyRevision: String
    public let now: Int64
    public let deadline: Int64
    public let isCancelled: Bool
    public init(expectedProposalID: ProposalIdentifier, expectedProjectID: ProjectIdentifier, expectedSnapshotDigest: String, snapshot: WorkspaceSnapshot, editableTargets: Set<String>, policyRevision: String, expectedPolicyRevision: String, now: Int64, deadline: Int64, isCancelled: Bool = false, generation: Int = 0, expectedGeneration: Int = 0) {
        self.expectedProposalID = expectedProposalID; self.generation = generation; self.expectedGeneration = expectedGeneration
        self.expectedProjectID = expectedProjectID; self.expectedSnapshotDigest = expectedSnapshotDigest; self.snapshot = snapshot; self.editableTargets = editableTargets; self.policyRevision = policyRevision; self.expectedPolicyRevision = expectedPolicyRevision; self.now = now; self.deadline = deadline; self.isCancelled = isCancelled
    }
}
/// Synchronous and side-effect-free. Accepted means structurally applicable to supplied DATA, never approved.
public struct CodingProposalValidator: Sendable {
    public init() {}
    public func validate(_ bytes: [UInt8], context: ProposalValidationContext) -> ProposalValidationResult {
        do { return validate(try CodingProposalCodec.decode(bytes), context:context) }
        catch { return rejected(error) }
    }
    public func validate(_ proposal: CodingProposal, context: ProposalValidationContext) -> ProposalValidationResult {
        do {
            guard !context.isCancelled, !Task.isCancelled else { throw ProposalRejectionReason.cancelled }
            guard proposal.proposalID == context.expectedProposalID else { throw ProposalRejectionReason.conflict }
            guard context.generation >= 0, context.generation == context.expectedGeneration else { throw ProposalRejectionReason.conflict }
            guard context.now >= 0, context.now < context.deadline else { throw ProposalRejectionReason.deadlineExceeded }
            _ = try CodingProposalCodec.encode(proposal) // Includes actual encoded-envelope/escape size.
            guard proposal.projectID == context.expectedProjectID, context.snapshot.projectID == context.expectedProjectID else { throw ProposalRejectionReason.projectMismatch }
            guard context.snapshot.schemaVersion == ProposalSchema.version else { throw ProposalRejectionReason.unsupportedSchema }
            guard ProposalStructure.validHash(context.expectedSnapshotDigest), ProposalStructure.validHash(context.snapshot.snapshotDigest) else { throw ProposalRejectionReason.invalidHash }
            guard ProposalStructure.policyIdentifier(context.policyRevision), ProposalStructure.policyIdentifier(context.expectedPolicyRevision) else { throw ProposalRejectionReason.malformed }
            guard context.policyRevision.utf8.elementsEqual(context.expectedPolicyRevision.utf8) else { throw ProposalRejectionReason.policyChanged }
            guard context.editableTargets.count <= ProposalLimits.snapshotEntries else { throw ProposalRejectionReason.oversized }
            try ProposalStructure.checkTargets(context.editableTargets.sorted())
            let actual = try ProposalHashing.snapshotDigest(projectID:context.snapshot.projectID, entries:context.snapshot.entries)
            guard actual == context.snapshot.snapshotDigest else { throw ProposalRejectionReason.invalidSnapshot }
            guard proposal.baseSnapshotDigest == actual, context.expectedSnapshotDigest == actual else { throw ProposalRejectionReason.staleSnapshot }
            var entries = context.snapshot.entries
            for change in proposal.changes {
                guard context.editableTargets.contains(change.relativePath) else { throw ProposalRejectionReason.unauthorizedTarget }
                guard let index = entries.firstIndex(where: { $0.relativePath.utf8.elementsEqual(change.relativePath.utf8) }) else { throw ProposalRejectionReason.invalidSnapshot }
                let entry = entries[index]
                if case .create = change, entry.fileState != .absent { throw ProposalRejectionReason.fileAlreadyExists }
                guard entry.fileRevision == change.expectedRevision else { throw ProposalRejectionReason.revisionMismatch }
                entries[index] = .init(relativePath:change.relativePath, fileRevision:.sha256(ProposalHashing.content(change.utf8Content)), fileState:.regular)
            }
            let digest = try ProposalHashing.proposalDigest(proposal)
            let canonicalChanges = proposal.changes.sorted { $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8) }
            let operations = try canonicalChanges.map(ProposalHashing.operationDigest)
            let post = try ProposalHashing.snapshotDigest(projectID:proposal.projectID, entries:entries)
            return .init(.validated(.init(proposalDigest:digest, projectID:proposal.projectID, baseSnapshotDigest:actual, expectedPostSnapshotDigest:post, policyRevision:context.policyRevision, operationDigests:operations, proposedContentHashes:canonicalChanges.map { ProposalHashing.content($0.utf8Content) })))
        } catch { return rejected(error) }
    }
    private func rejected(_ error: any Error) -> ProposalValidationResult { .init(.rejected([error as? ProposalRejectionReason ?? .malformed])) }
}
