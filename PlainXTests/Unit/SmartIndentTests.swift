//
//  SmartIndentTests.swift
//  PlainXTests
//
//  Basic lexer-aware auto-indent: Return after an opening bracket indents one
//  level, except when the bracket is inside a comment or string.
//

import XCTest
@testable import PlainX

final class SmartIndentTests: XCTestCase {

    /// The coordinator must outlive the window (windows hold it unowned; the
    /// app delegate owns it for the app's lifetime), so it is returned too.
    private func makeTab(languageID: String) -> (AppCoordinator, MainWindowController, DocumentTabController) {
        let coordinator = AppCoordinator()
        let window = coordinator.newWindow()
        let document = PlainXDocument(url: nil)
        document.languageOverrideID = languageID
        window.addTab(for: document, select: true)
        guard let tab = window.activeTab as? DocumentTabController else {
            fatalError("expected an editor tab")
        }
        return (coordinator, window, tab)
    }

    func testIndentAfterOpeningBrace() {
        let (coordinator, window, tab) = makeTab(languageID: "swift")
        let pane = tab.activePane
        pane.facade.text = "func f() {\n"
        pane.facade.gotoPosition(pane.facade.length)
        tab.applySmartIndent(to: pane)
        let indentation = pane.facade.send(SCI_GETLINEINDENTATION, w: 1)
        XCTAssertEqual(indentation, Preferences.shared.tabWidth)
        _ = coordinator
        window.forceCloseWindow()
    }

    func testIndentAfterParenAndBracket() {
        for opener in ["call(", "list["] {
            let (coordinator, window, tab) = makeTab(languageID: "swift")
            let pane = tab.activePane
            pane.facade.text = opener + "\n"
            pane.facade.gotoPosition(pane.facade.length)
            tab.applySmartIndent(to: pane)
            XCTAssertEqual(pane.facade.send(SCI_GETLINEINDENTATION, w: 1), Preferences.shared.tabWidth,
                           "expected indent after \(opener)")
            _ = coordinator
        window.forceCloseWindow()
        }
    }

    func testNoIndentAfterOrdinaryLine() {
        let (coordinator, window, tab) = makeTab(languageID: "swift")
        let pane = tab.activePane
        pane.facade.text = "let value = 42\n"
        pane.facade.gotoPosition(pane.facade.length)
        tab.applySmartIndent(to: pane)
        XCTAssertEqual(pane.facade.send(SCI_GETLINEINDENTATION, w: 1), 0)
        _ = coordinator
        window.forceCloseWindow()
    }

    func testNoIndentWhenOpenerIsInsideComment() {
        let (coordinator, window, tab) = makeTab(languageID: "swift")
        let pane = tab.activePane
        pane.facade.text = "// {\n"
        pane.setLanguage(LanguageRegistry.language(withID: "swift"))
        pane.facade.gotoPosition(pane.facade.length)
        tab.applySmartIndent(to: pane)
        XCTAssertEqual(pane.facade.send(SCI_GETLINEINDENTATION, w: 1), 0,
                       "an opening brace inside a comment must not trigger indentation")
        _ = coordinator
        window.forceCloseWindow()
    }

    func testNoIndentWhenOpenerIsInsideString() {
        let (coordinator, window, tab) = makeTab(languageID: "swift")
        let pane = tab.activePane
        pane.facade.text = "let s = \"{\"\n"
        pane.setLanguage(LanguageRegistry.language(withID: "swift"))
        pane.facade.gotoPosition(pane.facade.length)
        tab.applySmartIndent(to: pane)
        XCTAssertEqual(pane.facade.send(SCI_GETLINEINDENTATION, w: 1), 0,
                       "an opening brace inside a string must not trigger indentation")
        _ = coordinator
        window.forceCloseWindow()
    }
}

final class WordCompletionTriggerTests: XCTestCase {

    private func makePane(text: String) -> (AppCoordinator, MainWindowController, EditorPaneController) {
        let coordinator = AppCoordinator()
        let window = coordinator.newWindow()
        let document = PlainXDocument(url: nil)
        window.addTab(for: document, select: true)
        guard let tab = window.activeTab as? DocumentTabController else {
            fatalError("expected editor tab")
        }
        let pane = tab.activePane
        pane.facade.text = text
        return (coordinator, window, pane)
    }

    func testPrefixExtraction() {
        let (coordinator, window, pane) = makePane(text: "alpha beta\nconfig")
        pane.facade.gotoPosition(pane.facade.length)
        XCTAssertEqual(pane.currentWordPrefix(), "config")
        pane.facade.insert(text: " ", at: pane.facade.length)
        pane.facade.gotoPosition(pane.facade.length)
        XCTAssertEqual(pane.currentWordPrefix(), "")
        _ = coordinator
        window.forceCloseWindow()
    }

    func testWordCollectionFindsIdentifiers() {
        let (coordinator, window, pane) = makePane(
            text: "configuration configurate config con x yy\n")
        let words = EditorPaneController.collectWords(from: pane.facade, limit: 100)
        XCTAssertTrue(words.contains("configuration"))
        XCTAssertTrue(words.contains("configurate"))
        XCTAssertTrue(words.contains("config"))
        XCTAssertTrue(words.contains("con"), "3-character words qualify")
        XCTAssertFalse(words.contains("x"), "single-character words are ignored")
        XCTAssertFalse(words.contains("yy"), "2-character words are ignored")
        _ = coordinator
        window.forceCloseWindow()
    }

    func testTypingDoesNotCrashAndKeepsPopupContract() {
        // In a headless test host the popup itself may not become visible, but
        // the trigger path must run safely and the cancel call must be valid.
        let (coordinator, window, pane) = makePane(text: "configuration configurate config\ncon")
        pane.facade.gotoPosition(pane.facade.length)
        pane.scintillaDidTypeCharacter(pane.facade, byte: UInt8(ascii: "f"))
        pane.facade.cancelAutoCompletion()
        XCTAssertFalse(pane.facade.isAutoCompletionActive)
        _ = coordinator
        window.forceCloseWindow()
    }
}
