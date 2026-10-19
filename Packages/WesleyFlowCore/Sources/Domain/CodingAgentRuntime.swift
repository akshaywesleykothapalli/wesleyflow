// Protocol values only. These identities and proposals convey no execution authority.
public enum RuntimeProtocolError: String, Error, Equatable, Sendable, Codable {
    case invalidManifest, invalidRequest, invalidStatus, invalidPayload, oversizedResponse
    case timeout, cancelled, transportFailure, busy, closed, unknownSession
    case foreignSession, staleConnection, malformedUTF8, oversizedFrame, bufferOverflow
    case criticalOverflow, duplicateConflict, identityLimit, unsupportedEvent, unexpectedEnd
}
public struct RuntimeSessionIdentifier: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else { throw RuntimeProtocolError.invalidManifest }
        self.rawValue = rawValue
    }
    public static func isValid(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_:.".contains($0)) }
    }
}
public struct SessionCorrelation: Equatable, Sendable, Codable {
    public let taskID: TaskIdentifier
    public let operationID: String
    public let sessionID: RuntimeSessionIdentifier
    public let generation: Int
    public let connectionEpoch: Int
    public init(taskID: TaskIdentifier, operationID: String, sessionID: RuntimeSessionIdentifier, generation: Int, connectionEpoch: Int = 0) throws {
        guard RuntimeSessionIdentifier.isValid(taskID.rawValue), RuntimeSessionIdentifier.isValid(operationID), generation >= 0, connectionEpoch >= 0 else { throw RuntimeProtocolError.invalidManifest }
        self.taskID = taskID; self.operationID = operationID; self.sessionID = sessionID
        self.generation = generation; self.connectionEpoch = connectionEpoch
    }
}
public struct SessionManifest: Equatable, Sendable {
    public let taskID: TaskIdentifier
    public let operationID: String
    public let generation: Int
    public let projectID: String
    public let contextDigest: String
    public let modelID: String
    public let deadline: Int64
    public init(taskID: TaskIdentifier, operationID: String, generation: Int, projectID: String, contextDigest: String, modelID: String, deadline: Int64) throws {
        guard [taskID.rawValue, operationID, projectID, modelID].allSatisfy(RuntimeSessionIdentifier.isValid), generation >= 0,
              contextDigest.utf8.count == 64, contextDigest.allSatisfy({ "0123456789abcdef".contains($0) }), deadline >= 0 else { throw RuntimeProtocolError.invalidManifest }
        self.taskID = taskID; self.operationID = operationID; self.generation = generation
        self.projectID = projectID; self.contextDigest = contextDigest; self.modelID = modelID; self.deadline = deadline
    }
}
public struct RuntimePermissionRequest: Equatable, Sendable {
    public let id: String
    public let action: String
    public let resources: [String]
    public init(id: String, action: String, resources: [String]) throws {
        guard RuntimeSessionIdentifier.isValid(id), RuntimeSessionIdentifier.isValid(action), resources.count <= 32,
              resources.allSatisfy({ $0.utf8.count <= 1024 }) else { throw RuntimeProtocolError.invalidPayload }
        self.id = id; self.action = action; self.resources = resources
    }
}
/// Native runtime approval is deliberately unrepresentable in this fixture foundation.
public struct RuntimePermissionResponse: Equatable, Sendable {
    public enum Decision: Sendable { case reject }
    public let requestID: String
    public let decision: Decision
    public init(reject request: RuntimePermissionRequest) { requestID = request.id; decision = .reject }
}
public enum RuntimeTerminalState: String, Sendable, Equatable { case idle, failed, cancelled, timedOut, uncertain }
public enum RuntimeEventKind: Equatable, Sendable {
    case progress(String)
    case status(String)
    case permission(RuntimePermissionRequest)
    case outcome(claimedSuccess: Bool)
    case error(RuntimeProtocolError)
    case terminal(RuntimeTerminalState)
    public var isCritical: Bool {
        switch self { case .progress, .status: false; default: true }
    }
}
public struct RuntimeEvent: Equatable, Sendable {
    public let id: String
    public let correlation: SessionCorrelation
    public let kind: RuntimeEventKind
    public init(id: String, correlation: SessionCorrelation, kind: RuntimeEventKind) throws {
        guard RuntimeSessionIdentifier.isValid(id) else { throw RuntimeProtocolError.invalidPayload }
        self.id = id; self.correlation = correlation; self.kind = kind
    }
}
public struct CancellationRequest: Equatable, Sendable {
    public let correlation: SessionCorrelation
    public init(correlation: SessionCorrelation) { self.correlation = correlation }
}
/// Disposal of fixture resources is not OS termination or an effect-disposition receipt.
public enum CleanupAssessment: Equatable, Sendable { case fixtureDisposed, uncertain }
public protocol CodingAgentRuntime: Sendable {
    func create(_ manifest: SessionManifest) async throws -> SessionCorrelation
    func nextEvent(for correlation: SessionCorrelation) async throws -> RuntimeEvent?
    func cancel(_ request: CancellationRequest) async -> CleanupAssessment
    func shutdown() async -> CleanupAssessment
}
/// Inert launch description. No method launches an executable or grants permissions.
public struct RuntimeLaunchManifest: Equatable, Sendable {
    public enum Authentication: Sendable { case requiredEphemeralCredential }
    public let executablePath: String
    public let expectedVersion: String
    public let expectedSHA256: String
    public let arguments: [String]
    public let workingDirectory: String
    public let environmentAllowlist: [String]
    public let configurationDirectory: String
    public let cacheDirectory: String
    public let dataDirectory: String
    public let serverEndpoint: String
    public let authentication: Authentication
    public init(executablePath: String, expectedVersion: String, expectedSHA256: String, arguments: [String], workingDirectory: String, environmentAllowlist: [String], configurationDirectory: String, cacheDirectory: String, dataDirectory: String, serverEndpoint: String) throws {
        let paths = [executablePath, workingDirectory, configurationDirectory, cacheDirectory, dataDirectory]
        guard paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") && $0.utf8.count <= 4096 }),
              expectedSHA256.count == 64, expectedSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
              expectedVersion.utf8.count <= 128, !expectedVersion.isEmpty, arguments.count <= 32,
              arguments.allSatisfy({ $0.utf8.count <= 1024 && !$0.contains("\0") }),
              environmentAllowlist.count <= 32, environmentAllowlist.allSatisfy(RuntimeSessionIdentifier.isValid),
              serverEndpoint.utf8.count <= 256 else { throw RuntimeProtocolError.invalidManifest }
        self.executablePath = executablePath; self.expectedVersion = expectedVersion; self.expectedSHA256 = expectedSHA256
        self.arguments = arguments; self.workingDirectory = workingDirectory; self.environmentAllowlist = environmentAllowlist
        self.configurationDirectory = configurationDirectory; self.cacheDirectory = cacheDirectory; self.dataDirectory = dataDirectory
        self.serverEndpoint = serverEndpoint; authentication = .requiredEphemeralCredential
    }
}
