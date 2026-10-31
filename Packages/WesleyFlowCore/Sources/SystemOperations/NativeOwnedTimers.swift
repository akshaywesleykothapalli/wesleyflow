import Foundation
import UserNotifications
import Domain
@MainActor public enum NativeOwnedTimers {
    static func isOwned(_ request:UNNotificationRequest)->Bool {
        request.identifier.hasPrefix("wesleyflow.timer.") || request.content.title=="Wesley Flow timer"
    }
    static func matchingName(_ name:String,requests:[UNNotificationRequest]) throws ->String {
        let matches=requests.filter {isOwned($0) && $0.content.body.caseInsensitiveCompare(name) == .orderedSame}
        guard matches.count==1,let target=matches.first else {throw PersonalAgentError.unsupported};return target.identifier
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let request=try PersonalTimerControl.decode(step.text),center=UNUserNotificationCenter.current()
        let pending=await center.pendingNotificationRequests().filter{isOwned($0)}
        try Task.checkCancellation()
        if request.action == .list {
            let text=pending.sorted{$0.identifier<$1.identifier}.prefix(50).map{item in item.content.body+" · "+(((item.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? (item.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate())?.formatted() ?? "due time unavailable")}.joined(separator:"; ")
            return .init(identifier:step.id.uuidString,evidence:pending.isEmpty ? "No active Wesley Flow timers.":"Active Wesley Flow timers: "+text)
        }
        let id=try matchingName(request.name,requests:pending)
        center.removePendingNotificationRequests(withIdentifiers:[id])
        guard await !center.pendingNotificationRequests().contains(where:{$0.identifier==id}) else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:id,evidence:"Pending timer “"+request.name+"” cancelled; removal verified. Already delivered notifications are not recalled.")
    }
}
