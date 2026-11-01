import Testing
import Foundation
@testable import Domain

@Suite("Local before-insertion formatting") struct LocalShortcutFormattingTests {
    @Test func polishCleansFillersAndPunctuationWithoutInventingWords() throws {
        let output = try LocalShortcutFormatting.format("um, please check the save button",kind:.polish)
        #expect(output == "Please check the save button.")
    }
    @Test func codeNumbersNegationAndRepetitionArePreserved() throws {
        let source = "check `buttonID` and do not remove -17 or go go go"
        let output = try LocalShortcutFormatting.format(source,kind:.polish)
        #expect(output.contains("`buttonID`") && output.contains("-17") && output.contains("do not") && output.contains("go go go"))
        try ProtectedRewriteText(.init(id:"test",text:source,localeIdentifier:"en-IN")).validateRestored(output)
    }
    @Test func promptUsesOnlyOriginalUnitsUnderRelevantHeadings() throws {
        let source = "Check the save button.\nKeep the current layout.\nReturn a short report."
        let output = try LocalShortcutFormatting.format(source,kind:.promptEngineering)
        #expect(output.contains("## Objective") && output.contains("## Constraints") && output.contains("## Expected output"))
        try PromptEngineeringContract(.init(id:"test",text:source,localeIdentifier:"en-IN",kind:.promptEngineering)).validateRendered(output)
    }
    @Test(arguments:["",String(repeating:"x",count:2049),"```swift\nrun()\n```"])
    func unsafeOrOversizedPromptIsRejectedForCallerToRetainOriginal(_ text:String) {
        #expect(throws:(any Error).self) { try LocalShortcutFormatting.format(text,kind:.promptEngineering) }
    }
}
