import Domain
import Workspace
import Foundation
import Testing

@Suite("Proposal path, syntax and resource boundaries", .timeLimit(.minutes(1)))
struct ProposalBoundaryTests {
    @Test(arguments:["/tmp/x","../x","Sources/../x","Sources/nested/../../x","","a\0b","a\\b","C:/x","//server/share","a//b","a/","~/x","~name/x","a:b","a%2fb","a/./b","a\nb","a\tb",".git/config","Sources/.env",".ssh/id_rsa","credentials","secrets.json","a/key.pem","build/a.swift","node_modules/a","AGENTS.md","opencode.json","Sources/a ","Sources/a.","Sources/cafe\u{301}.swift"])
    func unsafePaths(_ path: String) throws {
        let f = try ProposalFixture();let change = ProposedFileChange.create(relativePath:path,expectedRevision:.absent,utf8Content:"x")
        expectRejection(CodingProposalValidator().validate(f.proposal([change]),context:f.context()),.invalidPath)
    }
    @Test(arguments:["Sources/A.swift","Sources/NEW.swift","Sources/New.swift/child.swift"])
    func duplicateCaseAndPrefixTargets(_ second: String) throws {
        let f = try ProposalFixture();let first = second == "Sources/A.swift" ? "Sources/A.swift" : "Sources/New.swift"
        let changes:[ProposedFileChange] = [.create(relativePath:first,expectedRevision:.absent,utf8Content:"x"),.create(relativePath:second,expectedRevision:.absent,utf8Content:"y")]
        expectRejection(CodingProposalValidator().validate(f.proposal(changes),context:f.context()),.duplicateTarget)
    }
    @Test func conflictingKindsAndSnapshotAliasesReject() throws {
        let f = try ProposalFixture();let update = ProposedFileChange.update(relativePath:"Sources/New.swift",expectedRevision:.sha256(f.oldHash),utf8Content:"x")
        expectRejection(CodingProposalValidator().validate(f.proposal([f.create,update]),context:f.context()),.duplicateTarget)
        let entries = f.snapshot.entries + [.init(relativePath:"sources/new.swift",fileRevision:.absent,fileState:.absent)]
        let snap = WorkspaceSnapshot(projectID:f.project,snapshotDigest:f.snapshot.snapshotDigest,entries:entries)
        expectRejection(CodingProposalValidator().validate(f.proposal(),context:f.context(snapshot:snap)),.duplicateTarget)
    }
    @Test(arguments:["delete","rename","move","execute","shell","script","install","chmod","patch","CREATE","replace"])
    func unknownOperations(_ kind: String) throws {
        let f = try ProposalFixture();let text = try json(f).replacingOccurrences(of:"\"kind\":\"create\"",with:"\"kind\":\"\(kind)\"")
        expectRejection(CodingProposalValidator().validate(Array(text.utf8),context:f.context()),.unknownOperation)
    }
    @Test(arguments:["command","shell","permissions","approval","verification","unexpected"])
    func injectedAuthorityOrUnknownFields(_ key: String) throws {
        let f = try ProposalFixture();let original = try json(f)
        for text in [original.replacingOccurrences(of:"{\"baseSnapshotDigest\"",with:"{\"\(key)\":true,\"baseSnapshotDigest\""),original.replacingOccurrences(of:"\"kind\":\"create\"",with:"\"\(key)\":true,\"kind\":\"create\"") ] {
            expectRejection(CodingProposalValidator().validate(Array(text.utf8),context:f.context()),.unknownField)
        }
    }
    @Test(arguments:["schemaVersion","proposalID","projectID","baseSnapshotDigest","changes"])
    func missingMetadata(_ key: String) throws {
        let f = try ProposalFixture();var object = try #require(JSONSerialization.jsonObject(with:Data(try json(f).utf8)) as? [String:Any]);object.removeValue(forKey:key)
        expectRejection(CodingProposalValidator().validate(Array(try JSONSerialization.data(withJSONObject:object)),context:f.context()),.malformed)
    }
    @Test(arguments:["relativePath","expectedRevision","utf8Content"])
    func missingChangeFields(_ key: String) throws {
        let f = try ProposalFixture();var object = try #require(JSONSerialization.jsonObject(with:Data(try json(f).utf8)) as? [String:Any]);var changes = try #require(object["changes"] as? [[String:Any]]);changes[0].removeValue(forKey:key);object["changes"] = changes
        expectRejection(CodingProposalValidator().validate(Array(try JSONSerialization.data(withJSONObject:object)),context:f.context()),.malformed)
    }
    @Test(arguments:["", "{}{}", "[]", "null", "{", "{\"a\":1,}", "{\"a\":01}", "{\"a\":+1}", "{\"a\":1.0}", "{\"a\":1e0}", "{\"a\":NaN}", "```json\n{}\n```", "\u{FEFF}{}", "{\"a\":\"raw\nnewline\"}"])
    func malformedJSON(_ text: String) throws {
        let f = try ProposalFixture();expectRejection(CodingProposalValidator().validate(Array(text.utf8),context:f.context()),.malformed)
    }
    @Test func duplicateEscapedAndNestedSecurityKeysRejectBeforeCodable() throws {
        let f = try ProposalFixture();let original = try json(f)
        let examples = [original.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1,\"schemaVersion\":2"), original.replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":1,\"schema\\u0056ersion\":1"),original.replacingOccurrences(of:"\"kind\":\"create\"",with:"\"kind\":\"create\",\"kind\":\"delete\""),original.replacingOccurrences(of:"\"kind\":\"absent\"",with:"\"kind\":\"absent\",\"kind\":\"sha256\"")]
        for text in examples { expectRejection(CodingProposalValidator().validate(Array(text.utf8),context:f.context()),.duplicateKey) }
    }
    @Test func unknownRevisionAndNestedFieldReject() throws {
        let f = try ProposalFixture();let original = try json(f)
        expectRejection(CodingProposalValidator().validate(Array(original.replacingOccurrences(of:"\"kind\":\"absent\"",with:"\"kind\":\"mtime\"").utf8),context:f.context()),.malformed)
        expectRejection(CodingProposalValidator().validate(Array(original.replacingOccurrences(of:"\"kind\":\"absent\"",with:"\"kind\":\"absent\",\"digest\":\"ignored\"").utf8),context:f.context()),.unknownField)
    }
    @Test func invalidUnicodeAndSurrogatesAreNeverRepaired() throws {
        let f = try ProposalFixture();let original = try json(f)
        expectRejection(CodingProposalValidator().validate([0xff,0xfe],context:f.context()),.invalidEncoding)
        for escaped in ["\\uD800", "\\uDC00", "\\uD800\\u0041", "\\uD800x"] {
            let text = original.replacingOccurrences(of:"new\\n",with:escaped)
            expectRejection(CodingProposalValidator().validate(Array(text.utf8),context:f.context()),.invalidEncoding)
        }
        let paired = original.replacingOccurrences(of:"new\\n",with:"\\uD83D\\uDC26")
        _ = try accepted(CodingProposalValidator().validate(Array(paired.utf8),context:f.context()))
    }
    @Test func validContentIsDataEvenIfItContainsCommandsOrMarkdown() throws {
        let f = try ProposalFixture();let content = "```sh\nrm -rf /fixture-only\n```\npermissions=allow\n"
        let change = ProposedFileChange.create(relativePath:"Sources/New.swift",expectedRevision:.absent,utf8Content:content)
        let result = try accepted(CodingProposalValidator().validate(f.proposal([change]),context:f.context()))
        #expect(result.proposedContentHashes == [ProposalHashing.content(content)])
        #expect(try CodingProposalCodec.decode(bytes(f.proposal([change]))).changes[0].utf8Content == content)
        // Acceptance says nothing about code safety; production module has no IO/process/network port.
    }
    @Test func contentAndAggregateEncodedLimits() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        for size in [ProposalLimits.contentBytes-1,ProposalLimits.contentBytes] {
            let change = ProposedFileChange.create(relativePath:"Sources/New.swift",expectedRevision:.absent,utf8Content:String(repeating:"a",count:size))
            _ = try accepted(validator.validate(f.proposal([change]),context:f.context()))
        }
        let tooLarge = ProposedFileChange.create(relativePath:"Sources/New.swift",expectedRevision:.absent,utf8Content:String(repeating:"a",count:ProposalLimits.contentBytes+1))
        expectRejection(validator.validate(f.proposal([tooLarge]),context:f.context()),.oversized)
        let changes = (0..<4).map { ProposedFileChange.create(relativePath:"Sources/F\($0).swift",expectedRevision:.absent,utf8Content:String(repeating:"a",count:ProposalLimits.contentBytes)) }
        expectRejection(validator.validate(f.proposal(changes),context:f.context()),.oversized) // Content alone fits; encoded envelope does not.
        let escaped = (0..<4).map { ProposedFileChange.create(relativePath:"Sources/F\($0).swift",expectedRevision:.absent,utf8Content:String(repeating:"\n",count:140_000)) }
        expectRejection(validator.validate(f.proposal(escaped),context:f.context()),.oversized)
        expectRejection(validator.validate(Array(repeating:32,count:ProposalLimits.inputBytes+1),context:f.context()),.oversized)
        let base = try bytes(f.proposal())
        for length in [ProposalLimits.inputBytes-1,ProposalLimits.inputBytes] {
            let padded = base + Array(repeating:32,count:length-base.count)
            _ = try accepted(validator.validate(padded,context:f.context()))
        }
    }
    @Test func operationAndSnapshotCountBoundaries() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        expectRejection(validator.validate(f.proposal([]),context:f.context()),.malformed)
        for count in [19,20,21] {
            let entries = (0..<count).map { WorkspaceSnapshot.Entry(relativePath:"Sources/F\($0).swift",fileRevision:.absent,fileState:.absent) }
            let snapshot = try ProposalHashing.snapshot(projectID:f.project,entries:entries)
            let changes = entries.map { ProposedFileChange.create(relativePath:$0.relativePath,expectedRevision:.absent,utf8Content:"x") }
            let result = validator.validate(f.proposal(changes,base:snapshot.snapshotDigest),context:f.context(snapshot:snapshot,expected:snapshot.snapshotDigest,allowed:Set(entries.map(\.relativePath))))
            if count <= 20 { _ = try accepted(result) } else { expectRejection(result,.oversized) }
        }
        let entries = (0..<101).map { WorkspaceSnapshot.Entry(relativePath:"Sources/F\($0).swift",fileRevision:.absent,fileState:.absent) }
        #expect(throws:ProposalRejectionReason.oversized) { try ProposalHashing.snapshot(projectID:f.project,entries:entries) }
    }
    @Test func pathBytesAndComponentBoundaries() throws {
        let f = try ProposalFixture()
        for size in [1_023,1_024,1_025] {
            let path = String(repeating:"a",count:size)
            let change = ProposedFileChange.create(relativePath:path,expectedRevision:.absent,utf8Content:"")
            if size <= 1_024 { #expect(throws:Never.self) { try CodingProposalCodec.encode(f.proposal([change])) } }
            else { #expect(throws:ProposalRejectionReason.invalidPath) { try CodingProposalCodec.encode(f.proposal([change])) } }
        }
        for count in [31,32,33] {
            let path = Array(repeating:"a",count:count).joined(separator:"/")
            let change = ProposedFileChange.create(relativePath:path,expectedRevision:.absent,utf8Content:"")
            if count <= 32 { _ = try CodingProposalCodec.encode(f.proposal([change])) }
            else { #expect(throws:ProposalRejectionReason.invalidPath) { try CodingProposalCodec.encode(f.proposal([change])) } }
        }
    }
    @Test func depthAndNodeBoundsAndInvalidSchemaNumericRepresentations() throws {
        let f = try ProposalFixture();let validator = CodingProposalValidator()
        for depth in [15,16,17] {
            let nested = String(repeating:"[",count:depth)+"0"+String(repeating:"]",count:depth)
            expectRejection(validator.validate(Array(nested.utf8),context:f.context()), depth < 16 ? .malformed : .oversized)
        }
        let deepTree = "["+Array(repeating:"["+Array(repeating:"["+Array(repeating:"0",count:20).joined(separator:",")+"]",count:20).joined(separator:",")+"]",count:20).joined(separator:",")+"]"
        expectRejection(validator.validate(Array(deepTree.utf8),context:f.context()),.oversized)
        for version in ["1.0","1e0","01","true","null"] {
            let text = try json(f).replacingOccurrences(of:"\"schemaVersion\":1",with:"\"schemaVersion\":\(version)")
            expectRejection(validator.validate(Array(text.utf8),context:f.context()),.malformed)
        }
    }
}
