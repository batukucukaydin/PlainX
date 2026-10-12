//
//  ScintillaSmokeTests.swift
//  PlainXTests
//
//  Milestone 0/1 smoke coverage: the vendored Scintilla builds, the bridge
//  installs lexers, and the facade's typed API round-trips text and
//  selections.
//

import XCTest
@testable import PlainX

final class ScintillaSmokeTests: XCTestCase {

    private func makePane() -> EditorPaneController {
        let pane = EditorPaneController(theme: .systemLight)
        _ = pane.view
        return pane
    }

    func testSetAndReadText() {
        let pane = makePane()
        pane.facade.text = "hello\nworld\n"
        XCTAssertEqual(pane.facade.text, "hello\nworld\n")
        XCTAssertEqual(pane.facade.lineCount, 3)
    }

    func testSelectionAndPositions() {
        let pane = makePane()
        pane.facade.text = "alpha\nbeta\ngamma"
        pane.facade.setSelection(anchor: 6, caret: 10)
        XCTAssertEqual(pane.facade.selectedText(), "beta")
        XCTAssertEqual(pane.facade.line(from: 6), 1)
        XCTAssertEqual(pane.facade.column(of: 6), 0)
        XCTAssertEqual(pane.facade.lineText(2), "gamma")
    }

    func testInsertAndDelete() {
        let pane = makePane()
        pane.facade.text = "one two three"
        pane.facade.insert(text: "X", at: 4)
        XCTAssertEqual(pane.facade.text, "one Xtwo three")
        pane.facade.deleteRange(location: 4, length: 1)
        XCTAssertEqual(pane.facade.text, "one two three")
    }

    func testDirtyTrackingViaSavePoint() {
        let pane = makePane()
        pane.facade.text = "content"
        pane.facade.setSavePoint()
        XCTAssertFalse(pane.facade.isModified)
        pane.facade.insert(text: "!", at: 7)
        XCTAssertTrue(pane.facade.isModified)
    }

    func testSwiftLexerInstalls() {
        let pane = makePane()
        pane.facade.text = "// comment\nlet value = 42\nfunc greet() {}\n\"string\"\n"
        pane.setLanguage(LanguageRegistry.language(withID: "swift"))
        // Verify lexer produced a keyword style at "let".
        let position = (pane.facade.text as NSString).range(of: "let").location
        let style = pane.facade.send(SCI_GETSTYLEAT, w: position)
        XCTAssertEqual(style, 6, "expected PXSwiftStyleKeyword for 'let'")
    }

    func testSwiftLexerBlockCommentIsNested() {
        let pane = makePane()
        pane.facade.text = "/* outer /* inner */ still comment */ let x = 1\n"
        pane.setLanguage(LanguageRegistry.language(withID: "swift"))
        let stillComment = (pane.facade.text as NSString).range(of: "still").location
        let style = pane.facade.send(SCI_GETSTYLEAT, w: stillComment)
        XCTAssertEqual(style, 3, "nested block comment should remain comment style")
        let keywordPosition = (pane.facade.text as NSString).range(of: "let").location
        let keywordStyle = pane.facade.send(SCI_GETSTYLEAT, w: keywordPosition)
        XCTAssertEqual(keywordStyle, 6, "'let' after comment should be a keyword again")
    }

    func testBridgeCreatesCuratedLexers() {
        for name in ["swift", "cpp", "python", "bash", "json", "yaml", "toml", "sql",
                     "markdown", "hypertext", "xml", "css", "powershell", "rust", "ruby",
                     "perl", "makefile", "props", "batch", "diff", "asm", "vb", "php"] {
            XCTAssertNotNil(PXSciBridge.createLexerNamed(name), "lexer missing: \(name)")
        }
        XCTAssertNil(PXSciBridge.createLexerNamed("does-not-exist"))
    }

    func testSearchInTargetLiteral() {
        let pane = makePane()
        pane.facade.text = "cat dog cat dog"
        pane.facade.setSearchFlags(caseSensitive: false, wholeWord: false, regex: false)
        let first = pane.facade.searchInTarget("dog", from: 0, to: pane.facade.length)
        XCTAssertEqual(first?.location, 4)
        let second = pane.facade.searchInTarget("dog", from: 5, to: pane.facade.length)
        XCTAssertEqual(second?.location, 12)
    }

    func testSearchInTargetRegex() {
        let pane = makePane()
        pane.facade.text = "a1 b22 c333"
        pane.facade.setSearchFlags(caseSensitive: false, wholeWord: false, regex: true)
        let found = pane.facade.searchInTarget("[a-z][0-9]+", from: 0, to: pane.facade.length)
        XCTAssertEqual(found?.location, 0)
        XCTAssertEqual(found?.length, 2)
    }

    func testBookmarkMarkers() {
        let pane = makePane()
        pane.facade.text = "a\nb\nc\nd"
        XCTAssertFalse(pane.facade.hasMarker(Int(ScintillaFacade.PXMarker.bookmark), line: 1))
        pane.facade.addMarker(Int(ScintillaFacade.PXMarker.bookmark), line: 1)
        XCTAssertTrue(pane.facade.hasMarker(Int(ScintillaFacade.PXMarker.bookmark), line: 1))
        XCTAssertEqual(pane.facade.nextMarkerLine(Int(ScintillaFacade.PXMarker.bookmark), from: 0), 1)
        pane.facade.removeMarker(Int(ScintillaFacade.PXMarker.bookmark), line: 1)
        XCTAssertFalse(pane.facade.hasMarker(Int(ScintillaFacade.PXMarker.bookmark), line: 1))
    }

    func testMultiSelectionSupport() {
        let pane = makePane()
        pane.facade.text = "foo bar foo baz foo"
        pane.facade.setSelection(anchor: 0, caret: 3)
        pane.facade.selectAllOccurrences()
        XCTAssertEqual(pane.facade.selectionCount, 3)
    }

    func testUndoRedo() {
        let pane = makePane()
        pane.facade.text = "start"
        pane.facade.beginUndoAction()
        pane.facade.insert(text: " end", at: 5)
        pane.facade.endUndoAction()
        XCTAssertTrue(pane.facade.canUndo)
        pane.facade.undo()
        XCTAssertEqual(pane.facade.text, "start")
        pane.facade.redo()
        XCTAssertEqual(pane.facade.text, "start end")
    }

    func testThemeApplicationDoesNotCrash() {
        let pane = makePane()
        pane.facade.text = "let x = 1"
        pane.setLanguage(LanguageRegistry.language(withID: "swift"))
        pane.applyTheme(.systemDark)
        pane.applyTheme(.systemLight)
    }
}
