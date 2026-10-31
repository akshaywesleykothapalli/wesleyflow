import AppKit
import Domain
@MainActor public enum NativeMediaActions {
    static func source(_ c:PersonalObjectCommand)->String {
        let spotify=([.mediaShuffleOn,.mediaShuffleOff,.mediaStatus].contains(c.action) && c.name.lowercased()=="spotify"),app=spotify ? "com.spotify.client":"com.apple.Music"
        let q=NativeAgentScript.literal
        let body:String
        switch c.action {
        case .mediaTrack:
            body="""
            set matches to tracks of library playlist 1 whose name is \(q(c.name))\(c.value.isEmpty ? "":" and artist is "+q(c.value))\(c.scopeName.map{" and album is "+q($0)} ?? "")
            if (count of matches) is not 1 then error "ambiguous-track"
            set selectedTrack to item 1 of matches
            set wanted to persistent ID of selectedTrack
            play selectedTrack
            if (persistent ID of current track) is not wanted then error "track-unconfirmed"
            return "Exact library track identity read back."
            """
        case .mediaPlaylist:
            body="""
            set matches to user playlists whose name is \(q(c.name))
            if (count of matches) is not 1 then error "ambiguous-playlist"
            set chosen to item 1 of matches
            set wanted to persistent ID of chosen
            play chosen
            if (persistent ID of current playlist) is not wanted then error "playlist-unconfirmed"
            return "Exact saved playlist identity read back."
            """
        case .mediaShuffleOn,.mediaShuffleOff:
            let key=spotify ? "shuffling":"shuffle enabled",value=c.action == .mediaShuffleOn ? "true":"false"
            body="set \(key) to \(value)\nif \(key) is not \(value) then error \"shuffle-unconfirmed\"\nreturn \"Shuffle setting read back.\""
        case .mediaRepeatOne,.mediaRepeatOff:
            let mode=c.action == .mediaRepeatOne ? "one":"off"
            body="set song repeat to \(mode)\nif song repeat is not \(mode) then error \"repeat-unconfirmed\"\nreturn \"Repeat setting read back.\""
        case .mediaSeek:
            guard let seconds=Int(c.value),(1...3600).contains(seconds) else {return "error \"invalid-seek\""}
            body="""
            set wantedID to persistent ID of current track
            set wanted to (player position) + \(seconds)
            set durationSeconds to duration of current track
            if wanted > (durationSeconds - 1) then set wanted to durationSeconds - 1
            if wanted < 0 then error "invalid-duration"
            set player position to wanted
            if (persistent ID of current track) is not wantedID then error "track-changed"
            if (player position) < (wanted - 2) or (player position) > (wanted + 2) then error "seek-unconfirmed"
            return "Position read back within two seconds on the same track."
            """
        case .mediaStatus:body="return (name of current track) & \" · \" & (artist of current track) & \" · \" & (player state as text)"
        default:return "error \"unsupported\""
        }
        return "with timeout of 8 seconds\ntell application id \""+app+"\"\n"+body+"\nend tell\nend timeout"
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let c=try PersonalObjectCommand.decode(step.text)
        guard c.tool == .mediaAction else {throw PersonalAgentError.invalidCommand}
        if c.action == .mediaAlbum {
            let app=try NativePersonalApps.target("com.spotify.client")
            guard !c.name.isEmpty,let encoded=("album:\""+c.name.replacingOccurrences(of:"\"",with:"\\\"")+"\"").addingPercentEncoding(withAllowedCharacters:.alphanumerics),let url=URL(string:"spotify:search:"+encoded) else {throw PersonalAgentError.invalidCommand}
            let config=NSWorkspace.OpenConfiguration();config.activates=true
            let opened=try await NSWorkspace.shared.open([url],withApplicationAt:app,configuration:config)
            guard !opened.isTerminated,opened.bundleIdentifier=="com.spotify.client" else {throw PersonalAgentError.verificationFailed}
            return .init(identifier:url.absoluteString,evidence:"Spotify album search opened for the exact requested title. Select the matching album and play in Spotify. Album-name resolution/playback is not exposed by this native adapter; the old queue was not played as a substitute.",verified:false)
        }
        let app=([.mediaShuffleOn,.mediaShuffleOff,.mediaStatus].contains(c.action) && c.name.lowercased()=="spotify") ? "com.spotify.client":"com.apple.Music"
        _=try NativePersonalApps.target(app)
        let result=try NativeAgentScript.execute(source(c))
        return .init(identifier:app,evidence:result+" Native metadata/state only; actual acoustic output not inspected.")
    }
}
