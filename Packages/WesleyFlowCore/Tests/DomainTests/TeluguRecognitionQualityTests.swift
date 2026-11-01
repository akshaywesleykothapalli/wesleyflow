import Testing
@testable import Domain

@Suite("Telugu recognition admission") struct TeluguRecognitionQualityTests {
    @Test(arguments:["ಸಿಲಿ" + String(repeating:"ಲಿ",count:52),"तेल्गुलो मात्लाडुतुन्नानू","こんにちは"])
    func unsupportedScriptIsRejected(_ text:String) { #expect(TeluguRecognitionQuality.failure(in:text) == .unsupportedRecognitionScript) }
    @Test(arguments:["సి" + String(repeating:"లి",count:52),String(repeating:"abcdef",count:12),String(repeating:"a",count:32),String(repeating:"లు",count:7),String(repeating:"మారిని ",count:30)])
    func repetitionIsRejected(_ text:String) { #expect(TeluguRecognitionQuality.failure(in:text) == .repetitiveRecognition) }
    @Test(arguments:["తెలుగులో మాట్లాడుతున్నాను","రేపు meeting API v2.0 café","go go go go go go go go go go go go","ha ha ha","cafe\u{301} ❤️","లలిత కలకలం","bookkeeper","https://example.com/a_b"]) 
    func ordinaryRepeatsMixedEnglishAndTechnicalTextRemain(_ text:String) { #expect(TeluguRecognitionQuality.failure(in:text) == nil) }
    @Test func metadataContainsCountsOnly() { #expect(TeluguRecognitionQuality.scriptCounts("API తెలుగు ಕ") == "teluguLetters=6 latinLetters=3 otherLetters=1") }
}
