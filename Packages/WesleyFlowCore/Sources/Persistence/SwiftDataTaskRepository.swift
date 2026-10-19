import Domain
import Foundation
import SwiftData
import Darwin

@Model final class StoredTask {
    @Attribute(.unique) var taskID: String
    var sequence: Int
    var payload: Data
    init(taskID: String, sequence: Int, payload: Data) { self.taskID = taskID; self.sequence = sequence; self.payload = payload }
}
@Model final class StoredEvent {
    @Attribute(.unique) var eventKey: String
    var taskID: String
    var sequence: Int
    var payload: Data
    init(taskID: String, sequence: Int, payload: Data) {
        self.taskID = taskID; self.sequence = sequence; self.payload = payload
        eventKey = "\(taskID):\(sequence)"
    }
}
enum HistorySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StoredTask.self, StoredEvent.self] }
}
enum HistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HistorySchemaV1.self] }
    static var stages: [MigrationStage] { [] } // Future versions require an explicit backed-up migration.
}
public enum PersistenceCheckpoint: Sendable { case beforeSave, afterSave }

public actor SwiftDataTaskRepository: TaskHistoryRepository {
    private nonisolated let storeExecutor: DefaultSerialModelExecutor
    public nonisolated var unownedExecutor: UnownedSerialExecutor { storeExecutor.asUnownedSerialExecutor() }
    private var container: ModelContainer?
    private var context: ModelContext?
    private var lockDescriptor: Int32
    private let directory: URL
    private let byteLimit: Int
    private let recoveryReserve: Int
    private let inject: (@Sendable (PersistenceCheckpoint) throws -> Void)?

    @concurrent
    public static func open(url: URL, byteLimit: Int = 100 * 1024 * 1024, recoveryReserve: Int = 10 * 1024 * 1024,
                            failureInjector: (@Sendable (PersistenceCheckpoint) throws -> Void)? = nil) async throws -> SwiftDataTaskRepository {
        // Construction happens off the caller's actor; all later access uses SwiftData's serial executor.
        try SwiftDataTaskRepository(url: url, byteLimit: byteLimit, recoveryReserve: recoveryReserve, failureInjector: failureInjector)
    }
    private init(url: URL, byteLimit: Int = 100 * 1024 * 1024, recoveryReserve: Int = 10 * 1024 * 1024,
                failureInjector: (@Sendable (PersistenceCheckpoint) throws -> Void)? = nil) throws {
        guard byteLimit > 0, recoveryReserve >= 0, recoveryReserve <= byteLimit else { throw TaskServiceError.invalidPlan }
        directory = url.deletingLastPathComponent()
        self.byteLimit = byteLimit; self.recoveryReserve = recoveryReserve; inject = failureInjector
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = url.appendingPathExtension("schema")
        if FileManager.default.fileExists(atPath: marker.path), try Data(contentsOf: marker) != Data("1\n".utf8) {
            throw TaskServiceError.incompatibleSchema
        }
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 16) == Data("SQLite format 3\0".utf8) else { throw TaskServiceError.corruptStore }
        }
        let fd = Darwin.open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw TaskServiceError.storageUnavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); throw TaskServiceError.storeAlreadyOpen }
        lockDescriptor = fd
        do {
            let schema = Schema(versionedSchema: HistorySchemaV1.self)
            let configuration = ModelConfiguration("TaskHistory", schema: schema, url: url, cloudKitDatabase: .none)
            let store = try ModelContainer(for: schema, migrationPlan: HistoryMigrationPlan.self, configurations: [configuration])
            container = store
            let ctx = ModelContext(store); ctx.autosaveEnabled = false; context = ctx
            storeExecutor = DefaultSerialModelExecutor(modelContext: ctx)
            if !FileManager.default.fileExists(atPath: marker.path) { try Data("1\n".utf8).write(to: marker, options: .atomic) }
        } catch {
            flock(fd, LOCK_UN); Darwin.close(fd)
            throw error // Preserve original store, WAL, and marker. No deletion or silent reset.
        }
    }
    deinit { if lockDescriptor >= 0 { flock(lockDescriptor, LOCK_UN); Darwin.close(lockDescriptor) } }
    public func close() {
        context = nil; container = nil
        if lockDescriptor >= 0 { flock(lockDescriptor, LOCK_UN); Darwin.close(lockDescriptor); lockDescriptor = -1 }
    }
    private func modelContext() throws -> ModelContext {
        guard let context else { throw TaskServiceError.closed }; return context
    }
    private func decode(_ data: Data) throws -> TaskRecord {
        do {
            let value = try JSONDecoder().decode(TaskRecord.self, from: data)
            try value.plan.validate()
            guard value.plan.id == value.lifecycle.id, value.lifecycle.retryOf == value.plan.retryOf, value.lifecycle.verification == value.plan.verificationRequirement,
                  value.sequence >= 0, value.durability == .committed,
                  Set(value.intents).count == value.intents.count,
                  Set(value.outcomes).isSubset(of: Set(value.intents)),
                  Set(value.completedOperations).isSubset(of: Set(value.plan.steps.map(\.id))),
                  (value.lateResults?.count ?? 0) <= 50,
                  (value.lateResults ?? []).allSatisfy({ item in
                      item.generation >= 0 && (value.plan.steps + (value.plan.verification.map { [$0] } ?? [])).contains(where: { $0.id == item.operationID })
                  }) else { throw TaskServiceError.corruptStore }
            return value
        } catch { throw TaskServiceError.corruptStore }
    }
    public func load() throws -> [TaskRecord] {
        let rows = try modelContext().fetch(FetchDescriptor<StoredTask>())
        return try rows.map { row in
            let record = try decode(row.payload)
            guard record.plan.id.rawValue == row.taskID, record.sequence == row.sequence else { throw TaskServiceError.corruptStore }
            let audit = try events(for: record.plan.id)
            guard record.sequence == audit.count - 1, audit.enumerated().allSatisfy({ $0.offset == $0.element.sequence }), audit.last?.state == record.lifecycle.state else { throw TaskServiceError.corruptStore }
            return record
        }.sorted { ($0.createdAt, $0.plan.id.rawValue) < ($1.createdAt, $1.plan.id.rawValue) }
    }
    public func events(for taskID: TaskIdentifier) throws -> [TaskEventRecord] {
        let id = taskID.rawValue
        let rows = try modelContext().fetch(FetchDescriptor<StoredEvent>(predicate: #Predicate { $0.taskID == id }, sortBy: [SortDescriptor(\.sequence)]))
        return try rows.map { row in
            do {
                let event = try JSONDecoder().decode(TaskEventRecord.self, from: row.payload)
                guard event.taskID == taskID, event.sequence == row.sequence else { throw TaskServiceError.corruptStore }
                return event
            } catch { throw TaskServiceError.corruptStore }
        }
    }
    public func storageBytes() throws -> Int {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]).reduce(0) {
            $0 + ((try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
    public func commit(_ record: TaskRecord, event: TaskEventRecord, expectedSequence: Int?) throws {
        let ctx = try modelContext()
        let bytes = try JSONEncoder().encode(record)
        _ = try decode(bytes)
        if let expectedSequence { guard expectedSequence >= 0, expectedSequence < Int.max else { throw TaskServiceError.repositoryConflict } }
        guard record.plan.id == event.taskID, record.sequence == event.sequence, record.lifecycle.state == event.state,
              record.updatedAt == event.timestamp,
              record.sequence == (expectedSequence.map { $0 + 1 } ?? 0) else { throw TaskServiceError.repositoryConflict }
        let id = record.plan.id.rawValue
        let existing = try ctx.fetch(FetchDescriptor<StoredTask>(predicate: #Predicate { $0.taskID == id })).first
        if let existing {
            let previous = try decode(existing.payload)
            guard existing.sequence == expectedSequence, previous.plan == record.plan,
                  !previous.lifecycle.state.isTerminal || previous.lifecycle.state == record.lifecycle.state else { throw TaskServiceError.repositoryConflict }
        } else if expectedSequence != nil { throw TaskServiceError.repositoryConflict }
        let key = "\(id):\(record.sequence)"
        guard try ctx.fetch(FetchDescriptor<StoredEvent>(predicate: #Predicate { $0.eventKey == key })).isEmpty else { throw TaskServiceError.repositoryConflict }
        let eventBytes = try JSONEncoder().encode(event)
        let essential = [.outcome, .verification, .cancellation, .cleanup, .interrupted, .lateResult].contains(event.kind) || record.lifecycle.state.isTerminal
        let ceiling = essential ? byteLimit : byteLimit - recoveryReserve
        guard try storageBytes() + bytes.count + eventBytes.count + 4096 <= ceiling else { throw TaskServiceError.quotaExceeded }
        do {
            if let existing { existing.sequence = record.sequence; existing.payload = bytes }
            else { ctx.insert(StoredTask(taskID: id, sequence: record.sequence, payload: bytes)) }
            ctx.insert(StoredEvent(taskID: id, sequence: event.sequence, payload: eventBytes))
            try inject?(.beforeSave)
            try ctx.save() // State and event share a single explicit store transaction.
            try inject?(.afterSave) // A thrown acknowledgement fault is an uncertain commit, not an automatic retry.
        } catch { ctx.rollback(); throw error }
    }
    public func prune(now: Int64) throws -> Int {
        let cutoff = now - 30 * 86_400_000
        let candidates = try load().filter { $0.lifecycle.state.isTerminal && !$0.requiresInspection && !$0.hasUnresolvedIntent && $0.updatedAt < cutoff }
        for record in candidates { try remove(record.plan.id) }
        return candidates.count
    }
    public func remove(_ id: TaskIdentifier) throws {
        let ctx = try modelContext(); let key = id.rawValue
        guard let row = try ctx.fetch(FetchDescriptor<StoredTask>(predicate: #Predicate { $0.taskID == key })).first else { return }
        let record = try decode(row.payload)
        guard record.lifecycle.state.isTerminal, !record.requiresInspection, !record.hasUnresolvedIntent else { throw TaskServiceError.blocked }
        do {
            for event in try ctx.fetch(FetchDescriptor<StoredEvent>(predicate: #Predicate { $0.taskID == key })) { ctx.delete(event) }
            ctx.delete(row); try ctx.save()
        } catch { ctx.rollback(); throw error }
    }
}
