import Domain
import Workspace
import Foundation
import Testing

private final class ProposalBundleMarker: NSObject {}
func fixture(_ name: String) throws -> Data {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle(for:ProposalBundleMarker.self)
    #endif
    let folder = try #require(bundle.url(forResource:"Fixtures", withExtension:nil))
    return try Data(contentsOf:folder.appendingPathComponent(name))
}
func vectors() throws -> [String:String] { try JSONDecoder().decode([String:String].self, from:fixture("vectors.json")) }
struct ProposalFixture {
    let project: ProjectIdentifier
    let id: ProposalIdentifier
    let snapshot: WorkspaceSnapshot
    let oldHash: String
    init() throws {
        let v = try vectors(); project = try .init(try #require(v["projectID"])); id = try .init(try #require(v["proposalID"])); oldHash = try #require(v["oldHash"])
        snapshot = .init(projectID:project, snapshotDigest:try #require(v["baseSnapshot"]), entries:[
            .init(relativePath:"Sources/New.swift", fileRevision:.absent, fileState:.absent),
            .init(relativePath:"Sources/Old.swift", fileRevision:.sha256(oldHash), fileState:.regular)])
    }
    var create: ProposedFileChange { .create(relativePath:"Sources/New.swift", expectedRevision:.absent, utf8Content:"new\n") }
    var update: ProposedFileChange { .update(relativePath:"Sources/Old.swift", expectedRevision:.sha256(oldHash), utf8Content:"replacement\n") }
    func proposal(_ changes: [ProposedFileChange]? = nil, version: Int = 1, base: String? = nil, projectID: ProjectIdentifier? = nil) -> CodingProposal {
        .init(schemaVersion:version, proposalID:id, projectID:projectID ?? project, baseSnapshotDigest:base ?? snapshot.snapshotDigest, changes:changes ?? [create])
    }
    func context(snapshot: WorkspaceSnapshot? = nil, expected: String? = nil, allowed: Set<String> = ["Sources/New.swift","Sources/Old.swift"], policy: String = "policy-1", expectedPolicy: String = "policy-1", now: Int64 = 0, deadline: Int64 = 100, cancelled: Bool = false, generation: Int = 0, expectedGeneration: Int = 0) -> ProposalValidationContext {
        .init(expectedProposalID:id, expectedProjectID:project, expectedSnapshotDigest:expected ?? self.snapshot.snapshotDigest, snapshot:snapshot ?? self.snapshot, editableTargets:allowed, policyRevision:policy, expectedPolicyRevision:expectedPolicy, now:now, deadline:deadline, isCancelled:cancelled,generation:generation,expectedGeneration:expectedGeneration)
    }
}
func accepted(_ result: ProposalValidationResult) throws -> ProposalValidationResult.Validated {
    guard case .validated(let value) = result.disposition else { Issue.record("Expected structural acceptance, received \(result)"); throw ProposalRejectionReason.malformed }
    return value
}
func expectRejection(_ result: ProposalValidationResult, _ reason: ProposalRejectionReason, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(result.disposition == .rejected([reason]), sourceLocation:sourceLocation)
}
func bytes(_ proposal: CodingProposal) throws -> [UInt8] { try CodingProposalCodec.encode(proposal) }
func json(_ f: ProposalFixture) throws -> String { String(decoding:try bytes(f.proposal()), as:UTF8.self) }
