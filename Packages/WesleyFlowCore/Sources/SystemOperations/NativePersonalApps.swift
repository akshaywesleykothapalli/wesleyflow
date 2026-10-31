import AppKit
import Darwin
import Contacts
import Domain

@MainActor public enum NativePersonalApps {
    private static let registryAliases:[String:[String]]=["com.apple.finder":["Finder"],"net.whatsapp.WhatsApp":["WhatsApp","Whats App","Whatsap","What sap"],"com.brave.Browser":["Brave","Brave Browser"],"com.microsoft.VSCode":["VS Code","VSCode","Code","Visual Studio Code"],"com.apple.Safari":["Safari"],"com.apple.systempreferences":["Settings","System Settings","System Preferences"]]
    public static func catalog() -> [PersonalApp] {
        var apps=Dictionary(uniqueKeysWithValues:discovered(roots:applicationRoots).map { ($0.app.id,$0.app) })
        for (id,aliases) in registryAliases {
            guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:id),Bundle(url:url)?.bundleIdentifier==id else { continue }
            let old=apps[id]
            apps[id]=PersonalApp(id:id,name:old?.name ?? url.deletingPathExtension().lastPathComponent,aliases:Array(Set((old?.aliases ?? [])+aliases)).sorted())
        }
        return apps.values.sorted { $0.name<$1.name }
    }
    private static var applicationRoots:[URL] {
        [URL(fileURLWithPath:"/Applications"),URL(fileURLWithPath:"/System/Applications"),FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }
    // Bounded folder traversal, including Utilities/vendor folders, never inside an app bundle.
    static func discovered(roots:[URL]) -> [(app:PersonalApp,url:URL)] {
        var found:[String:(app:PersonalApp,url:URL)]=[:],visited=0
        let keys:[URLResourceKey]=[.isDirectoryKey,.isSymbolicLinkKey,.isPackageKey]
        var pending=roots.map { (url:$0,depth:0) }
        while !pending.isEmpty,visited<16384,found.count<PersonalConversation.maximumApps {
            let directory=pending.removeFirst()
            let children=(try? FileManager.default.contentsOfDirectory(at:directory.url,includingPropertiesForKeys:keys,options:[])) ?? []
            for url in children.sorted(by:{$0.path<$1.path}) where !url.lastPathComponent.hasPrefix(".") {
                visited+=1
                guard visited<=16384,found.count<PersonalConversation.maximumApps else { break }
                guard let values=try? url.resourceValues(forKeys:Set(keys)) else { continue }
                if values.isSymbolicLink == true && url.pathExtension.lowercased() != "app" { continue }
                if url.pathExtension.lowercased() == "app" {
                    let bundleURL=url.resolvingSymlinksInPath()
                    guard let bundle=Bundle(url:bundleURL),let id=bundle.bundleIdentifier,id != Bundle.main.bundleIdentifier else { continue }
                    let stem=bundleURL.deletingPathExtension().lastPathComponent
                    let names=[bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,bundle.infoDictionary?["CFBundleDisplayName"] as? String,bundle.localizedInfoDictionary?["CFBundleName"] as? String,bundle.infoDictionary?["CFBundleName"] as? String,stem].compactMap { $0 }.filter { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
                    let common:[String] = switch id { case "com.brave.Browser": ["Brave","Brave browser"];case "net.whatsapp.WhatsApp":["Whats App","WhatsApp"];case "com.apple.Safari":["Safari"];case "com.microsoft.VSCode":["VS Code","VSCode","Visual Studio Code","Code"];default:[] }
                    let aliases=names+common+[url.deletingPathExtension().lastPathComponent]+(found[id]?.app.aliases ?? [])
                    found[id]=(PersonalApp(id:id,name:names.first ?? stem,aliases:Array(Set(aliases)).sorted()),found[id]?.url ?? bundleURL)
                } else if values.isDirectory == true,values.isPackage != true,directory.depth<5 { pending.append((url,directory.depth+1)) }
            }
        }
        return found.values.sorted { $0.app.name == $1.app.name ? $0.app.id<$1.app.id:$0.app.name<$1.app.name }
    }
    public static func target(_ id:String) throws -> URL {
        guard id != Bundle.main.bundleIdentifier else { throw PersonalAgentError.unsupported }
        if let entry=discovered(roots:applicationRoots).first(where:{$0.app.id==id}),Bundle(url:entry.url)?.bundleIdentifier==id { return entry.url }
        guard catalog().contains(where:{$0.id==id}),let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:id),Bundle(url:url)?.bundleIdentifier==id else { throw PersonalAgentError.unsupported }
        return url
    }
    public static func open(_ id:String) async throws -> PersonalReceipt {
        let url=try target(id);let config=NSWorkspace.OpenConfiguration();config.activates=true
        let app=try await NSWorkspace.shared.openApplication(at:url,configuration:config)
        guard !app.isTerminated else { throw PersonalAgentError.verificationFailed }
        return .init(identifier:id,evidence:"NSWorkspace returned running application; launch only")
    }
    public static func close(_ id:String) async throws -> PersonalReceipt {
        _=try target(id)
        return try await NativeAppClosing.perform(id)
    }
    public static func searchURL(_ text:String,youtube:Bool) throws -> URL {
        guard !text.isEmpty,text.utf8.count<=2048 else { throw PersonalAgentError.invalidCommand }
        var components=URLComponents();components.scheme="https";components.host=youtube ? "www.youtube.com" : "www.google.com";components.path=youtube ? "/results" : "/search"
        components.queryItems=[URLQueryItem(name:youtube ? "search_query" : "q",value:text)]
        guard let url=components.url else { throw PersonalAgentError.invalidCommand };return url
    }
    public static func search(_ text:String,youtube:Bool) async throws -> PersonalReceipt {
        let url=try searchURL(text,youtube:youtube)
        guard NSWorkspace.shared.open(url) else { throw PersonalAgentError.verificationFailed }
        return .init(identifier:url.absoluteString,evidence:"NSWorkspace accepted search URL handoff; page/results not verified")
    }
}
@MainActor public enum NativePersonalMessages {
    static func matches(_ query:String,fullName:String,givenName:String)->Bool {
        [fullName,givenName].contains { !$0.isEmpty && $0.compare(query,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame }
    }
    static func preferredAddress(phones:[String],mobiles:[String],emails:[String]) throws -> String {
        let candidates = phones.count == 1 ? phones : mobiles.count == 1 ? mobiles : phones.isEmpty ? emails : []
        guard candidates.count == 1,let value=candidates.first,PersonalMessage.validAddress(value) else { throw PersonalPlanningFailure.recipientAmbiguous }
        return value
    }
    /// Invoked only for an explicit message request, never on launch or for other tools.
    public static func resolve(_ plan:PersonalPlan) async throws -> PersonalPlan {
        try Task.checkCancellation()
        var steps:[PersonalStep]=[]
        for step in plan.steps {
            try Task.checkCancellation()
            guard step.tool == .message else { steps.append(step);continue }
            var message=try PersonalMessage.decode(step.text)
            if let address=message.address,PersonalMessage.validAddress(address) { steps.append(step);continue }
            if PersonalMessage.validAddress(message.recipient) { message.address=message.recipient }
            else {
                func clarification(_ options:[PersonalRecipientOption],_ prompt:String)->PersonalRecipientChoiceRequired {
                    PersonalRecipientChoiceRequired(plan:plan,stepID:step.id,options:options,prompt:prompt)
                }
                let store=CNContactStore()
                if CNContactStore.authorizationStatus(for:.contacts) == .notDetermined {
                    let allowed=(try? await store.requestAccess(for:.contacts)) ?? false
                    guard allowed else { throw clarification([],"Contacts access is unavailable. What exact phone number or email should receive this message?") }
                }
                guard CNContactStore.authorizationStatus(for:.contacts) == .authorized else { throw clarification([],"Contacts access is unavailable. What exact phone number or email should receive this message?") }
                let keys:[CNKeyDescriptor]=[CNContactFormatter.descriptorForRequiredKeys(for:.fullName),CNContactGivenNameKey as CNKeyDescriptor,CNContactPhoneNumbersKey as CNKeyDescriptor,CNContactEmailAddressesKey as CNKeyDescriptor]
                try Task.checkCancellation()
                let contacts:[CNContact]
                do {
                    contacts=try store.unifiedContacts(matching:CNContact.predicateForContacts(matchingName:message.recipient),keysToFetch:keys).filter { matches(message.recipient,fullName:CNContactFormatter.string(from:$0,style:.fullName) ?? "",givenName:$0.givenName) }
                } catch { throw clarification([],"Contacts could not be read. What exact phone number or email should receive the message?") }
                var choices:[PersonalRecipientOption]=[]
                for contact in contacts.prefix(6) {
                    let name=CNContactFormatter.string(from:contact,style:.fullName) ?? message.recipient
                    let phones=contact.phoneNumbers.map { $0.value.stringValue }
                    let mobiles=contact.phoneNumbers.filter { [CNLabelPhoneNumberMobile,CNLabelPhoneNumberiPhone].contains($0.label ?? "") }.map { $0.value.stringValue }
                    let emails=contact.emailAddresses.map { String($0.value) }
                    let candidates=(try? preferredAddress(phones:phones,mobiles:mobiles,emails:emails)).map { [$0] } ?? (phones.isEmpty ? emails:phones)
                    for value in candidates where PersonalMessage.validAddress(value) {
                        let option=PersonalRecipientOption(name:name,address:value)
                        if !choices.contains(option) { choices.append(option) }
                    }
                }
                guard contacts.count==1,choices.count==1,let choice=choices.first else {
                    throw clarification(Array(choices.prefix(6)),choices.isEmpty ? "I couldn't uniquely match that contact. What exact phone number or email should receive the message?":"Which recipient/address do you mean? Choose an option, say its number, or give an exact phone/email.")
                }
                message=PersonalMessage(recipient:choice.name,body:message.body,address:choice.address)
            }
            steps.append(.init(id:step.id,tool:.message,text:try message.encoded()))
        }
        return try PersonalPlan(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
}
