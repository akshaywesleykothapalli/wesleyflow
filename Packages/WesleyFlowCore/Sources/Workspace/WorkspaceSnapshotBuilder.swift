import Domain
import Foundation

public struct ObservedSnapshotFile: Sendable, Equatable {
    public let relativePath: String
    public let byteCount: Int
    public let revision: ExpectedFileRevision
    public let identity: ObservedFileIdentity
    public let fileType = "regularUTF8"
    public let consistency = "metadataChecked"
}
/// Built only through the injected observation port. Trusted composition must supply the broker.
/// Not Codable, not an effect capability, and not an atomic/current filesystem attestation.
public struct ObservedWorkspaceSnapshot: Sendable {
    public let schemaVersion = 1
    public let snapshot: WorkspaceSnapshot
    public let rootIdentity: ObservedFileIdentity
    public let files: [ObservedSnapshotFile]
    public let excludedCount: Int
    public let manifestDigest: String
    let sources: [ObservedSourceFile]
}
public struct WorkspaceSnapshotBuilder: Sendable {
    private let source: any WorkspaceObservationSource
    private let now: @Sendable () -> ContinuousClock.Instant
    public init(source: any WorkspaceObservationSource) { self.source = source; now = { .now } }
    init(source: any WorkspaceObservationSource, now: @escaping @Sendable () -> ContinuousClock.Instant) {
        self.source = source; self.now = now
    }
    public func build(projectID: ProjectIdentifier, absentCandidates: [String] = [], limits: WorkspaceObservationLimits) async throws -> ObservedWorkspaceSnapshot {
        let started = now()
        func check() throws {
            guard !Task.isCancelled else { throw WorkspaceObservationError.cancelled }
            let elapsed = started.duration(to: now())
            guard elapsed >= .zero, elapsed < .milliseconds(limits.durationMilliseconds) else { throw WorkspaceObservationError.deadlineExceeded }
        }
        try check()
        let observation = try await source.observe(projectID: projectID, absentCandidates: absentCandidates, limits: limits)
        try check()
        guard observation.projectID == projectID, observation.excludedCount >= 0,
              observation.files.count + observation.absentPaths.count <= limits.files,
              Set(observation.absentPaths).isSubset(of: Set(absentCandidates)) else { throw WorkspaceObservationError.invalidSelection }
        var entries: [WorkspaceSnapshot.Entry] = []; var files: [ObservedSnapshotFile] = []; var bytes = 0
        let sources = observation.files.sorted { $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8) }
        for file in sources {
            try check()
            guard WorkspaceContextPolicy.permitsFile(file.relativePath), WorkspaceContextPolicy.permitsText(file.utf8Content) else { throw WorkspaceObservationError.excluded }
            let count = file.utf8Content.utf8.count; bytes += count
            guard count <= limits.individualBytes, bytes <= min(limits.aggregateBytes, limits.retainedBytes) else { throw WorkspaceObservationError.limitExceeded }
            let revision = ExpectedFileRevision.sha256(ProposalHashing.content(file.utf8Content))
            entries.append(.init(relativePath: file.relativePath, fileRevision: revision, fileState: .regular))
            files.append(.init(relativePath: file.relativePath, byteCount: count, revision: revision, identity: file.identity))
        }
        for path in observation.absentPaths {
            try check()
            guard WorkspaceContextPolicy.permitsFile(path) else { throw WorkspaceObservationError.excluded }
            entries.append(.init(relativePath: path, fileRevision: .absent, fileState: .absent))
        }
        let snapshot = try ProposalHashing.snapshot(projectID: projectID, entries: ProposalHashing.sorted(entries))
        // Deterministic, length-prefixed manifest, separate from PB's content revision digest.
        // Identity changes alter manifestDigest; identical bytes/paths retain the PB digest.
        var manifest = ""
        func append(_ text: String) { manifest += "\(text.utf8.count):" + text }
        append("workspace-observation-v1"); append(projectID.rawValue); append(snapshot.snapshotDigest)
        append(String(observation.excludedCount))
        append(String(observation.rootIdentity.device)); append(String(observation.rootIdentity.inode))
        for file in files {
            append(file.relativePath); append(file.fileType); append(String(file.byteCount)); append(file.consistency)
            let id = file.identity
            for value in [String(id.device), String(id.inode), String(id.modifiedSeconds), String(id.modifiedNanoseconds), String(id.changedSeconds), String(id.changedNanoseconds)] { append(value) }
        }
        let manifestDigest = ProposalHashing.content(manifest)
        try check() // Includes transport wait, source hashing and manifest work in the snapshot deadline.
        return .init(snapshot: snapshot, rootIdentity: observation.rootIdentity, files: files, excludedCount: observation.excludedCount, manifestDigest: manifestDigest, sources: sources)
    }
}

