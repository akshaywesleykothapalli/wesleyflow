import AppKit
import Domain
import Testing
@testable import SystemOperations

@Suite("Bounded focused text policy") struct FocusedTextResolverTests {
    @Test func selectionPrecedesDraftAndDoesNotRequireUnselectedConsent() {
        let range = NSRange(location:6,length:5)
        #expect(FocusedTextPolicy.select(count:20,selection:range,allowUnselected:false) == range)
        #expect(FocusedTextPolicy.resolve(text:"hello",count:20,selection:range,retrieved:range) == .init(text:"hello",source:.selection))
    }
    @Test func shortDraftRequiresConsent() {
        let caret = NSRange(location:3,length:0)
        #expect(FocusedTextPolicy.select(count:5,selection:caret,allowUnselected:false) == nil)
        let range = FocusedTextPolicy.select(count:5,selection:caret,allowUnselected:true)!
        #expect(range == NSRange(location:0,length:5))
        #expect(FocusedTextPolicy.resolve(text:"hello",count:5,selection:caret,retrieved:range).source == .draft)
    }
    @Test func boundedParagraphHasBothBoundaries() {
        let text = "tail of previous\nCurrent paragraph.\nstart of next"
        let range = NSRange(location:100,length:text.utf16.count)
        let selection = NSRange(location:125,length:0)
        #expect(FocusedTextPolicy.resolve(text:text,count:5000,selection:selection,retrieved:range) == .init(text:"Current paragraph.\n",source:.paragraph))
    }
    @Test func clippedLongParagraphIsNotWholeFileFallback() {
        let text = String(repeating:"x",count:1024)
        #expect(FocusedTextPolicy.resolve(text:text,count:5000,selection:NSRange(location:1500,length:0),retrieved:NSRange(location:1000,length:1024)).text.isEmpty)
        #expect(FocusedTextPolicy.select(count:500_000,selection:NSRange(location:250_000,length:0),allowUnselected:true)?.length == 1024)
    }
    @Test(arguments:[-1,Int.max]) func invalidRangeFailsClosed(_ offset:Int) {
        #expect(FocusedTextPolicy.select(count:10,selection:NSRange(location:offset,length:1),allowUnselected:true) == nil)
    }
    @Test func emptyOversizedAndIncompleteTextAreManual() {
        #expect(FocusedTextPolicy.select(count:0,selection:NSRange(location:0,length:0),allowUnselected:true) == nil)
        #expect(FocusedTextPolicy.select(count:5000,selection:NSRange(location:0,length:2049),allowUnselected:true) == nil)
        #expect(FocusedTextPolicy.resolve(text:"partial",count:30,selection:NSRange(location:0,length:0),retrieved:NSRange(location:0,length:30)).text.isEmpty)
        let text = String(repeating:"字",count:1000)
        #expect(FocusedTextPolicy.resolve(text:text,count:1000,selection:NSRange(location:0,length:0),retrieved:NSRange(location:0,length:1000)).text.isEmpty)
    }
    @Test(arguments:["secure","readonly","disabled","unknown","marked","window"]) func unsafeMetadataRejectsBeforeText(_ kind:String) {
        #expect(!FocusedTextPolicy.eligible(role:kind == "window" ? kAXWindowRole : kAXTextAreaRole,
            subrole:kind == "secure" ? kAXSecureTextFieldSubrole : kind == "unknown" ? nil : "",
            enabled:kind != "disabled",editable:kind != "readonly",writable:true,marked:kind == "marked"))
    }
    @Test func unicodeOffsetsUseUTF16AndCRLFIsNotSplit() {
        let text = "old\r\nHello 👋🏽.\r\nnext"
        let range = NSRange(location:100,length:text.utf16.count)
        #expect(FocusedTextPolicy.resolve(text:text,count:5000,selection:NSRange(location:108,length:0),retrieved:range).text == "Hello 👋🏽.\r\n")
    }
}

