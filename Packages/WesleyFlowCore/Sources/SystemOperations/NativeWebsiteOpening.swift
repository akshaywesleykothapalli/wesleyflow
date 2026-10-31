import AppKit
import Domain
@MainActor public enum NativeWebsiteOpening {
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let request=try PersonalWebsiteRequest.decode(step.text)
        guard let url=PersonalWebsiteRequest.url(request.address) else {throw PersonalAgentError.invalidCommand}
        let target:URL
        if let browser=request.browser {target=try NativePersonalApps.target(browser.bundleID)}
        else {guard let app=NSWorkspace.shared.urlForApplication(toOpen:url) else {throw PersonalAgentError.unsupported};target=app}
        guard let expectedID=Bundle(url:target)?.bundleIdentifier else {throw PersonalAgentError.unsupported}
        let configuration=NSWorkspace.OpenConfiguration();configuration.activates=true
        let app=try await NSWorkspace.shared.open([url],withApplicationAt:target,configuration:configuration)
        guard !app.isTerminated,app.bundleIdentifier==expectedID else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:url.absoluteString,evidence:"Website URL handed directly to "+(request.browser?.rawValue.capitalized ?? "your default browser")+": "+url.absoluteString+". No search query was created. Page loading is unverified.",verified:false)
    }
}
