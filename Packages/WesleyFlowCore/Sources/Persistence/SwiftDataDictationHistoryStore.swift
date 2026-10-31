import Domain
import Foundation
import SwiftData
import Darwin

@Model final class StoredDictationEntry {
    @Attribute(.unique) var identity: String
    var timestamp: Date
    var payload: Data
    init(_ entry: DictationHistoryEntry, payload: Data) { identity = entry.id; timestamp = entry.timestamp; self.payload = payload }
}
enum DictationSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1,0,0)
    static var models: [any PersistentModel.Type] { [StoredDictationEntry.self] }
}
enum DictationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [DictationSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
/// A separate versioned store leaves the existing task/event schema untouched.
public actor SwiftDataDictationHistoryStore: DictationHistoryStore {
    private nonisolated let executor: DefaultSerialModelExecutor
    public nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    private var container: ModelContainer?
    private var context: ModelContext?
    private var descriptor: Int32
    private let url: URL
    private let entryLimit: Int
    @concurrent public static func open(url: URL, entryLimit: Int = 2000) async throws -> SwiftDataDictationHistoryStore { try .init(url:url,entryLimit:entryLimit) }
    private init(url: URL, entryLimit: Int) throws {
        guard (1...2000).contains(entryLimit) else { throw DictationHistoryFailure.invalidEntry }
        self.entryLimit = entryLimit; self.url = url
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let marker = url.appendingPathExtension("schema")
        if FileManager.default.fileExists(atPath:marker.path), try Data(contentsOf:marker) != Data("1\n".utf8) { throw DictationHistoryFailure.incompatibleSchema }
        if FileManager.default.fileExists(atPath:url.path) {
            let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
            guard try file.read(upToCount:16) == Data("SQLite format 3\0".utf8) else { throw DictationHistoryFailure.corrupt }
        }
        let fd = Darwin.open(url.appendingPathExtension("lock").path,O_CREAT|O_RDWR,S_IRUSR|S_IWUSR)
        guard fd >= 0 else { throw DictationHistoryFailure.unavailable }
        guard flock(fd,LOCK_EX|LOCK_NB) == 0 else { Darwin.close(fd); throw DictationHistoryFailure.alreadyOpen }
        descriptor = fd
        do {
            let schema = Schema(versionedSchema:DictationSchemaV1.self)
            let config = ModelConfiguration("DictationHistory",schema:schema,url:url,cloudKitDatabase:.none)
            let container = try ModelContainer(for:schema,migrationPlan:DictationMigrationPlan.self,configurations:[config])
            self.container = container
            let context = ModelContext(container); context.autosaveEnabled = false; self.context = context
            executor = DefaultSerialModelExecutor(modelContext:context)
            if !FileManager.default.fileExists(atPath:marker.path) { try Data("1\n".utf8).write(to:marker,options:.atomic) }
            for suffix in ["","-wal","-shm",".schema",".lock"] {
                let file = url.path + suffix
                if FileManager.default.fileExists(atPath:file) { try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file) }
            }
        } catch { flock(fd,LOCK_UN); Darwin.close(fd); throw error }
    }
    deinit { if descriptor >= 0 { flock(descriptor,LOCK_UN); Darwin.close(descriptor) } }
    private func ctx() throws -> ModelContext { guard let context else { throw DictationHistoryFailure.closed }; return context }
    public func load() throws -> [DictationHistoryEntry] {
        var fetch = FetchDescriptor<StoredDictationEntry>(); fetch.fetchLimit = entryLimit + 1
        let rows = try ctx().fetch(fetch)
        guard rows.count <= entryLimit else { throw DictationHistoryFailure.corrupt }
        return try rows.map { row in
            guard row.payload.count <= DictationText.maximumBytes * 12 + 8192, let entry = try? JSONDecoder().decode(DictationHistoryEntry.self,from:row.payload),
                  entry.id == row.identity, entry.timestamp == row.timestamp else { throw DictationHistoryFailure.corrupt }
            try entry.validate(); return entry
        }.sorted { ($0.timestamp,$0.id) > ($1.timestamp,$1.id) }
    }
    public func append(_ entry: DictationHistoryEntry) throws {
        try entry.validate(); let context = try ctx()
        let id = entry.id
        guard try context.fetchCount(FetchDescriptor<StoredDictationEntry>()) < entryLimit else { throw DictationHistoryFailure.full }
        guard try context.fetch(FetchDescriptor<StoredDictationEntry>(predicate:#Predicate { $0.identity == id })).isEmpty else { throw DictationHistoryFailure.invalidEntry }
        let size = ["","-wal","-shm"].reduce(0) { sum,suffix in
            sum + ((try? FileManager.default.attributesOfItem(atPath:url.path+suffix)[.size] as? NSNumber)?.intValue ?? 0)
        }
        guard size < 100 * 1024 * 1024 - (DictationText.maximumBytes * 12 + 8192) * 2 else { throw DictationHistoryFailure.full }
        do { context.insert(StoredDictationEntry(entry,payload:try JSONEncoder().encode(entry))); try context.save() }
        catch { context.rollback(); throw DictationHistoryFailure.unavailable }
    }
    public func delete(id: String) throws {
        let context = try ctx()
        do {
            let rows = try context.fetch(FetchDescriptor<StoredDictationEntry>(predicate:#Predicate { $0.identity == id }))
            rows.forEach { context.delete($0) }; try context.save()
        } catch { context.rollback(); throw DictationHistoryFailure.unavailable }
    }
    public func clear() throws {
        let context = try ctx()
        do { try context.delete(model:StoredDictationEntry.self); try context.save() }
        catch { context.rollback(); throw DictationHistoryFailure.unavailable }
    }
    public func close() {
        context = nil; container = nil
        if descriptor >= 0 { flock(descriptor,LOCK_UN); Darwin.close(descriptor); descriptor = -1 }
    }
}
