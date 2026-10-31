import Foundation
import Darwin
import Domain
@MainActor public final class PersonalRoutineStore {
    public static var defaultURL:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WesleyFlow/PersonalAgent/routines.json")}
    private let url:URL
    public init(url:URL=PersonalRoutineStore.defaultURL) {self.url=url}
    public func definitions() throws ->[PersonalRoutineDefinition] {
        guard FileManager.default.fileExists(atPath:url.path) else {return []}
        let fd=Darwin.open(url.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else {throw PersonalAgentError.permissionDenied}
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? handle.close()}
        let data=try handle.read(upToCount:256*1024+1) ?? Data();guard data.count<=256*1024 else {throw PersonalAgentError.storageFull}
        let list=try JSONDecoder().decode([PersonalRoutineDefinition].self,from:data)
        guard list.count<=32,Set(list.map{$0.name.lowercased()}).count==list.count,Set(list.map(\.id)).count==list.count else {throw PersonalAgentError.invalidCommand}
        for c in list {_ = try PersonalRoutineDefinition(id:c.id,name:c.name,steps:c.steps,createdAt:c.createdAt)};return list
    }
    public func named(_ name:String) throws ->PersonalRoutineDefinition {
        let matches=try definitions().filter{$0.name.caseInsensitiveCompare(name) == .orderedSame}
        guard matches.count==1,let found=matches.first else {throw PersonalAgentError.unsupported};return found
    }
    @discardableResult public func save(_ request:PersonalRoutineSave) throws ->PersonalReceipt {
        var list=try definitions();let c=request.definition
        let matching=list.firstIndex{$0.name.caseInsensitiveCompare(c.name) == .orderedSame}
        if let index=matching {guard request.replacing==list[index].id else {throw PersonalAgentError.approvalRequired};list[index]=c}
        else {guard request.replacing==nil,list.count<32 else {throw PersonalAgentError.approvalRequired};list.append(c)}
        let data=try JSONEncoder().encode(list);guard data.count<=256*1024 else {throw PersonalAgentError.storageFull}
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard (try url.deletingLastPathComponent().resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else {throw PersonalAgentError.unsupported}
        if FileManager.default.fileExists(atPath:url.path) {guard (try url.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else {throw PersonalAgentError.unsupported}}
        try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        guard try named(c.name)==c else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:c.id.uuidString,evidence:"Reviewed routine “"+c.name+"” saved with \(c.steps.count) typed steps. Saving executes none of those steps; every run requires fresh review.")
    }
}
