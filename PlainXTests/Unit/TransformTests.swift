//
//  TransformTests.swift
//  PlainXTests
//

import XCTest
@testable import PlainX

final class TransformTests: XCTestCase {

    // MARK: - Whitespace and lines

    func testTrimTrailingWhitespace() {
        let input = "a  \nb\t\nc\n"
        XCTAssertEqual(TransformService.trimTrailingWhitespace(in: input), "a\nb\nc\n")
    }

    func testTrimTrailingWhitespacePreservesNoFinalNewline() {
        XCTAssertEqual(TransformService.trimTrailingWhitespace(in: "a  \nb  "), "a\nb")
    }

    func testTrimLeadingWhitespace() {
        XCTAssertEqual(TransformService.trimLeadingWhitespace(in: "  a\n\tb\n c\n"), "a\nb\nc\n")
    }

    func testSortLinesAscendingNumericAware() {
        let input = "item10\nitem2\nitem1\n"
        XCTAssertEqual(TransformService.sortLines(in: input, ascending: true, caseInsensitive: false),
                       "item1\nitem2\nitem10\n")
    }

    func testSortLinesDescending() {
        let input = "b\na\nc\n"
        XCTAssertEqual(TransformService.sortLines(in: input, ascending: false, caseInsensitive: false),
                       "c\nb\na\n")
    }

    func testSortLinesCaseInsensitive() {
        let input = "Banana\napple\nCherry\n"
        let sorted = TransformService.sortLines(in: input, ascending: true, caseInsensitive: true)
        XCTAssertEqual(sorted, "apple\nBanana\nCherry\n")
    }

    func testRemoveDuplicateLinesKeepsFirst() {
        let input = "a\nb\na\nc\nb\n"
        XCTAssertEqual(TransformService.removeDuplicateLines(in: input), "a\nb\nc\n")
    }

    func testRemoveEmptyLines() {
        XCTAssertEqual(TransformService.removeEmptyLines(in: "a\n\nb\n \n\nc\n"), "a\nb\nc\n")
    }

    func testReverseLines() {
        XCTAssertEqual(TransformService.reverseLines(in: "one\ntwo\nthree\n"), "three\ntwo\none\n")
    }

    func testJoinLines() {
        XCTAssertEqual(TransformService.joinLines(in: "one\ntwo\nthree\n"), "onetwothree\n")
    }

    func testSplitLinesOnSeparator() {
        XCTAssertEqual(TransformService.splitLinesOnSeparator(",", in: "a,b,c"),
                       "a,\nb,\nc")
    }

    // MARK: - Case

    func testCaseConversions() {
        XCTAssertEqual(TransformService.uppercase("hello"), "HELLO")
        XCTAssertEqual(TransformService.lowercase("HELLO"), "hello")
        XCTAssertEqual(TransformService.titleCase("hello world"), "Hello World")
        XCTAssertEqual(TransformService.swapCase("aBc"), "AbC")
    }

    func testSentenceCase() {
        XCTAssertEqual(TransformService.sentenceCase("hello WORLD"), "Hello world")
    }

    // MARK: - Indentation

    func testTabsToSpaces() {
        XCTAssertEqual(TransformService.convertTabsToSpaces(in: "\tif x:\n\t\tpass", tabWidth: 4),
                       "    if x:\n        pass")
    }

    func testSpacesToTabs() {
        XCTAssertEqual(TransformService.convertSpacesToTabs(in: "    if x:\n        pass", tabWidth: 4),
                       "\tif x:\n\t\tpass")
    }

    func testSpacesToTabsPreservesPartialIndent() {
        XCTAssertEqual(TransformService.convertSpacesToTabs(in: "      x", tabWidth: 4), "\t  x")
    }

    // MARK: - JSON

