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

    /// Cached document words for autocompletion; rebuilt periodically rather
    /// than on every keystroke.
    private var completionWordCache: [String] = []
    private var modificationsSinceCacheBuild = 0
    private var completionCacheIsStale = true

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

    func scintillaDidChangeDirtyState(_ facade: ScintillaFacade, isDirty: Bool) {
        delegate?.editorPaneDidChangeDirtyState(self)
    }

    func scintillaDidTypeCharacter(_ facade: ScintillaFacade, byte: UInt8) {
        if preferences.autoCompletion {
            maybeShowWordCompletion(typedByte: byte)
        }
        delegate?.editorPaneDidTypeCharacter(self, byte: byte)
    }

    func scintillaDidChangeContent(_ facade: ScintillaFacade, modification: ScintillaModification) {
        if modification.isInsertText || modification.isDeleteText {
            // Saturating counter: never overflow, only marks the cache stale.
            modificationsSinceCacheBuild = min(modificationsSinceCacheBuild + 1, 10_000)
        }
        delegate?.editorPane(self, didApply: modification)
    }

    // MARK: - Word autocompletion

    private func maybeShowWordCompletion(typedByte: UInt8) {
        // Only after identifier characters (ASCII letters, digits, underscore).
        let isIdentifierByte = (typedByte >= 0x30 && typedByte <= 0x39)
            || (typedByte >= 0x41 && typedByte <= 0x5A)
            || (typedByte >= 0x61 && typedByte <= 0x7A)
            || typedByte == 0x5F
        guard isIdentifierByte else { return }
        guard facade.length < 4 * 1024 * 1024 else { return }
        guard !facade.isAutoCompletionActive else { return }

        let caret = facade.currentPosition
        // Skip inside comments and strings.
        let style = facade.send(SCI_GETSTYLEAT, w: max(0, caret - 1))
        if let semantic = currentLanguage.styleMap[style] {
            switch semantic {
            case .comment, .docComment, .string, .character:
                return
            default:
                break
            }
        }

        let prefix = currentWordPrefix()
        guard prefix.count >= 2 else { return }

        if completionCacheIsStale || modificationsSinceCacheBuild > 40 || completionWordCache.isEmpty {
            completionWordCache = Self.collectWords(from: facade, limit: 1500)
            modificationsSinceCacheBuild = 0
            completionCacheIsStale = false
        }
        let lowerPrefix = prefix.lowercased()
        let matches = completionWordCache.filter {
            $0.count > prefix.count && $0.lowercased().hasPrefix(lowerPrefix)
        }
        guard !matches.isEmpty else { return }
        facade.showAutoCompletion(prefixLength: prefix.utf8.count, words: Array(matches.prefix(300)))
    }

    func currentWordPrefix() -> String {
        var position = facade.currentPosition
        var bytes: [UInt8] = []
        while position > 0, bytes.count < 64 {
            let byte = facade.character(at: position - 1)
            let isIdentifierByte = (byte >= 0x30 && byte <= 0x39)
                || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x5F
            guard isIdentifierByte else { break }
            bytes.append(byte)
            position -= 1
        }
        return String(decoding: bytes.reversed(), as: UTF8.self)
    }

    static func collectWords(from facade: ScintillaFacade, limit: Int) -> [String] {
        let text = facade.text
        var words = Set<String>()
        var current = ""
        current.reserveCapacity(32)
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                if current.count > 64 {
                    current.removeFirst()
                }
            } else {
                if current.count >= 3 {
                    words.insert(current)
                    if words.count >= limit { break }
                }
                current = ""
            }
        }
        if current.count >= 3, words.count < limit {
            words.insert(current)
        }
        return Array(words)
    }

    func scintillaMarginClicked(_ facade: ScintillaFacade, margin: Int, modifiers: NSEvent.ModifierFlags, position: Int) {
        let line = facade.line(from: position)
        if margin == 1 {
            toggleBookmark(at: line)
        }
        delegate?.editorPane(self, didClickMargin: margin, line: line)
    }
}
