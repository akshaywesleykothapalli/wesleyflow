import Domain
import ModelProviders
import Workspace
import SystemOperations
import Foundation
import Darwin

private struct EvaluationCase: Codable {
    let id: String; let category: String; let instruction: String; let path: String
    let operation: String; let existing: Bool; let expectRejection: Bool
}
private actor EvaluationTransport: OllamaHTTPTransport {
    private let base = LocalOllamaHTTPTransport()
    private var counts: [String:Int] = [:]
    private var last: Data?
    func send(_ request: OllamaHTTPRequest) async throws -> OllamaHTTPResponse {
        guard counts.values.reduce(0,+) < 512 else { throw InferenceFailure.invalidRequest }
        counts[request.route.rawValue,default:0] += 1
        let response = try await base.send(request)
        if request.route == .chat { last = response.body }
        return response
    }
    func clear() { last = nil }
    func response() -> Data? { last }
    func requestCounts() -> [String:Int] { counts }
}
private struct Row: Codable {
    let caseID: String; let category: String; let model: String; let state: String; let reason: String?
    let elapsedSeconds: Double?; let validJSON: Bool?; let schemaValid: Bool?; let validated: Bool?
    let correctFile: Bool?; let correctOperation: Bool?; let correctRevision: Bool?; let expectedOutcome: Bool?
}
private func elapsed(_ from: ContinuousClock.Instant) -> Double {
    let c = from.duration(to:.now).components; return Double(c.seconds)+Double(c.attoseconds)/1e18
}
@main struct OllamaEvaluation {
    static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe-transport" {
            do {
                let response = try await LocalOllamaHTTPTransport().send(.init(endpoint:OllamaEndpoint(CommandLine.arguments[2]),route:.version,timeoutSeconds:0.5,responseLimit:128))
                print("transportStatus=\(response.status);bytes=\(response.body.count)")
            } catch { print("transportFailure=\(error)") }
            return
        }
        guard CommandLine.arguments.count == 2 else { throw InferenceFailure.invalidRequest }
        let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let corpusURL = Bundle.module.url(forResource:"Corpus",withExtension:"json")!
        let corpus = try JSONDecoder().decode([EvaluationCase].self,from:Data(contentsOf:corpusURL))
        guard corpus.count == 20 else { throw InferenceFailure.invalidRequest }
        let memory = SystemInferenceMemory(), clock = SystemTaskClock(), transport = EvaluationTransport()
        let provider = try OllamaProvider(endpoint:OllamaEndpoint(),transport:transport,memory:memory,clock:clock)
        Darwin.signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal:SIGINT,queue:.global())
        interrupt.setEventHandler { Task { _ = await provider.shutdown() } }; interrupt.resume()
        defer { interrupt.cancel() }
        let baseline = try memory.sample(), models = try await provider.discover()
        let pins = ["qwen3:8b":"500a1f067a9f782620b40bee6f7b0c89e17ae61f686b92c24933e4ca4b2b8b41", "qwen2.5-coder:7b":"dae161e27b0e90dd1856c8bb3209201fd6736d8eb66298e75ed87571486f4364"]
        guard models.count == 2, models.allSatisfy({ pins[$0.name] == $0.digest }) else { throw InferenceFailure.modelIdentityMismatch }
        var rows: [Row] = []; var stopReason: String?
        for (modelIndex,model) in models.enumerated() {
            var blocked = stopReason
            for (index,item) in corpus.enumerated() {
                let project = try ProjectIdentifier("88888888-8888-4888-8888-888888888888")
                let proposalID = try ProposalIdentifier(String(format:"99999999-9999-4999-8999-%012d",index))
                let revision: ExpectedFileRevision = item.existing ? .sha256(ProposalHashing.content("func old() -> Int { 0 }\n")) : .absent
                let snapshot = try ProposalHashing.snapshot(projectID:project,entries:[.init(relativePath:item.path,fileRevision:revision,fileState:item.existing ? .regular : .absent),.init(relativePath:"Sources/Decoy.swift",fileRevision:.absent,fileState:.absent)])
                let now = await clock.now(), deadline = now + 120_000
                let context = ProposalValidationContext(expectedProposalID:proposalID,expectedProjectID:project,expectedSnapshotDigest:snapshot.snapshotDigest,snapshot:snapshot,
                    editableTargets:item.expectRejection ? [] : [item.path,"Sources/Decoy.swift"],policyRevision:"frozen-synthetic-1",expectedPolicyRevision:"frozen-synthetic-1",now:now,deadline:deadline)
                let request = try ProposalGenerator.makeRequest(id:"eval_\(modelIndex)_\(index)",model:model,taskInstruction:item.instruction,syntheticContext:item.existing ? "Synthetic existing file contains func old() -> Int { 0 }; Decoy.swift is absent." : "Both files are absent. All filenames and content are synthetic.",context:context,deadline:deadline)
                if let blocked {
                    rows.append(.init(caseID:item.id,category:item.category,model:model.name,state:"BLOCKED",reason:blocked,elapsedSeconds:nil,validJSON:nil,schemaValid:nil,validated:nil,correctFile:nil,correctOperation:nil,correctRevision:nil,expectedOutcome:nil));continue
                }
                await transport.clear()
                let start = ContinuousClock.now
                let generator = ProposalGenerator(provider:provider,context:context,clock:clock)
                var prepared: PreparedProposal?; var reason: String?
                do { prepared = try await generator.prepare(request) }
                catch {
                    reason = String(describing:error)
                    switch error as? InferenceFailure {
                    case .memoryAdmissionDenied: blocked = "memoryAdmissionDenied"
                    case .proposalRejected: break
                    default: blocked = reason; stopReason = reason
                    }
                }
                let raw = await transport.response()
                var jsonValid = false; var schemaValid = false; var parsed: CodingProposal?
                if let raw {
                    try raw.write(to:output.appendingPathComponent("\(modelIndex)-\(item.id)-synthetic-response.json"))
                    if let outer = try? JSONSerialization.jsonObject(with:raw) as? [String:Any], let message = outer["message"] as? [String:Any], let text = message["content"] as? String {
                        jsonValid = (try? JSONSerialization.jsonObject(with:Data(text.utf8))) != nil
                        parsed = try? CodingProposalCodec.decode(Array(text.utf8)); schemaValid = parsed?.proposalID == context.expectedProposalID && parsed?.projectID == context.expectedProjectID && parsed?.baseSnapshotDigest == context.expectedSnapshotDigest && parsed?.changes.allSatisfy({ [item.path,"Sources/Decoy.swift"].contains($0.relativePath) }) == true
                    }
                }
                let first = parsed?.changes.first
                let correctFile = parsed?.changes.count == 1 && first?.relativePath == item.path
                let correctOperation = first?.kind == item.operation, correctRevision = first?.expectedRevision == revision
                let validated = prepared != nil
                let outcome = item.expectRejection ? (!validated && reason?.hasPrefix("proposalRejected") == true) : (validated && correctFile && correctOperation && correctRevision)
                rows.append(.init(caseID:item.id,category:item.category,model:model.name,state:raw == nil && blocked != nil ? "BLOCKED" : "TESTED",reason:reason,elapsedSeconds:elapsed(start),validJSON:raw == nil ? nil : jsonValid,schemaValid:raw == nil ? nil : schemaValid,validated:raw == nil ? nil : validated,correctFile:raw == nil ? nil : correctFile,correctOperation:raw == nil ? nil : correctOperation,correctRevision:raw == nil ? nil : correctRevision,expectedOutcome:raw == nil ? nil : outcome))
            }
        }
        let final = try memory.sample()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(rows).write(to:output.appendingPathComponent("results.json"))
        let counts = await transport.requestCounts()
        let summary: [String:Any] = ["corpusTasks":corpus.count,"models":models.map(\.name),"requestCounts":counts,"chatRequests":counts["chat",default:0],
            "baselineAvailableBytes":baseline.conservativeAvailableBytes,"baselineSwapUsedBytes":baseline.swapUsedBytes,"baselinePressureNormal":baseline.pressureNormal,
            "finalAvailableBytes":final.conservativeAvailableBytes,"finalSwapUsedBytes":final.swapUsedBytes,"finalPressureNormal":final.pressureNormal,
            "testedCases":rows.filter { $0.state == "TESTED" }.count,"blockedCases":rows.filter { $0.state == "BLOCKED" }.count,
            "contextTokens":4096,"outputTokens":768,"keepAlive":0,"regenerationAttempts":0,"shutdown":String(describing:await provider.shutdown())]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("summary.json"))
        print("Evaluation finished; tested=\(rows.filter { $0.state == "TESTED" }.count), blocked=\(rows.filter { $0.state == "BLOCKED" }.count), chatRequests=\(counts["chat",default:0])")
    }
}
