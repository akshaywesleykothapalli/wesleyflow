import Foundation

/// Fixed local origins, never a guessed domain or a remote name-resolution service.
public struct PersonalWebsiteName:Sendable,Equatable,Identifiable {
    public var id:String {name}
    public let name:String
    public let address:String
    public let aliases:[String]
}
public enum PersonalWebsiteNames {
    public static let sites:[PersonalWebsiteName]=[
        .init(name:"Google",address:"https://www.google.com/",aliases:[]),
        .init(name:"Gmail",address:"https://mail.google.com/",aliases:["G mail","Google mail"]),
        .init(name:"YouTube",address:"https://www.youtube.com/",aliases:["You tube"]),
        .init(name:"Google Maps",address:"https://maps.google.com/",aliases:["Maps"]),
        .init(name:"Google Drive",address:"https://drive.google.com/",aliases:["Drive"]),
        .init(name:"Google Docs",address:"https://docs.google.com/document/",aliases:["Docs"]),
        .init(name:"Google Sheets",address:"https://docs.google.com/spreadsheets/",aliases:["Sheets"]),
        .init(name:"Google Slides",address:"https://docs.google.com/presentation/",aliases:["Slides"]),
        .init(name:"Google Calendar",address:"https://calendar.google.com/",aliases:[]),
        .init(name:"Google Meet",address:"https://meet.google.com/",aliases:[]),
        .init(name:"Google Photos",address:"https://photos.google.com/",aliases:[]),
        .init(name:"YouTube Music",address:"https://music.youtube.com/",aliases:[]),
        .init(name:"GitHub",address:"https://github.com/",aliases:["Git hub"]),
        .init(name:"Wikipedia",address:"https://www.wikipedia.org/",aliases:[]),
        .init(name:"Reddit",address:"https://www.reddit.com/",aliases:[]),
        .init(name:"LinkedIn",address:"https://www.linkedin.com/",aliases:["Linked in"]),
        .init(name:"Instagram",address:"https://www.instagram.com/",aliases:[]),
        .init(name:"Facebook",address:"https://www.facebook.com/",aliases:[]),
        .init(name:"Netflix",address:"https://www.netflix.com/",aliases:[]),
        .init(name:"WhatsApp Web",address:"https://web.whatsapp.com/",aliases:[]),
        .init(name:"Spotify Web",address:"https://open.spotify.com/",aliases:["Spotify web player"]),
        .init(name:"DuckDuckGo",address:"https://duckduckgo.com/",aliases:["Duck duck go"]),
        .init(name:"Bing",address:"https://www.bing.com/",aliases:[])
    ]
    private static func key(_ input:String)->String {input.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")).lowercased().filter{$0.isLetter || $0.isNumber}}
    public static func address(_ input:String)->String? {
        let wanted=key(input),matches=sites.filter{([$0.name]+$0.aliases).contains{key($0)==wanted}}
        return matches.count==1 ? matches[0].address:nil
    }
}
public struct PersonalWebsiteAddressRequired:Error,Sendable {
    public let browser:PersonalWebsiteRequest.Browser?
    public init(browser:PersonalWebsiteRequest.Browser?) {self.browser=browser}
}
