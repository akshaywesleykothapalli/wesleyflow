import AppKit
import Domain
@MainActor public enum NativeBrowserExtra {
    private static let q=NativeAgentScript.literal
    private static func execute(_ browser:PersonalBrowserQuery.Browser,_ body:String) throws ->String {try NativeAgentScript.execute(source(browser,body))}
    static func source(_ browser:PersonalBrowserQuery.Browser,_ body:String)->String {"with timeout of 8 seconds\ntell application id \""+browser.bundleID+"\"\n"+body+"\nend tell\nend timeout"}
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .browserExtra {
            var c=try PersonalBrowserExtra.decode(steps[i].text)
            _=try NativePersonalApps.target(c.browser.bundleID)
            if [.close,.duplicate].contains(c.action) {
                let current=c.browser == .safari ? "current tab":"active tab"
                guard let id=Int(try execute(c.browser,"if (count of windows) is 0 then error \"no-window\"\nreturn id of front window")) else {throw PersonalAgentError.unsupported};c.windowID=id
                let w="window id "+String(id)
                c.url=try execute(c.browser,"return URL of \(current) of \(w)")
                c.title=try execute(c.browser,"return \(c.browser == .safari ? "name":"title") of \(current) of \(w)")
                if c.browser == .brave {c.tabID=try execute(c.browser,"return id of active tab of \(w)")}
                else {c.tabIndex=Int(try execute(c.browser,"return index of current tab of \(w)"))}
            }
            steps[i] = .init(id:steps[i].id,tool:.browserExtra,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    static func body(_ c:PersonalBrowserExtra) throws ->String {
        switch c.action {
        case .close:
            guard c.browser == .brave,let window=c.windowID,window>0,let tab=c.tabID,let url=c.url,let title=c.title else {throw PersonalAgentError.approvalRequired}
            return """
            set w to window id \(window)
            set matches to tabs of w whose id is \(q(tab))
            if (count of matches) is not 1 then error "tab-changed"
            set chosen to item 1 of matches
            if (URL of chosen) is not \(q(url)) or (title of chosen) is not \(q(title)) then error "metadata-changed"
            close chosen
            if exists (tab id \(q(tab)) of w) then error "close-unconfirmed"
            return "Reviewed tab ID is absent after native close; no dialogs forced."
            """
        case .duplicate:
            guard c.browser == .safari,let window=c.windowID,window>0,let index=c.tabIndex,(1...500).contains(index),let raw=c.url,let url=URL(string:raw),url.scheme=="https",url.host != nil,url.user==nil,url.password==nil else {throw PersonalAgentError.unsupported}
            return """
            set w to window id \(window)
            if (URL of tab \(index) of w) is not \(q(raw)) then error "source-tab-changed"
            set beforeCount to count of tabs of w
            if beforeCount>500 then error "too-many-tabs"
            set created to make new tab at end of tabs of w with properties {URL:\(q(raw))}
            set current tab of w to created
            if (count of tabs of w) is not (beforeCount + 1) then error "duplicate-unconfirmed"
            activate
            return "One new tab created with the exact reviewed HTTPS URL; page loading not verified."
            """
        case .findTitle,.findDomain:
            let safari=c.browser == .safari
            guard !c.query.isEmpty else {throw PersonalAgentError.invalidCommand}
            let predicate:String
            if c.action == .findDomain {
                guard c.query.range(of:#"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$"#,options:.regularExpression) != nil else {throw PersonalAgentError.invalidCommand}
                predicate="set link to URL of candidate\nif link starts with "+q("https://"+c.query+"/")+" or link is "+q("https://"+c.query)+" or link starts with "+q("http://"+c.query+"/")+" then set end of matches to {id of w, i}"
            } else {predicate="if (title of candidate) contains "+q(c.query)+" then set end of matches to {id of w, i}"}
            let select=safari ? "set current tab of w to tab wanted of w":"set active tab index of w to wanted"
            return """
            if (count of windows)>10 then error "too-many-windows"
            set matches to {}
            set inspected to 0
            repeat with w in windows
              repeat with i from 1 to (count of tabs of w)
                set inspected to inspected + 1
                if inspected>500 then error "too-many-tabs"
                set candidate to tab i of w
                \(predicate)
              end repeat
            end repeat
            if (count of matches) is not 1 then error "missing-or-ambiguous-tab"
            set chosen to item 1 of matches
            set w to window id (item 1 of chosen)
            set wanted to item 2 of chosen
            \(select)
            set index of w to 1
            activate
            if (\(safari ? "index of current tab of w":"active tab index of w")) is not wanted then error "selection-unconfirmed"
            return "Unique metadata match selected and active tab index read back; page bodies not read."
            """
        }
    }
    public static func perform(_ step:PersonalStep) throws ->PersonalReceipt {
        let c=try PersonalBrowserExtra.decode(step.text)
        let result=try execute(c.browser,body(c))
        return .init(identifier:step.id.uuidString,evidence:result)
    }
}
