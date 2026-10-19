import Domain
@testable import ModelProviders
import Workspace
import SystemOperations
import TaskExecution
import Foundation
import Testing

private let fixtureDigest = String(repeating:"a",count:64)
private func providerModel() throws -> ModelDescriptor { try .init(name:"qwen3:8b",digest:fixtureDigest,storedBytes:5_225_388_164,capabilities:.init(structuredOutput:true,maximumContext:4096)) }
private func basicRequest(_ id: String = "request_1", deadline: Int64 = 121_000) throws -> InferenceRequest {
    try .init(id:id,model:providerModel(),systemInstruction:"fixture",syntheticUserContent:"synthetic",outputSchema:"{\"type\":\"object\"}",deadline:deadline)
}
private actor ProviderClock: TaskClock {
    private var value: Int64 = 1000
    private var waits: [Int64: CheckedContinuation<Void, any Error>] = [:]
    private var observers: [Int64: CheckedContinuation<Void, Never>] = [:]
    func now() -> Int64 { value }
    func sleep(until deadline: Int64) async throws {
        if deadline <= value { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waits[deadline] = continuation; observers.removeValue(forKey:deadline)?.resume()
            }
        } onCancel: { Task { await self.cancel(deadline) } }
    }
    private func cancel(_ deadline: Int64) { waits.removeValue(forKey:deadline)?.resume(throwing:CancellationError()) }
    func waitForSleep(_ deadline: Int64) async { if waits[deadline] == nil { await withCheckedContinuation { observers[deadline] = $0 } } }
    func advance(_ value: Int64) { self.value = value; for deadline in waits.keys.filter({ $0 <= value }) { waits.removeValue(forKey:deadline)?.resume() } }
}
private actor ProviderMemory: InferenceMemorySource {
    private var value = InferenceMemorySample(conservativeAvailableBytes:16_000_000_000,pressureNormal:true)
    func sample() -> InferenceMemorySample { value }
    func set(_ value: InferenceMemorySample) { self.value = value }
}
private actor ProviderTransport: OllamaHTTPTransport {
    var chat: Data
    var status = 200
    var hold = false
    var foreign = false
    var version = "0.33.0"
    var tagDigest = fixtureDigest
    var replacementDigest: String?
    var chatFailure: InferenceFailure?
    private var entered = false
    private var observer: CheckedContinuation<Void,Never>?
    private var waiter: CheckedContinuation<OllamaHTTPResponse,any Error>?
    private(set) var requests: [OllamaHTTPRequest] = []
    init(content: String = "{}") {
        chat = try! JSONSerialization.data(withJSONObject:["model":"qwen3:8b","message":["role":"assistant","content":content],"done":true,"done_reason":"stop","prompt_eval_count":10,"eval_count":10])
    }
    func configure(chat: Data? = nil, status: Int = 200, hold: Bool = false, foreign: Bool = false, version: String = "0.33.0", tagDigest: String = fixtureDigest, replacementDigest: String? = nil, chatFailure: InferenceFailure? = nil) {
        self.replacementDigest = replacementDigest; self.chatFailure = chatFailure
        if let chat { self.chat = chat }; self.status = status; self.hold = hold; self.foreign = foreign; self.version = version; self.tagDigest = tagDigest
    }
    func send(_ request: OllamaHTTPRequest) async throws -> OllamaHTTPResponse {
        requests.append(request)
        let object: [String:Any]
        switch request.route {
        case .version: object = ["version":version]
        case .tags: object = ["models":[["name":"qwen3:8b","digest":tagDigest,"size":5_225_388_164]]]
        case .show: object = ["capabilities":["completion","thinking"]]
        case .ps: object = ["models":foreign ? [["name":"foreign"]] : []]
        case .chat:
            if let replacementDigest { tagDigest = replacementDigest }
            if let chatFailure { throw chatFailure }
            entered = true; observer?.resume(); observer = nil
            if hold {
                return try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        if Task.isCancelled { continuation.resume(throwing:InferenceFailure.cancelled) } else { waiter = continuation }
                    }
                } onCancel: { Task { await self.abort() } }
            }
            return .init(status:status,body:chat)
        }
        return .init(body:try JSONSerialization.data(withJSONObject:object))
    }
    private func abort() { waiter?.resume(throwing:InferenceFailure.cancelled); waiter = nil }
    func waitUntilChat() async { if !entered { await withCheckedContinuation { observer = $0 } } }
}
private func makeProvider(_ t: ProviderTransport, memory: ProviderMemory = .init(), clock: ProviderClock = .init(), gate: OllamaLeaseGate = .init()) throws -> OllamaProvider {
    try .init(endpoint:OllamaEndpoint(),transport:t,memory:memory,clock:clock,gate:gate)
}
private func providerFailure(_ reason: InferenceFailure, _ body: () async throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) async {
    do { try await body(); Issue.record("Expected typed provider failure",sourceLocation:sourceLocation) }
    catch { #expect(error as? InferenceFailure == reason,sourceLocation:sourceLocation) }
}
@Suite(.serialized) struct ProviderTests {
    @Test(arguments:["https://127.0.0.1:11434","http://localhost:11434","http://example.com:11434","http://127.0.0.1:11434/","http://user:secret@127.0.0.1:11434","http://127.0.0.1:11434?host=cloud","http://[::1]:11434","file:///tmp/service"])
    func endpointRejection(_ url: String) { #expect(throws:InferenceFailure.endpointDenied) { try OllamaEndpoint(url) } }
    @Test func requestWireHasNoToolsAndNoDownloads() async throws {
        let t = ProviderTransport(), p = try makeProvider(t)
        let r = try await p.generate(basicRequest()); #expect(r.requestID == "request_1"); #expect(r.modelDigest == fixtureDigest)
        let requests = await t.requests; let request = try #require(requests.first { $0.route == .chat })
        let data = try #require(request.body)
        let object = try JSONSerialization.jsonObject(with:data)
        let body = try #require(object as? [String:Any])
        #expect(body["tools"] == nil); #expect(body["keep_alive"] as? Int == 0); #expect(body["stream"] as? Bool == false)
        #expect(body["think"] as? Bool == false); #expect(body["truncate"] as? Bool == false)
        let options = try #require(body["options"] as? [String:Int]); #expect(options["num_ctx"] == 4096); #expect(options["num_predict"] == 768)
        #expect(requests.allSatisfy { [OllamaRoute.version,.tags,.ps,.show,.chat].contains($0.route) })
    }
    @Test(arguments:[302,307,500,404]) func invalidStatus(_ status: Int) async throws {
        let t = ProviderTransport(); await t.configure(status:status); let p = try makeProvider(t)
        await providerFailure((300...399).contains(status) ? .redirectDenied : .invalidStatus) { _ = try await p.generate(basicRequest()) }
    }
    @Test(arguments:["garbage","{}","{\"model\":\"qwen3:8b\",\"message\":{\"role\":\"assistant\",\"content\":\"{}\",\"tool_calls\":[]},\"done\":true,\"done_reason\":\"stop\"}","{\"model\":\"qwen3:8b\",\"message\":{\"role\":\"assistant\",\"content\":\"{}\"},\"done\":false,\"done_reason\":\"stop\"}"])
    func invalidEnvelope(_ text: String) async throws {
        let t = ProviderTransport(); await t.configure(chat:Data(text.utf8)); let p = try makeProvider(t)
        await providerFailure(.invalidResponse) { _ = try await p.generate(basicRequest()) }
    }
    @Test func modelAndVersionMismatch() async throws {
        let t = ProviderTransport(); await t.configure(version:"0.34.0"); let p = try makeProvider(t)
        await providerFailure(.unsupportedVersion) { _ = try await p.generate(basicRequest()) }
        await t.configure(tagDigest:String(repeating:"b",count:64))
        await providerFailure(.modelIdentityMismatch) { _ = try await p.generate(basicRequest("request_2")) }
    }
    @Test func oversizedResponse() async throws {
        let t = ProviderTransport(); await t.configure(chat:Data(repeating:65,count:131_073)); let p = try makeProvider(t)
        await providerFailure(.oversized) { _ = try await p.generate(basicRequest()) }
    }
    @Test func memoryAdmissionAndForeignResidencyPreventChat() async throws {
        let t = ProviderTransport(), memory = ProviderMemory(); await memory.set(.init(conservativeAvailableBytes:1,pressureNormal:true))
        let p = try makeProvider(t,memory:memory)
        await providerFailure(.memoryAdmissionDenied) { _ = try await p.generate(basicRequest()) }
        #expect(await t.requests.allSatisfy { $0.route != .chat })
        await t.configure(foreign:true)
        await providerFailure(.busy) { _ = try await p.generate(basicRequest("request_2")) }
    }
    @Test func cancellationBeforeSending() async throws {
        let t = ProviderTransport(), p = try makeProvider(t)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; await providerFailure(.cancelled) { _ = try await p.generate(basicRequest()) } }
        await task.value; #expect(await t.requests.isEmpty)
    }
    @Test func activeCancellationQuarantineAndAnotherRequest() async throws {
        let t = ProviderTransport(); await t.configure(hold:true); let p = try makeProvider(t)
        let task = Task { try await p.generate(basicRequest()) }; await t.waitUntilChat()
        #expect(await p.cancel(requestID:"request_1") == .httpCancelledProviderUncertain)
        await providerFailure(.cancelled) { _ = try await task.value }
        await providerFailure(.quarantined) { _ = try await p.generate(basicRequest("request_2")) }
        #expect(try await p.reconcile() == .residencyAbsent)
        await t.configure(); _ = try await p.generate(basicRequest("request_3"))
    }
    @Test func timeoutUsesControlledClock() async throws {
        let t = ProviderTransport(), clock = ProviderClock(); await t.configure(hold:true); let p = try makeProvider(t,clock:clock)
        let task = Task { try await p.generate(basicRequest(deadline:2000)) }; await t.waitUntilChat(); await clock.waitForSleep(2000); await clock.advance(2000)
        await providerFailure(.timeout) { _ = try await task.value }
    }
    @Test func concurrentInstancesShareOneLease() async throws {
        let t = ProviderTransport(), gate = OllamaLeaseGate(); await t.configure(hold:true)
        let a = try makeProvider(t,gate:gate), b = try makeProvider(ProviderTransport(),gate:gate)
        let task = Task { try await a.generate(basicRequest()) }; await t.waitUntilChat()
        await providerFailure(.busy) { _ = try await b.generate(basicRequest("second")) }
        _ = await a.cancel(requestID:"request_1"); await providerFailure(.cancelled) { _ = try await task.value }
    }
    @Test func pressureCancelsOwnedGeneration() async throws {
        let t = ProviderTransport(), clock = ProviderClock(), memory = ProviderMemory(); await t.configure(hold:true)
        let p = try makeProvider(t,memory:memory,clock:clock), task = Task { try await p.generate(basicRequest()) }
        await t.waitUntilChat(); await clock.waitForSleep(2000); await memory.set(.init(conservativeAvailableBytes:1,pressureNormal:false)); await clock.advance(2000)
        await providerFailure(.memoryPressure) { _ = try await task.value }
    }
    @Test func shutdownIsIdempotentAndRejectsNewWork() async throws {
        let t = ProviderTransport(); await t.configure(hold:true); let p = try makeProvider(t)
        let task = Task { try await p.generate(basicRequest()) }; await t.waitUntilChat()
        #expect(await p.shutdown() == .httpCancelledProviderUncertain); _ = await p.shutdown()
        await providerFailure(.cancelled) { _ = try await task.value }
        await providerFailure(.cancelled) { _ = try await p.generate(basicRequest("after_shutdown")) }
    }
}

private func generationContext(allowed: Set<String> = ["Sources/New.swift"]) throws -> ProposalValidationContext {
    let project = try ProjectIdentifier("66666666-6666-4666-8666-666666666666"), proposal = try ProposalIdentifier("77777777-7777-4777-8777-777777777777")
    let snapshot = try ProposalHashing.snapshot(projectID:project,entries:[.init(relativePath:"Sources/New.swift",fileRevision:.absent,fileState:.absent)])
    return .init(expectedProposalID:proposal,expectedProjectID:project,expectedSnapshotDigest:snapshot.snapshotDigest,snapshot:snapshot,editableTargets:allowed,policyRevision:"synthetic-1",expectedPolicyRevision:"synthetic-1",now:1000,deadline:121000)
}
private func generationProposal(_ context: ProposalValidationContext) -> CodingProposal {
    .init(proposalID:context.expectedProposalID,projectID:context.expectedProjectID,baseSnapshotDigest:context.expectedSnapshotDigest,
          changes:[.create(relativePath:"Sources/New.swift",expectedRevision:.absent,utf8Content:"func value() -> Int { 1 }\n")])
}
private actor GenerationHistory: TaskHistoryRepository {
    var records: [TaskIdentifier:TaskRecord] = [:]
    var log: [TaskIdentifier:[TaskEventRecord]] = [:]
    func load() -> [TaskRecord] { Array(records.values) }
    func events(for id: TaskIdentifier) -> [TaskEventRecord] { log[id,default:[]] }
    func commit(_ record: TaskRecord,event: TaskEventRecord,expectedSequence: Int?) throws {
        guard records[record.plan.id]?.sequence == expectedSequence else { throw TaskServiceError.repositoryConflict }
        records[record.plan.id] = record; log[record.plan.id,default:[]].append(event)
    }
}
private actor NoGenerationVerifier: TaskVerificationRunner {
    func verify(_ operation: ScopedOperation,token: OperationToken) throws -> VerificationEvidence { throw TaskServiceError.unsupportedOperation }
    func cancel(_ token: OperationToken) -> CancellationAcknowledgement { .stopped }
}
@Suite(.serialized) struct ProposalGenerationTests {
    @Test func schemaAndStrictProposalValidation() async throws {
        let context = try generationContext(), expected = generationProposal(context)
        let t = ProviderTransport(content:String(decoding:try CodingProposalCodec.encode(expected),as:UTF8.self)), clock = ProviderClock()
        let p = try makeProvider(t,clock:clock), generator = ProposalGenerator(provider:p,context:context,clock:clock)
        let request = try ProposalGenerator.makeRequest(id:"proposal_1",model:providerModel(),taskInstruction:"Create Sources/New.swift with a value function",syntheticContext:"All content here is synthetic",context:context,deadline:121000)
        let result = try await generator.prepare(request)
        #expect(result.proposal == expected); #expect(result.validation.baseSnapshotDigest == context.expectedSnapshotDigest)
        let schemaValue = try JSONSerialization.jsonObject(with:Data(request.outputSchema.utf8)); let schema = try #require(schemaValue as? [String:Any]); #expect(schema["additionalProperties"] as? Bool == false)
    }
    @Test(arguments:["{}","{\"command\":\"sh\"}","not JSON"])
    func malformedGeneratedProposals(_ content: String) async throws {
        let context = try generationContext(), t = ProviderTransport(content:content), clock = ProviderClock()
        let g = ProposalGenerator(provider:try makeProvider(t,clock:clock),context:context,clock:clock)
        let request = try ProposalGenerator.makeRequest(id:"proposal_1",model:providerModel(),taskInstruction:"Create Sources/New.swift",syntheticContext:"synthetic",context:context,deadline:121000)
        do { _ = try await g.prepare(request); Issue.record("Unvalidated output escaped") }
        catch { guard case .proposalRejected = error as? InferenceFailure else { Issue.record("Wrong failure class"); return } }
    }
    @Test func unsupportedOperationAndUnapprovedTargetsFail() async throws {
        for (content, allowed) in [("{\"schemaVersion\":1,\"changes\":[{\"kind\":\"delete\"}]}",Set(["Sources/New.swift"])),
                                  ("valid",Set<String>())] {
            let context = try generationContext(allowed:allowed), text = content == "valid" ? String(decoding:try CodingProposalCodec.encode(generationProposal(context)),as:UTF8.self) : content
            let t = ProviderTransport(content:text), clock = ProviderClock()
            let g = ProposalGenerator(provider:try makeProvider(t,clock:clock),context:context,clock:clock)
            let request = try ProposalGenerator.makeRequest(id:"proposal",model:providerModel(),taskInstruction:"Synthetic request",syntheticContext:"synthetic",context:context,deadline:121000)
            do { _ = try await g.prepare(request); Issue.record("Unauthorized proposal accepted") }
            catch { guard case .proposalRejected = error as? InferenceFailure else { Issue.record("Wrong failure class"); return } }
        }
    }
    @Test @MainActor func existingCoordinatorOwnsApprovalIntentAndProposalResult() async throws {
        let context = try generationContext(), t = ProviderTransport(content:String(decoding:try CodingProposalCodec.encode(generationProposal(context)),as:UTF8.self)), clock = ProviderClock()
        let provider = try makeProvider(t,clock:clock), generator = ProposalGenerator(provider:provider,context:context,clock:clock)
        let request = try ProposalGenerator.makeRequest(id:"coordinator_proposal",model:providerModel(),taskInstruction:"Create Sources/New.swift",syntheticContext:"synthetic",context:context,deadline:121000)
        let operation = ScopedOperation(id:"prepare",kind:.inspection,digest:ProposalHashing.content(request.systemInstruction+request.syntheticUserContent+request.outputSchema),workspaceID:context.expectedProjectID.rawValue,revision:context.expectedSnapshotDigest)
        let id = TaskIdentifier(rawValue:"proposal_task"), executor = try ProposalTaskExecutor(taskID:id,operation:operation,request:request,service:generator)
        let history = GenerationHistory(), pair = PermissionBroker.compose(clock:clock)
        let coordinator = TaskCoordinator(history:history,policy:pair.policy,executor:executor,verifier:NoGenerationVerifier(),clock:clock)
        try await coordinator.start()
        try await coordinator.submit(TaskPlan(id:id,workspaceID:operation.workspaceID,revision:operation.revision,steps:[operation]))
        let waiting = try await coordinator.waitForState(id,.awaitingApproval)
        #expect(await t.requests.isEmpty)
        try await pair.authority.approve(try #require(waiting.pendingApproval).id); try await coordinator.resumeApproval(id)
        #expect(try await coordinator.waitForState(id,.succeeded).lifecycle.state == .succeeded)
        #expect(await executor.takePreparedProposal()?.proposal.changes.count == 1)
        #expect(await executor.takePreparedProposal() == nil)
        let events = await history.events(for:id), kinds = events.map(\.kind)
        let approvalIndex = try #require(kinds.firstIndex(of:.approvalGranted)), intentIndex = try #require(kinds.firstIndex(of:.intent))
        #expect(approvalIndex < intentIndex)
        #expect(kinds.contains(.outcome)); #expect((await history.load()).first?.plan.revision == context.expectedSnapshotDigest)
        await coordinator.shutdown()
    }
}

private struct UnavailableProviderTransport: OllamaHTTPTransport {
    func send(_ request: OllamaHTTPRequest) throws -> OllamaHTTPResponse { throw URLError(.cannotConnectToHost) }
}
@Suite(.serialized) struct ProviderBoundaryTests {
    @Test func unavailableIsTypedAndNoAutomaticStart() async throws {
        let p = try OllamaProvider(endpoint:OllamaEndpoint(),transport:UnavailableProviderTransport(),memory:ProviderMemory(),clock:ProviderClock(),gate:OllamaLeaseGate())
        await providerFailure(.unavailable) { _ = try await p.generate(basicRequest()) }
        await providerFailure(.unavailable) { _ = try await p.discover() }
    }
    @Test(arguments:["model","thinking","length","negative","huge"])
    func envelopeIdentityAndMetricBoundaries(_ variant: String) async throws {
        var message: [String:Any] = ["role":"assistant","content":"{}"]
        if variant == "thinking" { message["thinking"] = "unrequested chain" }
        let body: [String:Any] = ["model":variant == "model" ? "foreign" : "qwen3:8b","message":message,"done":true,"done_reason":variant == "length" ? "length" : "stop","prompt_eval_count":variant == "negative" ? -1 : variant == "huge" ? Int.max : 10,"eval_count":10]
        let t = ProviderTransport(); await t.configure(chat:try JSONSerialization.data(withJSONObject:body)); let p = try makeProvider(t)
        await providerFailure(variant == "model" ? .modelIdentityMismatch : .invalidResponse) { _ = try await p.generate(basicRequest()) }
    }
    @Test func requestBoundsAndRepeatIDs() async throws {
        #expect(throws:InferenceFailure.invalidRequest) { try InferenceRequest(id:"bad id",model:providerModel(),systemInstruction:"s",syntheticUserContent:"u",outputSchema:"{}",deadline:1) }
        #expect(throws:InferenceFailure.invalidRequest) { try InferenceRequest(id:"id",model:providerModel(),systemInstruction:String(repeating:"x",count:5000),syntheticUserContent:"u",outputSchema:"{}",deadline:1) }
        #expect(throws:InferenceFailure.invalidRequest) { try OllamaHTTPRequest(endpoint:OllamaEndpoint(),route:.chat,body:Data(repeating:0,count:16385)) }
        #expect(throws:InferenceFailure.invalidRequest) { try OllamaHTTPRequest(endpoint:OllamaEndpoint(),route:.ps,body:Data()) }
        let p = try makeProvider(ProviderTransport()); _ = try await p.generate(basicRequest())
        await providerFailure(.invalidRequest) { _ = try await p.generate(basicRequest()) }
    }
    @Test func domainDescriptorIsProviderIndependent() throws {
        let descriptor = try ModelDescriptor(name:"alternate-local:1b",digest:fixtureDigest,storedBytes:500_000_000,capabilities:.init(structuredOutput:true,maximumContext:2048))
        #expect(descriptor.name == "alternate-local:1b")
    }
    @Test func declaredModelContextLimitIsEnforced() throws {
        let model = try ModelDescriptor(name:"qwen3:8b",digest:fixtureDigest,storedBytes:5_225_388_164,capabilities:.init(structuredOutput:true,maximumContext:2048))
        #expect(throws:InferenceFailure.invalidRequest) { try InferenceRequest(id:"context",model:model,systemInstruction:"s",syntheticUserContent:"u",outputSchema:"{}",deadline:121000,contextTokens:4096) }
    }
    @Test func staleExecutorGenerationCannotPrepareOrCancel() async throws {
        let context = try generationContext(), t = ProviderTransport(), clock = ProviderClock()
        let request = try ProposalGenerator.makeRequest(id:"scope",model:providerModel(),taskInstruction:"synthetic",syntheticContext:"synthetic",context:context,deadline:121000)
        let service = ProposalGenerator(provider:try makeProvider(t),context:context,clock:clock)
        let op = ScopedOperation(id:"inspect",kind:.inspection,digest:fixtureDigest,workspaceID:"fixture",revision:fixtureDigest)
        let executor = try ProposalTaskExecutor(taskID:.init(rawValue:"owner"),operation:op,request:request,generation:2,service:service)
        let stale = OperationToken(taskID:.init(rawValue:"owner"),operationID:op.id,generation:1)
        #expect(await executor.cancel(stale) == .uncertain)
        do { _ = try await executor.execute(op,token:stale); Issue.record("Stale generation accepted") }
        catch { #expect(error as? TaskServiceError == .staleOperation) }
        #expect(await t.requests.isEmpty)
    }
    @Test func expiredRequestNeverChats() async throws {
        let t = ProviderTransport(), p = try makeProvider(t)
        await providerFailure(.timeout) { _ = try await p.generate(basicRequest(deadline:999)) }
        #expect(await t.requests.isEmpty)
    }
    @Test func runtimePressureSwapGrowthIsBounded() async throws {
        let t = ProviderTransport(), clock = ProviderClock(), memory = ProviderMemory(); await t.configure(hold:true)
        let p = try makeProvider(t,memory:memory,clock:clock), task = Task { try await p.generate(basicRequest()) }
        await t.waitUntilChat(); await clock.waitForSleep(2000)
        await memory.set(.init(conservativeAvailableBytes:16_000_000_000,pressureNormal:true,swapUsedBytes:300_000_000))
        await clock.advance(2000); await clock.waitForSleep(3000); await clock.advance(3000)
        await providerFailure(.memoryPressure) { _ = try await task.value }
    }
    @Test func modelReplacementAfterGenerationRejectsResult() async throws {
        let t = ProviderTransport(); await t.configure(replacementDigest:String(repeating:"b",count:64)); let p = try makeProvider(t)
        await providerFailure(.modelIdentityMismatch) { _ = try await p.generate(basicRequest()) }
        await providerFailure(.quarantined) { _ = try await p.generate(basicRequest("next")) }
    }
    @Test func generationConnectionDropIsTypedAndQuarantined() async throws {
        let t = ProviderTransport(); await t.configure(chatFailure:.unavailable); let p = try makeProvider(t)
        await providerFailure(.unavailable) { _ = try await p.generate(basicRequest()) }
        await providerFailure(.quarantined) { _ = try await p.generate(basicRequest("next")) }
    }
    @Test func cancellingCallerTaskCancelsOwnedHTTP() async throws {
        let t = ProviderTransport(); await t.configure(hold:true); let p = try makeProvider(t)
        let task = Task { try await p.generate(basicRequest()) }; await t.waitUntilChat(); task.cancel()
        await providerFailure(.cancelled) { _ = try await task.value }
        await providerFailure(.quarantined) { _ = try await p.generate(basicRequest("next")) }
    }
    @Test func operationEffectsRemainUnsupported() async throws {
        let context = try generationContext(), t = ProviderTransport(), clock = ProviderClock()
        let request = try ProposalGenerator.makeRequest(id:"none",model:providerModel(),taskInstruction:"synthetic",syntheticContext:"synthetic",context:context,deadline:121000)
        let service = ProposalGenerator(provider:try makeProvider(t),context:context,clock:clock)
        #expect(throws:TaskServiceError.unsupportedOperation) { try ProposalTaskExecutor(taskID:.init(rawValue:"task"),operation:.init(id:"write",kind:.fileWrite,digest:fixtureDigest,workspaceID:"fixture",revision:fixtureDigest),request:request,service:service) }
        #expect(await t.requests.isEmpty)
    }
}
