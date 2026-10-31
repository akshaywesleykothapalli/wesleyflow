import Foundation
import UserNotifications
import Domain
@MainActor public enum NativeScheduledMessages {
    public static func notificationID(_ id:UUID)->String {"wesleyflow.scheduled-message."+id.uuidString}
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .messageSchedule {
            var c=try PersonalMessageSchedule.decode(steps[i].text)
            if c.action == .cancel {let record=try PersonalScheduledMessageStore().pending(c.recipient);c.recordID=record.id;c.message=record.message;c.date=record.date}
            else {guard let date=c.date,date.timeIntervalSinceNow>=60,date.timeIntervalSinceNow<=90*86400 else {throw PersonalAgentError.invalidCommand}}
            steps[i] = .init(id:steps[i].id,tool:.messageSchedule,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let c=try PersonalMessageSchedule.decode(step.text),center=UNUserNotificationCenter.current(),store=PersonalScheduledMessageStore()
        if c.action == .create {
            guard let message=c.message,let date=c.date,date.timeIntervalSinceNow>=60,try await center.requestAuthorization(options:[.alert,.sound]) else {throw PersonalAgentError.permissionDenied}
            try Task.checkCancellation();guard date.timeIntervalSinceNow>=1 else {throw PersonalAgentError.invalidCommand}
            let record=try PersonalScheduledMessage(id:step.id,message:message,date:date);try store.add(record)
            let content=UNMutableNotificationContent();content.title="Message ready for review";content.body="Open Wesley Flow Command Mode to review and send your scheduled draft. Nothing is sent automatically.";content.sound = .default
            let trigger=UNCalendarNotificationTrigger(dateMatching:Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone],from:date),repeats:false),id=notificationID(record.id)
            try await center.add(UNNotificationRequest(identifier:id,content:content,trigger:trigger))
            guard await center.pendingNotificationRequests().contains(where:{$0.identifier==id}),try store.records().contains(record) else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:record.id.uuidString,evidence:"Local message draft and review notification scheduled for "+date.formatted()+". At due time, use Review and then Send. There is no unattended sending.")
        }
        guard let id=c.recordID else {throw PersonalAgentError.approvalRequired}
        let record=try store.pending(c.recipient);guard record.id==id,record.message==c.message,record.date==c.date else {throw PersonalAgentError.verificationFailed}
        try store.cancel(id);center.removePendingNotificationRequests(withIdentifiers:[notificationID(id)])
        guard await !center.pendingNotificationRequests().contains(where:{$0.identifier==notificationID(id)}) else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:id.uuidString,evidence:"Pending local message draft cancelled and review notification removed. No dispatched message was recalled.")
    }
}
