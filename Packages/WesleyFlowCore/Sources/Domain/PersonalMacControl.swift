import Foundation
public struct PersonalMacControl:Codable,Sendable,Equatable {
    public enum Action:String,Codable,Sendable {case brightnessUp,brightnessDown,brightnessSet,battery,outputDevice,inputDevice,lowPower}
    public let action:Action
    public let value:String
    public var originPID:Int32?
    public var originBundleID:String?
    public init(action:Action,value:String="") throws {
        guard value.utf8.count<=200,!value.unicodeScalars.contains(where:{$0.value<32}) else {throw PersonalAgentError.invalidCommand}
        if action == .brightnessSet {guard let n=Int(value),(0...100).contains(n) else {throw PersonalAgentError.invalidCommand}}
        if [.outputDevice,.inputDevice].contains(action) {guard !value.isEmpty else {throw PersonalAgentError.invalidCommand}}
        self.action=action;self.value=value
    }
    public func encoded() throws ->String {String(decoding:try JSONEncoder().encode(self),as:UTF8.self)}
    public static func decode(_ text:String) throws ->Self {let v=try JSONDecoder().decode(Self.self,from:Data(text.utf8));var c=try Self(action:v.action,value:v.value);c.originPID=v.originPID;c.originBundleID=v.originBundleID;return c}
    public static func parse(_ input:String,now:Date) throws ->PersonalPlan? {
        let text=PersonalAgentDialogue.canonical(input).lowercased()
        var action:Action?,value=""
        if ["increase the brightness","increase brightness","brightness up"].contains(text) {action = .brightnessUp}
        if ["dim the screen","decrease brightness","brightness down","lower the brightness"].contains(text) {action = .brightnessDown}
        if text=="turn on low power mode" {action = .lowPower}
        if ["what is my battery level","what's my battery level","battery status","check battery"].contains(text) {action = .battery}
        if text.hasPrefix("set brightness to ") {
            let number=String(text.dropFirst(18)).replacingOccurrences(of:" percent",with:"").replacingOccurrences(of:"%",with:"")
            let words=["zero":0,"ten":10,"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90,"one hundred":100]
            guard let n=Int(number) ?? words[number] else {throw PersonalPlanningFailure.unsupported};action = .brightnessSet;value=String(n)
        }
        for (prefix,kind) in [("switch sound output to ",Action.outputDevice),("use microphone ",.inputDevice)] where text.hasPrefix(prefix) {action=kind;value=String(text.dropFirst(prefix.count));if value.hasPrefix("my ") {value=String(value.dropFirst(3))}}
        if text=="use the built-in microphone" || text=="use the built in microphone" {action = .inputDevice;value="built-in"}
        guard let action else {return nil}
        return try .init(steps:[.init(tool:.macControl,text:try Self(action:action,value:value).encoded())],createdAt:now)
    }
}
