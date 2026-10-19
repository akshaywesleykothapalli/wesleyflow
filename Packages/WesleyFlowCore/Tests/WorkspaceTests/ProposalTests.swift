import Domain
import Workspace
import SystemOperations
import Foundation
import Testing

@Suite("Structured proposal values and pure validation", .timeLimit(.minutes(1)))
struct ProposalTests {
    @Test func knownCreateFixtureAndIndependentHashVector() throws {
        let f = try ProposalFixture(); let v = try vectors()
        let proposal = try CodingProposalCodec.decode(Array(fixture("create.json")))
        #expect(proposal == f.proposal())
        let result = try accepted(CodingProposalValidator().validate(proposal, context:f.context()))
        #expect(result.proposalDigest == v["createDigest"])
        #expect(result.expectedPostSnapshotDigest == v["postCreate"])
        #expect(result.operationDigests == [try #require(v["createOperation"])])
        #expect(result.proposedContentHashes == [ProposalHashing.content("new\n")])
        #expect(result.policyRevision == "policy-1")
        #expect(result.projectID == f.project)
    }
    @Test func replacementAndMultipleIndependentChanges() throws {
        let f = try ProposalFixture(); let v = try vectors(); let validator = CodingProposalValidator()
        let update = try accepted(validator.validate(f.proposal([f.update]), context:f.context()))
        #expect(update.proposalDigest == v["updateDigest"])
        #expect(update.operationDigests == [try #require(v["updateOperation"])])
        let both = try accepted(validator.validate(f.proposal([f.create,f.update]), context:f.context()))
        #expect(both.proposalDigest == v["bothDigest"])
        #expect(both.proposedContentHashes.count == 2)
        #expect(both.expectedPostSnapshotDigest != f.snapshot.snapshotDigest)
    }
    @Test func canonicalDigestsAndResultsIgnoreInputOrdering() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        #expect(validator.validate(f.proposal([f.create,f.update]),context:f.context()) == validator.validate(f.proposal([f.update,f.create]),context:f.context()))
        #expect(try ProposalHashing.snapshotDigest(projectID:f.project, entries:Array(f.snapshot.entries.reversed())) == f.snapshot.snapshotDigest)
    }
    @Test func deterministicRoundTripAndKnownSHA256() throws {
        let f = try ProposalFixture(); let v = try vectors(); let validator = CodingProposalValidator()
        let encoded = try bytes(f.proposal()); let decoded = try CodingProposalCodec.decode(encoded)
        #expect(try bytes(decoded) == encoded)
        #expect(ProposalHashing.content("") == v["emptyHash"])
        #expect(ProposalHashing.content("café 🐦\n") == v["unicodeHash"])
        for _ in 0..<100 { #expect(validator.validate(decoded, context:f.context()) == validator.validate(f.proposal(), context:f.context())) }
        #expect(ProposalHashing.content("é") != ProposalHashing.content("e\u{301}")) // Exact content bytes, no silent normalization.
    }
    @Test(arguments:["", "ABCDEFAB-1234-5678-9012-123456789abc", "../x", "11111111111141118111111111111111", "11111111-1111-4111-8111-11111111111g", "１1111111-1111-4111-8111-111111111111"])
    func invalidIdentifiers(_ id: String) {
        #expect(throws:ProposalRejectionReason.invalidIdentifier) { try ProposalIdentifier(id) }
        #expect(throws:ProposalRejectionReason.invalidIdentifier) { try ProjectIdentifier(id) }
    }
    @Test(arguments:[0,2,-1,Int.max]) func unsupportedVersion(_ version: Int) throws {
        let f = try ProposalFixture();expectRejection(CodingProposalValidator().validate(f.proposal(version:version), context:f.context()), .unsupportedSchema)
    }
    @Test(arguments:["", "a", String(repeating:"A",count:64), String(repeating:"g",count:64), String(repeating:"a",count:63), String(repeating:"a",count:65)])
    func malformedHashes(_ hash: String) throws {
        let f = try ProposalFixture();expectRejection(CodingProposalValidator().validate(f.proposal(base:hash),context:f.context()), .invalidHash)
        let change = ProposedFileChange.update(relativePath:"Sources/Old.swift",expectedRevision:.sha256(hash),utf8Content:"x")
        expectRejection(CodingProposalValidator().validate(f.proposal([change]),context:f.context()),.invalidHash)
    }
    @Test func staleProjectRevisionAndSnapshotTampering() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator();let other = try ProjectIdentifier("33333333-3333-4333-8333-333333333333")
        expectRejection(validator.validate(f.proposal(projectID:other),context:f.context()),.projectMismatch)
        expectRejection(validator.validate(f.proposal(base:String(repeating:"b",count:64)),context:f.context()),.staleSnapshot)
        expectRejection(validator.validate(f.proposal(),context:f.context(expected:String(repeating:"b",count:64))),.staleSnapshot)
        let bad = WorkspaceSnapshot(projectID:f.project,snapshotDigest:String(repeating:"b",count:64),entries:f.snapshot.entries)
        expectRejection(validator.validate(f.proposal(),context:f.context(snapshot:bad)),.invalidSnapshot)
        let wrong = WorkspaceSnapshot(projectID:other,snapshotDigest:f.snapshot.snapshotDigest,entries:f.snapshot.entries)
        expectRejection(validator.validate(f.proposal(),context:f.context(snapshot:wrong)),.projectMismatch)
    }
    @Test func requiredSnapshotAndExpectedRevisionAreNotJustFormattedHashes() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        let wrong = ProposedFileChange.update(relativePath:"Sources/Old.swift",expectedRevision:.sha256(String(repeating:"a",count:64)),utf8Content:"x")
        expectRejection(validator.validate(f.proposal([wrong]),context:f.context()),.revisionMismatch)
        let exists = ProposedFileChange.create(relativePath:"Sources/Old.swift",expectedRevision:.absent,utf8Content:"x")
        expectRejection(validator.validate(f.proposal([exists]),context:f.context()),.fileAlreadyExists)
        let incompatible = ProposedFileChange.create(relativePath:"Sources/New.swift",expectedRevision:.sha256(f.oldHash),utf8Content:"x")
        expectRejection(validator.validate(f.proposal([incompatible]),context:f.context()),.revisionMismatch)
        let missing = ProposedFileChange.update(relativePath:"Sources/Old.swift",expectedRevision:.absent,utf8Content:"x")
        expectRejection(validator.validate(f.proposal([missing]),context:f.context()),.revisionMismatch)
        let empty = try ProposalHashing.snapshot(projectID:f.project,entries:[])
        expectRejection(validator.validate(f.proposal(base:empty.snapshotDigest),context:f.context(snapshot:empty,expected:empty.snapshotDigest)),.invalidSnapshot)
        let updatingAbsent = ProposedFileChange.update(relativePath:"Sources/New.swift",expectedRevision:.sha256(f.oldHash),utf8Content:"x")
        expectRejection(validator.validate(f.proposal([updatingAbsent]),context:f.context()),.revisionMismatch)
    }
    @Test(arguments:[WorkspaceSnapshot.FileState.symlink,.hardlink,.directory,.unknown])
    func unsupportedInjectedFileState(_ state: WorkspaceSnapshot.FileState) throws {
        let f = try ProposalFixture();let entry = WorkspaceSnapshot.Entry(relativePath:"Sources/New.swift",fileRevision:.absent,fileState:state)
        let snapshot = WorkspaceSnapshot(projectID:f.project,snapshotDigest:f.snapshot.snapshotDigest,entries:[entry])
        expectRejection(CodingProposalValidator().validate(f.proposal(),context:f.context(snapshot:snapshot)),.unsafeFileType)
    }
    @Test func unauthorizedPolicyChangedExpiredAndCancelled() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        expectRejection(validator.validate(f.proposal(),context:f.context(allowed:[])),.unauthorizedTarget)
        expectRejection(validator.validate(f.proposal(),context:f.context(expectedPolicy:"new-policy")),.policyChanged)
        expectRejection(validator.validate(f.proposal(),context:f.context(policy:"")),.malformed)
        expectRejection(validator.validate(f.proposal(),context:f.context(now:100)),.deadlineExceeded)
        expectRejection(validator.validate(f.proposal(),context:f.context(now:101)),.deadlineExceeded)
        _ = try accepted(validator.validate(f.proposal(),context:f.context(now:99)))
        expectRejection(validator.validate(f.proposal(),context:f.context(cancelled:true)),.cancelled)
    }
    @Test func implicitTaskCancellationIsNotApproval() async throws {
        let f = try ProposalFixture()
        let task = Task { () -> ProposalValidationResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return CodingProposalValidator().validate(f.proposal(),context:f.context())
        }
        expectRejection(await task.value,.cancelled)
    }
    @Test @MainActor func acceptanceDoesNotGrantExistingPermissionAuthority() async throws {
        let f = try ProposalFixture();let result = try accepted(CodingProposalValidator().validate(f.proposal(),context:f.context()))
        let requirement = try ApprovalRequirement(evaluation:result,taskID:.init(rawValue:"fixture"),operationID:"edit",sessionID:"fixture-session",generation:0,deadline:100,maximumTTLMilliseconds:300_000)
        #expect(requirement.schemaVersion == 1)
        let pair = PermissionBroker.compose(clock:ProposalClock())
        for kind in [OperationKind.fileWrite,.process,.automation] {
            let op = ScopedOperation(id:"edit",kind:kind,digest:result.proposalDigest,workspaceID:f.project.rawValue,revision:f.snapshot.snapshotDigest)
            await #expect(throws:TaskServiceError.unsupportedOperation) { try await pair.policy.request(taskID:requirement.taskID,operation:op,generation:0) }
        }
        #expect(throws:ProposalRejectionReason.malformed) { try ApprovalRequirement(evaluation:result,taskID:.init(rawValue:"fixture"),operationID:"edit",sessionID:"s",generation:0,deadline:100,maximumTTLMilliseconds:300_001) }
    }
    @Test func allTenContractsAreSendableAndReportsAreNotModelWireValues() throws {
        func sendable<T: Sendable>(_ value: T) {}
        let f = try ProposalFixture(); let result = CodingProposalValidator().validate(f.proposal(),context:f.context());let value = try accepted(result)
        sendable(f.proposal());sendable(f.id);sendable(f.project);sendable(f.snapshot);sendable(f.create);sendable(f.create.expectedRevision);sendable(result);sendable(ProposalRejectionReason.conflict)
        let requirement = try ApprovalRequirement(evaluation:value,taskID:.init(rawValue:"f"),operationID:"o",sessionID:"s",generation:0,deadline:1,maximumTTLMilliseconds:1);sendable(requirement)
        let receipt = VerifiedChangeResult.Receipt(relativePath:"Sources/New.swift",before:.absent,after:.sha256(ProposalHashing.content("new\n")),disposition:.uncertain,intentReference:"intent",outcomeReference:nil)
        let report = VerifiedChangeResult(proposalDigest:value.proposalDigest,projectID:f.project,baseSnapshotDigest:f.snapshot.snapshotDigest,observedPostSnapshotDigest:value.expectedPostSnapshotDigest,receipts:[receipt],verificationScope:.fileContent,evidenceDigest:String(repeating:"a",count:64),outcome:.uncertain)
        sendable(report);#expect(report.schemaVersion == 1);#expect(report.receipts[0].outcomeReference == nil);#expect(report.outcome == .uncertain)
    }
}
private struct ProposalClock: TaskClock {
    func now() async -> Int64 { 0 }
    func sleep(until deadline: Int64) async throws { throw CancellationError() }
}

