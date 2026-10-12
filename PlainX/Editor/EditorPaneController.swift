//
//  EditorPaneController.swift
//  PlainX Editor
//
//  One editable Scintilla pane bound to a document. A document can be shown
//  in more than one pane (split view / cloned view); text synchronisation
//  between panes is coordinated by DocumentTabController.
//

import AppKit

protocol EditorPaneControllerDelegate: AnyObject {
    func editorPaneDidChangeDirtyState(_ pane: EditorPaneController)
    func editorPaneDidUpdateUI(_ pane: EditorPaneController)
    func editorPane(_ pane: EditorPaneController, didApply modification: ScintillaModification)
    func editorPaneDidTypeCharacter(_ pane: EditorPaneController, byte: UInt8)
    func editorPane(_ pane: EditorPaneController, didClickMargin margin: Int, line: Int)
    func editorPane(_ pane: EditorPaneController, didToggleBookmarkOn line: Int)
}

extension EditorPaneControllerDelegate {
    func editorPaneDidChangeDirtyState(_ pane: EditorPaneController) {}
    func editorPaneDidUpdateUI(_ pane: EditorPaneController) {}
    func editorPane(_ pane: EditorPaneController, didApply modification: ScintillaModification) {}
    func editorPaneDidTypeCharacter(_ pane: EditorPaneController, byte: UInt8) {}
    func editorPane(_ pane: EditorPaneController, didClickMargin margin: Int, line: Int) {}
    func editorPane(_ pane: EditorPaneController, didToggleBookmarkOn line: Int) {}
}

final class EditorPaneController: NSViewController, ScintillaFacadeDelegate {
    let paneID = UUID()
    let facade: ScintillaFacade
    weak var delegate: EditorPaneControllerDelegate?
    private(set) weak var document: PlainXDocument?

    private var currentTheme: EditorTheme
    private var currentLanguage: LanguageDefinition = LanguageRegistry.plainText
    private var preferences: Preferences { .shared }

