import Foundation
public struct PersonalCloseProcess:Codable,Sendable,Equatable,Hashable {
    public let pid:Int32
    public let seconds:UInt64
    public let microseconds:UInt64
    public init(pid:Int32,seconds:UInt64,microseconds:UInt64=0) {self.pid=pid;self.seconds=seconds;self.microseconds=microseconds}
}
/// Read-only native evidence bound to the original process instances, never another execution grant.
public struct PersonalAppCloseObservation:Codable,Sendable,Equatable {
    public enum Outcome:String,Codable,Sendable {case pending,closed,refused,reopened,unavailable,unconfirmed}
    public let token:UUID
    public let bundleID:String
    public let processes:[PersonalCloseProcess]
    public let outcome:Outcome
    public init(token:UUID=UUID(),bundleID:String,processes:[PersonalCloseProcess],outcome:Outcome) throws {
        guard !bundleID.isEmpty,bundleID.utf8.count<=200,!bundleID.unicodeScalars.contains(where:{$0.properties.isWhitespace || $0.properties.generalCategory == .control}),processes.count<=16,Set(processes).count==processes.count,Set(processes.map(\.pid)).count==processes.count,processes.allSatisfy({$0.pid>0 && $0.seconds>0 && $0.microseconds<1000000}),!processes.isEmpty || [.closed,.unavailable].contains(outcome) else {throw PersonalAgentError.invalidCommand}
        self.token=token;self.bundleID=bundleID;self.processes=processes;self.outcome=outcome
    }
    public func validated() throws ->Self {try .init(token:token,bundleID:bundleID,processes:processes,outcome:outcome)}
    public func changing(_ outcome:Outcome) throws ->Self {try .init(token:token,bundleID:bundleID,processes:processes,outcome:outcome)}
    public var receipt:PersonalReceipt {
        let evidence:String=switch outcome {
        case .closed:processes.isEmpty ? "Application was already closed; no quit request was sent.":"The original app processes exited, and no replacement app instance is running. Native process identity checked; no force quit or retry."
        case .pending:"Normal quit was requested once. The original app process is still running or cannot yet be verified. Finish any native save/confirmation prompt; shutdown may also be taking time. A separate bounded read-only check can confirm a later exit. No force quit or retry."
        case .refused:"The app did not accept a normal quit request. Check its native window or save/confirmation prompt. No force quit or automatic retry."
        case .reopened:"A replacement app instance appeared. It was not quit. Inspect the app; no automatic retry or force quit."
        case .unconfirmed:"The quit was not confirmed within the observation window. Check whether the app remains open or a save/confirmation prompt needs attention. No further quit request was sent; automatic observation stopped."
        case .unavailable:"The app process identity could not be checked safely. No quit request was sent. Check the app manually."
        }
        return .init(identifier:bundleID,evidence:evidence,verified:outcome == .closed,appClose:self)
    }
}
