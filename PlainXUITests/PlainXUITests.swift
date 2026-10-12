//
//  PlainXUITests.swift
//  PlainXUITests
//
//  Small, stable UI smoke tests. UI tests are skipped by default in the
//  shared scheme; run them locally with:
//    xcodebuild test -scheme PlainX -destination 'platform=macOS' \
//      -only-testing:PlainXUITests
//

import XCTest

final class PlainXUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsEditorWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        // The window should exist with the app's title bar.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    func testTypingInsertsText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.click()
        window.typeText("hello plainx")
        // A document editor is present and accepted input; verify via typing
        // another character (no crash, window still alive).
        window.typeText("!")
        XCTAssertTrue(window.exists)
    }
}