extension FocusedTextResolverTests {
    @Test func compatibleCustomTextAreaRequiresEditableMetadata() {
        #expect(FocusedTextPolicy.eligible(role:kAXTextAreaRole,subrole:"",enabled:true,editable:true,writable:false,marked:false))
        #expect(!FocusedTextPolicy.eligible(role:kAXGroupRole,subrole:"",enabled:true,editable:true,writable:true,marked:false))
    }
    @Test(arguments:[AXError.attributeUnsupported,.parameterizedAttributeUnsupported,.notImplemented,.noValue])
    func boundedValueFallbackWhenRangeIsUnsupported(_ error:AXError) {
        #expect(FocusedTextPolicy.permitsValueFallback(rangeStatus:error,selectionLength:0,count:128))
        #expect(!FocusedTextPolicy.permitsValueFallback(rangeStatus:error,selectionLength:2,count:128))
        #expect(!FocusedTextPolicy.permitsValueFallback(rangeStatus:error,selectionLength:0,count:1025))
    }
    @Test(arguments:[AXError.cannotComplete,.invalidUIElement,.failure]) func staleRangeDoesNotBroadenRead(_ error:AXError) {
        #expect(!FocusedTextPolicy.permitsValueFallback(rangeStatus:error,selectionLength:0,count:128))
    }
    @Test func failureMessagesAreSpecificAndNeverMemoryErrors() {
        #expect(FocusedTextStatus.permissionRequired.explanation != FocusedTextStatus.disabled.explanation)
        for status in FocusedTextStatus.allCases { #expect(!status.explanation.lowercased().contains("memory")) }
    }
}

extension FocusedTextResolverTests {
    @Test func actualBoundedReaderUsesValueOnlyForShortUnselectedDraft() {
        var selectedCalls = 0, valueCalls = 0
        let draft = FocusedTextPolicy.readBounded(rangeStatus:.attributeUnsupported,rangeText:nil,selectionLength:0,count:12,selected:{ selectedCalls += 1; return "selection" },value:{ valueCalls += 1; return "bounded draft" })
        #expect(draft.text == "bounded draft" && draft.stage == .valueRead && selectedCalls == 0 && valueCalls == 1)
        let selection = FocusedTextPolicy.readBounded(rangeStatus:.parameterizedAttributeUnsupported,rangeText:nil,selectionLength:3,count:5000,selected:{ selectedCalls += 1; return "yes" },value:{ valueCalls += 1; return "wrong whole file" })
        #expect(selection.text == "yes" && selection.stage == .selectedRead && valueCalls == 1)
        let stale = FocusedTextPolicy.readBounded(rangeStatus:.cannotComplete,rangeText:nil,selectionLength:0,count:12,selected:{ selectedCalls += 1; return "bad" },value:{ valueCalls += 1; return "bad" })
        #expect(stale.text == nil && valueCalls == 1 && selectedCalls == 1)
        let long = FocusedTextPolicy.readBounded(rangeStatus:.attributeUnsupported,rangeText:nil,selectionLength:0,count:5000,selected:{ "bad" },value:{ valueCalls += 1; return "bad" })
        #expect(long.text == nil && valueCalls == 1)
    }
}

@Suite("Verified dictation span") struct DictationSpanVerificationTests {
    @Test(arguments:["Hello."," trailing ","‘curly’ and “quotes”", "first\nsecond", "first\r\nsecond", "🙂 👨‍👩‍👧‍👦", "e\u{301} नमस्ते"])
    func exactPostInsertionSpanPreservesUTF16AndSurroundings(_ text:String) throws {
        let prefix = "🙂 before ", suffix = " after"
        let expected = try DictationInsertionExpectation(original:.init(text:prefix+suffix,selection:.init(location:prefix.utf16.count,length:0)),insertedText:text)
        #expect(expected.matches(prefix+text+suffix))
        #expect(try DictationInsertionExpectation.readSpan(expected.document,range:expected.span).utf16.elementsEqual(text.utf16))
        try DictationInsertionExpectation.validateCaret(.init(location:expected.span.location+expected.span.length,length:0),span:expected.span)
        try DictationInsertionExpectation.validateCaret(expected.span,span:expected.span)
    }
    @Test(arguments:["extra-space","line-ending","punctuation","unicode-normalization","own-text","surrounding-text"])
    func noMeaningfulDifferenceIsNormalizedAway(_ change:String) throws {
        let original = "before e\u{301}\n“ok” after"
        let expectation = try DictationInsertionExpectation(original:.init(text:"before  after",selection:.init(location:7,length:0)),insertedText:"e\u{301}\n“ok”")
        let observed = switch change {
        case "extra-space": "before e\u{301}\n“ok”  after"
        case "line-ending": "before e\u{301}\r\n“ok” after"
        case "punctuation": "before e\u{301}\n\"ok\" after"
        case "unicode-normalization": "before é\n“ok” after"
        case "own-text": "before x\n“ok” after"
        default: "Before e\u{301}\n“ok” after"
        }
        #expect(expectation.matches(original))
        #expect(!expectation.matches(observed))
        if change == "unicode-normalization" { #expect(original == observed); #expect(!DictationInsertionExpectation.exact(original,observed)) }
    }
    @Test func invalidRangeMissingTextAndMovedCaretAreNotTextMismatch() throws {
        let expectation = try DictationInsertionExpectation(original:.init(text:"abc",selection:.init(location:1,length:0)),insertedText:"hello")
        #expect(throws:DictationRewriteValidationFailure.textUnavailable) { try expectation.verified(nil) }
        #expect(throws:DictationRewriteValidationFailure.invalidRange) { try DictationInsertionExpectation.readSpan("🙂",range:.init(location:1,length:1)) }
        #expect(throws:DictationRewriteValidationFailure.invalidRange) { try DictationInsertionExpectation.readSpan("abc",range:.init(location:Int.max,length:1)) }
        #expect(throws:DictationRewriteValidationFailure.caretChanged) { try DictationInsertionExpectation.validateCaret(.init(location:0,length:0),span:expectation.span) }
        #expect(throws:DictationRewriteValidationFailure.invalidRange) { try DictationInsertionExpectation.validateCaret(nil,span:expectation.span) }
        #expect(throws:DictationRewriteValidationFailure.caretChanged) { try DictationInsertionExpectation.validateCaret(.init(location:6,length:0),span:expectation.span,selected:expectation.span) }
    }
    @Test func duplicatesNeverSelectTheFirstMatchingString() throws {
        let e = try DictationInsertionExpectation(original:.init(text:"word before  after",selection:.init(location:12,length:0)),insertedText:"word")
        #expect(e.span.location == 12 && e.matches("word before word after"))
        #expect(!e.matches("word before edit after"))
    }
}

extension DictationSpanVerificationTests {
    @Test func absentNativeAttributesDoNotBecomeTextMismatch() throws {
        #expect(throws:DictationRewriteValidationFailure.unsupportedEditor) { try DictationRewriteCapabilities.validateEditor(subrole:nil,editable:true) }
        #expect(throws:DictationRewriteValidationFailure.unsupportedEditor) { try DictationRewriteCapabilities.validateEditor(subrole:"",editable:false) }
        #expect(throws:DictationRewriteValidationFailure.secureInput) { try DictationRewriteCapabilities.validateEditor(subrole:"AXSecureTextField",editable:true) }
        #expect(throws:DictationRewriteValidationFailure.compositionUnavailable) { try DictationRewriteCapabilities.validateComposition(markedLength:nil) }
        #expect(throws:DictationRewriteValidationFailure.compositionUnavailable) { try DictationRewriteCapabilities.validateComposition(markedLength:-1) }
        #expect(throws:DictationRewriteValidationFailure.secureInput) { try DictationRewriteCapabilities.validateComposition(markedLength:2) }
        try DictationRewriteCapabilities.validateEditor(subrole:"",editable:true)
        try DictationRewriteCapabilities.validateComposition(markedLength:0)
    }
}
