import Foundation
import Darwin
import Domain

private func boundedPersonalData(_ url: URL, limit: Int) throws -> Data {
    let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
    let data = try file.read(upToCount:limit+1) ?? Data()
    guard data.count <= limit else { throw PersonalAgentError.storageFull }
    return data
}
private final class PersonalJournalLease: Sendable {
    let descriptor: Int32
    init(url: URL) throws {
        descriptor = Darwin.open(url.path,O_CREAT | O_RDWR | O_NOFOLLOW,0o600)
        guard descriptor >= 0 else { throw PersonalAgentError.interrupted }
        guard flock(descriptor,LOCK_EX | LOCK_NB) == 0 else { Darwin.close(descriptor); throw PersonalAgentError.busy }
    }
    deinit { flock(descriptor,LOCK_UN); Darwin.close(descriptor) }
}

/// Single owner and write-ahead journal. Executing steps become uncertain after restart.
/// No automatic replay of an effect whose completion could not be journaled.
@MainActor public final class PersonalAgentEngine {
    public private(set) var records: [PersonalTaskRecord]
    public var onChange: (@MainActor ([PersonalTaskRecord]) -> Void)?
    private let url: URL
    private let runner: any PersonalToolRunning
    private let now:@MainActor () ->Date
    private var lease: PersonalJournalLease?
    private var active: UUID?
    private var cancellation = false
    private var pauseRequested=false
    public init(url: URL, runner: any PersonalToolRunning,now:@escaping @MainActor () ->Date={Date()}) throws {
        self.url = url; self.runner = runner;self.now=now
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        lease = try PersonalJournalLease(url:url.appendingPathExtension("lock"))
        if FileManager.default.fileExists(atPath:url.path) {
            let data = try boundedPersonalData(url,limit:4*1024*1024)
            guard data.count <= 4*1024*1024 else { throw PersonalAgentError.storageFull }
            records = try JSONDecoder().decode([PersonalTaskRecord].self,from:data)
            guard records.count <= 100, Set(records.map(\.id)).count == records.count else { throw PersonalAgentError.storageFull }
            for i in records.indices {
                _ = try PersonalPlan(id:records[i].plan.id,steps:records[i].plan.steps,createdAt:records[i].plan.createdAt)
                guard records[i].steps.count == records[i].plan.steps.count else { throw PersonalAgentError.interrupted }
                if records[i].state == .running || records[i].steps.contains(.executing) {
                    records[i].state = .needsReview
                    for j in records[i].steps.indices where records[i].steps[j] == .executing { records[i].steps[j] = .uncertain }
                    records[i].diagnostic = "interrupted-no-automatic-replay"
                }
            }
        } else { records = [] }
        try persist()
    }
    private func persist() throws {
        let data = try JSONEncoder().encode(records)
        guard data.count <= 4*1024*1024 else { throw PersonalAgentError.storageFull }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        onChange?(records)
    }
    @discardableResult public func enqueue(_ plan: PersonalPlan) throws -> UUID {
        guard lease != nil, active == nil else { throw PersonalAgentError.busy }
        if records.contains(where: { $0.id == plan.id }) { return plan.id }
        guard records.count < 100 else { throw PersonalAgentError.storageFull }
        records.append(PersonalTaskRecord(plan:plan))
        do { try persist() } catch { records.removeLast(); throw error }
        return plan.id
    }
    /// Fresh user-request path for routine tools only. Saved pending plans are never auto-drained.
    public func runRequestedRoutine(_ plan:PersonalPlan) async throws {
        guard PersonalAuthorization.routine(plan) else { throw PersonalAgentError.approvalRequired }
        try await approveAndRun(plan)
    }
    /// Trusted human interface supplies the exact displayed plan, never a model-generated grant.
    public func approveAndRun(_ reviewed: PersonalPlan) async throws {
        guard lease != nil, active == nil else { throw PersonalAgentError.busy }
        guard let i = records.firstIndex(where: { $0.id == reviewed.id }), records[i].plan == reviewed,
              records[i].state == .awaitingApproval else { throw PersonalAgentError.approvalRequired }
        active = reviewed.id; cancellation = false;pauseRequested=false
        defer { active = nil }
        records[i].state = .running
        do { try persist() } catch { records[i].state = .awaitingApproval; throw error }
        for j in reviewed.steps.indices {
            if pauseRequested && !cancellation && !Task.isCancelled {records[i].state = .paused;try persist();return}
            if cancellation || Task.isCancelled {
                let previous=records[i].state; records[i].state = .cancelled
        do { try persist() } catch { records[i].state=previous;throw error }; return
            }
            records[i].steps[j] = .executing
            // If this write fails, do not invoke the tool.
            do { try persist() } catch { records[i].state = .needsReview; throw error }
            do {
                let receipt = try await runner.perform(reviewed.steps[j])
                records[i].receipts[j] = receipt
                if !receipt.verified {
                    records[i].steps[j] = .uncertain; records[i].state = .needsReview
                    records[i].diagnostic = "dispatched-outcome-unverified-no-replay"
                    try persist(); return
                }
                records[i].steps[j] = .verified
            } catch {
                // An error can occur after a native write: never infer no effect or retry.
                records[i].steps[j] = .uncertain; records[i].state = .needsReview
                records[i].diagnostic = (error as? PersonalAgentError) == .permissionDenied ? "permission-denied" : "native-failure-or-unverified"
                try persist(); return
            }
            do { try persist() } catch { records[i].state = .needsReview; records[i].steps[j] = .uncertain; throw error }
        }
        records[i].state = cancellation || Task.isCancelled ? .cancelled : .completed
        if records[i].state == .completed {records[i].completedAt=now()}
        try persist()
    }
    /// A native read-only observation may settle only its original pending quit, never execute or resume a step.
    public func reconcileAppClose(_ id:UUID,expectedStep:PersonalStep,receipt:PersonalReceipt) throws {
        guard lease != nil,active != id,expectedStep.tool == .closeApp,let i=records.firstIndex(where:{$0.id==id}),records[i].state == .needsReview,records[i].supersededBy==nil,let j=records[i].plan.steps.firstIndex(of:expectedStep),records[i].steps[j] == .uncertain,let before=records[i].receipts[j]?.appClose,let after=receipt.appClose else {throw PersonalAgentError.approvalRequired}
        _=try before.validated();_=try after.validated()
        guard [PersonalAppCloseObservation.Outcome.pending,.refused].contains(before.outcome),before.token==after.token,before.bundleID==expectedStep.text,after.bundleID==before.bundleID,after.processes==before.processes,receipt.identifier==before.bundleID,(after.outcome == .closed && receipt.verified) || ([PersonalAppCloseObservation.Outcome.reopened,.unconfirmed].contains(after.outcome) && !receipt.verified) else {throw PersonalAgentError.verificationFailed}
        let prior=records;records[i].receipts[j]=receipt
        if after.outcome == .closed {records[i].steps[j] = .verified;records[i].diagnostic="native-process-exit-observed-no-retry";if records[i].steps.allSatisfy({$0 == .verified}) {records[i].state = .completed;records[i].completedAt=now()}}
        else {records[i].diagnostic=after.outcome == .reopened ? "app-reopened-no-retry":"quit-not-confirmed-after-observation"}
        do {try persist()} catch {records=prior;throw error}
    }
    /// Trusted native UI only: an explicit user observation records evidence; it never calls a tool.
    public func confirmObservedOutcome(_ id:UUID,expectedStep:PersonalStep) throws {
        guard lease != nil,active==nil,let i=records.firstIndex(where:{$0.id==id}),records[i].state == .needsReview,records[i].supersededBy==nil,let j=records[i].plan.steps.firstIndex(where:{$0==expectedStep}),records[i].steps[j] == .uncertain else {throw PersonalAgentError.approvalRequired}
        let prior=records
        let old=records[i].receipts[j]
        records[i].receipts[j] = .init(identifier:old?.identifier ?? expectedStep.id.uuidString,evidence:"User explicitly checked the exact requested outcome in the native app. Human observation, not automatic native verification or proof of recipient delivery.")
        records[i].steps[j] = .verified;records[i].diagnostic="human-observed-outcome-no-replay"
        if records[i].steps.allSatisfy({$0 == .verified}) {records[i].state = .completed;records[i].completedAt=now()}
        do {try persist()} catch {records=prior;throw error}
    }
    public func pause(_ id:UUID) throws {
        guard lease != nil,active==id else {throw PersonalAgentError.busy}
        pauseRequested=true
    }
    public func continuationPlan(_ id:UUID,now:Date) throws ->PersonalPlan {
        guard active==nil,let source=records.first(where:{$0.id==id}),source.supersededBy==nil,[PersonalTaskState.paused,.cancelled,.needsReview].contains(source.state),!source.steps.contains(where:{[PersonalStepState.executing,.uncertain,.failed].contains($0)}) else {throw PersonalAgentError.approvalRequired}
        for i in source.steps.indices where source.steps[i] == .verified {guard source.receipts[i]?.verified==true else {throw PersonalAgentError.verificationFailed}}
        let remaining=try source.plan.steps.enumerated().filter{source.steps[$0.offset] == .pending}.map {entry in
            let step=entry.element
            var date=step.date
            if let prior=date {
                if step.tool == .timer {let delay=prior.timeIntervalSince(source.plan.createdAt);guard delay>0,delay<=31536000 else {throw PersonalAgentError.invalidCommand};date=now.addingTimeInterval(delay)}
                else {guard prior>now else {throw PersonalAgentError.invalidCommand}}
            }
            return PersonalStep(tool:step.tool,text:step.text,date:date)
        }
        return try .init(steps:remaining,createdAt:now,requiresReview:true)
    }
    public func enqueueContinuation(_ plan:PersonalPlan,from id:UUID) throws {
        guard lease != nil,active==nil,plan.requiresReview,let i=records.firstIndex(where:{$0.id==id}),records[i].supersededBy==nil else {throw PersonalAgentError.approvalRequired}
        _=try continuationPlan(id,now:plan.createdAt)
        let pending=records[i].plan.steps.enumerated().filter{records[i].steps[$0.offset] == .pending}.map{$0.element.tool}
        guard plan.steps.map(\.tool)==pending,records.count<100,!records.contains(where:{$0.id==plan.id}) else {throw PersonalAgentError.approvalRequired}
        let prior=records;records[i].supersededBy=plan.id;records.append(PersonalTaskRecord(plan:plan))
        do {try persist()} catch {records=prior;throw error}
    }
    public func cancel(_ id: UUID) throws {
        guard lease != nil else { throw PersonalAgentError.interrupted }
        if active == id { cancellation = true; return } // Stop between effects; retain in-flight verification.
        guard let i = records.firstIndex(where: { $0.id == id }), records[i].state == .awaitingApproval else { return }
        let previous=records[i].state; records[i].state = .cancelled
        do { try persist() } catch { records[i].state=previous;throw error }
    }
    public func close() throws {
        guard active == nil else { throw PersonalAgentError.busy }; lease = nil
    }
    public func delete(_ id: UUID) throws {
        guard lease != nil, active == nil else { throw PersonalAgentError.busy }
        let prior = records; records.removeAll { $0.id == id }
        do { try persist() } catch { records = prior; throw error }
    }
}