public struct ProjectContext: Sendable {
    public enum Completeness: String, Sendable { case completeSelection, incompleteSelection }
    public struct Excerpt: Sendable {
        public let relativePath: String
        public let revision: ExpectedFileRevision
        public let utf8Text: String
        /// Repository content is untrusted data, never user/system instructions or authorization.
        public let provenance = "untrustedRepositoryText"
    }
    public let projectID: ProjectIdentifier
    public let snapshotDigest: String
    public let excerpts: [Excerpt]
    public let omittedPaths: [String]
    public let excludedCount: Int
    public let completeness: Completeness
}
public struct ContextAssembler: Sendable {
    private let registry: any ProjectRegistry
    public init(registry: any ProjectRegistry) { self.registry = registry }
    /// Explicit whole-file selection. Byte count is exact; one UTF8 byte consumes one conservative token unit.
    /// No lossy truncation or tokenization claim; providers must still enforce their own tokenizer limit.
    public func assemble(projectID: ProjectIdentifier, observation: ObservedWorkspaceSnapshot, selectedPaths: [String], byteBudget: Int, tokenBudget: Int) async throws -> ProjectContext {
        guard projectID == observation.snapshot.projectID, selectedPaths.count <= 100,
              Set(selectedPaths).count == selectedPaths.count, (0...4_194_304).contains(byteBudget),
              (0...4_194_304).contains(tokenBudget) else { throw WorkspaceObservationError.invalidSelection }
        try await registry.validateObservation(projectID: projectID, rootIdentity: observation.rootIdentity)
        guard selectedPaths.allSatisfy(WorkspaceContextPolicy.permitsFile) else { throw WorkspaceObservationError.excluded }
        do { try ProposalStructure.checkTargets(selectedPaths) } catch { throw WorkspaceObservationError.invalidSelection }
        var excerpts: [ProjectContext.Excerpt] = []; var omitted: [String] = []; var remaining = min(byteBudget, tokenBudget)
        for path in selectedPaths.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            guard !Task.isCancelled else { throw WorkspaceObservationError.cancelled }
            guard WorkspaceContextPolicy.permitsFile(path) else { throw WorkspaceObservationError.excluded }
            guard let file = observation.sources.first(where: { $0.relativePath == path }), file.utf8Content.utf8.count <= remaining else { omitted.append(path); continue }
            remaining -= file.utf8Content.utf8.count
            excerpts.append(.init(relativePath: path, revision: .sha256(ProposalHashing.content(file.utf8Content)), utf8Text: file.utf8Content))
        }
        guard !Task.isCancelled else { throw WorkspaceObservationError.cancelled }
        try await registry.validateObservation(projectID: projectID, rootIdentity: observation.rootIdentity)
        guard !Task.isCancelled else { throw WorkspaceObservationError.cancelled }
        return .init(projectID: projectID, snapshotDigest: observation.snapshot.snapshotDigest, excerpts: excerpts,
                     omittedPaths: omitted, excludedCount: observation.excludedCount, completeness: omitted.isEmpty ? .completeSelection : .incompleteSelection)
    }
}
public extension CodingProposalValidator {
    /// Uses broker-derived observations; still pure validation, never authorization or a current-state lease.
    func validate(_ proposal: CodingProposal, observed: ObservedWorkspaceSnapshot, context: ProposalValidationContext) -> ProposalValidationResult {
        guard observed.snapshot == context.snapshot else { return .init(.rejected([.staleSnapshot])) }
        return validate(proposal, context: context)
    }
}
