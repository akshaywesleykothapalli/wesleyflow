import Domain
import Foundation
import Darwin

/// Application-enforced read boundary for explicitly injected roots; never an OS sandbox.
/// No app/UI composition uses this fixture-phase service.
public actor ReadOnlyWorkspaceBroker: ProjectRegistry, WorkspaceObservationSource {
    private struct Registration { let root: String; let identity: ObservedFileIdentity; var revoked = false }
    private var registrations: [ProjectIdentifier: Registration] = [:]
    private let checkpoint: @Sendable (String) throws -> Void
    private let now: @Sendable () -> UInt64
    public init() { checkpoint = { _ in }; now = { DispatchTime.now().uptimeNanoseconds } }
    // Deterministic test seams, unavailable to clients importing normally.
    init(checkpoint: @escaping @Sendable (String) throws -> Void,
         now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.checkpoint = checkpoint; self.now = now
    }
    public func register(projectID: ProjectIdentifier, selectedRoot: String) throws {
        guard registrations[projectID] == nil else { throw WorkspaceObservationError.identityConflict }
        guard registrations.count < 32 else { throw WorkspaceObservationError.limitExceeded }
        let fd = try rootDescriptor(selectedRoot); defer { close(fd) }
        let metadata = try info(fd)
        try safeDirectory(metadata)
        var filesystem = statfs()
        guard fstatfs(fd, &filesystem) == 0, filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else { throw WorkspaceObservationError.unavailable }
        let identity = identity(metadata)
        guard !registrations.values.contains(where: { $0.identity.device == identity.device && $0.identity.inode == identity.inode }) else { throw WorkspaceObservationError.duplicateRegistration }
        let rootKey = selectedRoot.lowercased()
        guard !registrations.values.contains(where: { entry in
            let existing = entry.root.lowercased()
            return rootKey.hasPrefix(existing + "/") || existing.hasPrefix(rootKey + "/")
        }) else { throw WorkspaceObservationError.identityConflict }
        registrations[projectID] = .init(root: selectedRoot, identity: identity)
    }
    public func revoke(_ projectID: ProjectIdentifier) throws {
        guard var value = registrations[projectID] else { throw WorkspaceObservationError.unknownProject }
        value.revoked = true; registrations[projectID] = value
    }
    public func validateObservation(projectID: ProjectIdentifier, rootIdentity: ObservedFileIdentity) throws {
        guard let entry = registrations[projectID] else { throw WorkspaceObservationError.unknownProject }
        guard !entry.revoked else { throw WorkspaceObservationError.revoked }
        guard sameNode(entry.identity, rootIdentity) else { throw WorkspaceObservationError.relocated }
        switch try availability(of: projectID) {
        case .available: return
        case .missing: throw WorkspaceObservationError.unavailable
        case .relocated: throw WorkspaceObservationError.relocated
        case .revoked: throw WorkspaceObservationError.revoked
        }
    }
    public func availability(of projectID: ProjectIdentifier) throws -> ProjectAvailability {
        guard let entry = registrations[projectID] else { throw WorkspaceObservationError.unknownProject }
        if entry.revoked { return .revoked }
        guard let fd = try? rootDescriptor(entry.root) else { return .missing }
        defer { close(fd) }
        let current = try info(fd)
        try safeDirectory(current)
        return sameNode(identity(current), entry.identity) ? .available : .relocated
    }
    // Pure pre-open policy seam: tests never need to inspect a real protected root.
    static func rootComponents(_ path: String) throws -> [Substring] {
        guard path.hasPrefix("/"), path != "/", path.utf8.count <= 4096, !path.utf8.contains(0) else { throw WorkspaceObservationError.invalidRoot }
        let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 64, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw WorkspaceObservationError.invalidRoot }
        // Conservative case folding also denies aliases on case-insensitive volumes.
        let key = path.lowercased()
        let deniedRoots = ["/system", "/library", "/applications", "/usr", "/bin", "/sbin", "/dev", "/etc", "/private/etc"]
        guard key != NSHomeDirectory().lowercased(), !deniedRoots.contains(where: { key == $0 || key.hasPrefix($0 + "/") }),
              !(parts.first?.lowercased() == "users" && parts.count <= 2), key != "/private", key != "/private/tmp", key != "/private/var" else { throw WorkspaceObservationError.invalidRoot }
        return parts
    }
    private func rootDescriptor(_ path: String) throws -> Int32 {
        let parts = try Self.rootComponents(path)
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw WorkspaceObservationError.unavailable }
        do {
            for part in parts {
                let child = openat(fd, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                guard child >= 0 else { throw WorkspaceObservationError.unavailable }
                close(fd); fd = child
            }
            return fd
        } catch { close(fd); throw error }
    }
    private func safeDirectory(_ s: stat) throws {
        guard s.st_mode & S_IFMT == S_IFDIR, s.st_uid == geteuid(), s.st_mode & 0o022 == 0 else { throw WorkspaceObservationError.unsafeType }
    }
    private func info(_ fd: Int32) throws -> stat {
        var s = stat(); guard fstat(fd, &s) == 0 else { throw WorkspaceObservationError.io }; return s
    }
    private func entryInfo(_ fd: Int32, _ name: String) throws -> stat {
        var s = stat(); guard fstatat(fd, name, &s, AT_SYMLINK_NOFOLLOW) == 0 else { throw WorkspaceObservationError.inconsistent }; return s
    }
    private func identity(_ s: stat) -> ObservedFileIdentity {
        .init(device: Int64(s.st_dev), inode: UInt64(s.st_ino), modifiedSeconds: Int64(s.st_mtimespec.tv_sec),
              modifiedNanoseconds: Int64(s.st_mtimespec.tv_nsec), changedSeconds: Int64(s.st_ctimespec.tv_sec), changedNanoseconds: Int64(s.st_ctimespec.tv_nsec))
    }
    private func sameNode(_ a: ObservedFileIdentity, _ b: ObservedFileIdentity) -> Bool { a.device == b.device && a.inode == b.inode }
    private func unchanged(_ a: stat, _ b: stat) -> Bool {
        identity(a) == identity(b) && a.st_size == b.st_size && a.st_mode == b.st_mode && a.st_nlink == b.st_nlink
    }
    // Kept explicit and tested without privileged mount creation.
    static func checkDevice(root: Int64, candidate: Int64) throws {
        guard root == candidate else { throw WorkspaceObservationError.mountBoundary }
    }
    private struct Scan {
        var files: [ObservedSourceFile] = []
        var directories: [(String, stat)] = []
        var accounted = 1_048_576 // fixed read/conversion scratch allowance; not an OS RSS quota
        var bytes = 0
        var work = 0
        var excluded = 0
    }
    public func observe(projectID: ProjectIdentifier, absentCandidates: [String] = [], limits: WorkspaceObservationLimits) throws -> WorkspaceReadObservation {
        guard let registration = registrations[projectID] else { throw WorkspaceObservationError.unknownProject }
        guard !registration.revoked else { throw WorkspaceObservationError.revoked }
        guard absentCandidates.count <= limits.files, Set(absentCandidates).count == absentCandidates.count,
              absentCandidates.allSatisfy(WorkspaceContextPolicy.permitsFile) else { throw WorkspaceObservationError.invalidSelection }
        let start = now()
        func check() throws {
            guard !Task.isCancelled else { throw WorkspaceObservationError.cancelled }
            let current = now()
            guard current >= start, current - start < UInt64(limits.durationMilliseconds) * 1_000_000 else { throw WorkspaceObservationError.deadlineExceeded }
        }
        try check()
        let root = try rootDescriptor(registration.root); defer { close(root) }
        let baseline = try info(root)
        guard sameNode(identity(baseline), registration.identity) else { throw WorkspaceObservationError.relocated }
        var scan = Scan()
        try walk(root, path: "", depth: 0, rootDevice: Int64(baseline.st_dev), limits: limits, scan: &scan, check: check)
        var absent: [String] = []
        for path in absentCandidates.sorted() {
            try check()
            if scan.files.contains(where: { $0.relativePath == path }) { continue }
            try verifyAbsent(path, root: root, rootDevice: Int64(baseline.st_dev), check: check)
            scan.accounted += path.utf8.count * 2 + 512
            guard scan.accounted <= limits.retainedBytes else { throw WorkspaceObservationError.limitExceeded }
            absent.append(path)
        }
        guard scan.files.count + absent.count <= limits.files else { throw WorkspaceObservationError.limitExceeded }
        try checkpoint("scan-finished"); try check()
        for (path, metadata) in scan.directories where !path.isEmpty {
            guard unchanged(metadata, try lookup(path, root: root, rootDevice: Int64(baseline.st_dev))) else { throw WorkspaceObservationError.inconsistent }
        }
        // Revalidate every path after the walk, not only immediately after each read.
        for file in scan.files {
            try check(); let metadata = try lookup(file.relativePath, root: root, rootDevice: Int64(baseline.st_dev))
            guard identity(metadata) == file.identity, metadata.st_size == file.utf8Content.utf8.count,
                  metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1 else { throw WorkspaceObservationError.inconsistent }
        }
        for path in absent { try verifyAbsent(path, root: root, rootDevice: Int64(baseline.st_dev), check: check) }
        try check()
        guard unchanged(baseline, try info(root)) else { throw WorkspaceObservationError.inconsistent }
        let reopened = try rootDescriptor(registration.root); defer { close(reopened) }
        guard sameNode(identity(try info(reopened)), registration.identity) else { throw WorkspaceObservationError.inconsistent }
        return .init(projectID: projectID, rootIdentity: identity(baseline), files: scan.files.sorted { $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8) }, absentPaths: absent, excludedCount: scan.excluded)
    }
    private func walk(_ fd: Int32, path: String, depth: Int, rootDevice: Int64, limits: WorkspaceObservationLimits,
                      scan: inout Scan, check: () throws -> Void) throws {
        try check(); guard depth <= limits.depth else { throw WorkspaceObservationError.limitExceeded }
        let before = try info(fd)
        try safeDirectory(before)
        scan.accounted += path.utf8.count * 2 + 512
        guard scan.accounted <= limits.retainedBytes else { throw WorkspaceObservationError.limitExceeded }
        scan.directories.append((path, before))
        let duplicate = fcntl(fd, F_DUPFD_CLOEXEC, 0); guard duplicate >= 0 else { throw WorkspaceObservationError.io }
        guard let directory = fdopendir(duplicate) else { close(duplicate); throw WorkspaceObservationError.io }
        defer { closedir(directory) }
        var names: [String] = []
        while true {
            try check(); errno = 0
            guard let entry = readdir(directory) else { guard errno == 0 else { throw WorkspaceObservationError.io }; break }
            scan.work += 1; guard scan.work <= limits.enumerationWork else { throw WorkspaceObservationError.limitExceeded }
            var raw = entry.pointee.d_name
            let name = withUnsafePointer(to: &raw) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: 1024) { String(validatingCString: $0) } }
            guard let name else { throw WorkspaceObservationError.invalidPath }
            if name == "." || name == ".." { continue }
            _ = try WorkspaceContextPolicy.components(name)
            if !WorkspaceContextPolicy.permitsComponent(name) { scan.excluded += 1; continue }
            scan.accounted += name.utf8.count * 2 + 128
            guard scan.accounted <= limits.retainedBytes else { throw WorkspaceObservationError.limitExceeded }
            names.append(name)
        }
        try checkpoint("directory-enumerated:" + path)
        for name in names.sorted() {
            try check()
            let relative = path.isEmpty ? name : path + "/" + name
            _ = try WorkspaceContextPolicy.components(relative)
            let beforeEntry = try entryInfo(fd, name)
            try Self.checkDevice(root: rootDevice, candidate: Int64(beforeEntry.st_dev))
            switch beforeEntry.st_mode & S_IFMT {
            case S_IFDIR:
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                guard child >= 0 else { throw WorkspaceObservationError.inconsistent }
                defer { close(child) }
                guard unchanged(beforeEntry, try info(child)) else { throw WorkspaceObservationError.inconsistent }
                try walk(child, path: relative, depth: depth + 1, rootDevice: rootDevice, limits: limits, scan: &scan, check: check)
                guard unchanged(beforeEntry, try entryInfo(fd, name)) else { throw WorkspaceObservationError.inconsistent }
            case S_IFREG:
                if !WorkspaceContextPolicy.permitsFile(relative) { scan.excluded += 1; continue }
                guard beforeEntry.st_nlink == 1 else { throw WorkspaceObservationError.unsafeType }
                guard scan.files.count < limits.files else { throw WorkspaceObservationError.limitExceeded }
                scan.accounted += relative.utf8.count * 2 + 1024
                guard scan.accounted <= limits.retainedBytes else { throw WorkspaceObservationError.limitExceeded }
                let file = try readFile(fd, name: name, path: relative, baseline: beforeEntry, rootDevice: rootDevice, limits: limits, remaining: min(limits.aggregateBytes - scan.bytes, limits.retainedBytes - scan.accounted), check: check)
                scan.bytes += file.utf8Content.utf8.count; scan.accounted += file.utf8Content.utf8.count; scan.files.append(file)
            default: throw WorkspaceObservationError.unsafeType
            }
        }
        guard unchanged(before, try info(fd)) else { throw WorkspaceObservationError.inconsistent }
    }
    private func readFile(_ parent: Int32, name: String, path: String, baseline: stat, rootDevice: Int64,
                          limits: WorkspaceObservationLimits, remaining: Int, check: () throws -> Void) throws -> ObservedSourceFile {
        guard baseline.st_size >= 0, baseline.st_size <= min(limits.individualBytes, remaining) else { throw WorkspaceObservationError.limitExceeded }
        try checkpoint("before-open:" + path); try check()
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | O_NOCTTY)
        guard fd >= 0 else { throw WorkspaceObservationError.inconsistent }
        defer { close(fd) }
        let before = try info(fd)
        try Self.checkDevice(root: rootDevice, candidate: Int64(before.st_dev))
        guard before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1 else { throw WorkspaceObservationError.unsafeType }
        guard unchanged(baseline, before) else { throw WorkspaceObservationError.inconsistent }
        var bytes: [UInt8] = []; var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            try check(); let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0 { if errno == EINTR { continue }; throw WorkspaceObservationError.io }
            if count == 0 { break }
            guard count <= min(limits.individualBytes, remaining) - bytes.count else { throw WorkspaceObservationError.limitExceeded }
            bytes.append(contentsOf: chunk.prefix(count)); try checkpoint("read-chunk:" + path)
        }
        try checkpoint("file-read:" + path); try check()
        guard unchanged(before, try info(fd)), unchanged(before, try entryInfo(parent, name)), bytes.count == before.st_size else { throw WorkspaceObservationError.inconsistent }
        guard String(bytes: bytes, encoding: .utf8) != nil else { throw WorkspaceObservationError.invalidUTF8 }
        // Foundation's encoding initializer strips a UTF8 BOM. Decode validated code units
        // with the standard library to preserve every original byte for revisions/excerpts.
        let text = String(decoding: bytes, as: UTF8.self)
        guard WorkspaceContextPolicy.permitsText(text) else { throw WorkspaceObservationError.sensitiveContent }
        return .init(relativePath: path, utf8Content: text, identity: identity(before))
    }
    private func withParent<T>(_ path: String, root: Int32, rootDevice: Int64, body: (Int32, String) throws -> T) throws -> T {
        let parts = try WorkspaceContextPolicy.components(path)
        guard parts.allSatisfy(WorkspaceContextPolicy.permitsComponent), let last = parts.last else { throw WorkspaceObservationError.excluded }
        var fd = fcntl(root, F_DUPFD_CLOEXEC, 0); guard fd >= 0 else { throw WorkspaceObservationError.io }; defer { close(fd) }
        for part in parts.dropLast() {
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard next >= 0 else { throw WorkspaceObservationError.inconsistent }
            close(fd); fd = next; try Self.checkDevice(root: rootDevice, candidate: Int64(try info(fd).st_dev))
        }
        return try body(fd, last)
    }
    private func lookup(_ path: String, root: Int32, rootDevice: Int64) throws -> stat {
        try withParent(path, root: root, rootDevice: rootDevice) { try entryInfo($0, $1) }
    }
    private func verifyAbsent(_ path: String, root: Int32, rootDevice: Int64, check: () throws -> Void) throws {
        try check()
        try withParent(path, root: root, rootDevice: rootDevice) { fd, name in
            var s = stat()
            guard fstatat(fd, name, &s, AT_SYMLINK_NOFOLLOW) != 0 else { throw WorkspaceObservationError.invalidSelection }
            guard errno == ENOENT else { throw WorkspaceObservationError.inconsistent }
        }
    }
}
