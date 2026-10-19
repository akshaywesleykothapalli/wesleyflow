import Domain
import Foundation

/// Narrow subset of the release-tag Event union; never interprets an event as authorization.
public enum OpenCodeV1EventDecoder {
    public static func decode(_ frame: SSEFrame, correlation: SessionCorrelation) throws -> RuntimeEvent {
        guard let bytes = frame.data.data(using: .utf8), bytes.count <= 65_536,
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let id = object["id"] as? String, id.hasPrefix("evt_"),
              let type = object["type"] as? String, let properties = object["properties"] as? [String: Any],
              let sessionID = properties["sessionID"] as? String else { throw RuntimeProtocolError.invalidPayload }
        // SSE last-event-id is a transport checkpoint, not the JSON event identity.
        guard sessionID == correlation.sessionID.rawValue else { throw RuntimeProtocolError.foreignSession }
        let kind: RuntimeEventKind
        switch type {
        case "message.part.delta":
            guard let delta = properties["delta"] as? String, let messageID = properties["messageID"] as? String, messageID.hasPrefix("msg"),
                  let partID = properties["partID"] as? String, partID.hasPrefix("prt"), properties["field"] is String else { throw RuntimeProtocolError.invalidPayload }
            kind = .progress(delta)
        case "permission.asked":
            guard let requestID = properties["id"] as? String, requestID.hasPrefix("per"),
                  let action = properties["permission"] as? String, let patterns = properties["patterns"] as? [String],
                  properties["metadata"] is [String: Any], properties["always"] is [String] else { throw RuntimeProtocolError.invalidPayload }
            kind = .permission(try RuntimePermissionRequest(id: requestID, action: action, resources: patterns))
        case "session.status":
            guard let status = properties["status"] as? [String: Any], let state = status["type"] as? String,
                  ["idle", "busy", "retry"].contains(state) else { throw RuntimeProtocolError.invalidPayload }
            if state == "retry" {
                guard let attempt = status["attempt"] as? Int, attempt >= 0, status["message"] is String,
                      let next = status["next"] as? Int, next >= 0 else { throw RuntimeProtocolError.invalidPayload }
            }
            // Idle is an observation, not verified coding success.
            kind = state == "idle" ? .terminal(.idle) : .status(state)
        case "session.idle": kind = .terminal(.idle)
        case "session.error":
            guard properties["error"] is [String: Any] else { throw RuntimeProtocolError.invalidPayload }
            kind = .error(.transportFailure) // Never retain or print raw provider error text.
        default: throw RuntimeProtocolError.unsupportedEvent
        }
        return try RuntimeEvent(id: id, correlation: correlation, kind: kind)
    }
    public static func rejectionPayload(_ response: RuntimePermissionResponse) -> [UInt8] {
        // Authenticated native approval is intentionally absent. No always/once path exists.
        Array("{\"reply\":\"reject\"}".utf8)
    }
}
