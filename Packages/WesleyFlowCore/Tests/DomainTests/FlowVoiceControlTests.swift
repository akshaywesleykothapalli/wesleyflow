import Testing
import Foundation
@testable import Domain

@Suite("Flow voice settings and Mac aliases") struct FlowVoiceControlTests {
    @Test(arguments:FlowVoiceControl.examples) func everyDisplayedControlHasAnExactMeaning(_ text:String) {
        #expect(FlowVoiceControl.parse(text) != nil)
    }
    @Test func languageAndCourtesyAreExplicit() {
        #expect(FlowVoiceControl.parse("Please switch dictation to Telugu.") == .language(.teluguRomanised,.teluguOnly))
        #expect(FlowVoiceControl.parse("Switch to English!") == .language(.english,nil))
        #expect(FlowVoiceControl.parse("use Telugu and English") == .language(.teluguRomanised,.automatic))
    }
    @Test(arguments:["do not switch to Telugu","create a note switch to Telugu","text Sam switch to Telugu","switch to Telugu and open Notes","switch to Telugu\nopen Notes","clear dictation history","switch engine to parakeet","say switch to Telugu","telugu",String(repeating:"x",count:513)])
    func partialCompoundDestructiveAndLiteralRequestsAreNotSettingsCommands(_ text:String) {
        #expect(FlowVoiceControl.parse(text) == nil)
    }
    @Test(arguments:["turn volume up","turn the volume up","turn system volume up","turn volume down","turn the volume down","turn system volume down"])
    func explicitVolumeAliasesUseExistingTypedAction(_ text:String) throws {
        let plan = try #require(try PersonalControlIntents.parse(text,now:Date(timeIntervalSince1970:1)))
        #expect(plan.steps.count == 1 && plan.steps[0].tool == .systemAudio)
        let command = try PersonalAudioCommand.decode(plan.steps[0].text)
        #expect(command.action == (text.hasSuffix("up") ? .up : .down))
    }
    @Test(arguments:["show battery status","how much battery is left"])
    func batteryAliasesRemainReadOnly(_ text:String) throws {
        let plan = try #require(try PersonalMacControl.parse(text,now:Date(timeIntervalSince1970:1)))
        #expect(plan.steps.count == 1 && plan.steps[0].tool == .macControl)
        #expect(try PersonalMacControl.decode(plan.steps[0].text).action == .battery)
    }
}
