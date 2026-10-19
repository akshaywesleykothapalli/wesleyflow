import Testing
import Domain
import CodingAgents

@Suite("Bounded standards-aware SSE")
struct SSETests {
    @Test(arguments: Array(0...33)) func splitFrames(_ split: Int) throws {
        let bytes = Array("id: evt_a\ndata: hello\ndata: world\n\n".utf8)
        let point = min(split, bytes.count)
        let result = try frames([Array(bytes.prefix(point)), Array(bytes.dropFirst(point))])
        #expect(result.count == 1); #expect(result.first?.data == "hello\nworld"); #expect(result.first?.id == "evt_a")
    }
    @Test func splitUTF8AndBOMOneByteAtATime() throws {
        let bytes = Array("\u{FEFF}data: hé🌍\r\n\r\n".utf8)
        let result = try frames(bytes.map { [$0] })
        #expect(result.map(\.data) == ["hé🌍"])
    }
    @Test func commentsHeartbeatsEmptyDataAndUnknownFields() throws {
        let result = try frames([Array(": heartbeat\n\nunknown: ignore\ndata:\n\nid: one\nevent: custom\ndata: x\n\n".utf8)])
        #expect(result.count == 2); #expect(result[0].data.isEmpty); #expect(result[0].event == "message")
        #expect(result[1].event == "custom"); #expect(result[1].id == "one")
    }
    @Test func idPersistenceResetNULAndRetry() throws {
        let result = try frames([Array("id: a\nretry: 42\ndata: 1\n\nid: bad\0id\nretry: -1\ndata: 2\n\nid:\ndata: 3\n\n".utf8)])
        #expect(result.map(\.id) == ["a", "a", ""]); #expect(result.allSatisfy { $0.retryMilliseconds == 42 })
    }
    @Test func CRLFAndCRSeparators() throws {
        #expect(try frames([Array("data: a\r\rdata: b\r\n\r\n".utf8)]).map(\.data) == ["a", "b"])
    }
    @Test func EOFDiscardsUnterminatedFrameAndFinishIsIdempotent() throws {
        var parser = try SSEParser(); var output: [SSEFrame] = []
        try parser.feed(Array("data: incomplete\n".utf8)) { output.append($0) }
        try parser.finish(); try parser.finish(); #expect(output.isEmpty)
        #expect(throws: RuntimeProtocolError.closed) { try parser.feed([10]) { _ in } }
    }
    @Test func malformedUTF8AndTruncatedScalar() throws {
        #expect(throws: RuntimeProtocolError.malformedUTF8) { _ = try frames([[0xff,10]]) }
        #expect(throws: RuntimeProtocolError.malformedUTF8) { _ = try frames([[0xf0,0x9f]]) }
    }
    @Test func frameAndInputLimits() throws {
        var parser = try SSEParser(frameLimit: 8, inputLimit: 16)
        #expect(throws: RuntimeProtocolError.oversizedFrame) { try parser.feed(Array(repeating: 65, count: 9)) { _ in } }
        var other = try SSEParser(frameLimit: 8, inputLimit: 16)
        #expect(throws: RuntimeProtocolError.bufferOverflow) { try other.feed(Array(repeating: 65, count: 17)) { _ in } }
        #expect(throws: RuntimeProtocolError.invalidManifest) { _ = try SSEParser(frameLimit: 0) }
    }
    @Test func consumerFailureStopsParsing() throws {
        var parser = try SSEParser(); var delivered = 0
        #expect(throws: RuntimeProtocolError.cancelled) {
            try parser.feed(Array("data: one\n\ndata: two\n\n".utf8)) { _ in delivered += 1; throw RuntimeProtocolError.cancelled }
        }
        #expect(delivered == 1)
    }
}