@Suite("Proposal request correlation")
struct ProposalCorrelationTests {
    @Test func responseIdentifierCannotBeSubstitutedWithinExpectedProject() throws {
        let f = try ProposalFixture()
        let replacement = try ProposalIdentifier("44444444-4444-4444-8444-444444444444")
        let proposal = CodingProposal(proposalID:replacement,projectID:f.project,baseSnapshotDigest:f.snapshot.snapshotDigest,changes:[f.create])
        expectRejection(CodingProposalValidator().validate(proposal,context:f.context()),.conflict)
    }
}

@Suite("Injected observation and metadata limits")
struct ProposalObservationTests {
    @Test func staleGenerationNeverProducesAnApprovalRequirement() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        for generation in [-1,0,2] {
            expectRejection(validator.validate(f.proposal(),context:f.context(generation:generation,expectedGeneration:1)),.conflict)
        }
        _ = try accepted(validator.validate(f.proposal(),context:f.context(generation:1,expectedGeneration:1)))
    }
    @Test func snapshotStateRevisionConsistencyAndLimits() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        for (state,revision) in [(WorkspaceSnapshot.FileState.absent,ExpectedFileRevision.sha256(f.oldHash)),(.regular,.absent)] {
            let entry = WorkspaceSnapshot.Entry(relativePath:"Sources/New.swift",fileRevision:revision,fileState:state)
            let snap = WorkspaceSnapshot(projectID:f.project,snapshotDigest:f.snapshot.snapshotDigest,entries:[entry])
            expectRejection(validator.validate(f.proposal(),context:f.context(snapshot:snap)),.invalidSnapshot)
        }
        let future = WorkspaceSnapshot(schemaVersion:2,projectID:f.project,snapshotDigest:f.snapshot.snapshotDigest,entries:f.snapshot.entries)
        expectRejection(validator.validate(f.proposal(),context:f.context(snapshot:future)),.unsupportedSchema)
        for count in [99,100] {
            let entries = (0..<count).map { WorkspaceSnapshot.Entry(relativePath:"Sources/F\($0).swift",fileRevision:.absent,fileState:.absent) }
            #expect(try ProposalHashing.snapshot(projectID:f.project,entries:entries).entries.count == count)
        }
        expectRejection(validator.validate(f.proposal(),context:f.context(allowed:Set((0..<101).map { "F\($0)" }))),.oversized)
    }
    @Test(arguments:["", "bad\0id", "/absolute", "id space", String(repeating:"a",count:129)])
    func approvalMetadataIsBoundedData(_ invalid: String) throws {
        let f = try ProposalFixture();let result = try accepted(CodingProposalValidator().validate(f.proposal(),context:f.context()))
        #expect(throws:ProposalRejectionReason.malformed) { try ApprovalRequirement(evaluation:result,taskID:.init(rawValue:invalid),operationID:"op",sessionID:"session",generation:0,deadline:100,maximumTTLMilliseconds:1) }
        #expect(throws:ProposalRejectionReason.malformed) { try ApprovalRequirement(evaluation:result,taskID:.init(rawValue:"task"),operationID:invalid,sessionID:"session",generation:0,deadline:100,maximumTTLMilliseconds:1) }
        #expect(throws:ProposalRejectionReason.malformed) { try ApprovalRequirement(evaluation:result,taskID:.init(rawValue:"task"),operationID:"op",sessionID:invalid,generation:0,deadline:100,maximumTTLMilliseconds:1) }
    }
    @Test func observedAbsenceAndUnicodeAreExplicit() throws {
        let f = try ProposalFixture();let path = "Sources/Café🐦.swift"
        let snap = try ProposalHashing.snapshot(projectID:f.project,entries:[.init(relativePath:path,fileRevision:.absent,fileState:.absent)])
        let change = ProposedFileChange.create(relativePath:path,expectedRevision:.absent,utf8Content:"café 🐦\n")
        _ = try accepted(CodingProposalValidator().validate(f.proposal([change],base:snap.snapshotDigest),context:f.context(snapshot:snap,expected:snap.snapshotDigest,allowed:[path])))
        let nul = ProposedFileChange.create(relativePath:path,expectedRevision:.absent,utf8Content:"text\0binary")
        expectRejection(CodingProposalValidator().validate(f.proposal([nul],base:snap.snapshotDigest),context:f.context(snapshot:snap,expected:snap.snapshotDigest,allowed:[path])),.invalidEncoding)
    }
}

