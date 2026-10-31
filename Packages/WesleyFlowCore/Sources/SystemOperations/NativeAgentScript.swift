import AppKit
import Domain
@MainActor public enum NativeAgentScript {
    public static func literal(_ text:String)->String {"\""+text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\r",with:"\\r").replacingOccurrences(of:"\n",with:"\\n")+"\""}
    public static func run(_ source:String)->Result<String,PersonalAgentError> {
        var failure:NSDictionary?;guard let script=NSAppleScript(source:source) else {return .failure(.invalidCommand)}
        let result=script.executeAndReturnError(&failure)
        if (failure?[NSAppleScript.errorNumber] as? Int)==(-1743) {return .failure(.permissionDenied)}
        guard failure==nil,let text=result.stringValue else {return .failure(.verificationFailed)};return .success(text)
    }
    public static func execute(_ source:String) throws ->String {try run(source).get()}
}
