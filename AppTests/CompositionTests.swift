import AppKit
import Domain
import Foundation
import TaskExecution
import Persistence
import SystemOperations
import Testing
@testable import WesleyFlow

@Suite("Native shell composition")
@MainActor
struct CompositionTests {
    @Test func productionCompositionConstructsHonestShell() {
        let composition = AppComposition()
        let state = composition.makeShellState()
        #expect(state.title == "Wesley Flow")
        #expect(state.phase == "Phase 1A · Task foundation")
        #expect(state.message.contains("separately approved phases"))
        #expect(composition.makeRootView().state == state)
    }

    @Test func compositionUsesInjectedProvider() {
        let expected = FoundationStatus(title: "Fixture", phase: "Composition test", message: "Injected value")
        let composition = AppComposition(statusProvider: FixedStatus(value: expected))
        #expect(composition.makeShellState() == expected)
        #expect(composition.makeRootView().state == expected)
    }

    @Test func localDomainProductLinksIntoApplicationTests() {
        let task = TaskLifecycle(id: .init(rawValue: "composition-test"), verification: .required)
        #expect(task.state == .queued)
        #expect(task.retryOf == nil)
        #expect(TaskState.Kind.allCases.count == 9)
    }

    @Test func appKitLifecycleClosesApplicationAfterLastWindow() {
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}

@MainActor
private struct FixedStatus: FoundationStatusProviding {
    let value: FoundationStatus
    func status() -> FoundationStatus { value }
}

@Suite("Phase 1A application composition", .timeLimit(.minutes(1)))
@MainActor
struct TaskServiceCompositionTests {
    @Test func compositionOpensRealStoreAndRunsOnlyInjectedExecutor() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WesleyFlow-Composition-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let executor = CompositionExecutor()
        let services = try await AppComposition().makeTaskServices(storeURL: folder.appendingPathComponent("history.store"), executor: executor, verifier: executor)
        let operation = ScopedOperation(id: "inspect", digest: String(repeating: "a", count: 64), workspaceID: "fixture", revision: "r1")
        let plan = try TaskPlan(id: .init(rawValue: "composition"), workspaceID: "fixture", revision: "r1", steps: [operation])
        try await services.coordinator.submit(plan)
        let waiting = try await services.coordinator.waitForState(plan.id, .awaitingApproval)
        try await services.approvals.approve(try #require(waiting.pendingApproval).id)
        try await services.coordinator.resumeApproval(plan.id)
        #expect(try await services.coordinator.waitForState(plan.id, .succeeded).lifecycle.state == .succeeded)
        #expect(try await services.repository.load().count == 1)
        await services.close()
    }
}
private actor CompositionExecutor: TaskOperationExecutor, TaskVerificationRunner {
    func execute(_ operation: ScopedOperation, token: OperationToken) -> OperationResult { .init(succeeded: true, observedRevision: operation.revision) }
    func verify(_ operation: ScopedOperation, token: OperationToken) -> VerificationEvidence { .init(passed: true, operationDigest: operation.digest, observedRevision: operation.revision) }
    func cancel(_ token: OperationToken) -> CancellationAcknowledgement { .stopped }
}


@MainActor private final class Agent39Runner: PersonalToolRunning {
    var calls: [UUID] = []
    var failure: PersonalAgentError?
    var onPerform: (() -> Void)?
    func perform(_ step: PersonalStep) async throws -> PersonalReceipt {
        calls.append(step.id); onPerform?()
        if let failure { throw failure }
        return PersonalReceipt(identifier:step.id.uuidString,evidence:"fixture readback")
    }
}
@Suite("Milestone39 offline personal agent") @MainActor struct PersonalAgent39Tests {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wesley39-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url
    }
    @Test func spokenCapitalizationPunctuationAndNumberWordsRemainGrounded() throws {
        let now = Date(timeIntervalSince1970:1000)
        let plan = try PersonalIntentParser.parse("Create a note Hello. Then remind me Review in ten minutes. Then open Notes.",now:now)
        #expect(plan.steps.map(\.tool) == [.note,.reminder,.openApp])
        #expect(plan.steps[0].text == "Hello."); #expect(plan.steps[1].date == now.addingTimeInterval(600))
    }
    @Test func publishedProgressFollowsPersistedStepTransitions() async throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let runner = Agent39Runner(), engine = try PersonalAgentEngine(url:base.appendingPathComponent("queue.json"),runner:runner)
        var states: [PersonalTaskState] = [], steps: [PersonalStepState] = []
        engine.onChange = { records in states.append(records[0].state); steps.append(records[0].steps[0]) }
        let plan = try PersonalIntentParser.parse("open Notes"); try engine.enqueue(plan); try await engine.approveAndRun(plan)
        #expect(states.first == .awaitingApproval); #expect(states.contains(.running)); #expect(states.last == .completed)
        #expect(steps.contains(.executing)); #expect(steps.last == .verified)
    }
    @Test func offlineMultiStepIsGroundedAndDatesBindAtIntake() throws {
        let now = Date(timeIntervalSince1970:1000)
        let plan = try PersonalIntentParser.parse("create note hello then remind me review in 10 minutes then open Notes",now:now)
        #expect(plan.steps.map(\.tool) == [.note,.reminder,.openApp])
        #expect(plan.steps[1].date == now.addingTimeInterval(600))
        #expect(plan.steps[0].text == "hello")
    }
    @Test(arguments:["", "do anything", "create note hello then send mail", "open Terminal", "open safari file:///etc/passwd", "open safari https://user:pass@example.com", "remind me review tomorrow", "timer tea in -1 minutes", "timer tea in 99999999999999999 minutes", "create note ", String(repeating:"x",count:4097)])
    func unsupportedInputHasNoPlan(_ text: String) {
        #expect(throws:(any Error).self) { try PersonalIntentParser.parse(text) }
    }
    @Test func supportsExplicitDatesAndClosedPlayerCommands() throws {
        let plan = try PersonalIntentParser.parse("calendar meeting at 2030-01-01T10:00:00Z then timer tea in 5 minutes then music pause then spotify play then open safari https://example.com")
        #expect(plan.steps.map(\.tool) == [.calendar,.timer,.music,.spotify,.safari])
    }
    @Test func enqueueHasNoEffectsAndStableIDIsIdempotent() throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let runner = Agent39Runner(), engine = try PersonalAgentEngine(url:base.appendingPathComponent("queue.json"),runner:runner)
        let plan = try PersonalIntentParser.parse("open Notes")
        try engine.enqueue(plan); try engine.enqueue(plan)
        #expect(runner.calls.isEmpty); #expect(engine.records.count == 1); #expect(engine.records[0].state == .awaitingApproval)
    }
    @Test func completedReplayAndRestartNeverDuplicateEffects() async throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let url = base.appendingPathComponent("queue.json"), runner = Agent39Runner()
        let engine = try PersonalAgentEngine(url:url,runner:runner)
        let plan = try PersonalIntentParser.parse("create note hello then remind me review in 10 minutes then open Notes")
        try engine.enqueue(plan); try await engine.approveAndRun(plan)
        #expect(engine.records[0].state == .completed); #expect(engine.records[0].receipts.count == 3)
        try engine.close()
        let reopened = try PersonalAgentEngine(url:url,runner:runner)
        await #expect(throws:PersonalAgentError.approvalRequired) { try await reopened.approveAndRun(plan) }
        #expect(runner.calls.count == 3)
    }
    @Test func mutatedApprovalCannotExecute() async throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let runner = Agent39Runner(), engine = try PersonalAgentEngine(url:base.appendingPathComponent("queue.json"),runner:runner)
        let plan = try PersonalIntentParser.parse("open Notes"); try engine.enqueue(plan)
        let changed = try PersonalPlan(id:plan.id,steps:[PersonalStep(tool:.openApp,text:"Music")],createdAt:plan.createdAt)
        await #expect(throws:PersonalAgentError.approvalRequired) { try await engine.approveAndRun(changed) }
        #expect(runner.calls.isEmpty)
    }
    @Test func partialFailureStopsAndPersistsUncertainty() async throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let runner = Agent39Runner(), url = base.appendingPathComponent("queue.json")
        let engine = try PersonalAgentEngine(url:url,runner:runner), plan = try PersonalIntentParser.parse("create note hello then open Notes")
        runner.failure = .permissionDenied
        try engine.enqueue(plan); try await engine.approveAndRun(plan)
        #expect(engine.records[0].state == .needsReview); #expect(engine.records[0].steps == [.uncertain,.pending])
        #expect(engine.records[0].diagnostic == "permission-denied"); #expect(runner.calls.count == 1)
        try engine.close()
        #expect(try PersonalAgentEngine(url:url,runner:runner).records[0].state == .needsReview)
    }
    @Test func cancellationBetweenToolsRetainsActualReceipt() async throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let runner = Agent39Runner(), engine = try PersonalAgentEngine(url:base.appendingPathComponent("queue.json"),runner:runner)
        let plan = try PersonalIntentParser.parse("create note hello then open Notes"); try engine.enqueue(plan)
        runner.onPerform = { try? engine.cancel(plan.id) }
        try await engine.approveAndRun(plan)
        #expect(engine.records[0].state == .cancelled); #expect(engine.records[0].steps == [.verified,.pending]); #expect(runner.calls.count == 1)
        runner.onPerform = nil
    }
    @Test func crashWindowRequiresReviewWithoutNativeReplay() throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let url = base.appendingPathComponent("queue.json"), runner = Agent39Runner()
        var record = PersonalTaskRecord(plan:try PersonalIntentParser.parse("create note hello then open Notes"))
        record.state = .running; record.steps[0] = .executing
        try JSONEncoder().encode([record]).write(to:url)
        let engine = try PersonalAgentEngine(url:url,runner:runner)
        #expect(engine.records[0].state == .needsReview); #expect(engine.records[0].steps == [.uncertain,.pending]); #expect(runner.calls.isEmpty)
    }
    @Test func pendingQueueCanResumeAfterRestartWithFreshApproval() async throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let url = base.appendingPathComponent("queue.json"), runner = Agent39Runner(), plan = try PersonalIntentParser.parse("open Notes")
        let engine = try PersonalAgentEngine(url:url,runner:runner); try engine.enqueue(plan)
        try engine.close()
        let reopened = try PersonalAgentEngine(url:url,runner:runner); try await reopened.approveAndRun(plan)
        #expect(runner.calls.count == 1)
    }
    @Test func corruptJournalIsPreservedAndFailClosed() throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let url = base.appendingPathComponent("queue.json"); try Data("invalid".utf8).write(to:url)
        #expect(throws:(any Error).self) { try PersonalAgentEngine(url:url,runner:Agent39Runner()) }
        #expect(try String(contentsOf:url,encoding:.utf8) == "invalid")
    }
    @Test func journalLeasePreventsTwoExecutorsAndReleasesOnClose() throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let url = base.appendingPathComponent("queue.json"), runner = Agent39Runner()
        let engine = try PersonalAgentEngine(url:url,runner:runner)
        #expect(throws:PersonalAgentError.busy) { try PersonalAgentEngine(url:url,runner:runner) }
        try engine.close()
        let second = try PersonalAgentEngine(url:url,runner:runner); try second.close()
    }
    @Test func failedWriteAheadNeverInvokesTool() async throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let url = base.appendingPathComponent("queue.json"), runner = Agent39Runner()
        let engine = try PersonalAgentEngine(url:url,runner:runner), plan = try PersonalIntentParser.parse("open Notes")
        try engine.enqueue(plan)
        try FileManager.default.removeItem(at:url)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false)
        await #expect(throws:(any Error).self) { try await engine.approveAndRun(plan) }
        #expect(runner.calls.isEmpty)
    }
    @Test func memoryOptInSearchCorrectionRetentionDeletionAndRestart() throws {
        let base = try directory(); defer { try? FileManager.default.removeItem(at:base) }
        let url = base.appendingPathComponent("memory.json"), memory = try PersonalContextMemory(url:url), now = Date()
        #expect(throws:PersonalAgentError.permissionDenied) { try memory.remember("tea") }
        memory.setEnabled(true); let id = try memory.remember("tea",days:1,now:now)
        #expect(try memory.search("TEA").count == 1)
        try memory.correct(id,text:"coffee"); #expect(try memory.search("tea").isEmpty)
        let reopened = try PersonalContextMemory(url:url); #expect(!reopened.enabled); #expect(try reopened.search("").isEmpty)
        reopened.setEnabled(true); #expect(try reopened.search("coffee").count == 1)
        #expect(try reopened.search("",now:now.addingTimeInterval(86401)).isEmpty)
        try memory.delete(); #expect(try memory.search("").isEmpty)
    }
    @Test func nativeValidationRejectsUnsafeDataBeforePermissionOrEffects() async {
        let tools = NativePersonalTools()
        for step in [PersonalStep(tool:.openApp,text:"Terminal"), PersonalStep(tool:.safari,text:"file:///tmp/x"), PersonalStep(tool:.music,text:"do shell script"), PersonalStep(tool:.reminder,text:"now"),PersonalStep(tool:.note,text:"\u{0000}")] {
            await #expect(throws:(any Error).self) { try await tools.perform(step) }
        }
    }
}
