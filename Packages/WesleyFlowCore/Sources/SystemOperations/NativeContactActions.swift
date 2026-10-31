import AppKit
import Contacts
import Domain
@MainActor public enum NativeContactActions {
    static func address(_ phones:[String])->String? {
        let clean=Array(Set(phones.map{$0.filter{$0.isNumber || $0=="+"}}))
        guard clean.count==1,let value=clean.first,value.hasPrefix("+"),PersonalMessage.validAddress(value) else {return nil};return value
    }
    private static func contacts(_ query:String,includePhones:Bool=false) async throws ->[CNContact] {
        let store=CNContactStore()
        if CNContactStore.authorizationStatus(for:.contacts) == .notDetermined {guard try await store.requestAccess(for:.contacts) else {throw PersonalAgentError.permissionDenied}}
        guard CNContactStore.authorizationStatus(for:.contacts) == .authorized else {throw PersonalAgentError.permissionDenied}
        var keys:[CNKeyDescriptor]=[CNContactFormatter.descriptorForRequiredKeys(for:.fullName),CNContactIdentifierKey as CNKeyDescriptor]
        if includePhones {keys.append(CNContactPhoneNumbersKey as CNKeyDescriptor)}
        let result=try store.unifiedContacts(matching:CNContact.predicateForContacts(matchingName:query),keysToFetch:keys)
        return Array(result.filter{NativePersonalMessages.matches(query,fullName:CNContactFormatter.string(from:$0,style:.fullName) ?? "",givenName:$0.givenName)}.prefix(20))
    }
    public static func resolve(_ plan:PersonalPlan) async throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .contactAction {
            var c=try PersonalObjectCommand.decode(steps[i].text)
            guard c.tool == .contactAction else {throw PersonalAgentError.invalidCommand}
            let chat=[PersonalObjectCommand.Action.contactMessages,.contactWhatsApp].contains(c.action)
            if c.action == .contactWhatsApp,!c.value.isEmpty {guard c.value.hasPrefix("+"),!c.value.contains("@") else {throw PersonalRecipientChoiceRequired(plan:plan,stepID:steps[i].id,options:[],prompt:"WhatsApp needs the exact full international phone number, including + and country code.")}}
            if chat,PersonalMessage.validAddress(c.value),c.targetID?.hasPrefix("literal:")==true {steps[i] = .init(id:steps[i].id,tool:.contactAction,text:try c.encoded());continue}
            if chat,PersonalMessage.validAddress(c.name),c.name.hasPrefix("+") {c.value=c.name;c.targetID="literal:"+c.name;steps[i] = .init(id:steps[i].id,tool:.contactAction,text:try c.encoded());continue}
            let matches=try await contacts(c.name,includePhones:chat)
            if chat {
                var options:[PersonalRecipientOption]=[]
                for contact in matches {
                    let name=CNContactFormatter.string(from:contact,style:.fullName) ?? c.name
                    for number in contact.phoneNumbers.map({$0.value.stringValue}) {
                        let cleaned=number.filter{$0.isNumber || $0=="+"}
                        if cleaned.hasPrefix("+"),PersonalMessage.validAddress(cleaned) {let option=PersonalRecipientOption(name:name,address:cleaned,sourceID:contact.identifier);if !options.contains(option) {options.append(option)}}
                    }
                }
                if let selected=c.targetID,!c.value.isEmpty,let matching=options.first(where:{$0.sourceID==selected && $0.address==c.value}) {c.name=matching.name}
                else if options.count==1,let one=options.first {c.name=one.name;c.targetID=one.sourceID;c.value=one.address}
                else {throw PersonalRecipientChoiceRequired(plan:plan,stepID:steps[i].id,options:Array(options.prefix(6)),prompt:"Which exact contact/phone number should this chat open? No message will be sent.")}
            } else if matches.count==1,let one=matches.first {c.name=CNContactFormatter.string(from:one,style:.fullName) ?? c.name;c.targetID=one.identifier}
            steps[i] = .init(id:steps[i].id,tool:.contactAction,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let c=try PersonalObjectCommand.decode(step.text)
        guard c.tool == .contactAction else {throw PersonalAgentError.invalidCommand}
        let literal=c.targetID?.hasPrefix("literal:")==true && c.targetID=="literal:"+c.value && PersonalMessage.validAddress(c.value)
        let matches=literal ? []:try await contacts(c.name,includePhones:c.action != .contactsFind)
        if c.action == .contactsFind {return .init(identifier:c.targetID ?? step.id.uuidString,evidence:matches.isEmpty ? "No exact contact matches.":matches.map{CNContactFormatter.string(from:$0,style:.fullName) ?? "Unnamed"}.joined(separator:"; "))}
        var current=c.value
        if !literal {
            guard matches.count==1,let target=matches.first,c.targetID==target.identifier else {throw PersonalPlanningFailure.recipientAmbiguous}
            let numbers=target.phoneNumbers.map{$0.value.stringValue}
            if c.action == .contactPhones {return .init(identifier:target.identifier,evidence:"Phone numbers for "+c.name+": "+numbers.joined(separator:"; "))}
            guard numbers.map({$0.filter{$0.isNumber || $0=="+"}}).contains(c.value) else {throw PersonalAgentError.verificationFailed}
            current=c.value
        }
        guard [.contactMessages,.contactWhatsApp].contains(c.action) else {throw PersonalAgentError.invalidCommand}
        let url:URL
        if c.action == .contactWhatsApp {
            guard current.hasPrefix("+"),!current.contains("@") else {throw PersonalAgentError.invalidCommand}
            _=try NativePersonalApps.target("net.whatsapp.WhatsApp")
            guard let link=URL(string:"https://wa.me/"+current.filter(\.isNumber)) else {throw PersonalAgentError.invalidCommand};url=link
        } else {
            var components=URLComponents();components.scheme="sms";components.path=current
            guard let link=components.url else {throw PersonalAgentError.invalidCommand};url=link
        }
        if c.action == .contactMessages {
            let app=try NativePersonalApps.target("com.apple.MobileSMS"),config=NSWorkspace.OpenConfiguration();config.activates=true
            let running=try await NSWorkspace.shared.open([url],withApplicationAt:app,configuration:config)
            guard running.bundleIdentifier=="com.apple.MobileSMS",!running.isTerminated else {throw PersonalAgentError.verificationFailed}
        } else {guard NSWorkspace.shared.open(url) else {throw PersonalAgentError.verificationFailed}}
        return .init(identifier:c.targetID ?? step.id.uuidString,evidence:"Exact reviewed phone-number chat link handed to macOS. No message text supplied or sent; actual conversation display is unverified.",verified:false)
    }
}
