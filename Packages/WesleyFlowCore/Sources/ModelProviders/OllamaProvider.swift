import Domain
import Foundation

actor OllamaLeaseGate {
    static let shared = OllamaLeaseGate()
    private var owner: String?
    private var uncertain = false
    func acquire(_ id: String) throws { guard !uncertain else { throw InferenceFailure.quarantined }; guard owner == nil else { throw InferenceFailure.busy }; owner = id }
    func release(_ id: String) { if owner == id { owner = nil; uncertain = false } }
    func quarantine(_ id: String) { if owner == id { uncertain = true } }
}
/// One WF lease globally; a shared daemon can still receive foreign requests outside this process.
public actor OllamaProvider: LocalModelProvider {
    private let endpoint: OllamaEndpoint
    private let transport: any OllamaHTTPTransport
    private let memory: any InferenceMemorySource
    private let clock: any TaskClock
    private let gate: OllamaLeaseGate
    private let owner = UUID().uuidString
    private var usedIDs: Set<String> = []
    private var activeID: String?
    private var sent = false
    private var stopped = false
    private var uncertain = false
    private var baselineSwap: UInt64 = 0
    private var failure: InferenceFailure?
    private var work: Task<OllamaHTTPResponse, any Error>?
    private var monitor: Task<Void, Never>?
    public init(endpoint: OllamaEndpoint, transport: any OllamaHTTPTransport, memory: any InferenceMemorySource, clock: any TaskClock) {
        self.endpoint = endpoint; self.transport = transport; self.memory = memory; self.clock = clock; gate = .shared
    }
    init(endpoint: OllamaEndpoint, transport: any OllamaHTTPTransport, memory: any InferenceMemorySource, clock: any TaskClock, gate: OllamaLeaseGate) {
        self.endpoint = endpoint; self.transport = transport; self.memory = memory; self.clock = clock; self.gate = gate
    }
    private struct Version: Decodable { let version: String }
    private struct Tag: Decodable { let name: String; let digest: String; let size: Int64 }
    private struct Tags: Decodable { let models: [Tag] }
    private struct Residents: Decodable { let models: [Resident] }
    private struct Resident: Decodable { let name: String }
    private struct Show: Decodable { let capabilities: [String]?; let remote_host: String?; let remote_model: String? }
    private struct Message: Decodable {
        let role: String; let content: String; let thinking: String?
        let tool_calls: [DiscardedTool]?; let images: [String]?; let tool_name: String?; let tool_call_id: String?
    }
    private struct DiscardedTool: Decodable {}
    private struct Chat: Decodable {
        let model: String; let message: Message; let done: Bool; let done_reason: String?
        let total_duration: Int64?; let load_duration: Int64?; let prompt_eval_count: Int?; let eval_count: Int?
    }
    private func exchange(_ route: OllamaRoute, object: [String: Any]? = nil, seconds: Double = 5) async throws -> OllamaHTTPResponse {
        let body = try object.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        let response: OllamaHTTPResponse
        do { response = try await transport.send(.init(endpoint: endpoint, route: route, body: body, timeoutSeconds: seconds)) }
        catch let error as InferenceFailure { throw error }
        catch { throw Task.isCancelled ? InferenceFailure.cancelled : .unavailable }
        guard !Task.isCancelled else { throw InferenceFailure.cancelled }
        guard response.body.count <= 131_072 else { throw InferenceFailure.oversized }
        guard !(300...399).contains(response.status) else { throw InferenceFailure.redirectDenied }
        guard response.status != 404 else { throw InferenceFailure.modelMissing }
        guard response.status == 200 else { throw InferenceFailure.invalidStatus }
        return response
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw InferenceFailure.invalidResponse }
    }
    public func discover() async throws -> [ModelDescriptor] {
        let v = try decode(Version.self, try await exchange(.version).body)
        guard v.version == "0.33.0" else { throw InferenceFailure.unsupportedVersion }
        let tags = try decode(Tags.self, try await exchange(.tags).body)
        guard tags.models.count <= 32, Set(tags.models.map(\.name)).count == tags.models.count else { throw InferenceFailure.invalidResponse }
        return try tags.models.filter { ["qwen3:8b", "qwen2.5-coder:7b"].contains($0.name) }.map {
            guard (4_000_000_000...6_442_450_944).contains($0.size) else { throw InferenceFailure.invalidResponse }
            return try ModelDescriptor(name: $0.name, digest: $0.digest, storedBytes: $0.size, capabilities: .init(structuredOutput: true, maximumContext: 4096))
        }
    }
    private func check(_ request: InferenceRequest) async throws {
        let now = await clock.now()
        guard !Task.isCancelled else { throw InferenceFailure.cancelled }
        if let failure { throw failure }
        guard !stopped, activeID == request.id else { throw InferenceFailure.cancelled }
        guard now >= 0, now < request.deadline else { throw InferenceFailure.timeout }
    }
    public func generate(_ request: InferenceRequest) async throws -> InferenceResponse {
        guard !Task.isCancelled, !stopped else { throw InferenceFailure.cancelled }
        guard activeID == nil else { throw InferenceFailure.busy }
        guard !uncertain else { throw InferenceFailure.quarantined }
        // Acquire before the first provider await; every later await is revalidated.
        guard !usedIDs.contains(request.id), usedIDs.count < 64 else { throw InferenceFailure.invalidRequest }
        usedIDs.insert(request.id)
        activeID = request.id; sent = false; failure = nil
        do { try await gate.acquire(owner) } catch { activeID = nil; throw error }
        var finished = false
        do {
            try await check(request)
            let now = await clock.now(); try await check(request)
            guard request.deadline - now <= 120_000 else { throw InferenceFailure.invalidRequest }
            let available = try await discover(); try await check(request)
            guard available.contains(where: { $0 == request.model }) else { throw InferenceFailure.modelIdentityMismatch }
            let ps = try decode(Residents.self, try await exchange(.ps).body); try await check(request)
            guard ps.models.isEmpty else { throw InferenceFailure.busy }
            let show = try decode(Show.self, try await exchange(.show, object: ["model":request.model.name]).body); try await check(request)
            guard show.capabilities?.contains("completion") == true, (show.remote_host ?? "").isEmpty, (show.remote_model ?? "").isEmpty else { throw InferenceFailure.modelIdentityMismatch }
            let sample = try await memory.sample(); try await check(request)
            // Weights + 2GiB KV/load/scratch estimate + 4GiB minimum headroom. Never count swap as admission capacity.
            baselineSwap = sample.swapUsedBytes
            guard sample.pressureNormal, sample.conservativeAvailableBytes >= UInt64(request.model.storedBytes) + 6_442_450_944 else { throw InferenceFailure.memoryAdmissionDenied }
            guard let schema = try? JSONSerialization.jsonObject(with: Data(request.outputSchema.utf8)) as? [String: Any] else { throw InferenceFailure.invalidRequest }
            let object: [String: Any] = ["model": request.model.name, "messages": [["role":"system","content":request.systemInstruction + "\nRequired JSON schema:\n" + request.outputSchema], ["role":"user","content":request.syntheticUserContent]], "format":schema,
                "stream":false,"think":false,"truncate":false,"shift":false,"keep_alive":0,
                "options":["temperature":0,"seed":42,"num_ctx":request.contextTokens,"num_predict":request.outputTokens]]
            let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let remaining = request.deadline - (await clock.now()); try await check(request)
            let http = try OllamaHTTPRequest(endpoint: endpoint, route: .chat, body: body, timeoutSeconds: Double(remaining) / 1000)
            // Bound to this actor's request; no credentials, tools, model pulls or executable data paths.
            sent = true
            let transport = self.transport
            let task = Task { try await transport.send(http) }; work = task
            monitor = Task { await self.watch(request) }
            let response = try await withTaskCancellationHandler { try await task.value } onCancel: { Task { _ = await self.cancel(requestID: request.id) } }
            try await check(request)
            guard response.body.count <= http.responseLimit else { throw InferenceFailure.oversized }
            guard !(300...399).contains(response.status) else { throw InferenceFailure.redirectDenied }
            guard response.status == 200 else { throw InferenceFailure.invalidStatus }
            let chat = try decode(Chat.self, response.body)
            guard chat.model == request.model.name else { throw InferenceFailure.modelIdentityMismatch }
            guard chat.done, chat.done_reason == "stop", chat.message.role == "assistant", chat.message.tool_calls == nil,
                  chat.message.images == nil, chat.message.tool_name == nil, chat.message.tool_call_id == nil,
                  (chat.message.thinking ?? "").isEmpty, !chat.message.content.isEmpty,
                  chat.message.content.utf8.count <= 65_536 else { throw InferenceFailure.invalidResponse }
            let metrics = InferenceMetrics(totalNanoseconds: chat.total_duration ?? 0, loadNanoseconds: chat.load_duration ?? 0, promptTokens: chat.prompt_eval_count ?? 0, generatedTokens: chat.eval_count ?? 0)
            guard metrics.totalNanoseconds >= 0, metrics.loadNanoseconds >= 0, metrics.promptTokens >= 0, metrics.generatedTokens >= 0,
                  metrics.promptTokens <= request.contextTokens, metrics.generatedTokens <= request.outputTokens,
                  metrics.promptTokens + metrics.generatedTokens <= request.contextTokens else { throw InferenceFailure.invalidResponse }
            let observed = try await discover(); try await check(request)
            guard observed.contains(request.model) else { throw InferenceFailure.modelIdentityMismatch }
            let result = InferenceResponse(requestID: request.id, modelDigest: request.model.digest, content: chat.message.content, metrics: metrics)
            try await check(request)
            await finish(uncertain: false); finished = true
            try await check(request)
            activeID = nil
            return result
        } catch {
            let mapped = failure ?? (error as? InferenceFailure ?? (error is CancellationError ? .cancelled : .unavailable))
            if !finished { await finish(uncertain: sent) }
            activeID = nil
            throw mapped
        }
    }
    private func watch(_ request: InferenceRequest) async {
        var swapWarnings = 0
        while activeID == request.id && !Task.isCancelled {
            do {
                let now = await clock.now(); try await clock.sleep(until: now + min(1000, max(0, request.deadline - now)))
                guard !Task.isCancelled, activeID == request.id else { return }
                let current = await clock.now()
                if current >= request.deadline { failure = .timeout; work?.cancel(); return }
                let sample = try await memory.sample()
                guard activeID == request.id, !Task.isCancelled else { return }
                swapWarnings = sample.swapUsedBytes > baselineSwap && sample.swapUsedBytes - baselineSwap > 268_435_456 ? swapWarnings + 1 : 0
                if !sample.pressureNormal || sample.conservativeAvailableBytes < 4_294_967_296 || swapWarnings >= 2 { failure = .memoryPressure; work?.cancel(); return }
            } catch { if !Task.isCancelled { failure = .memoryPressure; work?.cancel() }; return }
        }
    }
    private func finish(uncertain failed: Bool) async {
        monitor?.cancel(); monitor = nil; work = nil
        if !sent { await gate.release(owner) }
        else {
            // A successful done frame ends this response, but residency still needs independent observation.
            let absent = (try? decode(Residents.self, try await exchange(.ps).body).models.isEmpty) == true
            if absent && !failed { await gate.release(owner) }
            else { uncertain = true; await gate.quarantine(owner) }
        }
    }
    public func cancel(requestID: String) -> InferenceCancellation {
        guard activeID == requestID else { return uncertain ? .httpCancelledProviderUncertain : .notSent }
        failure = .cancelled; work?.cancel()
        return sent ? .httpCancelledProviderUncertain : .notSent
    }
    public func reconcile() async throws -> InferenceCancellation {
        guard activeID == nil else { throw InferenceFailure.busy }
        guard uncertain else { return .completed }
        let ps = try decode(Residents.self, try await exchange(.ps).body)
        guard activeID == nil, ps.models.isEmpty else { return .httpCancelledProviderUncertain }
        await gate.release(owner); uncertain = false
        return .residencyAbsent // Observable sample, not proof of global daemon idleness or memory zeroization.
    }
    public func shutdown() -> InferenceCancellation { stopped = true; if let id = activeID { return cancel(requestID: id) }; return uncertain ? .httpCancelledProviderUncertain : .notSent }
}
