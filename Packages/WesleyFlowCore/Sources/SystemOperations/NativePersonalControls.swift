import AppKit
import Domain

/// Closed native control templates. No user-supplied code, URLs, keystrokes or page contents.
@MainActor public enum NativePersonalControls {
    private static func script(_ source:String) throws ->String {
        var error:NSDictionary?
        guard let script=NSAppleScript(source:source) else {throw PersonalAgentError.invalidCommand}
        let result=script.executeAndReturnError(&error)
        if (error?[NSAppleScript.errorNumber] as? Int)==(-1743) {throw PersonalAgentError.permissionDenied}
        guard error==nil,let text=result.stringValue else {throw PersonalAgentError.verificationFailed}
        return text
    }
    public static func audioSource(_ request:PersonalAudioCommand)->String {
        let change:String=switch request.action {
        case .status:""
        case .set:"set wanted to \(request.percent ?? -1)\nset volume output volume wanted"
        case .up:"set wanted to (output volume of (get volume settings)) + 10\nif wanted > 100 then set wanted to 100\nset volume output volume wanted"
        case .down:"set wanted to (output volume of (get volume settings)) - 10\nif wanted < 0 then set wanted to 0\nset volume output volume wanted"
        case .mute:"set volume output muted true"
        case .unmute:"set volume output muted false"
        }
        let verify:String=switch request.action {
        case .set,.up,.down:"if (absValue(actual - wanted)) > 1 then error \"volume-not-confirmed\""
        case .mute:"if silent is not true then error \"mute-not-confirmed\""
        case .unmute:"if silent is not false then error \"unmute-not-confirmed\""
        case .status:""
        }
        return """
        on absValue(n)
          if n < 0 then return -n
          return n
        end absValue
        with timeout of 5 seconds
          \(change)
          set settings to get volume settings
          set actual to output volume of settings
          set silent to output muted of settings
          \(verify)
          return (actual as text) & ":" & (silent as text)
        end timeout
        """
    }
    public static func audioEvidence(_ result:String) throws ->String {
        let values=result.split(separator:":")
        guard values.count==2,let n=Int(values[0]),(0...100).contains(n),["true","false"].contains(String(values[1])) else {throw PersonalAgentError.verificationFailed}
        return "Output volume: \(n)% · " + (values[1]=="true" ? "muted":"unmuted") + ". System setting read back."
    }
    public static func browserSource(_ request:PersonalBrowserControl)->String {
        let safari=request.browser == .safari
        let makeWindow=safari ? "make new document with properties {URL:\"about:blank\"}":"make new window"
        let selected=safari ? "index of current tab of w":"active tab index of w"
        let select=safari ? "set current tab of w to tab wanted of w":"set active tab index of w to wanted"
        let body:String
        switch request.action {
        case .newWindow:
            body="""
            set beforeCount to count of windows
            \(makeWindow)
            if (count of windows) is not (beforeCount + 1) then error "window-not-confirmed"
            activate
            return "new-window"
            """
        case .newTab:
            body="""
            if (count of windows) is 0 then
              \(makeWindow)
              if (count of windows) is 0 then error "window-not-confirmed"
              activate
              return "new-window"
            end if
            set windowID to id of front window
            set w to window id windowID
            set beforeCount to count of tabs of w
            if beforeCount > 500 then error "too-many-tabs"
            make new tab at end of tabs of w with properties {URL:"about:blank"}
            if (count of tabs of w) is not (beforeCount + 1) then error "tab-not-confirmed"
            set wanted to beforeCount + 1
            \(select)
            if (\(selected)) is not wanted then error "selection-not-confirmed"
            activate
            return "new-tab"
            """
        case .nextTab,.previousTab:
            let delta=request.action == .nextTab ? 1:-1
            body="""
            if (count of windows) is 0 then error "no-browser-window"
            set windowID to id of front window
            set w to window id windowID
            set total to count of tabs of w
            if total < 1 or total > 500 then error "invalid-tab-count"
            set wanted to (\(selected)) + (\(delta))
            if wanted > total then set wanted to 1
            if wanted < 1 then set wanted to total
            \(select)
            if (\(selected)) is not wanted then error "selection-not-confirmed"
            activate
            return "tab:" & wanted & "/" & total
            """
        }
        return """
        with timeout of 5 seconds
          tell application id "\(request.browser.bundleID)"
            \(body)
          end tell
        end timeout
        """
    }
    public static func perform(_ step:PersonalStep) throws ->PersonalReceipt {
        try Task.checkCancellation()
        switch step.tool {
        case .systemAudio:
            let request=try PersonalAudioCommand.decode(step.text)
            return .init(identifier:step.id.uuidString,evidence:try audioEvidence(script(audioSource(request))))
        case .browserControl:
            let request=try PersonalBrowserControl.decode(step.text)
            _=try NativePersonalApps.target(request.browser.bundleID)
            if [.nextTab,.previousTab].contains(request.action) {
                guard NSRunningApplication.runningApplications(withBundleIdentifier:request.browser.bundleID).contains(where:{!$0.isTerminated}) else {throw PersonalAgentError.unsupported}
            }
            let result=try script(browserSource(request))
            guard ["new-tab","new-window"].contains(result) || result.range(of:#"^tab:[1-9][0-9]{0,2}/[1-9][0-9]{0,2}$"#,options:.regularExpression) != nil else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:request.browser.bundleID,evidence:request.label+" · native tab/window state verified ("+result+"). Page contents not read.")
        default:throw PersonalAgentError.unsupported
        }
    }
    static func observeChangedTrack(_ before:String,read:@MainActor () throws ->String,pause:@MainActor () async throws ->Void) async throws {
        guard !before.isEmpty else {throw PersonalAgentError.verificationFailed}
        for attempt in 0..<12 {
            try Task.checkCancellation()
            let after=try read()
            guard !after.isEmpty else {throw PersonalAgentError.verificationFailed}
            if after != before {return}
            if attempt<11 {try await pause()}
        }
        throw PersonalAgentError.verificationFailed
    }
    public static func changeTrack(_ step:PersonalStep) async throws ->PersonalReceipt {
        guard [.music,.spotify].contains(step.tool),["next","previous"].contains(step.text) else {throw PersonalAgentError.invalidCommand}
        let app=step.tool == .music ? "com.apple.Music":"com.spotify.client"
        _=try NativePersonalApps.target(app)
        guard NSRunningApplication.runningApplications(withBundleIdentifier:app).contains(where:{!$0.isTerminated}) else {throw PersonalAgentError.unsupported}
        let track=step.tool == .music ? "persistent ID of current track":"id of current track"
        try Task.checkCancellation()
        let beforeID=try script("""
        with timeout of 5 seconds
          tell application id "\(app)"
            set beforeID to \(track)
            \(step.text) track
            return beforeID as text
          end tell
        end timeout
        """)
        try await observeChangedTrack(beforeID,read:{try script("""
        with timeout of 5 seconds
          tell application id "\(app)"
            return (\(track)) as text
          end tell
        end timeout
        """)},pause:{try await Task.sleep(for:.milliseconds(150))})
        return .init(identifier:app,evidence:"Requested \(step.text) track; changed native track identity read back. Playback/audio quality not inspected.")
    }
}