public struct PersonalMemoryItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var text: String
    public var expiresAt: Date
}
/// Explicit user-authored memory only. No activity, audio, clipboard or transcript capture.
@MainActor public final class PersonalContextMemory {
    private let url: URL
    public private(set) var enabled = false
    private var items: [PersonalMemoryItem] = []
    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath:url.path) {
            let data = try boundedPersonalData(url,limit:256*1024); guard data.count <= 256*1024 else { throw PersonalAgentError.storageFull }
            items = try JSONDecoder().decode([PersonalMemoryItem].self,from:data)
            guard items.count <= 100, Set(items.map(\.id)).count == items.count, items.allSatisfy({ !$0.text.isEmpty && $0.text.utf8.count <= 2048 }) else { throw PersonalAgentError.storageFull }
        }
    }
    public func setEnabled(_ value: Bool) { enabled = value }
    private func save() throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(items).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    @discardableResult public func remember(_ text: String, days: Int = 30, now: Date = Date()) throws -> UUID {
        guard enabled else { throw PersonalAgentError.permissionDenied }
        guard !text.isEmpty, text.utf8.count <= 2048, (1...365).contains(days), items.count < 100 else { throw PersonalAgentError.storageFull }
        let item = PersonalMemoryItem(id:UUID(),text:text,expiresAt:now.addingTimeInterval(Double(days)*86400))
        let prior = items; items.append(item)
        do { try save() } catch { items = prior; throw error }; return item.id
    }
    public func search(_ query: String, now: Date = Date()) throws -> [PersonalMemoryItem] {
        let prior = items; items.removeAll { $0.expiresAt <= now }
        do { try save() } catch { items = prior; throw error }
        guard enabled else { return [] }
        return items.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
    }
    public func correct(_ id: UUID, text: String) throws {
        guard enabled, !text.isEmpty, text.utf8.count <= 2048, let i = items.firstIndex(where: { $0.id == id }) else { throw PersonalAgentError.invalidCommand }
        let prior = items; items[i].text = text
        do { try save() } catch { items = prior; throw error }
    }
    public func delete(_ id: UUID? = nil) throws {
        let prior = items; items.removeAll { id == nil || $0.id == id }
        do { try save() } catch { items = prior; throw error }
    }
}
