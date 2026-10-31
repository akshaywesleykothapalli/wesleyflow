import Foundation
public struct PersonalScreenCapture:Codable,Sendable,Equatable {
    public let region:Bool
    public var displayID:UInt32?
    public var originPID:Int32?
    public var originBundleID:String?
    public var visibleOwnWindows:[Int]?
    public init(region:Bool,displayID:UInt32?=nil) {self.region=region;self.displayID=displayID}
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {try JSONDecoder().decode(Self.self,from:Data(text.utf8))}
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input).lowercased()
        guard ["take a screenshot of this display","take a screenshot of an area"].contains(text) else {return nil}
        return try .init(steps:[.init(tool:.screenCapture,text:try Self(region:text.hasSuffix("an area")).encoded())],createdAt:now)
    }
}
