import AppKit
import CoreAudio
import IOKit
import IOKit.graphics
import IOKit.ps
import Domain
@MainActor public enum NativeMacControl {
    static func uniqueDevice(_ wanted:String,devices:[(id:UInt32,name:String,builtIn:Bool)]) throws ->UInt32 {
        let key=wanted.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
        let exact=devices.filter{$0.name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))==key}
        let matches=exact.isEmpty ? devices.filter {key=="built-in" ? $0.builtIn:$0.name.localizedCaseInsensitiveContains(key)}:exact
        guard matches.count==1,let one=matches.first else {throw PersonalAgentError.unsupported};return one.id
    }
    private static func device(_ request:PersonalMacControl) throws ->PersonalReceipt {
        let input=request.action == .inputDevice,scope=input ? kAudioDevicePropertyScopeInput:kAudioDevicePropertyScopeOutput
        var listAddress=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var bytes:UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&listAddress,0,nil,&bytes)==noErr,bytes<=4096 else {throw PersonalAgentError.unsupported}
        var ids=[AudioDeviceID](repeating:0,count:Int(bytes)/MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&listAddress,0,nil,&bytes,&ids)==noErr else {throw PersonalAgentError.verificationFailed}
        var candidates:[(id:UInt32,name:String,builtIn:Bool)]=[]
        for id in ids {
            var streams=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:scope,mElement:kAudioObjectPropertyElementMain),size:UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&streams,0,nil,&size)==noErr,size>0 else {continue}
            var nameAddress=AudioObjectPropertyAddress(mSelector:kAudioObjectPropertyName,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var rawName:Unmanaged<CFString>?;size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id,&nameAddress,0,nil,&size,&rawName)==noErr,let name=rawName?.takeRetainedValue() else {continue}
            var transportAddress=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyTransportType,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain),transport:UInt32=0
            size=UInt32(MemoryLayout<UInt32>.size);_ = AudioObjectGetPropertyData(id,&transportAddress,0,nil,&size,&transport)
            candidates.append((id,name as String,transport==kAudioDeviceTransportTypeBuiltIn))
        }
        var target=try uniqueDevice(request.value,devices:candidates)
        var address=AudioObjectPropertyAddress(mSelector:input ? kAudioHardwarePropertyDefaultInputDevice:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size=UInt32(MemoryLayout<AudioDeviceID>.size)
        var writable=DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(AudioObjectID(kAudioObjectSystemObject),&address,&writable)==noErr,writable.boolValue else {throw PersonalAgentError.unsupported}
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,size,&target)==noErr else {throw PersonalAgentError.permissionDenied}
        var observed:AudioDeviceID=0
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&observed)==noErr,observed==target else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:String(target),evidence:"Default \(input ? "input":"output") device verified: "+(candidates.first(where:{$0.id==target})?.name ?? request.value))
    }
    private static func nativeBrightnessAvailable()->Bool {
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IODisplayConnect"),&iterator)==KERN_SUCCESS else {return false}
        defer {IOObjectRelease(iterator)}
        var count=0
        while true {let service=IOIteratorNext(iterator);if service==0 {break};var level:Float=0;if IODisplayGetFloatParameter(service,0,kIODisplayBrightnessKey as CFString,&level)==kIOReturnSuccess {count+=1};IOObjectRelease(service)}
        return count==1
    }
    public static func resolve(_ plan:PersonalPlan) throws ->PersonalPlan {
        var steps=plan.steps
        for i in steps.indices where steps[i].tool == .macControl {
            var c=try PersonalMacControl.decode(steps[i].text)
            c.originPID=NSWorkspace.shared.frontmostApplication?.processIdentifier;c.originBundleID=NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            steps[i] = .init(id:steps[i].id,tool:.macControl,text:try c.encoded())
        }
        return try .init(id:plan.id,steps:steps,createdAt:plan.createdAt)
    }
    private static func restoreFocus(_ c:PersonalMacControl) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier=="com.apple.systempreferences",let pid=c.originPID,let app=NSRunningApplication(processIdentifier:pid),app.bundleIdentifier==c.originBundleID,!app.isTerminated else {return}
        app.activate(options:[])
    }
    public static func perform(_ step:PersonalStep) async throws ->PersonalReceipt {
        let request=try PersonalMacControl.decode(step.text);try Task.checkCancellation()
        if request.action == .lowPower {let receipt=try await NativeSystemSettings.lowPower();restoreFocus(request);return receipt}
        if [.brightnessUp,.brightnessDown,.brightnessSet].contains(request.action) {guard NSScreen.screens.count==1 else {throw PersonalAgentError.unsupported}}
        if [.brightnessUp,.brightnessDown,.brightnessSet].contains(request.action),!nativeBrightnessAvailable() {let receipt=try await NativeSystemSettings.brightness(request);restoreFocus(request);return receipt}
        if [.outputDevice,.inputDevice].contains(request.action) {return try device(request)}
        if request.action == .battery {
            guard let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),let sources=IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {throw PersonalAgentError.unsupported}
            for source in sources {
                guard let value=IOPSGetPowerSourceDescription(info,source)?.takeUnretainedValue() as? [String:Any],value[kIOPSTypeKey]==nil || (value[kIOPSTypeKey] as? String)==kIOPSInternalBatteryType,let current=value[kIOPSCurrentCapacityKey] as? Int,let maximum=value[kIOPSMaxCapacityKey] as? Int,maximum>0 else {continue}
                let n=max(0,min(100,Int(Double(current)*100/Double(maximum)))),charging=value[kIOPSIsChargingKey] as? Bool ?? false
                return .init(identifier:step.id.uuidString,evidence:"Battery: \(n)% · \(charging ? "charging":"not charging") · Low Power Mode \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on":"off"). Native power status read back.")
            }
            throw PersonalAgentError.unsupported
        }
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IODisplayConnect"),&iterator)==KERN_SUCCESS else {throw PersonalAgentError.unsupported}
        defer {IOObjectRelease(iterator)}
        var displays:[io_service_t]=[]
        while true {let service=IOIteratorNext(iterator);if service==0 {break};var level:Float=0;if IODisplayGetFloatParameter(service,0,kIODisplayBrightnessKey as CFString,&level)==kIOReturnSuccess {displays.append(service)} else {IOObjectRelease(service)}}
        defer {for item in displays {IOObjectRelease(item)}}
        guard displays.count==1,let display=displays.first else {throw PersonalAgentError.unsupported}
        var prior:Float=0
        guard IODisplayGetFloatParameter(display,0,kIODisplayBrightnessKey as CFString,&prior)==kIOReturnSuccess else {throw PersonalAgentError.unsupported}
        let wanted:Float=request.action == .brightnessSet ? Float(Int(request.value) ?? 0)/100:max(0,min(1,prior+(request.action == .brightnessUp ? 0.1:-0.1)))
        guard IODisplaySetFloatParameter(display,0,kIODisplayBrightnessKey as CFString,wanted)==kIOReturnSuccess else {throw PersonalAgentError.unsupported}
        var observed:Float=0
        guard IODisplayGetFloatParameter(display,0,kIODisplayBrightnessKey as CFString,&observed)==kIOReturnSuccess,abs(observed-wanted)<=0.02 else {throw PersonalAgentError.verificationFailed}
        return .init(identifier:String(display),evidence:"Display brightness setting read back: \(Int(observed*100))%. Supported IOKit display only.")
    }
}