@Suite("Exact proposal byte identity")
struct ProposalByteIdentityTests {
    @Test func canonicalUnicodeEquivalenceCannotHideChangedProposalBytes() throws {
        let f = try ProposalFixture()
        let composed = ProposedFileChange.create(relativePath:"Sources/New.swift",expectedRevision:.absent,utf8Content:"é")
        let decomposed = ProposedFileChange.create(relativePath:"Sources/New.swift",expectedRevision:.absent,utf8Content:"e\u{301}")
        #expect(composed != decomposed)
        #expect(f.proposal([composed]) != f.proposal([decomposed]))
        #expect(try ProposalHashing.proposalDigest(f.proposal([composed])) != ProposalHashing.proposalDigest(f.proposal([decomposed])))
        let roundTrip = try CodingProposalCodec.decode(bytes(f.proposal([decomposed])))
        #expect(roundTrip.changes[0].utf8Content.utf8.elementsEqual("e\u{301}".utf8))
    }
    @Test func policyRevisionMetadataRejectsNoncanonicalUnicodeAliases() throws {
        let f = try ProposalFixture()
        expectRejection(CodingProposalValidator().validate(f.proposal(),context:f.context(policy:"policy-é",expectedPolicy:"policy-e\u{301}")),.malformed)
    }
}
