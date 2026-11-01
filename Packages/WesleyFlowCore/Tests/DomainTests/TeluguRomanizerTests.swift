import Testing
@testable import Domain

@Suite("Telugu Unicode and mixed-script output") struct TeluguRomanizerTests {
    @Test(arguments:[("బాగుంది రండి సంపాదన","baagundi randi sampaadana"),("నేను రేపు మీటింగ్ కి వస్తాను","nenu repu meeting ki vastaanu"),("తెలుగు","telugu"),("రామ","raama"),("క","ka"),("క్","k"),("క్ష","ksha"),("స్త్రీ","stree"),("క్రాంతి","kraanti"),("కా కి కీ కు కూ కె కే కై కొ కో కౌ","kaa ki kee ku koo ke ke kai ko ko kau"),("అ ఆ ఇ ఈ ఉ ఊ ఎ ఏ ఐ ఒ ఓ ఔ","a aa i ee u oo e e ai o o au"),("ం ః ౦౧౨౩౪౫౬౭౮౯","m h 0123456789"),("క్\u{200D}ష","ksha"),("క్\u{200C}ష","ksha"),("! API v2.0 /src/main.swift\n","! API v2.0 /src/main.swift\n"),("క\u{0C46}\u{0C56}","kai")])
    func unicode(_ sample:(String,String)) { #expect(TeluguRomanizer.romanise(sample.0) == sample.1) }
    @Test func mixedSpansAndLiteralPunctuation() {
        #expect(TeluguDictationText.render("రేపు meeting, API ఫైల్! foo_bar") == "repu meeting, API file! foo_bar")
        #expect(TeluguRomanizer.romanise("cafe\u{301} తెలుగు") == "cafe\u{301} telugu")
        #expect(TeluguDictationText.render("మీటింగ్ మీటింగ్లు") == "meeting meetinglu")
    }
    @Test func userRulesWinWithoutRecursiveOrSubstringExpansion() {
        let rules:[DictationPhraseReplacement] = [.init(phrase:"మీటింగ్",replacement:"sync"),.init(phrase:"meeting",replacement:"standup"),.init(phrase:"sync",replacement:"wrong"),.init(phrase:"repu",replacement:"repu")]
        #expect(TeluguDictationText.render("మీటింగ్ meeting రేపు",overrides:rules) == "sync standup repu")
        #expect(TeluguDictationText.render("APIFile mymeeting",overrides:rules) == "APIFile mymeeting")
        #expect(TeluguDictationText.render("రేపు మీటింగ్",overrides:[.init(phrase:"రేపు మీటింగ్",replacement:"tomorrow sync")]) == "tomorrow sync")
        #expect(TeluguDictationText.render("మీటింగ్",overrides:[.init(phrase:"meeting",replacement:"custom")]) == "custom")
    }
    @Test func explicitModesNeverForceTeluguByDefault() {
        #expect(TeluguRecognitionLanguage.automatic.whisperLanguage == "auto")
        #expect(TeluguRecognitionLanguage.teluguOnly.whisperLanguage == "te")
    }
}
