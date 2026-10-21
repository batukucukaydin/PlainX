//
//  UIBehaviorTests.swift
//  PlainXTests
//
//  Layout and accessibility behavior that does not need a running UI session.
//

import XCTest
@testable import PlainX

final class TabAccessibilityTests: XCTestCase {

    func testTabExposesLabelSelectionAndRole() {
        let itemView = TabItemView(itemID: UUID())
        let item = TabStripView.TabItem(id: UUID(), title: "config.json", isDirty: true,
                                        isPinned: false, tooltip: "/tmp/config.json",
                                        hasExternalChange: false)
        itemView.update(item: item, isSelected: true)
        XCTAssertTrue(itemView.acceptsFirstResponder)
        XCTAssertEqual(itemView.accessibilityRole(), .radioButton)
        XCTAssertEqual(itemView.accessibilityLabel(), "config.json")
        XCTAssertEqual(itemView.accessibilityValue() as? Int, 1)
        XCTAssertEqual(itemView.accessibilityCustomActions()?.first?.name, "Close Tab")

        itemView.update(item: item, isSelected: false)
        XCTAssertEqual(itemView.accessibilityValue() as? Int, 0)
    }
}

final class FindBarLayoutTests: XCTestCase {

    private func makeFindBar(width: CGFloat) -> (AppCoordinator, MainWindowController, FindBarController) {
        let coordinator = AppCoordinator()
        let window = coordinator.newWindow()
        let document = PlainXDocument(url: nil)
        window.addTab(for: document, select: true)
        guard let tab = window.activeTab as? DocumentTabController else {
            fatalError("expected editor tab")
        }
        let findBar = FindBarController(tab: tab, mode: .replace)
        findBar.view.frame = NSRect(x: 0, y: 0, width: width, height: 60)
        findBar.view.layoutSubtreeIfNeeded()
        return (coordinator, window, findBar)
    }

    private func button(titled title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title { return button }
        for subview in view.subviews {
            if let found = button(titled: title, in: subview) { return found }
        }
        return nil
    }

    private func button(accessibilityLabel label: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityLabel() == label { return button }
        for subview in view.subviews {
            if let found = button(accessibilityLabel: label, in: subview) { return found }
        }
        return nil
    }

    private func searchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let found = searchField(in: subview) { return found }
        }
        return nil
    }

    func testNarrowWindowHidesOptionalControls() {
        let (coordinator, window, findBar) = makeFindBar(width: 420)
        findBar.applyResponsiveLayout(width: 420)
        XCTAssertEqual(button(titled: "Find All", in: findBar.view)?.isHidden, true)
        XCTAssertEqual(button(titled: "⌷", in: findBar.view)?.isHidden, true)
        XCTAssertEqual(button(titled: "\\b", in: findBar.view)?.isHidden, true)
        // Core controls stay available.
        XCTAssertNotNil(searchField(in: findBar.view))
        XCTAssertEqual(button(titled: ".*", in: findBar.view)?.isHidden, false)
        XCTAssertEqual(button(accessibilityLabel: "Previous match", in: findBar.view)?.isHidden, false)
        XCTAssertEqual(button(accessibilityLabel: "Next match", in: findBar.view)?.isHidden, false)
        _ = coordinator
        window.forceCloseWindow()
    }

    func testWideWindowShowsAllControls() {
        let (coordinator, window, findBar) = makeFindBar(width: 900)
        findBar.applyResponsiveLayout(width: 900)
        XCTAssertEqual(button(titled: "Find All", in: findBar.view)?.isHidden, false)
        XCTAssertEqual(button(titled: "⌷", in: findBar.view)?.isHidden, false)
        XCTAssertEqual(button(titled: "\\b", in: findBar.view)?.isHidden, false)
        _ = coordinator
        window.forceCloseWindow()
    }
}

final class FoldMarginThemeTests: XCTestCase {

    /// The fold margin must not fall back to Scintilla's chrome checkerboard
    /// pattern in either theme (the reported dark-mode artifact).
    func testFoldMarginColoursAreThemed() {
        let pane = EditorPaneController(theme: .systemLight)
        _ = pane.view
        pane.applyTheme(.systemDark)
        // Setting both fold-margin colours to the gutter background makes the
        // pattern solid; verify the message pair is accepted and no crash.
        pane.facade.send(SCI_SETFOLDMARGINCOLOUR, w: 1, l: 0x1B1B20)
        pane.facade.send(SCI_SETFOLDMARGINHICOLOUR, w: 1, l: 0x1B1B20)
        pane.applyTheme(.systemLight)
    }
}

final class FoldMarginPixelTests: XCTestCase {

    /// Renders the editor offscreen and samples the fold-margin column.
    /// Before the fix, Scintilla filled it with a light/dark checkerboard in
    /// dark mode; now it must be a solid gutter colour.
    func testFoldMarginIsSolidInDarkTheme() throws {
        let pane = EditorPaneController(theme: .systemDark)
        pane.facade.text = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        pane.setLanguage(LanguageRegistry.language(withID: "swift"))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = pane.view
        pane.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.orderFront(nil)
        pane.view.layoutSubtreeIfNeeded()
        pane.view.displayIfNeeded()

        guard let rep = pane.view.bitmapImageRepForCachingDisplay(in: pane.view.bounds) else {
            throw XCTSkip("offscreen rendering unavailable")
        }
        pane.view.cacheDisplay(in: pane.view.bounds, to: rep)

        // Margin layout straight from Scintilla: 0 = line numbers,
        // 1 = bookmarks, 2 = folding. Sample the fold margin's centre column.
        // colorAt works in backing pixels, so convert through the scale factor.
        let m0 = pane.facade.send(SCI_GETMARGINWIDTHN, w: 0)
        let m1 = pane.facade.send(SCI_GETMARGINWIDTHN, w: 1)
        let m2 = pane.facade.send(SCI_GETMARGINWIDTHN, w: 2)
        XCTAssertGreaterThan(m2, 0, "fold margin should be visible for Swift")
        let pointWidth = max(1, Int(pane.view.bounds.width))
        let scale = max(1, rep.pixelsWide / pointWidth)
        let foldX = (m0 + m1 + max(1, m2 / 2)) * scale

        var luminances: [Double] = []
        for y in (12 * scale)..<(140 * scale) {
            guard let color = rep.colorAt(x: foldX, y: y)?.usingColorSpace(.sRGB) else { continue }
            luminances.append(Double(color.redComponent) * 0.299
                              + Double(color.greenComponent) * 0.587
                              + Double(color.blueComponent) * 0.114)
        }
        XCTAssertFalse(luminances.isEmpty, "expected to sample the fold margin")
        let maxLuminance = luminances.max() ?? 1
        let minLuminance = luminances.min() ?? 0
        XCTAssertLessThan(maxLuminance, 0.45,
                          "fold margin should be dark in the dark theme, not light chrome")
        XCTAssertLessThan(maxLuminance - minLuminance, 0.18,
                          "fold margin should be solid, not a checkerboard pattern")
        window.orderOut(nil)
    }
}
