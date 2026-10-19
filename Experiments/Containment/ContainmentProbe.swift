import Foundation
import Darwin
import Security

// EXPERIMENT ONLY. All operations are fixed benign probes against runner-created synthetic fixtures.
struct ProbeRequest: Codable, Sendable {
    let token: String
    let mode: String
    let authorized: String
    let unauthorized: String
    let unrelated: String
    let configuration: String
    let output: String
    let port: UInt16
}
struct Attempt: Codable, Sendable {
    let operation: String
    let result: Int32
    let error: Int32
    let matchedSyntheticContent: Bool?
}
func emit<T: Encodable>(_ value: T) {
    if let data = try? JSONEncoder().encode(value) {
        FileHandle.standardOutput.write(data + Data([10]))
    }
}
func readAttempt(_ name: String, _ path: String) -> Attempt {
    errno = 0; let fd = Darwin.open(path, O_RDONLY); let failure = errno
    guard fd >= 0 else { return .init(operation: name, result: -1, error: failure, matchedSyntheticContent: nil) }
    defer { Darwin.close(fd) }
    var buffer = [UInt8](repeating: 0, count: 256)
    let count = Darwin.read(fd, &buffer, buffer.count); let readError = errno
    return .init(operation: name, result: Int32(count), error: count < 0 ? readError : 0,
                 matchedSyntheticContent: count >= 0 ? String(bytes: buffer.prefix(max(0,count)), encoding: .utf8) == "synthetic-fixture\n" : nil)
}
func writeAttempt(_ name: String, _ path: String) -> Attempt {
    errno = 0; let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR); let failure = errno
    guard fd >= 0 else { return .init(operation: name, result: -1, error: failure, matchedSyntheticContent: nil) }
    defer { Darwin.close(fd) }
    let bytes = Array("synthetic-write\n".utf8); let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }; let error = errno
    return .init(operation: name, result: Int32(count), error: count < 0 ? error : 0, matchedSyntheticContent: nil)
}
func networkAttempt(_ port: UInt16) -> Attempt {
    errno = 0; let fd = socket(AF_INET, SOCK_STREAM, 0); let socketError = errno
    guard fd >= 0 else { return .init(operation: "loopbackConnect", result: -1, error: socketError, matchedSyntheticContent: nil) }
    defer { Darwin.close(fd) }
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian; address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }; let failure = errno
    if result == 0 { _ = "synthetic-network-probe".withCString { Darwin.send(fd, $0, strlen($0), 0) } }
    return .init(operation: "loopbackConnect", result: result, error: result < 0 ? failure : 0, matchedSyntheticContent: nil)
}
func signature() -> [String: String] {
    var code: SecCode?; var staticCode: SecStaticCode?; var information: CFDictionary?
    let own = SecCodeCopySelf([], &code)
    let staticStatus = code.map { SecCodeCopyStaticCode($0, [], &staticCode) } ?? errSecParam
    let infoStatus = staticCode.map { SecCodeCopySigningInformation($0, SecCSFlags(rawValue: kSecCSSigningInformation), &information) } ?? errSecParam
    let dictionary = information as? [String: Any]
    let entitlements = dictionary?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    return ["selfStatus": String(own), "staticStatus": String(staticStatus), "informationStatus": String(infoStatus),
            "identifier": dictionary?[kSecCodeInfoIdentifier as String] as? String ?? "unavailable",
            "appSandbox": String(describing: entitlements?["com.apple.security.app-sandbox"] ?? "absent"),
            "inherit": String(describing: entitlements?["com.apple.security.inherit"] ?? "absent"),
            "networkClient": String(describing: entitlements?["com.apple.security.network.client"] ?? "absent")]
}
struct Ready: Encodable {
    let type = "ready"
    let pid: Int32
    let parent: Int32
    let group: Int32
    let temporary: String
    let bundle: String
    let signing: [String: String]
}
struct ProbeResult: Encodable {
    let type = "probeResult"
    let pid: Int32
    let attempts: [Attempt]
    let peakResidentBytes: Int64
}
struct ChildResult: Encodable {
    let type: String
    let pid: Int32
    let launched: Bool
    let running: Bool
    let exitStatus: Int32?
    let signalTermination: Bool?
    let errorDomain: String?
    let errorCode: Int?
    let output: String?
}
@main @MainActor struct ContainmentProbe {
    static func main() throws {
        emit(Ready(pid: getpid(), parent: getppid(), group: getpgrp(), temporary: NSTemporaryDirectory(), bundle: Bundle.main.bundlePath, signing: signature()))
        guard let line = readLine(), line.utf8.count <= 16_384 else { exit(64) }
        let request = try JSONDecoder().decode(ProbeRequest.self, from: Data(line.utf8))
        // Fixture scope, not a permission decision: each requested directory belongs to this unique test run.
        guard request.token.hasPrefix("wf-containment-"), request.token.count <= 80,
              [request.authorized,request.unauthorized,request.unrelated,request.configuration,request.output].allSatisfy({ $0.contains(request.token) && $0.hasPrefix("/") }) else { exit(64) }
        let isChild = CommandLine.arguments.contains("--child")
        if request.mode == "hold" && isChild {
            let lock = request.authorized + "/resource.lock"
            let fd = Darwin.open(lock, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            let locked = fd >= 0 ? flock(fd, LOCK_EX | LOCK_NB) : -1
            emit(["type":"childHolding", "pid":String(getpid()), "group":String(getpgrp()), "lockResult":String(locked), "lockError":String(errno)])
            // Deliberately retain the synthetic resource until signalled, even if the parent dies.
            // The external test supervisor owns a hard watchdog and reaps/cleans this fixture.
            while true { pause() }
        }
        if ["lifecycle", "hold"].contains(request.mode) && !isChild {
            try lifecycle(request); return
        }
        var attempts = [readAttempt("approvedRead", request.authorized + "/input.txt"),
                        writeAttempt("approvedWrite", request.authorized + "/written.txt"),
                        readAttempt("unauthorizedRead", request.unauthorized + "/input.txt"),
                        writeAttempt("unauthorizedWrite", request.unauthorized + "/written.txt"),
                        readAttempt("unrelatedRead", request.unrelated + "/input.txt"),
                        readAttempt("configurationRead", request.configuration + "/config.txt"),
                        writeAttempt("outputWrite", request.output + "/written.txt"),
                        readAttempt("symlinkEscape", request.authorized + "/escape-link/input.txt"),
                        readAttempt("traversalEscape", request.authorized + "/escape-traversal/../input.txt"),
                        networkAttempt(request.port)]
        if !isChild {
            for (name,path) in [("inheritingChild",Bundle.main.bundlePath + "/Contents/Helpers/InheritedProbe"),
                                ("unapprovedInside",request.authorized + "/UnapprovedProbe"),
                                ("unapprovedOutside",request.unauthorized + "/OutsideProbe")] {
                let child = Process(); child.executableURL = URL(fileURLWithPath: path); child.arguments = ["--child"]
                let input = Pipe(); let output = Pipe(); child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.standardError
                do {
                    try child.run(); try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request) + Data([10])); try input.fileHandleForWriting.close()
                    let data = try output.fileHandleForReading.readToEnd() ?? Data(); child.waitUntilExit()
                    emit(ChildResult(type: name, pid: child.processIdentifier, launched: true, running: child.isRunning, exitStatus: child.terminationStatus, signalTermination: child.terminationReason == .uncaughtSignal, errorDomain: nil, errorCode: nil, output: String(data: data, encoding: .utf8)))
                } catch {
                    let failure = error as NSError
                    emit(ChildResult(type: name, pid: child.processIdentifier, launched: false, running: child.isRunning, exitStatus: nil, signalTermination: nil, errorDomain: failure.domain, errorCode: failure.code, output: nil))
                }
            }
            // Observing that a system executable can run does not claim an executable allowlist.
            let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            do { try child.run(); child.waitUntilExit(); emit(ChildResult(type: "systemExecutable", pid: child.processIdentifier, launched: true, running: child.isRunning, exitStatus: child.terminationStatus, signalTermination: child.terminationReason == .uncaughtSignal, errorDomain: nil, errorCode: nil, output: nil)) }
            catch { let failure = error as NSError; emit(ChildResult(type:"systemExecutable",pid:child.processIdentifier,launched:false,running:child.isRunning,exitStatus:nil,signalTermination:nil,errorDomain:failure.domain,errorCode:failure.code,output:nil)) }
        }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        emit(ProbeResult(pid:getpid(),attempts:attempts,peakResidentBytes:Int64(usage.ru_maxrss)))
        attempts.removeAll()
    }
    static func lifecycle(_ request: ProbeRequest) throws {
        let child = Process(); child.executableURL = URL(fileURLWithPath: Bundle.main.bundlePath + "/Contents/Helpers/InheritedProbe"); child.arguments = ["--child"]
        let input = Pipe(); let output = Pipe(); child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.standardError
        try child.run(); var heldRequest = request
        // Use a fixed Codable request with hold mode; the child only holds a synthetic lock and waits on stdin.
        heldRequest = ProbeRequest(token:request.token,mode:"hold",authorized:request.authorized,unauthorized:request.unauthorized,unrelated:request.unrelated,configuration:request.configuration,output:request.output,port:request.port)
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(heldRequest) + Data([10]))
        let reader = output.fileHandleForReading
        // Read two bounded newline records (identity, then confirmed resource ownership).
        for _ in 0..<2 {
            var data = Data()
            while data.count < 16_384 {
                guard let one = try reader.read(upToCount:1), !one.isEmpty else { break }
                data.append(one); if one.first == 10 { break }
            }
            FileHandle.standardOutput.write(data)
        }
        emit(["type":"parentHolding", "pid":String(getpid()), "childPID":String(child.processIdentifier)])
        while let command = readLine() {
            guard ["cancel","quit"].contains(command) else { continue }
            if child.isRunning { child.terminate(); child.waitUntilExit() }
            emit(ChildResult(type:"cleanup",pid:child.processIdentifier,launched:true,running:child.isRunning,exitStatus:child.terminationStatus,signalTermination:child.terminationReason == .uncaughtSignal,errorDomain:nil,errorCode:nil,output:nil))
            if command == "quit" { try input.fileHandleForWriting.close(); return }
        }
        if child.isRunning { child.terminate(); child.waitUntilExit() }
        emit(ChildResult(type:"parentShutdownCleanup",pid:child.processIdentifier,launched:true,running:child.isRunning,exitStatus:child.terminationStatus,signalTermination:child.terminationReason == .uncaughtSignal,errorDomain:nil,errorCode:nil,output:nil))
    }
}
