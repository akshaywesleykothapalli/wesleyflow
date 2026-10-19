import Testing
import Domain
import CodingAgents

@Suite("Fixture HTTP exchanges", .timeLimit(.minutes(1)))
struct HTTPTests {
    @Test func successDisposalAndNoImplicitReplay() async throws {
        let transport = try FixtureHTTPTransport(chunks: [Array("{\"a\":".utf8), Array("true}".utf8)])
        let client = FixtureHTTPClient(transport: transport, clock: ProtocolClock())
        let request = try HTTPRequest(id: "one", method: .post, path: "/fixture")
        #expect(try await client.perform(request) == Array("{\"a\":true}".utf8))
        await transport.waitUntilDisposed()
        #expect(await transport.openCount == 1)
        await #expect(throws: RuntimeProtocolError.closed) { _ = try await client.perform(request) }
    }
    @Test(arguments: [199, 301, 401, 500]) func invalidStatus(_ status: Int) async throws {
        let transport = try FixtureHTTPTransport(status: status, chunks: [Array("true".utf8)])
        let client = FixtureHTTPClient(transport: transport, clock: ProtocolClock())
        await #expect(throws: RuntimeProtocolError.invalidStatus) { _ = try await client.perform(HTTPRequest(id: "status", method: .get, path: "/fixture")) }
        await transport.waitUntilDisposed(); #expect(await transport.openCount == 1)
    }
    @Test(arguments: ["", "not json", "{", "\u{0000}"]) func invalidPayload(_ text: String) async throws {
        let client = try FixtureHTTPClient(transport: FixtureHTTPTransport(chunks: [Array(text.utf8)]), clock: ProtocolClock())
        await #expect(throws: RuntimeProtocolError.invalidPayload) { _ = try await client.perform(HTTPRequest(id: "payload", method: .get, path: "/fixture")) }
    }
    @Test func contentTypeAndOversize() async throws {
        let badType = try FixtureHTTPClient(transport: FixtureHTTPTransport(contentType: "text/html", chunks: [Array("true".utf8)]), clock: ProtocolClock())
        await #expect(throws: RuntimeProtocolError.invalidPayload) { _ = try await badType.perform(HTTPRequest(id: "type", method: .get, path: "/fixture")) }
        let large = try FixtureHTTPClient(transport: FixtureHTTPTransport(chunks: [Array("tru".utf8),Array("e".utf8)]), clock: ProtocolClock())
        await #expect(throws: RuntimeProtocolError.oversizedResponse) { _ = try await large.perform(HTTPRequest(id: "size", method: .get, path: "/fixture", responseLimit: 3)) }
    }
    @Test func timeoutWithHeldTransport() async throws {
        let clock = ProtocolClock(); let transport = try FixtureHTTPTransport(chunks: [Array("true".utf8)], holdOpen: true)
        let client = FixtureHTTPClient(transport: transport, clock: clock)
        let pending = Task { try await client.perform(HTTPRequest(id: "timeout", method: .post, path: "/fixture", timeoutMilliseconds: 20)) }
        await transport.waitUntilOpened(); await clock.waitUntilScheduled(1_020); await clock.advance(to: 1_020)
        await #expect(throws: RuntimeProtocolError.timeout) { _ = try await pending.value }
        await transport.waitUntilDisposed(); #expect(await transport.openCount == 1)
    }
    @Test(arguments: [-1,0,1]) func deadlineCheckedWithoutWatchdog(_ offset: Int64) async throws {
        let clock = ProtocolClock(); let transport = try FixtureHTTPTransport(chunks: [Array("true".utf8)], holdOpen: true)
        let client = FixtureHTTPClient(transport: transport, clock: clock)
        let pending = Task { try await client.perform(HTTPRequest(id: "late", method: .get, path: "/fixture", timeoutMilliseconds: 20)) }
        await transport.waitUntilOpened(); await clock.advance(to: 1_020 + offset, wake: false); await transport.release()
        if offset < 0 { #expect(try await pending.value == Array("true".utf8)) }
        else { await #expect(throws: RuntimeProtocolError.timeout) { _ = try await pending.value } }
    }
    @Test func cancellationResumesHeldRequestAndDisposes() async throws {
        let transport = try FixtureHTTPTransport(chunks: [], holdOpen: true)
        let client = FixtureHTTPClient(transport: transport, clock: ProtocolClock())
        let pending = Task { try await client.perform(HTTPRequest(id: "cancel", method: .get, path: "/fixture")) }
        await transport.waitUntilOpened(); pending.cancel()
        await #expect(throws: RuntimeProtocolError.cancelled) { _ = try await pending.value }
        await transport.waitUntilDisposed(); #expect(await transport.disposed)
    }
    @Test func preCancelledRequestAndBackendFailureAreTyped() async throws {
        let transport = try FixtureHTTPTransport(chunks: [])
        let client = FixtureHTTPClient(transport: transport, clock: ProtocolClock())
        await client.cancel()
        await #expect(throws: RuntimeProtocolError.closed) { _ = try await client.perform(HTTPRequest(id: "closed", method: .get, path: "/fixture")) }
        let failed = FixtureHTTPClient(transport: FailingHTTPTransport(), clock: ProtocolClock())
        await #expect(throws: RuntimeProtocolError.transportFailure) { _ = try await failed.perform(HTTPRequest(id: "failure", method: .post, path: "/fixture")) }
    }
    @Test func backendFixtureMemoryIsBounded() throws {
        #expect(throws: RuntimeProtocolError.invalidManifest) { _ = try FixtureHTTPTransport(chunks: [Array(repeating: 0, count: 262_145)]) }
        #expect(throws: RuntimeProtocolError.invalidManifest) { _ = try FixtureHTTPTransport(chunks: Array(repeating: [], count: 65)) }
    }
    @Test func rejectInvalidRequests() throws {
        #expect(throws: RuntimeProtocolError.invalidRequest) { _ = try HTTPRequest(id: "bad", method: .post, path: "//external") }
        #expect(throws: RuntimeProtocolError.invalidRequest) { _ = try HTTPRequest(id: "bad", method: .get, path: "/ok", timeoutMilliseconds: 0) }
    }
}

private actor FailingHTTPTransport: HTTPTransport {
    struct PrivateFixtureError: Error { let secret = "fixture secret never exported" }
    func open(_ request: HTTPRequest) throws -> HTTPResponseHead { throw PrivateFixtureError() }
    func nextChunk() -> [UInt8]? { nil }
    func dispose() -> CleanupAssessment { .fixtureDisposed }
}
