import Foundation
import Synchronization

public struct ApplicationNetworkDenied: Error, Sendable {}
/// Process-local app-owned request admission, not an OS firewall. No payload or URL is retained.
public final class ApplicationNetworkPolicy: Sendable {
    public static let shared = ApplicationNetworkPolicy()
    public struct Snapshot: Sendable {
        public let blocked: Bool
        public let attempts: Int
        public let allowed: Int
        public let denied: Int
        public let lastTime: Date?
        public let lastDestination: String?
    }
    private struct State { var blocked = false; var attempts = 0; var allowed = 0; var denied = 0; var lastTime: Date?; var lastDestination: String?; var cancellations: [UUID:@Sendable () -> Void] = [:] }
    private let state = Mutex(State())
    public init() {}
    public func setBlocked(_ blocked: Bool) {
        let callbacks = state.withLock { s in
            s.blocked = blocked
            let pending = blocked ? Array(s.cancellations.values) : []
            if blocked { s.cancellations.removeAll() }; return pending
        }
        callbacks.forEach { $0() }
    }
    public func begin(_ url: URL, cancel: @escaping @Sendable () -> Void) throws -> UUID {
        // Serialize registration and blocking so no newly admitted session escapes revocation.
        let id = UUID()
        let ok = state.withLock { s in
            s.attempts += 1; s.lastTime = Date()
            let host = url.host?.lowercased()
            s.lastDestination = ["127.0.0.1","localhost","::1","[::1]"].contains(host ?? "") ? "Loopback service" : "External destination"
            guard !s.blocked, ["http","https"].contains(url.scheme?.lowercased() ?? "") else { s.denied += 1; return false }
            s.allowed += 1; s.cancellations[id] = cancel; return true
        }
        guard ok else { throw ApplicationNetworkDenied() }; return id
    }
    public func finish(_ id: UUID) { _ = state.withLock { $0.cancellations.removeValue(forKey:id) } }

    public func snapshot() -> Snapshot { state.withLock { .init(blocked:$0.blocked,attempts:$0.attempts,allowed:$0.allowed,denied:$0.denied,lastTime:$0.lastTime,lastDestination:$0.lastDestination) } }
    public func authorize(_ url: URL, now: Date = Date()) throws {
        let allowed = state.withLock { s in
            s.attempts += 1; s.lastTime = now
            // Coarse identifiers only. No hostname, path, credentials, query or body retained.
            let host = url.host?.lowercased()
            let loopback = host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
            s.lastDestination = loopback ? "Loopback service" : "External destination"
            let ok = !s.blocked && ["http","https"].contains(url.scheme?.lowercased() ?? "")
            if ok { s.allowed += 1 } else { s.denied += 1 }
            return ok
        }
        if !allowed { throw ApplicationNetworkDenied() }
    }
}
