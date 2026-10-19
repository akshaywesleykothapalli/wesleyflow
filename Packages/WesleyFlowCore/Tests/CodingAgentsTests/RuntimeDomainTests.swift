import Testing
import Domain
import CodingAgents

@Suite("Runtime value contracts")
struct RuntimeDomainTests {
    private func requireSendable<T: Sendable>(_ value: T) {}
    @Test func valuesAreSendableAndRuntimeConforms() throws {
        let plan = try manifest(); let identity = try SessionCorrelation(taskID: plan.taskID, operationID: plan.operationID, sessionID: .init("ses_fixture"), generation: plan.generation)
        let permission = try RuntimePermissionRequest(id: "per_fixture", action: "edit", resources: ["file.swift"])
        requireSendable(plan); requireSendable(identity); requireSendable(permission); requireSendable(RuntimePermissionResponse(reject: permission))
        requireSendable(CancellationRequest(correlation: identity)); requireSendable(CleanupAssessment.uncertain)
        requireSendable(try RuntimeEvent(id: "evt_fixture", correlation: identity, kind: .outcome(claimedSuccess: true)))
        let (runtime,_,_) = try manager(); let value: any CodingAgentRuntime = runtime; requireSendable(value)
    }
    @Test func malformedIdentifiersAndScopeRejected() throws {
        #expect(throws: RuntimeProtocolError.invalidManifest) { _ = try RuntimeSessionIdentifier("../outside") }
        #expect(throws: RuntimeProtocolError.invalidManifest) { _ = try RuntimeSessionIdentifier("") }
        #expect(throws: RuntimeProtocolError.invalidManifest) { _ = try SessionCorrelation(taskID: .init(rawValue: "task"), operationID: "op", sessionID: .init("ses_ok"), generation: -1) }
        #expect(throws: RuntimeProtocolError.invalidPayload) { _ = try RuntimePermissionRequest(id: "per_a", action: "edit", resources: [String(repeating: "x", count: 1025)]) }
    }
    @Test func inertLaunchManifestContainsNoCredentialsOrLaunchBehavior() throws {
        let value = try RuntimeLaunchManifest(executablePath: "/fixture/opencode", expectedVersion: "1.18.25", expectedSHA256: String(repeating: "a", count: 64), arguments: ["inert-fixture"], workingDirectory: "/fixture", environmentAllowlist: ["LANG"], configurationDirectory: "/fixture/config", cacheDirectory: "/fixture/cache", dataDirectory: "/fixture/data", serverEndpoint: "http://127.0.0.1:4096")
        requireSendable(value); #expect(value.authentication == .requiredEphemeralCredential)
        #expect(value.environmentAllowlist == ["LANG"])
        #expect(throws: RuntimeProtocolError.invalidManifest) { _ = try RuntimeLaunchManifest(executablePath: "relative", expectedVersion: "1", expectedSHA256: "bad", arguments: [], workingDirectory: "/", environmentAllowlist: [], configurationDirectory: "/", cacheDirectory: "/", dataDirectory: "/", serverEndpoint: "") }
    }
    @Test func criticalCategoriesAndNoGrantIssuance() {
        #expect(RuntimeEventKind.outcome(claimedSuccess: true).isCritical)
        #expect(RuntimeEventKind.error(.invalidPayload).isCritical)
        #expect(RuntimeEventKind.terminal(.idle).isCritical)
        #expect(!RuntimeEventKind.progress("text").isCritical)
        // Runtime values have no TaskPermissionPolicy, executor or approval authority references.
    }
}

import Foundation

