import AppKit
import Darwin
import Domain

enum CloseProcessState:Equatable {case running,exited,unknown}
@MainActor protocol AppCloseEnvironment:AnyObject {
    func instances(_ id:String)->[PersonalCloseProcess]?
    func state(_ process:PersonalCloseProcess)->CloseProcessState
    func request(_ process:PersonalCloseProcess,bundleID:String)->Bool
    func sleep(milliseconds:Int) async throws
}
@MainActor private final class SystemAppCloseEnvironment:AppCloseEnvironment {
    private var bound:[PersonalCloseProcess:NSRunningApplication]=[:]
    private func info(_ pid:Int32)->(proc_bsdinfo?,Int32) {
        var value=proc_bsdinfo();errno=0
        let count=proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&value,Int32(MemoryLayout<proc_bsdinfo>.size)),failure=errno
        if count==Int32(MemoryLayout<proc_bsdinfo>.size) {return (value,0)}
        // Signal 0 only checks existence; it never terminates or changes a process.
        if Darwin.kill(pid,0) == -1,errno==ESRCH {return (nil,ESRCH)}
        return (nil,failure)
    }
    func instances(_ id:String)->[PersonalCloseProcess]? {
        let apps=NSRunningApplication.runningApplications(withBundleIdentifier:id).filter{!$0.isTerminated}
        guard apps.count<=16 else {return nil}
        var result:[PersonalCloseProcess]=[]
        for app in apps {
            let (value,error)=info(app.processIdentifier)
            guard let value else {if error==ESRCH {continue};return nil}
            if value.pbi_status==UInt32(SZOMB) {continue}
            let process=PersonalCloseProcess(pid:app.processIdentifier,seconds:value.pbi_start_tvsec,microseconds:value.pbi_start_tvusec)
            bound[process]=app;result.append(process)
        }
        return Array(Set(result))
    }
    func state(_ process:PersonalCloseProcess)->CloseProcessState {
        let (value,error)=info(process.pid)
        return NativeAppClosing.classify(process,observed:value.map{.init(pid:process.pid,seconds:$0.pbi_start_tvsec,microseconds:$0.pbi_start_tvusec)},zombie:value?.pbi_status==UInt32(SZOMB),failure:error)
    }
    func request(_ process:PersonalCloseProcess,bundleID:String)->Bool {
        guard let app=bound[process],app.bundleIdentifier==bundleID,!app.isTerminated,state(process) == .running else {return false}
        return app.terminate()
    }
    func sleep(milliseconds:Int) async throws {try await Task.sleep(for:.milliseconds(milliseconds))}
}
@MainActor public enum NativeAppClosing {
    static func classify(_ expected:PersonalCloseProcess,observed:PersonalCloseProcess?,zombie:Bool,failure:Int32)->CloseProcessState {
        if let observed {return observed != expected || zombie ? .exited:.running}
        return failure==ESRCH ? .exited:.unknown
    }
    static func observed(_ original:PersonalAppCloseObservation,environment:any AppCloseEnvironment) throws ->PersonalAppCloseObservation {
        guard let current=environment.instances(original.bundleID) else {return original}
        if current.contains(where:{!original.processes.contains($0)}) {return try original.changing(.reopened)}
        if original.processes.allSatisfy({environment.state($0) == .exited}),current.isEmpty {return try original.changing(.closed)}
        return original
    }
    static func perform(_ id:String,environment:any AppCloseEnvironment) async throws ->PersonalReceipt {
        try Task.checkCancellation()
        guard let processes=environment.instances(id) else {return try PersonalAppCloseObservation(bundleID:id,processes:[],outcome:.unavailable).receipt}
        let token=try PersonalAppCloseObservation(bundleID:id,processes:processes,outcome:processes.isEmpty ? .closed:.pending)
        if processes.isEmpty {return token.receipt}
        var refused=false
        for process in processes {
            try Task.checkCancellation()
            if environment.state(process) == .exited {continue}
            if !environment.request(process,bundleID:id) {refused=true}
        }
        var result=try observed(token,environment:environment)
        if result.outcome != .pending {return result.receipt}
        if refused {return try token.changing(.refused).receipt}
        // Keep the interactive command short; slower quits continue as read-only observation.
        for _ in 0..<8 {
            try await environment.sleep(milliseconds:100);try Task.checkCancellation()
            result=try observed(token,environment:environment)
            if result.outcome != .pending {return result.receipt}
        }
        return token.receipt
    }
    public static func perform(_ id:String) async throws ->PersonalReceipt {try await perform(id,environment:SystemAppCloseEnvironment())}
    static func followup(_ receipt:PersonalReceipt,environment:any AppCloseEnvironment) async ->PersonalReceipt? {
        guard let token=try? receipt.appClose?.validated(),[PersonalAppCloseObservation.Outcome.pending,.refused].contains(token.outcome),!receipt.verified,receipt.identifier==token.bundleID else {return nil}
        for _ in 0..<150 {
            if Task.isCancelled {return nil}
            guard let result=try? observed(token,environment:environment) else {return nil}
            if [.closed,.reopened].contains(result.outcome) {return result.receipt}
            do {try await environment.sleep(milliseconds:200)} catch {return nil}
        }
        return try? token.changing(.unconfirmed).receipt
    }
    public static func followup(_ receipt:PersonalReceipt) async ->PersonalReceipt? {await followup(receipt,environment:SystemAppCloseEnvironment())}
}
