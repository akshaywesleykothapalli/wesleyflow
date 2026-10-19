// Read-only observation data and ports. IDs and manifests never grant effect authority.
public enum WorkspaceObservationError: String, Error, Equatable, Sendable {
    case invalidRoot, invalidPath, duplicateRegistration, identityConflict, unknownProject, revoked
    case unavailable, relocated, excluded, unsafeType, mountBoundary, io, inconsistent
    case invalidUTF8, sensitiveContent, limitExceeded, cancelled, deadlineExceeded, invalidSelection
}
public enum ProjectAvailability: Sendable, Equatable { case available, missing, relocated, revoked }
public protocol ProjectRegistry: Sendable {
    func register(projectID: ProjectIdentifier, selectedRoot: String) async throws
    func availability(of projectID: ProjectIdentifier) async throws -> ProjectAvailability
    func validateObservation(projectID: ProjectIdentifier, rootIdentity: ObservedFileIdentity) async throws
    func revoke(_ projectID: ProjectIdentifier) async throws
}
public struct WorkspaceObservationLimits: Sendable, Equatable {
    public let files: Int
    public let individualBytes: Int
    public let aggregateBytes: Int
    public let depth: Int
    public let enumerationWork: Int
    public let durationMilliseconds: Int
    public let retainedBytes: Int
    public init(files: Int = 100, individualBytes: Int = 262_144, aggregateBytes: Int = 4_194_304,
                depth: Int = 16, enumerationWork: Int = 4096, durationMilliseconds: Int = 5000,
                retainedBytes: Int = 8_388_608) throws {
        guard (1...100).contains(files), (1...262_144).contains(individualBytes),
              (1...4_194_304).contains(aggregateBytes), (1...32).contains(depth),
              (1...16_384).contains(enumerationWork), (1...30_000).contains(durationMilliseconds),
              (1...8_388_608).contains(retainedBytes) else { throw WorkspaceObservationError.limitExceeded }
        self.files = files; self.individualBytes = individualBytes; self.aggregateBytes = aggregateBytes
        self.depth = depth; self.enumerationWork = enumerationWork; self.durationMilliseconds = durationMilliseconds
        self.retainedBytes = retainedBytes
    }
}
public struct ObservedFileIdentity: Sendable, Equatable {
    public let device: Int64
    public let inode: UInt64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let changedSeconds: Int64
    public let changedNanoseconds: Int64
    public init(device: Int64, inode: UInt64, modifiedSeconds: Int64, modifiedNanoseconds: Int64,
                changedSeconds: Int64, changedNanoseconds: Int64) {
        self.device = device; self.inode = inode; self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds; self.changedSeconds = changedSeconds
        self.changedNanoseconds = changedNanoseconds
    }
}
public struct ObservedSourceFile: Sendable, Equatable {
    public let relativePath: String
    public let utf8Content: String
    public let identity: ObservedFileIdentity
    public init(relativePath: String, utf8Content: String, identity: ObservedFileIdentity) {
        self.relativePath = relativePath; self.utf8Content = utf8Content; self.identity = identity
    }
}
/// Complete means the bounded allowlist walk finished, not that excluded/private files were read.
public struct WorkspaceReadObservation: Sendable {
    public let projectID: ProjectIdentifier
    public let rootIdentity: ObservedFileIdentity
    public let files: [ObservedSourceFile]
    public let absentPaths: [String]
    public let excludedCount: Int
    public init(projectID: ProjectIdentifier, rootIdentity: ObservedFileIdentity, files: [ObservedSourceFile], absentPaths: [String], excludedCount: Int) {
        self.projectID = projectID; self.rootIdentity = rootIdentity; self.files = files; self.absentPaths = absentPaths; self.excludedCount = excludedCount
    }
}
public protocol WorkspaceObservationSource: Sendable {
    func observe(projectID: ProjectIdentifier, absentCandidates: [String], limits: WorkspaceObservationLimits) async throws -> WorkspaceReadObservation
}
/// Shared conservative allowlist, applied BEFORE opening source files. ASCII names avoid volume aliases.
public enum WorkspaceContextPolicy {
    public static func components(_ path: String) throws -> [String] {
        guard !path.isEmpty, path.utf8.count <= 1024 else { throw WorkspaceObservationError.invalidPath }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 32 else { throw WorkspaceObservationError.invalidPath }
        for part in parts {
            guard !part.isEmpty, part.utf8.count <= 255, part != ".", part != "..", !part.hasSuffix("."),
                  part.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,95,46].contains($0) }) else { throw WorkspaceObservationError.invalidPath }
        }
        return parts
    }
    public static func permitsComponent(_ part: String) -> Bool {
        let name = part.lowercased()
        let denied: Set<String> = ["build","dist","node_modules","deriveddata","pods","cache","caches","vendor","credentials","secrets","ssh","auth","authentication","tokens","browser","profiles","chrome","safari","firefox","id_rsa","id_ed25519","known_hosts","authorized_keys","agents.md","skill.md","package.resolved","opencode.json","opencode.jsonc"]
        return !name.hasPrefix(".") && !denied.contains(name) && !["credential","secret","token","password","auth."].contains(where: name.contains)
    }
    public static func permitsFile(_ path: String) -> Bool {
        guard let parts = try? components(path), parts.allSatisfy(permitsComponent), let name = parts.last,
              let dot = name.lastIndex(of: ".") else { return false }
        return ["swift","c","h","m","mm","rs","py","js","ts","tsx","md","txt"].contains(String(name[name.index(after: dot)...]).lowercased())
    }
    public static func permitsText(_ text: String) -> Bool {
        guard !text.unicodeScalars.contains(where: { $0.value < 32 && ![9,10,13].contains($0.value) }) else { return false }
        let lower = text.lowercased()
        return !["-----begin ","api_key=","api_key =","password=","password =","authorization: bearer ","sk-proj-"].contains(where: lower.contains)
    }
}
