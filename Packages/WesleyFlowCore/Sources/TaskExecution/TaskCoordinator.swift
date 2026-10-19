import Domain

/// A single actor owns the FIFO and all worker leases. Executors receive no approval issuer.
public actor TaskCoordinator {
    private let history: any TaskHistoryRepository
    private let policy: any TaskPermissionPolicy
    private let executor: any TaskOperationExecutor
    private let verifier: any TaskVerificationRunner
    private let clock: any TaskClock
    private var records: [TaskIdentifier: TaskRecord] = [:]
    private var queue: [TaskIdentifier] = []
    private var active: TaskIdentifier?
    private var generations: [TaskIdentifier: Int] = [:]
    private var workers: [TaskIdentifier: Task<Void, Never>] = [:]
    private var cancelledWorkers: [TaskIdentifier: Task<Void, Never>] = [:]
    private var timers: [TaskIdentifier: Task<Void, Never>] = [:]
    private var drivers: [TaskIdentifier: Task<Void, Never>] = [:]
    private var inFlight: [TaskIdentifier: ScopedOperation] = [:]
    private var verifying: Set<TaskIdentifier> = []
    private var continuing: Set<TaskIdentifier> = []
    private var cancellationsPending: Set<TaskIdentifier> = []
    private var cleanupResults: [TaskIdentifier: CancellationAcknowledgement] = [:]
    private var usedTime: [TaskIdentifier: Int64] = [:]
    private var segmentStart: [TaskIdentifier: Int64] = [:]
    private struct StateWaiter {
        let kind: TaskState.Kind
        let continuation: CheckedContinuation<TaskRecord, any Error>
    }
    private var waiters: [TaskIdentifier: [Int: StateWaiter]] = [:]
    private var nextWaiter = 0
    private var deadlines: [TaskIdentifier: Int64] = [:]
    private var admissions: Set<TaskIdentifier> = []
    private var cancelledAdmissions: Set<TaskIdentifier> = []
    private var admissionTimers: [TaskIdentifier: Task<Void, Never>] = [:]
    private struct WriteWaiter {
        let taskID: TaskIdentifier
        let sequence: Int
        var continuation: CheckedContinuation<Void, any Error>?
    }
    private var nextWrite = 0
    private var writes: [Int: WriteWaiter] = [:]
    private var writeTasks: [Int: Task<Void, Never>] = [:]
    private var persistenceDisabled = false
    private var shutdownTimer: Task<Void, Never>?
    private var shutdownDriver: Task<Void, Never>?
    private var shutdownCancellations: [TaskIdentifier: Task<Void, Never>] = [:]
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private var emergencyJobs: [TaskIdentifier: Task<Void, Never>] = [:]
    public private(set) var shutdownCompleted = false
    public private(set) var latePersistenceAcknowledgements: [PersistenceAcknowledgement] = []
    public var hasPendingPersistence: Bool { !writeTasks.isEmpty }
    public var pendingAdmissionIDs: Set<TaskIdentifier> { admissions }
    private var mutationHeld = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private var stopped = false
    public private(set) var isBlocked = false
    public private(set) var isQuarantined = false

    public init(history: any TaskHistoryRepository, policy: any TaskPermissionPolicy,
                executor: any TaskOperationExecutor, verifier: any TaskVerificationRunner, clock: any TaskClock) {
        self.history = history; self.policy = policy; self.executor = executor; self.verifier = verifier; self.clock = clock
    }
    private func acquireMutation() async {
        if !mutationHeld { mutationHeld = true; return }
        await withCheckedContinuation { mutationWaiters.append($0) }
    }
    private func releaseMutation() {
        if mutationWaiters.isEmpty { mutationHeld = false } else { mutationWaiters.removeFirst().resume() }
        checkShutdown()
    }
    private func current(_ id: TaskIdentifier, _ generation: Int) -> Bool {
        !stopped && !isBlocked && !isQuarantined && active == id && generations[id] == generation && records[id]?.lifecycle.state.isTerminal == false && records[id]?.lifecycle.state.kind != .cancelling
    }
    private func publish(_ record: TaskRecord) {
        records[record.plan.id] = record
        for (token, waiter) in waiters[record.plan.id] ?? [:] {
            if record.lifecycle.state.kind == waiter.kind || record.lifecycle.state.isTerminal {
                waiters[record.plan.id]?.removeValue(forKey: token)
                waiter.continuation.resume(returning: record)
            }
        }
        if waiters[record.plan.id]?.isEmpty == true { waiters[record.plan.id] = nil }
    }
    public func snapshot(_ id: TaskIdentifier) -> TaskRecord? { records[id] }
    public func allRecords() -> [TaskRecord] { records.values.sorted { ($0.createdAt, $0.plan.id.rawValue) < ($1.createdAt, $1.plan.id.rawValue) } }
    public func waitForState(_ id: TaskIdentifier, _ kind: TaskState.Kind) async throws -> TaskRecord {
        try Task.checkCancellation()
        guard let record = records[id] else { throw TaskServiceError.unknownTask }
        if record.lifecycle.state.kind == kind || record.lifecycle.state.isTerminal { return record }
        let token = nextWaiter; nextWaiter += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                waiters[id, default: [:]][token] = StateWaiter(kind: kind, continuation: continuation)
            }
        } onCancel: {
            // Finite, nonthrowing actor hop; never owns effects or persistence.
            Task { await self.cancelWaiter(id, token) }
        }
    }
    private func cancelWaiter(_ id: TaskIdentifier, _ token: Int) {
        waiters[id]?.removeValue(forKey: token)?.continuation.resume(throwing: CancellationError())
        if waiters[id]?.isEmpty == true { waiters[id] = nil }
    }
    /// Explicit diagnostic drain. May wait indefinitely for a broken backend; never used by shutdown/close.
    public func waitForPersistenceSettlement() async {
        for task in Array(writeTasks.values) { await task.value }
    }
    private func write(_ record: TaskRecord, event: TaskEventRecord, expectedSequence: Int?) async throws {
        guard !persistenceDisabled else { throw TaskServiceError.storageUnavailable }
        let token = nextWrite; nextWrite += 1
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writes[token] = WriteWaiter(taskID: record.plan.id, sequence: record.sequence, continuation: continuation)
            // An owned task is necessary: a structured group would wait forever for a noncooperative backend.
            writeTasks[token] = Task {
                do {
                    try await Self.commitOnRepository(self.history, record: record, event: event, expectedSequence: expectedSequence)
                    self.writeFinished(token, error: nil)
                } catch { self.writeFinished(token, error: error) }
            }
        }
    }
    @concurrent
    private static func commitOnRepository(_ history: any TaskHistoryRepository, record: TaskRecord,
                                           event: TaskEventRecord, expectedSequence: Int?) async throws {
        // Do not let synchronous adapter I/O inherit the coordinator's execution context.
        try await history.commit(record, event: event, expectedSequence: expectedSequence)
    }
    private func writeFinished(_ token: Int, error: (any Error)?) {
        guard let waiter = writes.removeValue(forKey: token) else { return }
        writeTasks[token] = nil
        if let continuation = waiter.continuation {
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        } else {
            // A late receipt resolves storage acknowledgement only. It cannot replace an emergency task outcome.
            latePersistenceAcknowledgements.append(.init(taskID: waiter.taskID, sequence: waiter.sequence, succeeded: error == nil,
                                                             failure: error.map { $0 as? TaskServiceError ?? .storageUnavailable }))
        }
        checkShutdown()
    }
    private func interruptWrites() {
        persistenceDisabled = true; isBlocked = true
        for token in Array(writes.keys) {
            let continuation = writes[token]?.continuation
            writes[token]?.continuation = nil
            continuation?.resume(throwing: TaskServiceError.storageUnavailable)
        }
        // Keep every underlying task/receipt owned until it acknowledges, even after bounded shutdown returns.
    }
    public func start() async throws {
        await acquireMutation(); defer { releaseMutation() }
        guard !started else { return }
        await policy.beginSession()
        let saved = try await history.load()
        for var record in saved {
            let previous = record.lifecycle.state
            if !previous.isTerminal || (record.hasUnresolvedIntent && !record.requiresInspection) {
                record.previousState = record.previousState ?? previous
                record.requiresInspection = record.hasUnresolvedIntent || record.requiresInspection
                record.pendingApproval = nil
                var facts = TransitionFacts(); facts.isStartupRecovery = true
                facts.previousSessionIsRevoked = true; facts.effectsAreUncertain = true
                if previous.kind == .cancelling { try record.lifecycle.apply(.cleanupFailed(.interrupted), facts: facts) }
                else if !previous.isTerminal { try record.lifecycle.apply(.interrupted, facts: facts) }
                let sequence = record.sequence; record.sequence += 1; record.updatedAt = await clock.now()
                try await write(record, event: .init(record: record, kind: .interrupted, generation: 0), expectedSequence: sequence)
            }
            publish(record)
            if record.requiresInspection { isBlocked = true; isQuarantined = true }
        }
        started = true // No queued work or approval is replayed from the old session.
    }
    public func submit(_ plan: TaskPlan) async throws {
        try Task.checkCancellation()
        try plan.validate()
        guard !stopped else { throw TaskServiceError.closed }
        guard started else { throw TaskServiceError.notStarted }
        guard !isBlocked, !isQuarantined else { throw TaskServiceError.blocked }
        guard records[plan.id] == nil, !admissions.contains(plan.id) else { throw TaskServiceError.duplicateTask }
        let capacity = active == nil ? 17 : 16
        let pendingCount = admissions.filter { $0 != active && !queue.contains($0) }.count
        guard queue.count + pendingCount < capacity else { throw TaskServiceError.queueFull }
        admissions.insert(plan.id) // Registered before the first suspension; shutdown/cancel can now account for it.
        defer { admissions.remove(plan.id); cancelledAdmissions.remove(plan.id); admissionTimers[plan.id]?.cancel(); admissionTimers[plan.id] = nil; checkShutdown() }
        let accepted = try await persistAdmission(plan)
        guard accepted else {
            // The initial transaction may have committed; terminalize that known record before rejecting acknowledgement.
            admissions.remove(plan.id)
            await cancel(plan.id)
            throw TaskServiceError.closed
        }
    }
    private func persistAdmission(_ plan: TaskPlan) async throws -> Bool {
        await acquireMutation(); defer { releaseMutation() }
        guard !stopped, !cancelledAdmissions.contains(plan.id), !Task.isCancelled else { throw TaskServiceError.closed }
        let record = TaskRecord(plan: plan, now: await clock.now())
        guard !stopped, !cancelledAdmissions.contains(plan.id), !Task.isCancelled else { throw TaskServiceError.closed }
        var provisional = record; provisional.durability = .uncommitted
        publish(provisional)
        do { try await write(record, event: .init(record: record, kind: .submitted, generation: 0), expectedSequence: nil) }
        catch {
            isBlocked = true
            emergencyTerminal(plan.id, reason: .storage)
            if let running = active { scheduleStorageFailure(running) }
            if stopped || cancelledAdmissions.contains(plan.id) { throw TaskServiceError.closed }
            throw error
        }
        // Acknowledgement linearizes here, without another await before the public call returns.
        guard !stopped, !cancelledAdmissions.contains(plan.id), !Task.isCancelled else {
            if records[plan.id]?.lifecycle.state.isTerminal != true { publish(record) }
            return false
        }
        publish(record); generations[plan.id] = 0; queue.append(plan.id); pump()
        return true
    }
    public func retry(_ id: TaskIdentifier, as newID: TaskIdentifier) async throws {
        guard let old = records[id], old.lifecycle.state.isTerminal else { throw TaskServiceError.invalidPlan }
        try await submit(TaskPlan(id: newID, workflowID: old.plan.workflowID, workflowVersion: old.plan.workflowVersion, workspaceID: old.plan.workspaceID,
                                 revision: old.plan.revision, steps: old.plan.steps, verification: old.plan.verification,
                                 retryOf: id, retryCount: old.plan.retryCount + 1))
    }
    private func pump() {
        guard active == nil, !queue.isEmpty, !isBlocked, !isQuarantined, !stopped else { return }
        let id = queue.removeFirst(); active = id; let generation = generations[id, default: 0]
        drivers[id] = Task { await self.begin(id, generation) }
    }
    private func change(_ id: TaskIdentifier, kind: TaskEventKind, operation: ScopedOperation? = nil,
                        generation: Int? = nil, edit: (inout TaskRecord) throws -> Void) async throws {
        await acquireMutation(); defer { releaseMutation() }
        if let generation, !current(id, generation) { throw TaskServiceError.staleOperation }
        guard var record = records[id] else { throw TaskServiceError.unknownTask }
        let sequence = record.sequence
        try edit(&record); record.sequence += 1; record.updatedAt = await clock.now()
        if let generation, !current(id, generation) { throw TaskServiceError.staleOperation }
        try await write(record, event: .init(record: record, kind: kind, operation: operation, generation: generations[id, default: 0]), expectedSequence: sequence)
        // A bounded emergency overlay must never be replaced by an older completed write.
        if records[id]?.durability == .uncommitted, records[id]?.lifecycle.state.isTerminal == true {
            throw TaskServiceError.staleOperation
        }
        publish(record)
        if let generation, !current(id, generation) && !record.lifecycle.state.isTerminal { throw TaskServiceError.staleOperation }
    }
    private func begin(_ id: TaskIdentifier, _ generation: Int) async {
        do {
            segmentStart[id] = await clock.now()
            try await change(id, kind: .transition, generation: generation) {
                var facts = TransitionFacts(); facts.isQueueHead = true; facts.hasExecutionLease = true
                try $0.lifecycle.apply(.start, facts: facts)
            }
            try await pauseForApproval(id, generation, verification: false)
        } catch { await handle(error, id, generation) }
    }
    private func pauseForApproval(_ id: TaskIdentifier, _ generation: Int, verification: Bool) async throws {
        guard current(id, generation), let record = records[id] else { throw TaskServiceError.staleOperation }
        let operation: ScopedOperation
        if verification { guard let item = record.plan.verification else { throw TaskServiceError.invalidPlan }; operation = item }
        else { operation = record.plan.steps[record.completedOperations.count] }
        let request = try await policy.request(taskID: id, operation: operation, generation: generation)
        guard current(id, generation) else { await policy.revoke(taskID: id); throw TaskServiceError.staleOperation }
        let now = await clock.now()
        if let start = segmentStart[id] { usedTime[id, default: 0] += max(0, now - start); segmentStart[id] = nil }
        guard usedTime[id, default: 0] < 900_000 else { throw TaskServiceError.executionLimit }
        try await change(id, kind: .approvalRequested, operation: operation, generation: generation) {
            var facts = TransitionFacts(); facts.hasPendingExactOperation = true
            try $0.lifecycle.apply(.requestApproval, facts: facts); $0.pendingApproval = request
        }
        guard current(id, generation) else { return }
        timers[id]?.cancel()
        timers[id] = Task {
            do { try await self.clock.sleep(until: request.expiresAt) }
            catch { return }
            if self.current(id, generation), self.records[id]?.pendingApproval?.id == request.id { await self.cancel(id, failure: .approvalExpired) }
        }
    }
    /// Only resumes a decision minted by the trusted authority. Calling this does not grant approval.
    public func resumeApproval(_ id: TaskIdentifier) async throws {
        guard let record = records[id], let request = record.pendingApproval,
              record.lifecycle.state.kind == .awaitingApproval, !continuing.contains(id) else { throw TaskServiceError.staleOperation }
        let generation = generations[id, default: 0]
        continuing.insert(id); defer { continuing.remove(id) }
        do {
            try await policy.validate(request, operation: request.operation, generation: generation)
            guard current(id, generation) else { throw TaskServiceError.staleOperation }
            timers[id]?.cancel(); segmentStart[id] = await clock.now()
            try await change(id, kind: .approvalGranted, operation: request.operation, generation: generation) {
                var facts = TransitionFacts(); facts.approvalIsValid = true
                try $0.lifecycle.apply(request.operation.kind == .verification ? .approveVerification : .approveExecution, facts: facts)
                $0.pendingApproval = nil
            }
            let now = await clock.now()
            let spent = usedTime[id, default: 0] + max(0, now - (segmentStart[id] ?? now))
            guard spent < 900_000 else { throw TaskServiceError.executionLimit }
            let deadline = now + min(300_000, 900_000 - spent)
            try await change(id, kind: .intent, operation: request.operation, generation: generation) {
                $0.intents.append(request.operation.id); $0.executionDeadline = deadline
            }
            // Intent is durable before authority is consumed and any executor is invoked.
            try await dispatch(id, generation, request.operation, approval: request, deadline: deadline)
        } catch TaskServiceError.approvalRequired { throw TaskServiceError.approvalRequired }
        catch TaskServiceError.approvalDenied { await cancel(id, failure: nil, kind: .approvalDenied) }
        catch { await handle(error, id, generation) }
    }
    private func dispatch(_ id: TaskIdentifier, _ generation: Int, _ operation: ScopedOperation,
                          approval: ApprovalRequest, deadline: Int64) async throws {
        guard current(id, generation) else { throw TaskServiceError.staleOperation }
        let token = OperationToken(taskID: id, operationID: operation.id, generation: generation)
        // Final authorization checks both grant expiry and the work deadline. No await follows before worker ownership is installed.
        try await policy.consume(approval, operation: operation, generation: generation, notAfter: deadline)
        guard current(id, generation) else { throw TaskServiceError.staleOperation }
        inFlight[id] = operation; deadlines[id] = deadline
        if operation.kind == .verification { verifying.insert(id) }
        timers[id] = Task {
            do { try await self.clock.sleep(until: deadline) } catch { return }
            if self.current(id, generation) { await self.cancel(id, failure: .timeout) }
        }
        workers[id] = Task {
            let dispatchTime = await self.clock.now()
            guard self.current(id, generation), !Task.isCancelled else { return }
            guard dispatchTime < deadline else { await self.cancel(id, failure: .timeout); return }
            do {
                if operation.kind == .verification {
                    let evidence = try await self.verifier.verify(operation, token: token)
                    await self.finished(id, generation, operation, passed: evidence.passed,
                                        revision: evidence.observedRevision, digest: evidence.operationDigest)
                } else {
                    let result = try await self.executor.execute(operation, token: token)
                    await self.finished(id, generation, operation, passed: result.succeeded,
                                        revision: result.observedRevision, digest: operation.digest)
                }
            } catch { await self.workerFailed(id, generation, error) }
        }
    }
    private func finished(_ id: TaskIdentifier, _ generation: Int, _ operation: ScopedOperation,
                          passed: Bool, revision: String, digest: String) async {
        let now = await clock.now()
        let diagnostic = LateOperationResult(operationID: operation.id, generation: generation, observedAt: now,
                                             succeeded: passed, revisionMatches: revision == operation.revision, digestMatches: digest == operation.digest)
        guard current(id, generation) else { await recordLateResult(id, diagnostic, operation: operation); return }
        guard let deadline = deadlines[id], now < deadline else {
            await cancelOwned(id, failure: .timeout, kind: .cancellation, diagnostic: diagnostic)
            return
        }
        // Acceptance linearizes at this monotonic check. Timers cannot reverse an on-time accepted result.
        timers[id]?.cancel(); deadlines[id] = nil; inFlight[id] = nil; workers[id] = nil; verifying.remove(id)
        do {
            let matches = revision == operation.revision && digest == operation.digest
            try await change(id, kind: operation.kind == .verification ? .verification : .outcome, operation: operation, generation: generation) {
                $0.outcomes.append(operation.id)
                if passed && matches && operation.kind != .verification { $0.completedOperations.append(operation.id) }
            }
            guard passed, matches else { await fail(id, generation, matches ? (operation.kind == .verification ? .verification : .execution) : .conflict); return }
            if operation.kind == .verification {
                try await change(id, kind: .transition, generation: generation) {
                    var facts = TransitionFacts(); facts.evidenceIsCommitted = true; facts.workspaceRevisionMatches = true
                    try $0.lifecycle.apply(.verificationPassed, facts: facts)
                }
                release(id)
            } else if let record = records[id], record.completedOperations.count < record.plan.steps.count {
                try await pauseForApproval(id, generation, verification: false)
            } else if records[id]?.plan.verification == nil {
                try await change(id, kind: .transition, generation: generation) {
                    var facts = TransitionFacts(); facts.executionIsComplete = true
                    try $0.lifecycle.apply(.noVerificationDone, facts: facts)
                }
                release(id)
            } else {
                try await change(id, kind: .transition, generation: generation) {
                    var facts = TransitionFacts(); facts.executionIsComplete = true
                    try $0.lifecycle.apply(.executionDone, facts: facts)
                }
                try await pauseForApproval(id, generation, verification: true)
            }
        } catch { await handle(error, id, generation) }
    }
    private func workerFailed(_ id: TaskIdentifier, _ generation: Int, _ error: any Error) async {
        guard current(id, generation) else { return }
        // A thrown adapter call does not prove that it released its resources.
        await cancel(id, failure: error is CancellationError ? .timeout : .execution)
    }
    private func fail(_ id: TaskIdentifier, _ generation: Int, _ reason: TaskFailure) async {
        guard current(id, generation) else { return }
        do {
            await policy.revoke(taskID: id)
            try await change(id, kind: .transition, generation: generation) {
                var facts = TransitionFacts(); facts.resourcesAreReleased = true
                try $0.lifecycle.apply(.failure(reason), facts: facts)
            }
            release(id)
        } catch TaskServiceError.staleOperation { return }
        catch { await storageFailure(id) }
    }
    private func handle(_ error: any Error, _ id: TaskIdentifier, _ generation: Int) async {
        guard current(id, generation) else { return }
        switch error {
        case TaskServiceError.staleOperation: return
        case TaskServiceError.approvalExpired: await cancel(id, failure: .approvalExpired)
        case TaskServiceError.executionLimit: await cancel(id, failure: .limitExceeded)
        case TaskServiceError.unsupportedOperation: await fail(id, generation, .policyDenied)
        default: await storageFailure(id)
        }
    }
    public func cancel(_ id: TaskIdentifier, failure: TaskFailure? = nil, kind: TaskEventKind = .cancellation) async {
        if admissions.contains(id) {
            cancelledAdmissions.insert(id)
            if admissionTimers[id] == nil {
                let deadline = await clock.now() + 5_000
                admissionTimers[id] = Task {
                    do { try await self.clock.sleep(until: deadline) } catch { return }
                    guard self.admissions.contains(id) else { return }
                    self.interruptWrites(); self.emergencyTerminal(id, reason: .storage)
                }
            }
            return
        }
        await cancelOwned(id, failure: failure, kind: kind, diagnostic: nil)
    }
    private func cancelOwned(_ id: TaskIdentifier, failure: TaskFailure?, kind: TaskEventKind,
                             diagnostic: LateOperationResult?) async {
        guard let record = records[id], !record.lifecycle.state.isTerminal, record.lifecycle.state.kind != .cancelling, !cancellationsPending.contains(id) else { return }
        cancellationsPending.insert(id)
        let oldGeneration = generations[id, default: 0]
        let generation = oldGeneration + 1; generations[id] = generation
        timers[id]?.cancel()
        if let worker = workers[id] { worker.cancel(); cancelledWorkers[id] = worker }
        drivers[id]?.cancel()
        queue.removeAll { $0 == id }
        await policy.revoke(taskID: id) // Never depends on a successful history save.
        let operation = inFlight[id]
        let wasVerification = verifying.contains(id)
        let token = operation.map { OperationToken(taskID: id, operationID: $0.id, generation: oldGeneration) }
        // Start cleanup before waiting for the cancellation record to save.
        let deadline = await clock.now() + 5_000
        timers[id] = Task {
            do { try await self.clock.sleep(until: deadline) } catch { return }
            self.cancellationDeadline(id, generation)
        }
        if let token {
            workers[id] = Task {
                let ack = wasVerification ? await self.verifier.cancel(token) : await self.executor.cancel(token)
                await self.cleanupFinished(id, generation, ack)
            }
        } else {
            // No dispatch occurred, so there is no adapter/resource whose acknowledgement can time out.
            cleanupResults[id] = .stopped
        }
        do {
            try await change(id, kind: kind) {
                guard !$0.lifecycle.state.isTerminal else { return }
                $0.pendingApproval = nil
                if let diagnostic { $0.lateResults = ($0.lateResults ?? []) + [diagnostic] }
                try $0.lifecycle.apply(.cancel(failure.map { .failed($0) } ?? .cancelled))
            }
        } catch {
            isBlocked = true
            if var value = records[id], !value.lifecycle.state.isTerminal {
                value.durability = .uncommitted; value.pendingApproval = nil
                if let diagnostic { value.lateResults = (value.lateResults ?? []) + [diagnostic] }
                if value.lifecycle.state.kind != .cancelling { try? value.lifecycle.apply(.cancel(.failed(.storage))) }
                publish(value)
            }
        }
        cancellationsPending.remove(id)
        if let result = cleanupResults.removeValue(forKey: id) { await cleanupFinished(id, generation, result) }
    }
    private func cleanupFinished(_ id: TaskIdentifier, _ generation: Int, _ ack: CancellationAcknowledgement) async {
        // Cleanup and cancellation commits serialize on the same lock. Callbacks cannot resume work.
        await acquireMutation(); defer { releaseMutation() }
        guard generations[id] == generation, var record = records[id], !record.lifecycle.state.isTerminal else { return }
        guard record.lifecycle.state.kind == .cancelling else {
            if cancellationsPending.contains(id) { cleanupResults[id] = ack }
            return
        }
        workers[id] = nil
        let stoppedCleanly = ack == .stopped
        var facts = TransitionFacts(); facts.cleanupIsComplete = stoppedCleanly; facts.cleanupDidFail = !stoppedCleanly
        let oldSequence = record.sequence
        do {
            if case .cancelling(intent: .cancelled) = record.lifecycle.state, stoppedCleanly { try record.lifecycle.apply(.cleanupCancelled, facts: facts) }
            else { try record.lifecycle.apply(.cleanupFailed(.cleanupIncomplete), facts: facts) }
            record.pendingApproval = nil
            record.requiresInspection = record.requiresInspection || record.hasUnresolvedIntent
            if !stoppedCleanly { record.requiresInspection = true; isQuarantined = true; isBlocked = true }
            record.sequence += 1; record.updatedAt = await clock.now()
            if record.durability == .committed {
                do { try await write(record, event: .init(record: record, kind: .cleanup, generation: generation), expectedSequence: oldSequence) }
                catch { record.durability = .uncommitted; isBlocked = true }
            }
            if records[id]?.lifecycle.state.isTerminal == true, records[id]?.durability == .uncommitted { return }
            publish(record); timers[id]?.cancel(); timers[id] = nil
            if stoppedCleanly { inFlight[id] = nil; verifying.remove(id); release(id) }
            // Unknown ownership retains the active lease, including after a terminal cleanup failure.
        } catch { isBlocked = true; isQuarantined = true }
    }
    private func storageFailure(_ id: TaskIdentifier) async {
        isBlocked = true
        await cancel(id, failure: .storage)
    }
    private func release(_ id: TaskIdentifier) {
        timers[id]?.cancel(); timers[id] = nil; workers[id] = nil; cancelledWorkers[id] = nil; drivers[id] = nil
        segmentStart[id] = nil; deadlines[id] = nil
        if active == id { active = nil }
        pump()
    }
    private func recordLateResult(_ id: TaskIdentifier, _ result: LateOperationResult, operation: ScopedOperation) async {
        await acquireMutation(); defer { releaseMutation() }
        guard var record = records[id], !(record.lateResults ?? []).contains(where: { $0.operationID == result.operationID && $0.generation == result.generation }) else { return }
        record.lateResults = Array(((record.lateResults ?? []) + [result]).suffix(50))
        if record.durability == .committed, !persistenceDisabled {
            let sequence = record.sequence; record.sequence += 1; record.updatedAt = result.observedAt
            do { try await write(record, event: .init(record: record, kind: .lateResult, operation: operation, generation: result.generation), expectedSequence: sequence) }
            catch { record.durability = .uncommitted; isBlocked = true }
        } else { record.durability = .uncommitted }
        // Diagnostics cannot change the established lifecycle or turn an unknown intent into an outcome.
        if let current = records[id], current.lifecycle.state != record.lifecycle.state { return }
        publish(record)
    }
    private func emergencyTerminal(_ id: TaskIdentifier, reason: TaskFailure) {
        guard var record = records[id], !record.lifecycle.state.isTerminal else { return }
        record.durability = .uncommitted; record.pendingApproval = nil
        record.requiresInspection = record.requiresInspection || record.hasUnresolvedIntent || hasPendingPersistence
        do {
            if record.lifecycle.state.kind != .cancelling { try record.lifecycle.apply(.cancel(.failed(reason))) }
            var facts = TransitionFacts(); facts.cleanupDidFail = true
            try record.lifecycle.apply(.cleanupFailed(reason), facts: facts)
            publish(record)
        } catch { isBlocked = true; isQuarantined = true }
    }
    private func cancellationDeadline(_ id: TaskIdentifier, _ generation: Int) {
        guard generations[id] == generation, records[id]?.lifecycle.state.isTerminal == false else { return }
        let storagePending = hasPendingPersistence
        isBlocked = true; isQuarantined = true
        if storagePending { interruptWrites() }
        emergencyTerminal(id, reason: storagePending ? .storage : .cleanupIncomplete)
        if !storagePending, !persistenceDisabled, emergencyJobs[id] == nil {
            emergencyJobs[id] = Task {
                await self.persistEmergency(id)
                self.emergencyJobs[id] = nil; self.checkShutdown()
            }
        }
        checkShutdown()
    }
    private func persistEmergency(_ id: TaskIdentifier) async {
        await acquireMutation(); defer { releaseMutation() }
        guard var record = records[id], record.lifecycle.state.isTerminal,
              record.durability == .uncommitted, !persistenceDisabled else { return }
        let sequence = record.sequence
        record.sequence += 1; record.updatedAt = await clock.now(); record.durability = .committed
        do {
            try await write(record, event: .init(record: record, kind: .cleanup, generation: generations[id, default: 0]), expectedSequence: sequence)
            publish(record)
        } catch { isBlocked = true } // The emergency overlay remains explicitly uncommitted.
    }
    private func scheduleStorageFailure(_ id: TaskIdentifier) {
        guard emergencyJobs[id] == nil else { return }
        emergencyJobs[id] = Task {
            await self.storageFailure(id); self.emergencyJobs[id] = nil; self.checkShutdown()
        }
    }
    public func shutdown() async {
        if shutdownCompleted { return }
        if !stopped {
            stopped = true // The admission gate closes atomically before any suspension.
            shutdownDriver = Task { await self.beginShutdown() }
        }
        await withCheckedContinuation { shutdownWaiters.append($0) }
    }
    private func beginShutdown() async {
        let deadline = await clock.now() + 5_000
        shutdownTimer = Task {
            do { try await self.clock.sleep(until: deadline) } catch { return }
            self.shutdownDeadline()
        }
        for id in admissions { cancelledAdmissions.insert(id) }
        for id in records.keys where records[id]?.lifecycle.state.isTerminal == false && !admissions.contains(id) {
            shutdownCancellations[id] = Task {
                await self.cancel(id)
                self.shutdownCancellations[id] = nil; self.checkShutdown()
            }
        }
        shutdownDriver = nil; checkShutdown()
    }
    private func checkShutdown() {
        guard stopped, !shutdownCompleted, shutdownDriver == nil, admissions.isEmpty,
              shutdownCancellations.isEmpty, emergencyJobs.isEmpty, !mutationHeld, !hasPendingPersistence,
              records.values.allSatisfy({ $0.lifecycle.state.isTerminal }) else { return }
        finishShutdown()
    }
    private func shutdownDeadline() {
        guard !shutdownCompleted else { return }
        let reason: TaskFailure = hasPendingPersistence ? .storage : .cleanupIncomplete
        interruptWrites(); isQuarantined = true
        for id in records.keys { emergencyTerminal(id, reason: reason) }
        finishShutdown() // Emergency status and return never wait for the durable mutation gate.
    }
    private func finishShutdown() {
        persistenceDisabled = true; shutdownCompleted = true
        shutdownTimer?.cancel(); shutdownTimer = nil
        let waiting = shutdownWaiters; shutdownWaiters = []
        waiting.forEach { $0.resume() }
    }
}
