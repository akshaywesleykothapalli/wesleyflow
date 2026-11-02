// Inert inference data and replaceable ports; none confer filesystem or execution authority.
public enum InferenceFailure: Error, Equatable, Sendable {
    case invalidRequest, endpointDenied, redirectDenied, unavailable, invalidStatus, invalidResponse
    case oversized, timeout, cancelled, busy, quarantined, modelMissing, modelIdentityMismatch
    case memoryAdmissionDenied, memoryPressure, unsupportedVersion, proposalRejected([ProposalRejectionReason])
}
public struct ModelCapabilities: Sendable, Equatable {
    public let structuredOutput: Bool
    public let maximumContext: Int
    public init(structuredOutput: Bool, maximumContext: Int) { self.structuredOutput = structuredOutput; self.maximumContext = maximumContext }
}
public struct ModelDescriptor: Sendable, Equatable {
    public let name: String
    public let digest: String
    public let storedBytes: Int64
    public let capabilities: ModelCapabilities
    public init(name: String, digest: String, storedBytes: Int64, capabilities: ModelCapabilities) throws {
        guard !name.isEmpty, name.utf8.count <= 128, name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,58,95].contains($0) }), digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), storedBytes > 0, capabilities.maximumContext >= 2048 else { throw InferenceFailure.invalidRequest }
        self.name = name; self.digest = digest; self.storedBytes = storedBytes; self.capabilities = capabilities
    }
}
public struct InferenceRequest: Sendable, Equatable {
    public let id: String
    public let model: ModelDescriptor
    public let systemInstruction: String
    public let syntheticUserContent: String
    public let outputSchema: String
    public let deadline: Int64
    public let contextTokens: Int
    public let outputTokens: Int
    public init(id: String, model: ModelDescriptor, systemInstruction: String, syntheticUserContent: String,
                outputSchema: String, deadline: Int64, contextTokens: Int = 4096, outputTokens: Int = 768) throws {
        guard !id.isEmpty, id.utf8.count <= 128, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,95].contains($0) }),
              (2048...4096).contains(contextTokens), contextTokens <= model.capabilities.maximumContext, (64...1024).contains(outputTokens), deadline > 0,
              !systemInstruction.isEmpty, !syntheticUserContent.isEmpty, !outputSchema.isEmpty,
              systemInstruction.utf8.count + syntheticUserContent.utf8.count + outputSchema.utf8.count + outputTokens + 256 <= contextTokens,
              model.capabilities.structuredOutput else { throw InferenceFailure.invalidRequest }
        self.id = id; self.model = model; self.systemInstruction = systemInstruction; self.syntheticUserContent = syntheticUserContent
        self.outputSchema = outputSchema; self.deadline = deadline; self.contextTokens = contextTokens; self.outputTokens = outputTokens
    }
}
public struct InferenceMetrics: Sendable, Equatable {
    public let totalNanoseconds: Int64
    public let loadNanoseconds: Int64
    public let promptTokens: Int
    public let generatedTokens: Int
    public init(totalNanoseconds: Int64 = 0, loadNanoseconds: Int64 = 0, promptTokens: Int = 0, generatedTokens: Int = 0) {
        self.totalNanoseconds = totalNanoseconds; self.loadNanoseconds = loadNanoseconds
        self.promptTokens = promptTokens; self.generatedTokens = generatedTokens
    }
}
public struct InferenceResponse: Sendable {
    public let requestID: String
    public let modelDigest: String
    public let content: String
    public let metrics: InferenceMetrics
    public init(requestID: String, modelDigest: String, content: String, metrics: InferenceMetrics) {
        self.requestID = requestID; self.modelDigest = modelDigest; self.content = content; self.metrics = metrics
    }
}
public enum InferenceCancellation: String, Sendable { case notSent, completed, httpCancelledProviderUncertain, residencyAbsent }
public enum InferenceMemoryPressure: String, Sendable { case normal, warning, critical, unknown }
public struct InferenceMemorySample: Sendable {
    public let conservativeAvailableBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressureNormal: Bool
    public let pressureLevel: InferenceMemoryPressure
    /// Legacy sources that only report a Boolean remain conservatively critical.
    public init(conservativeAvailableBytes: UInt64, pressureNormal: Bool, swapUsedBytes: UInt64 = 0) {
        self.init(conservativeAvailableBytes:conservativeAvailableBytes,pressureLevel:pressureNormal ? .normal : .critical,swapUsedBytes:swapUsedBytes)
    }
    public init(conservativeAvailableBytes:UInt64,pressureLevel:InferenceMemoryPressure,swapUsedBytes:UInt64 = 0) {
        self.conservativeAvailableBytes = conservativeAvailableBytes; self.pressureLevel = pressureLevel
        self.pressureNormal = pressureLevel == .normal; self.swapUsedBytes = swapUsedBytes
    }
}
public protocol InferenceMemorySource: Sendable { func sample() async throws -> InferenceMemorySample }
public protocol LocalModelProvider: Sendable {
    func discover() async throws -> [ModelDescriptor]
    func generate(_ request: InferenceRequest) async throws -> InferenceResponse
    func cancel(requestID: String) async -> InferenceCancellation
    func reconcile() async throws -> InferenceCancellation
    func shutdown() async -> InferenceCancellation
}
public struct PreparedProposal: Sendable {
    public let proposal: CodingProposal
    public let validation: ProposalValidationResult.Validated
    public let metrics: InferenceMetrics
    public init(proposal: CodingProposal, validation: ProposalValidationResult.Validated, metrics: InferenceMetrics) {
        self.proposal = proposal; self.validation = validation; self.metrics = metrics
    }
}
public protocol ProposalPreparationService: Sendable {
    func prepare(_ request: InferenceRequest) async throws -> PreparedProposal
    func cancel(requestID: String) async -> InferenceCancellation
}
