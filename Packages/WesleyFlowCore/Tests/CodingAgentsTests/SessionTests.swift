import Testing
import Domain
import CodingAgents

@Suite("Fixture session lifecycle", .timeLimit(.minutes(1)))
struct SessionTests {
    @Test func creationIdentityAndSingleOwnership() async throws {
        let (runtime,_,transport) = try manager(); let identity = try await runtime.create(manifest())
        #expect(identity.taskID.rawValue == "task"); #expect(identity.generation == 2)
        #expect(await runtime.snapshot().state == .active); #expect(await transport.createCount == 1)
        await #expect(throws: RuntimeProtocolError.closed) { _ = try await runtime.create(manifest()) }
        #expect(await runtime.shutdown() == .fixtureDisposed)
    }
    @Test func permissionIsCriticalAndCannotAuthorize() async throws {
        let (runtime,_,_) = try manager(); let identity = try await runtime.create(manifest())
        try await runtime.receive(packet(type: "permission.asked"), for: identity)
        let event = try #require(try await runtime.nextEvent(for: identity))
        guard case .permission(let request) = event.kind else { Issue.record("Missing permission"); return }
        #expect(event.kind.isCritical); #expect(request.action == "bash")
        #expect(OpenCodeV1EventDecoder.rejectionPayload(.init(reject: request)) == Array("{\"reply\":\"reject\"}".utf8))
        _ = await runtime.shutdown()
    }
    @Test func foreignSessionAndCorrelationAreRejected() async throws {
        let (runtime,_,_) = try manager(); let identity = try await runtime.create(manifest())
        await #expect(throws: RuntimeProtocolError.foreignSession) { try await runtime.receive(packet(session: "ses_other"), for: identity) }
        let foreign = try SessionCorrelation(taskID: .init(rawValue: "other"), operationID: "proposal", sessionID: identity.sessionID, generation: 2)
        await #expect(throws: RuntimeProtocolError.foreignSession) { try await runtime.receive(packet(), for: foreign) }
        #expect(await runtime.snapshot().queuedEvents == 0); #expect(await runtime.snapshot().state == .active)
        _ = await runtime.shutdown()
    }
    @Test func duplicatesAcrossReconnectDoNotRedeliverOrResend() async throws {
        let (runtime,_,transport) = try manager(); let first = try await runtime.create(manifest())
        try await runtime.receive(packet(), for: first); try await runtime.receive(packet(), for: first)
        #expect(await runtime.snapshot().queuedEvents == 1)
        try await runtime.disconnect(for: first)
        let second = try await runtime.reconnect(for: first)
        #expect(second.connectionEpoch == 1); #expect(await transport.createCount == 1)
        await #expect(throws: RuntimeProtocolError.staleConnection) { try await runtime.receive(packet("evt_2"), for: first) }
        try await runtime.receive(packet(), for: second)
        #expect(await runtime.snapshot().queuedEvents == 1); #expect(await runtime.snapshot().identityCount == 1)
        _ = await runtime.shutdown()
    }
    @Test func duplicateIDWithChangedPayloadFailsUncertain() async throws {
        let (runtime,_,_) = try manager(); let identity = try await runtime.create(manifest())
        try await runtime.receive(packet(), for: identity)
        await #expect(throws: RuntimeProtocolError.duplicateConflict) { try await runtime.receive(packet(text: "different"), for: identity) }
        #expect(await runtime.snapshot().state == .terminal(.uncertain))
        #expect(await runtime.snapshot().error == .duplicateConflict); _ = await runtime.shutdown()
    }
    @Test func slowConsumerCoalescesOnlyProgress() async throws {
        let (runtime,_,_) = try manager(queue: 3); let identity = try await runtime.create(manifest())
        for index in 0..<40 { try await runtime.receive(packet("evt_\(index)", text: "\(index)"), for: identity) }
        #expect(await runtime.snapshot().queuedEvents == 1)
        #expect(try await runtime.nextEvent(for: identity)?.kind == .progress("39"))
        _ = await runtime.shutdown()
    }
    @Test func criticalEventsEvictProgressButKeepOrder() async throws {
        let (runtime,_,_) = try manager(queue: 2); let identity = try await runtime.create(manifest())
        try await runtime.receive(packet("evt_progress"), for: identity)
        try await runtime.receive(packet("evt_permission", type: "permission.asked"), for: identity)
        try await runtime.receive(packet("evt_end", type: "session.idle"), for: identity)
        let first = try #require(try await runtime.nextEvent(for: identity))
        #expect(first.id == "evt_permission"); #expect(first.kind.isCritical)
        #expect(try await runtime.nextEvent(for: identity)?.kind == .terminal(.idle))
        #expect(try await runtime.nextEvent(for: identity) == nil)
        #expect(await runtime.snapshot().state == .terminal(.idle)); _ = await runtime.shutdown()
    }
    @Test func criticalOverflowPreservesAcceptedCriticalAndInspectableError() async throws {
        let (runtime,_,_) = try manager(queue: 1); let identity = try await runtime.create(manifest())
        try await runtime.receive(packet("evt_first", type: "permission.asked"), for: identity)
        await #expect(throws: RuntimeProtocolError.criticalOverflow) { try await runtime.receive(packet("evt_second", type: "permission.asked"), for: identity) }
        #expect(await runtime.snapshot().state == .terminal(.uncertain))
        #expect(try await runtime.nextEvent(for: identity)?.id == "evt_first")
        await #expect(throws: RuntimeProtocolError.criticalOverflow) { _ = try await runtime.nextEvent(for: identity) }
        _ = await runtime.shutdown()
    }
    @Test func byteOverflowAndIdentityLimitFailClosed() async throws {
        let (runtime,_,_) = try manager(bytes: 16); let identity = try await runtime.create(manifest())
        await #expect(throws: RuntimeProtocolError.criticalOverflow) { try await runtime.receive(packet(type: "permission.asked"), for: identity) }
        #expect(await runtime.snapshot().queuedBytes == 0); _ = await runtime.shutdown()
        let (limited,_,_) = try manager(identities: 1); let scope = try await limited.create(manifest())
        try await limited.receive(packet(), for: scope)
        await #expect(throws: RuntimeProtocolError.identityLimit) { try await limited.receive(packet("evt_new"), for: scope) }
        #expect(await limited.snapshot().identityCount == 1); _ = await limited.shutdown()
    }
    @Test func cancelAndRepeatedShutdownDisposeOnce() async throws {
        let (runtime,_,transport) = try manager(); let identity = try await runtime.create(manifest())
        #expect(await runtime.cancel(.init(correlation: identity)) == .fixtureDisposed)
        async let one = runtime.shutdown(); async let two = runtime.shutdown()
        let results = await [one,two]; #expect(results == [.fixtureDisposed,.fixtureDisposed])
        #expect(await transport.disposeCount == 1); #expect(await runtime.snapshot().state == .terminal(.cancelled))
        await #expect(throws: RuntimeProtocolError.cancelled) { try await runtime.receive(packet(), for: identity) }
    }
    @Test func uncertainCleanupIsNotStoppedProof() async throws {
        let (runtime,_,_) = try manager(cleanup: .uncertain); let identity = try await runtime.create(manifest())
        #expect(await runtime.cancel(.init(correlation: identity)) == .uncertain)
        #expect(await runtime.snapshot().cleanup == .uncertain)
    }
    @Test func timeoutAndLateTerminalCannotPromote() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest(deadline: 1_050))
        await clock.waitUntilScheduled(1_050); await clock.advance(to: 1_050)
        await #expect(throws: RuntimeProtocolError.timeout) { try await runtime.receive(packet(type: "session.idle"), for: identity) }
        #expect(await runtime.snapshot().state == .terminal(.timedOut)); _ = await runtime.shutdown()
    }
    @Test(arguments: [-1,0,1]) func deadlineWithoutTimerDelivery(_ offset: Int64) async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest(deadline: 1_050))
        await clock.advance(to: 1_050 + offset, wake: false)
        if offset < 0 {
            try await runtime.receive(packet(type: "session.idle"), for: identity)
            #expect(await runtime.snapshot().state == .terminal(.idle))
        } else {
            await #expect(throws: RuntimeProtocolError.timeout) { try await runtime.receive(packet(type: "session.idle"), for: identity) }
            #expect(await runtime.snapshot().state == .terminal(.timedOut))
        }
        _ = await runtime.shutdown()
    }
    @Test func shutdownDuringObserverRegistrationCannotStrandContinuation() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest())
        await clock.holdNextNow()
        let pending = Task { try await runtime.nextEvent(for: identity) }
        await clock.waitForHeldNow(); _ = await runtime.shutdown(); await clock.releaseNow()
        await #expect(throws: RuntimeProtocolError.cancelled) { _ = try await pending.value }
    }
    @Test func terminalDuringObserverRegistrationIsDelivered() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest())
        await clock.holdNextNow(); let pending = Task { try await runtime.nextEvent(for: identity) }
        await clock.waitForHeldNow()
        try await runtime.receive(packet(type: "session.idle"), for: identity)
        await clock.releaseNow()
        #expect(try await pending.value?.kind == .terminal(.idle)); _ = await runtime.shutdown()
    }
    @Test func shutdownDuringIncomingFrameTimeCheckRejectsDelivery() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest())
        await clock.holdNextNow(); let pending = Task { try await runtime.receive(packet(type: "permission.asked"), for: identity) }
        await clock.waitForHeldNow(); _ = await runtime.shutdown(); await clock.releaseNow()
        await #expect(throws: RuntimeProtocolError.cancelled) { try await pending.value }
        #expect(await runtime.snapshot().queuedEvents == 0)
    }
    @Test func observerCancellationBeforeRegistrationAndWhileWaiting() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest())
        await clock.holdNextNow(); let pending = Task { try await runtime.nextEvent(for: identity) }
        await clock.waitForHeldNow(); pending.cancel(); await clock.releaseNow()
        await #expect(throws: RuntimeProtocolError.cancelled) { _ = try await pending.value }
        #expect(await runtime.snapshot().isObserving == false); _ = await runtime.shutdown()
    }
    @Test func EOFAndMalformedUnknownEventsRemainUncertain() async throws {
        let (runtime,_,_) = try manager(); let identity = try await runtime.create(manifest())
        try await runtime.endOfStream(for: identity)
        #expect(await runtime.snapshot().error == .unexpectedEnd); _ = await runtime.shutdown()
        let (other,_,_) = try manager(); let scope = try await other.create(manifest())
        await #expect(throws: RuntimeProtocolError.unsupportedEvent) { try await other.receive(packet(type: "unknown.critical"), for: scope) }
        #expect(await other.snapshot().state == .terminal(.uncertain)); _ = await other.shutdown()
    }
    @Test func rawProviderErrorIsSanitized() async throws {
        let (runtime,_,_) = try manager(); let identity = try await runtime.create(manifest())
        try await runtime.receive(packet(type: "session.error"), for: identity)
        #expect(try await runtime.nextEvent(for: identity)?.kind == .error(.transportFailure))
        #expect(await runtime.snapshot().error == .transportFailure); _ = await runtime.shutdown()
    }
    @Test func shutdownBeforeCreationAndExpiredManifest() async throws {
        let (runtime,_,transport) = try manager(); _ = await runtime.shutdown()
        await #expect(throws: RuntimeProtocolError.closed) { _ = try await runtime.create(manifest()) }
        #expect(await transport.createCount == 0)
        let (expired,_,other) = try manager()
        await #expect(throws: RuntimeProtocolError.timeout) { _ = try await expired.create(manifest(deadline: 1_000)) }
        #expect(await other.createCount == 0); _ = await expired.shutdown()
    }
    @Test func concurrentChunksCannotOvertakeAtClockSuspension() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest())
        await clock.holdNextNow(); let pending = Task { try await runtime.receive(packet("evt_first"), for: identity) }
        await clock.waitForHeldNow()
        await #expect(throws: RuntimeProtocolError.busy) { try await runtime.receive(packet("evt_second"), for: identity) }
        await clock.releaseNow(); try await pending.value
        #expect(await runtime.snapshot().queuedEvents == 1)
        #expect(try await runtime.nextEvent(for: identity)?.id == "evt_first"); _ = await runtime.shutdown()
    }
    @Test func reconnectRejectsPreviouslySuspendedChunk() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest())
        await clock.holdNextNow(); let pending = Task { try await runtime.receive(packet(), for: identity) }
        await clock.waitForHeldNow(); try await runtime.disconnect(for: identity)
        let fresh = try await runtime.reconnect(for: identity)
        await clock.releaseNow()
        await #expect(throws: RuntimeProtocolError.staleConnection) { try await pending.value }
        #expect(await runtime.snapshot().queuedEvents == 0)
        try await runtime.receive(packet("evt_new"), for: fresh)
        #expect(try await runtime.nextEvent(for: fresh)?.id == "evt_new"); _ = await runtime.shutdown()
    }

    @Test func disconnectedObservationIsRejectedBeforeDeadlineCheck() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest(deadline: 1_050))
        await clock.waitUntilScheduled(1_050)
        try await runtime.disconnect(for: identity)
        // Hold watchdog delivery: a retired connection must fail at the connection gate,
        // without starting an observer or interpreting this invalid read as task timeout.
        await clock.advance(to: 1_050, wake: false)
        await #expect(throws: RuntimeProtocolError.staleConnection) { _ = try await runtime.nextEvent(for: identity) }
        #expect(await runtime.snapshot().state == .reconnecting)
        #expect(await runtime.snapshot().isObserving == false)
        _ = await runtime.shutdown()
    }

    @Test func disconnectDuringObservationClockAwaitRejectsOldWaiter() async throws {
        let (runtime,clock,_) = try manager(); let identity = try await runtime.create(manifest())
        await clock.holdNextNow()
        let pending = Task { try await runtime.nextEvent(for: identity) }
        await clock.waitForHeldNow(); try await runtime.disconnect(for: identity)
        await clock.releaseNow()
        await #expect(throws: RuntimeProtocolError.staleConnection) { _ = try await pending.value }
        #expect(await runtime.snapshot().isObserving == false)
        let fresh = try await runtime.reconnect(for: identity)
        try await runtime.receive(packet("evt_fresh", type: "permission.asked"), for: fresh)
        #expect(try await runtime.nextEvent(for: fresh)?.correlation == fresh)
        _ = await runtime.shutdown()
    }

}
