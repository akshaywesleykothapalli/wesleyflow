import Domain
import CodingAgents
import Testing
import Foundation

actor ProtocolClock: TaskClock {
    private var time: Int64 = 1_000
    private var next = 0
    private var sleepers: [Int: (Int64, CheckedContinuation<Void, any Error>)] = [:]
    private var scheduled: [(Int64, CheckedContinuation<Void, Never>)] = []
    private var holdNow = false
    private var nowWaiter: CheckedContinuation<Void, Never>?
    private var holdObservers: [CheckedContinuation<Void, Never>] = []
    func now() async -> Int64 {
        if holdNow {
            holdNow = false
            await withCheckedContinuation { nowWaiter = $0; let pending = holdObservers; holdObservers = []; pending.forEach { $0.resume() } }
        }
        return time
    }
    func holdNextNow() { holdNow = true }
    func waitForHeldNow() async { if nowWaiter != nil { return }; await withCheckedContinuation { holdObservers.append($0) } }
    func releaseNow() { let waiter = nowWaiter; nowWaiter = nil; waiter?.resume() }
    func sleep(until deadline: Int64) async throws {
        try Task.checkCancellation()
        if time >= deadline { return }
        let id = next; next += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                sleepers[id] = (deadline, continuation)
                let pending = scheduled.filter { $0.0 == deadline }; scheduled.removeAll { $0.0 == deadline }
                pending.forEach { $0.1.resume() }
            }
        } onCancel: { Task { await self.cancelSleep(id) } }
    }
    private func cancelSleep(_ id: Int) { sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
    func waitUntilScheduled(_ deadline: Int64) async {
        if time >= deadline || sleepers.values.contains(where: { $0.0 == deadline }) { return }
        await withCheckedContinuation { scheduled.append((deadline, $0)) }
    }
    func advance(to value: Int64, wake: Bool = true) {
        precondition(value >= time); time = value
        if wake {
            let ids = sleepers.filter { $0.value.0 <= time }.map(\.key)
            for id in ids { sleepers.removeValue(forKey: id)?.1.resume() }
        }
    }
}
func manifest(deadline: Int64 = 10_000) throws -> SessionManifest {
    try .init(taskID: .init(rawValue: "task"), operationID: "proposal", generation: 2, projectID: "fixture-project", contextDigest: String(repeating: "a", count: 64), modelID: "fixture-model", deadline: deadline)
}
func manager(queue: Int = 64, bytes: Int = 262_144, identities: Int = 256, cleanup: CleanupAssessment = .fixtureDisposed) throws -> (FixtureSessionManager, ProtocolClock, FixtureSessionTransport) {
    let clock = ProtocolClock(); let transport = FixtureSessionTransport(sessionID: try .init("ses_fixture"), cleanup: cleanup)
    return (try FixtureSessionManager(transport: transport, clock: clock, queueLimit: queue, byteLimit: bytes, identityLimit: identities), clock, transport)
}
func packet(_ id: String = "evt_1", type: String = "message.part.delta", session: String = "ses_fixture", text: String = "hello") throws -> [UInt8] {
    var properties: [String: Any] = ["sessionID": session]
    switch type {
    case "permission.asked": properties.merge(["id": "per_fixture", "permission": "bash", "patterns": ["echo test"], "metadata": [:], "always": ["*"]]) { _, b in b }
    case "message.part.delta": properties.merge(["messageID": "msg_fixture", "partID": "prt_fixture", "field": "text", "delta": text]) { _, b in b }
    case "session.error": properties["error"] = ["name": "UnknownError", "data": ["message": "secret fixture must not be retained"]]
    case "session.status": properties["status"] = ["type": text]
    default: break
    }
    let body = try JSONSerialization.data(withJSONObject: ["id": id, "type": type, "properties": properties], options: [.sortedKeys])
    return Array("id: \(id)\ndata: ".utf8) + body + Array("\n\n".utf8)
}
func frames(_ chunks: [[UInt8]]) throws -> [SSEFrame] {
    var parser = try SSEParser(); var values: [SSEFrame] = []
    for chunk in chunks { try parser.feed(chunk) { values.append($0) } }
    try parser.finish(); return values
}