private final class ContractBundleMarker: NSObject {}
@Suite("Pinned V1 schema subset")
struct PinnedContractTests {
    private var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        Bundle(for: ContractBundleMarker.self)
        #endif
    }
    private func load(_ name: String) throws -> Any {
        let url = try #require(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }
    /// Independent small schema oracle for the captured fixture subset, not a general OpenAPI validator.
    private func valid(_ value: Any, schema: [String: Any], schemas: [String: Any]) -> Bool {
        if let reference = schema["$ref"] as? String, let name = reference.split(separator: "/").last,
           let target = schemas[String(name)] as? [String: Any] { return valid(value, schema: target, schemas: schemas) }
        if let alternatives = schema["anyOf"] as? [[String: Any]] { return alternatives.contains { valid(value, schema: $0, schemas: schemas) } }
        if let options = schema["enum"] as? [String], let text = value as? String, !options.contains(text) { return false }
        switch schema["type"] as? String {
        case "object":
            guard let object = value as? [String: Any] else { return false }
            if let required = schema["required"] as? [String], !required.allSatisfy({ object[$0] != nil }) { return false }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            if schema["additionalProperties"] as? Bool == false, !object.keys.allSatisfy({ properties[$0] != nil }) { return false }
            return object.allSatisfy { key,value in properties[key].map { valid(value, schema: $0, schemas: schemas) } ?? true }
        case "array":
            guard let array = value as? [Any], let item = schema["items"] as? [String: Any] else { return false }
            return array.allSatisfy { valid($0, schema: item, schemas: schemas) }
        case "string":
            guard let text = value as? String else { return false }
            if let pattern = schema["pattern"] as? String, text.range(of: pattern, options: .regularExpression) == nil { return false }
            return true
        case "integer":
            guard let number = value as? Int else { return false }
            return number >= (schema["minimum"] as? Int ?? Int.min)
        default: return true
        }
    }
    @Test func sanitizedFixturesMatchPinnedSchemaAndDecoder() throws {
        let contract = try #require(try load("contract-subset") as? [String: Any])
        let components = try #require(contract["components"] as? [String: Any]); let schemas = try #require(components["schemas"] as? [String: Any])
        #expect(contract["sourceCommit"] as? String == "cb7d8b2f5e44876ef98b661dc10590c915af3a9f")
        let identity = try SessionCorrelation(taskID: .init(rawValue: "task"), operationID: "proposal", sessionID: .init("ses_fixture"), generation: 0)
        let fixtures = try #require(try load("events") as? [[String: Any]])
        #expect(fixtures.count == 4)
        for fixture in fixtures {
            let name = try #require(fixture["schema"] as? String); let object = try #require(fixture["event"] as? [String: Any]); let schema = try #require(schemas[name] as? [String: Any])
            #expect(valid(object, schema: schema, schemas: schemas))
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let parsed = try frames([Array("data: ".utf8)+Array(data)+Array("\n\n".utf8)])
            let event = try OpenCodeV1EventDecoder.decode(try #require(parsed.first), correlation: identity)
            #expect(event.correlation == identity)
        }
        let permission = try RuntimePermissionRequest(id: "per_fixture", action: "bash", resources: [])
        let reply = try JSONSerialization.jsonObject(with: Data(OpenCodeV1EventDecoder.rejectionPayload(.init(reject: permission))))
        #expect(valid(reply, schema: try #require(contract["permissionReply"] as? [String: Any]), schemas: schemas))
    }
    @Test func malformedPermissionAndRetryAreRejected() throws {
        let identity = try SessionCorrelation(taskID: .init(rawValue: "task"), operationID: "op", sessionID: .init("ses_fixture"), generation: 0)
        let incomplete = Array("data: {\"id\":\"evt_bad\",\"type\":\"permission.asked\",\"properties\":{\"sessionID\":\"ses_fixture\",\"id\":\"per_bad\",\"permission\":\"bash\",\"patterns\":[]}}\n\n".utf8)
        #expect(throws: RuntimeProtocolError.invalidPayload) { _ = try OpenCodeV1EventDecoder.decode(try #require(frames([incomplete]).first), correlation: identity) }
        let retry = try packet(type: "session.status", text: "retry")
        #expect(throws: RuntimeProtocolError.invalidPayload) { _ = try OpenCodeV1EventDecoder.decode(try #require(frames([retry]).first), correlation: identity) }
    }
    @Test func transportCheckpointIsIndependentFromJSONEventIdentity() throws {
        let identity = try SessionCorrelation(taskID: .init(rawValue: "task"), operationID: "op", sessionID: .init("ses_fixture"), generation: 0)
        let body = "{\"id\":\"evt_independent\",\"type\":\"session.idle\",\"properties\":{\"sessionID\":\"ses_fixture\"}}"
        let parsed = try frames([Array("id: transport_checkpoint\ndata: ".utf8)+Array(body.utf8)+Array("\n\n".utf8)])
        let frame = try #require(parsed.first)
        #expect(frame.id == "transport_checkpoint")
        #expect(try OpenCodeV1EventDecoder.decode(frame, correlation: identity).id == "evt_independent")
    }

}