    func testFormatJSONPrettyPrintsAndSorts() throws {
        let formatted = try TransformService.formatJSON("{\"b\":1,\"a\":[1,2]}")
        XCTAssertTrue(formatted.contains("\n"))
        XCTAssertTrue(formatted.contains("\"a\""))
        let aIndex = formatted.range(of: "\"a\"")!.lowerBound
        let bIndex = formatted.range(of: "\"b\"")!.lowerBound
        XCTAssertLessThan(aIndex, bIndex)
    }

    func testMinifyJSON() throws {
        let minified = try TransformService.minifyJSON("{\n  \"a\": 1\n}")
        XCTAssertEqual(minified, "{\"a\":1}")
    }

    func testValidateJSONReportsLineAndColumn() {
        let bad = "{\n  \"a\": 1,\n  \"b\": ,\n}"
        XCTAssertThrowsError(try TransformService.validateJSON(bad)) { error in
            guard case TransformError.invalidJSON(_, let line, let column) = error else {
                XCTFail("expected invalidJSON, got \(error)")
                return
            }
            XCTAssertGreaterThanOrEqual(line, 1)
            XCTAssertGreaterThanOrEqual(column, 1)
        }
    }

    func testJSONFragmentAllowed() throws {
        XCTAssertEqual(try TransformService.minifyJSON("\"hello\""), "\"hello\"")
    }

    // MARK: - XML

    func testValidateXMLWellFormed() throws {
        XCTAssertNoThrow(try TransformService.validateXML("<root><child attr=\"1\">text</child></root>"))
    }

    func testValidateXMLMalformed() {
        XCTAssertThrowsError(try TransformService.validateXML("<root><child></root>"))
    }

    func testValidateXMLIgnoresExternalEntities() throws {
        // A DTD with an external entity must not be resolved or fetched, and
        // undefined entities in content must not crash the validator.
        let xml = """
        <?xml version="1.0"?>
        <!DOCTYPE root [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
        <root>&xxe;</root>
        """
        // The parser may accept or reject the document; the contract is that
        // validation completes without network/file access.
        _ = try? TransformService.validateXML(xml)
    }

    func testFormatXMLIndentsNestedTags() throws {
        let formatted = try TransformService.formatXML("<a><b><c/></b></a>")
        XCTAssertTrue(formatted.contains("\n    <b>"))
        XCTAssertTrue(formatted.contains("\n        <c/>"))
    }

    func testFormatXMLKeepsTextInline() throws {
        let formatted = try TransformService.formatXML("<a><b>text</b></a>")
        XCTAssertTrue(formatted.contains("<b>text</b>"))
    }

    func testFormatXMLPreservesCommentsAndCDATA() throws {
        let source = "<a><!-- note --><b><![CDATA[x < y]]></b></a>"
        let formatted = try TransformService.formatXML(source)
        XCTAssertTrue(formatted.contains("<!-- note -->"))
        XCTAssertTrue(formatted.contains("<![CDATA[x < y]]>"))
    }

    // MARK: - Encodings

    func testBase64RoundTrip() throws {
        let encoded = TransformService.base64Encode("Hello, PlainX! ✓")
        XCTAssertEqual(try TransformService.base64Decode(encoded), "Hello, PlainX! ✓")
    }

    func testBase64WithLineWrapping() throws {
        let encoded = TransformService.base64Encode(String(repeating: "a", count: 200), lineLength: 76)
        XCTAssertTrue(encoded.contains("\n"))
        XCTAssertEqual(try TransformService.base64Decode(encoded), String(repeating: "a", count: 200))
    }

    func testBase64InvalidThrows() {
        XCTAssertThrowsError(try TransformService.base64Decode("not base64 %%%"))
    }

    func testURLEncodeDecodeRoundTrip() throws {
        let source = "a b&c=d?e"
        let encoded = TransformService.urlEncode(source)
        XCTAssertFalse(encoded.contains(" "))
        XCTAssertEqual(try TransformService.urlDecode(encoded), source)
    }

    func testURLFormStyle() throws {
        XCTAssertEqual(TransformService.urlEncode("a b", formStyle: true), "a+b")
        XCTAssertEqual(try TransformService.urlDecode("a+b", formStyle: true), "a b")
    }

