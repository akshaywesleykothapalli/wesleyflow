import Foundation
import Darwin
import Domain
@MainActor public final class PersonalScheduledMessageStore {
    public static var defaultURL:URL {PersonalRoutineStore.defaultURL.deletingLastPathComponent().appendingPathComponent("scheduled-message-drafts.json")}
    private let url:URL
    public init(url:URL=PersonalScheduledMessageStore.defaultURL) {self.url=url}
    public func records() throws ->[PersonalScheduledMessage] {
        guard FileManager.default.fileExists(atPath:url.path) else {return []}
        let fd=Darwin.open(url.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else {throw PersonalAgentError.permissionDenied}
        let file=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? file.close()}
        let data=try file.read(upToCount:256*1024+1) ?? Data();guard data.count<=256*1024 else {throw PersonalAgentError.storageFull}
        let list=try JSONDecoder().decode([PersonalScheduledMessage].self,from:data)
        guard list.count<=64,Set(list.map(\.id)).count==list.count else {throw PersonalAgentError.storageFull}
        for item in list {_ = try PersonalScheduledMessage(id:item.id,message:item.message,date:item.date,state:item.state)};return list
    }
    private func persist(_ items:[PersonalScheduledMessage]) throws {
        let data=try JSONEncoder().encode(items);guard data.count<=256*1024,items.count<=64 else {throw PersonalAgentError.storageFull}
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard (try url.deletingLastPathComponent().resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else {throw PersonalAgentError.unsupported}
        if FileManager.default.fileExists(atPath:url.path) {guard (try url.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else {throw PersonalAgentError.unsupported}}
        try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    public func add(_ item:PersonalScheduledMessage) throws {
        var items=try records()
        if let prior=items.first(where:{$0.id==item.id}) {guard prior==item else {throw PersonalAgentError.approvalRequired};return}
        guard items.filter({$0.state == .pending}).count<32 else {throw PersonalAgentError.storageFull}
        items.append(item);try persist(items)
    }
    public func pending(_ recipient:String) throws ->PersonalScheduledMessage {
        let found=try records().filter{$0.state == .pending && $0.message.recipient.caseInsensitiveCompare(recipient) == .orderedSame}
        guard found.count==1,let one=found.first else {throw PersonalAgentError.unsupported};return one
    }
    @discardableResult public func claim(_ id:UUID,now:Date) throws ->PersonalScheduledMessage {
        var items=try records();guard let i=items.firstIndex(where:{$0.id==id}),items[i].state == .pending,items[i].date<=now else {throw PersonalAgentError.approvalRequired}
        items[i].state = .claimed;try persist(items);return items[i]
    }
    public func cancel(_ id:UUID) throws {
        var items=try records();guard let i=items.firstIndex(where:{$0.id==id}),items[i].state == .pending else {throw PersonalAgentError.approvalRequired};items[i].state = .cancelled;try persist(items)
    }
    public func delete(_ id:UUID) throws {var items=try records();guard !items.contains(where:{$0.id==id && $0.state == .pending}) else {throw PersonalAgentError.approvalRequired};items.removeAll{$0.id==id};try persist(items)}
}
