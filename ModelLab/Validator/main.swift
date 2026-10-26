// Synthetic data only. Uses the production decoder, hashing and validator; no effect ports.
import Foundation
import Domain
import Workspace
struct Entry: Decodable { let relativePath:String; let content:String? }
struct Input: Decodable { let projectID:String; let proposalID:String; let entries:[Entry]; let editableTargets:[String]; let response:String? }
func evaluate(_ input:Input) throws -> [String:Any] {
    let project = try ProjectIdentifier(input.projectID), proposalID = try ProposalIdentifier(input.proposalID)
    let entries = input.entries.map { e in WorkspaceSnapshot.Entry(relativePath:e.relativePath,fileRevision:e.content.map { .sha256(ProposalHashing.content($0)) } ?? .absent,fileState:e.content == nil ? .absent : .regular) }
    let snapshot = try ProposalHashing.snapshot(projectID:project,entries:entries)
    let context = ProposalValidationContext(expectedProposalID:proposalID,expectedProjectID:project,expectedSnapshotDigest:snapshot.snapshotDigest,snapshot:snapshot,editableTargets:Set(input.editableTargets),policyRevision:"model-lab1-synthetic",expectedPolicyRevision:"model-lab1-synthetic",now:1000,deadline:2000)
    var result:[String:Any] = ["snapshotDigest":snapshot.snapshotDigest,"revisions":Dictionary(uniqueKeysWithValues:entries.map { e -> (String,Any) in
        switch e.fileRevision { case .absent:return (e.relativePath,["kind":"absent"]);case .sha256(let digest):return (e.relativePath,["kind":"sha256","digest":digest]) }
    }),"schema":try ProposalGenerator.outputSchema(context:context)]
    if let response = input.response {
        result["jsonValid"] = (try? JSONSerialization.jsonObject(with:Data(response.utf8),options:[.fragmentsAllowed])) != nil
        do {
            let proposal = try CodingProposalCodec.decode(Array(response.utf8)); result["schemaValid"] = true
            switch CodingProposalValidator().validate(proposal,context:context).disposition {
            case .validated(let value):result["accepted"] = true;result["proposalDigest"] = value.proposalDigest
            case .rejected(let reasons):result["accepted"] = false;result["reasons"] = reasons.map(\.rawValue)
            }
        } catch { result["schemaValid"] = false;result["accepted"] = false;result["reasons"] = [(error as? ProposalRejectionReason ?? .malformed).rawValue] }
    }
    return result
}
while let line = readLine() {
    do {
        guard line.utf8.count <= 2_097_152 else { throw ProposalRejectionReason.oversized }
        let input = try JSONDecoder().decode(Input.self,from:Data(line.utf8));let output = try evaluate(input)
        print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]),as:UTF8.self))
    } catch { print("{\"bridgeError\":\"invalidSyntheticContext\"}") }
}
