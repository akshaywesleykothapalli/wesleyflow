import Domain
import Foundation

public struct SSEFrame: Equatable, Sendable {
    public let id: String?
    public let event: String
    public let data: String
    public let retryMilliseconds: Int?
}
/// Incremental UTF-8 SSE parsing. Incomplete events at EOF are discarded per SSE rules.
public struct SSEParser: Sendable {
    public let frameLimit: Int
    public let inputLimit: Int
    private var line: [UInt8] = []
    private var frameBytes = 0
    private var dataLines: [String] = []
    private var hasData = false
    private var eventName = ""
    private var lastID: String?
    private var retry: Int?
    private var skipLF = false
    private var firstLine = true
    private var ended = false
    public init(frameLimit: Int = 65_536, inputLimit: Int = 262_144) throws {
        guard frameLimit > 0, frameLimit <= 65_536, inputLimit > 0, inputLimit <= 262_144 else { throw RuntimeProtocolError.invalidManifest }
        self.frameLimit = frameLimit; self.inputLimit = inputLimit
    }
    public mutating func feed(_ bytes: [UInt8], emit: (SSEFrame) throws -> Void) throws {
        guard !ended else { throw RuntimeProtocolError.closed }
        guard bytes.count <= inputLimit else { throw RuntimeProtocolError.bufferOverflow }
        for byte in bytes {
            if skipLF { skipLF = false; if byte == 10 { continue } }
            frameBytes += 1
            guard frameBytes <= frameLimit else { throw RuntimeProtocolError.oversizedFrame }
            if byte == 10 || byte == 13 {
                if byte == 13 { skipLF = true }
                try finishLine(emit: emit)
            } else {
                guard line.count < inputLimit else { throw RuntimeProtocolError.bufferOverflow }
                line.append(byte)
            }
        }
    }
    private mutating func finishLine(emit: (SSEFrame) throws -> Void) throws {
        guard var text = String(bytes: line, encoding: .utf8) else { throw RuntimeProtocolError.malformedUTF8 }
        line.removeAll(keepingCapacity: true)
        if firstLine { firstLine = false; if text.first == "\u{FEFF}" { text.removeFirst() } }
        if text.isEmpty {
            if hasData { try emit(SSEFrame(id: lastID, event: eventName.isEmpty ? "message" : eventName, data: dataLines.joined(separator: "\n"), retryMilliseconds: retry)) }
            dataLines.removeAll(keepingCapacity: true); hasData = false; eventName = ""; frameBytes = 0
            return
        }
        if text.hasPrefix(":") { return }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0]); var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "data": hasData = true; dataLines.append(value)
        case "event": eventName = value
        case "id": if !value.contains("\0") { lastID = value }
        case "retry": if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(value) { retry = number }
        default: break
        }
    }
    public mutating func finish() throws {
        guard !ended else { return }
        ended = true
        // Validate any partial line, but never dispatch an unterminated event.
        guard String(bytes: line, encoding: .utf8) != nil else { throw RuntimeProtocolError.malformedUTF8 }
        line = []; dataLines = []; hasData = false
    }
}