    init(theme: EditorTheme) {
        self.currentTheme = theme
        let scintilla = ScintillaView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.facade = ScintillaFacade(view: scintilla)
        super.init(nibName: nil, bundle: nil)
        facade.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let scintilla = facade.view
        scintilla.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scintilla)
        NSLayoutConstraint.activate([
            scintilla.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scintilla.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scintilla.topAnchor.constraint(equalTo: container.topAnchor),
            scintilla.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        configureBaseEditor()
    }

    private func configureBaseEditor() {
        facade.setCodePageUTF8()
        facade.configureLineNumberMargin(width: 44)
        facade.configureBookmarkMargin()
        facade.configureFoldMargin()
        facade.defineStandardMarkers()
        facade.configureMultipleSelection()
        facade.eolMode = preferences.defaultEOL.concreteFallback
        facade.setTabWidth(preferences.tabWidth)
        facade.setUseTabs(preferences.useTabs)
        facade.setMarginWidth(0, width: preferences.showLineNumbers ? 44 : 0)
        facade.setWhitespaceVisible(preferences.showWhitespace)
        facade.setEOLVisible(preferences.showEOL)
        facade.setIndentationGuides(preferences.showIndentGuides)
        facade.send(SCI_SETCARETLINEVISIBLE, w: preferences.highlightCurrentLine ? 1 : 0)
        facade.send(SCI_SETCARETSTYLE, w: Int(CARETSTYLE_LINE))
        facade.view.scrollView?.hasVerticalScroller = true
        facade.view.scrollView?.hasHorizontalScroller = true
        applyTheme(currentTheme)
    }

    // MARK: - Binding

    func bind(document: PlainXDocument, text: String, preserveViewState: Bool) {
        self.document = document
        currentLanguage = document.language
        if let wrapOverride = document.wordWrapOverride {
            facade.setWrapMode(wrapOverride)
        } else {
            facade.setWrapMode(preferences.wordWrapDefault)
        }
        facade.text = text
        facade.setLanguage(currentLanguage)
        facade.eolMode = document.eolMode.concreteFallback
        facade.emptyUndoBuffer()
        facade.setSavePoint()
        restoreBookmarks(from: document)
        if preserveViewState, let state = document.viewStates[paneID] {
            applyViewState(state)
        } else {
            facade.gotoPosition(0)
        }
        refreshAppearanceForDocument()
    }

    private func refreshAppearanceForDocument() {
        applyTheme(currentTheme)
        facade.setMarginWidth(0, width: preferences.showLineNumbers ? lineNumberMarginWidth() : 0)
    }

    private func lineNumberMarginWidth() -> Int {
        let digits = max(3, String(max(1, facade.lineCount)).count) + 1
        var sample = ""
        for _ in 0..<digits { sample.append("9") }
        let width = facade.send(SCI_TEXTWIDTH, w: Int(STYLE_LINENUMBER), string: sample) + 16
        return max(40, width)
    }

    // MARK: - Language / theme

    func setLanguage(_ language: LanguageDefinition) {
        currentLanguage = language
        facade.setLanguage(language)
        applyTheme(currentTheme)
    }

    func applyTheme(_ theme: EditorTheme) {
        currentTheme = theme
        facade.applyTheme(theme, fontName: preferences.fontName, fontSize: preferences.fontSize,
                          language: currentLanguage)
        facade.setMarginWidth(0, width: preferences.showLineNumbers ? lineNumberMarginWidth() : 0)
        view.appearance = theme.isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        facade.view.scrollView?.backgroundColor = theme.background
        facade.view.scrollView?.drawsBackground = true
    }

    func applyEditorPreferences() {
        facade.setTabWidth(preferences.tabWidth)
        facade.setUseTabs(preferences.useTabs)
        facade.setWhitespaceVisible(preferences.showWhitespace)
        facade.setEOLVisible(preferences.showEOL)
        facade.setIndentationGuides(preferences.showIndentGuides)
        facade.send(SCI_SETCARETLINEVISIBLE, w: preferences.highlightCurrentLine ? 1 : 0)
        facade.setMarginWidth(0, width: preferences.showLineNumbers ? lineNumberMarginWidth() : 0)
        if document?.wordWrapOverride == nil {
            facade.setWrapMode(preferences.wordWrapDefault)
        }
        applyTheme(currentTheme)
    }

    // MARK: - View state

    func captureViewState() -> EditorViewState {
        let selections = facade.allSelections().map {
            EditorViewState.CodableSelection(anchor: $0.anchor, caret: $0.caret)
        }
        return EditorViewState(
            caretPosition: facade.currentPosition,
            anchorPosition: facade.anchorPosition,
            firstVisibleLine: facade.firstVisibleLine,
            xOffset: facade.xOffset,
            selections: selections
        )
    }

    func applyViewState(_ state: EditorViewState) {
        if !state.selections.isEmpty {
            let selections = state.selections.map { EditorSelection(anchor: $0.anchor, caret: $0.caret) }
            facade.setSelections(selections)
        } else {
            facade.setSelection(anchor: state.anchorPosition, caret: state.caretPosition)
        }
        facade.setScrollState(firstVisibleLine: state.firstVisibleLine, xOffset: state.xOffset)
    }

    var text: String {
        get { facade.text }
        set { facade.text = newValue }
    }

    var isDirty: Bool { facade.isModified }

    func markClean() {
        facade.setSavePoint()
    }

    // MARK: - Bookmarks

    func restoreBookmarks(from document: PlainXDocument) {
        facade.clearMarkers(Int(ScintillaFacade.PXMarker.bookmark))
        for line in document.bookmarks where line >= 0 && line < facade.lineCount {
            facade.addMarker(Int(ScintillaFacade.PXMarker.bookmark), line: line)
        }
    }

    func toggleBookmark(at line: Int) {
        let marker = Int(ScintillaFacade.PXMarker.bookmark)
        if facade.hasMarker(marker, line: line) {
            facade.removeMarker(marker, line: line)
            document?.bookmarks.remove(line)
        } else {
            facade.addMarker(marker, line: line)
            document?.bookmarks.insert(line)
        }
        delegate?.editorPane(self, didToggleBookmarkOn: line)
    }

    func clearBookmarks() {
        facade.clearMarkers(Int(ScintillaFacade.PXMarker.bookmark))
        document?.bookmarks.removeAll()
    }

    func nextBookmark(from line: Int) -> Int? {
        facade.nextMarkerLine(Int(ScintillaFacade.PXMarker.bookmark), from: line)
    }

    func previousBookmark(from line: Int) -> Int? {
        facade.previousMarkerLine(Int(ScintillaFacade.PXMarker.bookmark), from: line)
    }

    var currentLine: Int { facade.line(from: facade.currentPosition) }

    // MARK: - ScintillaFacadeDelegate

    func scintillaDidUpdateUI(_ facade: ScintillaFacade) {
        delegate?.editorPaneDidUpdateUI(self)
    }

    func scintillaDidChangeContent(_ facade: ScintillaFacade, modification: ScintillaModification) {
        delegate?.editorPane(self, didApply: modification)
    }

    func scintillaDidChangeDirtyState(_ facade: ScintillaFacade, isDirty: Bool) {
        delegate?.editorPaneDidChangeDirtyState(self)
    }

    func scintillaDidTypeCharacter(_ facade: ScintillaFacade, byte: UInt8) {
        delegate?.editorPaneDidTypeCharacter(self, byte: byte)
    }

    func scintillaMarginClicked(_ facade: ScintillaFacade, margin: Int, modifiers: NSEvent.ModifierFlags, position: Int) {
        let line = facade.line(from: position)
        if margin == 1 {
            toggleBookmark(at: line)
        }
        delegate?.editorPane(self, didClickMargin: margin, line: line)
    }
}