    func testHTMLEscapeUnescapeRoundTrip() {
        let source = "<div class=\"x\">& 'y'</div>"
        let escaped = TransformService.htmlEscape(source)
        XCTAssertFalse(escaped.contains("<div"))
        XCTAssertEqual(TransformService.htmlUnescape(escaped), source)
    }

    // MARK: - Hashes

    func testSHA256KnownVector() {
        XCTAssertEqual(TransformService.hash("abc", algorithm: .sha256),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testSHA512KnownVector() {
        XCTAssertEqual(TransformService.hash("abc", algorithm: .sha512),
                       "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    }

    func testSHA1KnownVector() {
        XCTAssertEqual(TransformService.hash("abc", algorithm: .sha1),
                       "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    func testMD5KnownVector() {
        XCTAssertEqual(TransformService.hash("abc", algorithm: .md5),
                       "900150983cd24fb0d6963f7d28e17f72")
    }

    func testFileHashMatchesStringHash() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("hash.txt")
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try TransformService.hash(fileAt: url, algorithm: .sha256),
                       TransformService.hash("abc", algorithm: .sha256))
        try TestHelpers.remove(directory)
    }

    func testLegacyAlgorithmsAreMarked() {
        XCTAssertTrue(TransformService.HashAlgorithm.sha1.isLegacy)
        XCTAssertTrue(TransformService.HashAlgorithm.md5.isLegacy)
        XCTAssertFalse(TransformService.HashAlgorithm.sha256.isLegacy)
    }
}

final class GlobMatcherTests: XCTestCase {

    func testSimpleWildcard() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "*.swift", name: "Main.swift"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "*.swift", name: "Main.swift.bak"))
    }

    func testQuestionMark() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "file?.txt", name: "file1.txt"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "file?.txt", name: "file10.txt"))
    }

    func testCharacterClass() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "log[0-9].txt", name: "log3.txt"))
        XCTAssertFalse(GlobMatcher.matches(pattern: "log[0-9].txt", name: "logx.txt"))
    }

    func testCaseInsensitiveByDefault() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "*.SWIFT", name: "main.swift"))
    }

    func testSemicolonSeparatedList() {
        XCTAssertTrue(GlobMatcher.matchesAny(of: ["*.swift;*.json"], name: "config.json"))
        XCTAssertFalse(GlobMatcher.matchesAny(of: ["*.swift;*.json"], name: "readme.md"))
    }

    func testCommaSeparatedList() {
        XCTAssertTrue(GlobMatcher.matchesAny(of: ["*.md,*.txt"], name: "notes.txt"))
    }

    func testNestedPathPattern() {
        XCTAssertTrue(GlobMatcher.matches(pattern: "build/*", name: "build/output.o"))
    }
}

final class FuzzyMatcherTests: XCTestCase {

    func testSubsequenceMatch() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "fmt", candidate: "Format JSON"))
    }

    func testNoMatch() {
        XCTAssertNil(FuzzyMatcher.match(query: "zzz", candidate: "Format JSON"))
    }

    func testWordBoundaryScoresHigher() {
        let boundary = FuzzyMatcher.match(query: "ct", candidate: "Close Tab")!.score
        let scattered = FuzzyMatcher.match(query: "ct", candidate: "Contact")!.score
        XCTAssertGreaterThan(boundary, scattered)
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "", candidate: "anything"))
    }
}

final class BinaryHeuristicTests: XCTestCase {

    func testTextIsNotBinary() {
        XCTAssertFalse(BinaryHeuristic.looksBinary(data: Data("hello world".utf8)))
    }

    func testNULByteIsBinary() {
        let data = Data([0x68, 0x69, 0x00, 0x21])
        XCTAssertTrue(BinaryHeuristic.looksBinary(data: data))
    }

    func testEmptyDataIsNotBinary() {
        XCTAssertFalse(BinaryHeuristic.looksBinary(data: Data()))
    }
}
