//
//  DocumentTabController.swift
//  PlainX Editor
//
//  One tab: a document plus one or two editor panes. When a document is
//  shown in two panes (split view / cloned view) the tab mirrors text
//  changes between them at the Scintilla modification level.
//

import AppKit

protocol DocumentTabControllerDelegate: AnyObject {
    func documentTabDidChangeState(_ tab: DocumentTabController)
    func documentTabDidChangeContent(_ tab: DocumentTabController)
    func documentTabDidChangeSelection(_ tab: DocumentTabController)
    func documentTabRequestsClose(_ tab: DocumentTabController)
}

/// How a second editor pane is arranged relative to the first.
enum SplitOrientation {
    /// Panes side by side (vertical divider).
    case vertical
    /// Panes stacked (horizontal divider).
    case horizontal
}

final class DocumentTabController: NSObject, EditorPaneControllerDelegate, DocumentTab {
    let id = UUID()
    let document: PlainXDocument
    unowned let controller: MainWindowController
    weak var delegate: DocumentTabControllerDelegate?

    private(set) var panes: [EditorPaneController] = []
    private(set) var activePaneIndex: Int = 0
    private(set) var splitOrientation: SplitOrientation = .vertical
    private var isSyncing = false

    /// Root view for the tab: optional find bar stacked above the pane area.
    let rootStack = NSStackView()
    private(set) var splitView: NSSplitView?
    var findBarController: FindBarController?

    var activePane: EditorPaneController { panes[activePaneIndex] }
    var isSplit: Bool { panes.count > 1 }
    private var theme: EditorTheme { controller.currentTheme }

    init(document: PlainXDocument, controller: MainWindowController) {
        self.document = document
        self.controller = controller
        super.init()

        rootStack.orientation = .vertical
        rootStack.spacing = 0
        rootStack.alignment = .leading

        let pane = makePane()
        panes = [pane]
        rootStack.addArrangedSubview(pane.view)
        pane.view.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        pane.view.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func makePane() -> EditorPaneController {
        let pane = EditorPaneController(theme: theme)
        pane.delegate = self
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        return pane
    }

    // MARK: - Document plumbing

    func loadInitialContent(from loaded: LoadedFile) {
        guard let primary = panes.first else { return }
        primary.bind(document: document, text: loaded.text, preserveViewState: false)
        document.isDirty = false
    }

    var currentText: String {
        activePane.facade.text
    }

    /// Applies a programmatic edit to every pane (used by transforms, macros,
    /// diff apply, and other whole-document operations).
    func replaceDocumentText(_ text: String, markDirty: Bool, preselectedRange: NSRange? = nil) {
        isSyncing = true
        defer { isSyncing = false }
        for pane in panes {
            pane.facade.text = text
            if let range = preselectedRange, range.upperBound <= pane.facade.length {
                pane.facade.setSelection(anchor: range.location, caret: range.upperBound)
                pane.facade.scrollCaret()
            }
        }
        if !markDirty {
            markClean()
        }
        delegate?.documentTabDidChangeContent(self)
    }

    /// Runs an undo-grouped edit on all panes in sync.
    func performSyncedEdit(_ body: (EditorPaneController) -> Void) {
        isSyncing = true
        defer { isSyncing = false }
        for pane in panes {
            pane.facade.beginUndoAction()
            body(pane)
            pane.facade.endUndoAction()
        }
        delegate?.documentTabDidChangeContent(self)
    }

    func markClean() {
        for pane in panes {
            pane.markClean()
        }
        document.isDirty = false
        delegate?.documentTabDidChangeState(self)
    }

    func markDirtyIfNeeded() {
        guard !document.isDirty else { return }
        document.isDirty = true
        delegate?.documentTabDidChangeState(self)
    }

    func saveViewStates() {
        for pane in panes {
            document.viewStates[pane.paneID] = pane.captureViewState()
        }
    }

    // MARK: - DocumentTab conformance

    var tabContentView: NSView { rootStack }
    var isLargeFileViewer: Bool { false }

    var tabDelegate: DocumentTabControllerDelegate? {
        get { delegate }
        set { delegate = newValue }
    }

    func statusSnapshot() -> StatusBarView.State {
        let pane = activePane
        let line = pane.currentLine
        let column = pane.facade.column(of: pane.facade.currentPosition)
        let selectionCount = pane.facade.selectionCount
        let selection = pane.facade.mainSelection

        var selectionSummary = ""
        if selectionCount > 1 {
            selectionSummary = "\(selectionCount) selections"
        } else if !selection.isEmpty {
            selectionSummary = "\(selection.length) selected"
        }

        var sizeSummary = ""
        if let metadata = document.lastKnownMetadata {
            sizeSummary = metadata.summary
        } else {
            sizeSummary = "\(pane.facade.length) bytes"
        }

        var modeSummary = ""
        if document.isLargeFileMode {
            modeSummary = "Large File Mode"
        } else if document.eolMode == .mixed {
            modeSummary = "Mixed EOL"
        }

        return StatusBarView.State(
            encodingName: document.encoding.displayName,
            encodingTooltip: "Change or convert file encoding",
            eolName: document.eolMode.displayName,
            eolTooltip: "Change line endings",
            languageName: document.language.displayName,
            languageTooltip: "Choose the syntax language",
            indentationName: Preferences.shared.useTabs
                ? "Tabs: \(Preferences.shared.tabWidth)"
                : "Spaces: \(Preferences.shared.tabWidth)",
            line: line,
            column: column,
            selectionSummary: selectionSummary,
            fileSizeSummary: sizeSummary,
            modeSummary: modeSummary
        )
    }

    func focusContent() {
        controller.window?.makeFirstResponder(activePane.facade.view)
    }

    // MARK: - Find bar

    func showFindBar(mode: FindBarController.Mode) {
        if let existing = findBarController {
            existing.setMode(mode)
            existing.focus()
            return
        }
        let controller = FindBarController(tab: self, mode: mode)
        findBarController = controller
        rootStack.insertArrangedSubview(controller.view, at: 0)
        controller.view.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        controller.focus()
    }

    func hideFindBar() {
        guard let controller = findBarController else { return }
        rootStack.removeArrangedSubview(controller.view)
        controller.view.removeFromSuperview()
        findBarController = nil
        activePane.facade.clearIndicators(.searchMatch)
        activePane.facade.clearIndicators(.currentMatch)
        focusEditor()
    }

    func searchNext() {
        if let findBarController {
            findBarController.findNext()
        } else {
            showFindBar(mode: .find)
        }
    }

    func searchPrevious() {
        if let findBarController {
            findBarController.findPrevious()
        } else {
            showFindBar(mode: .find)
        }
    }

    func selectNextHighlightedMatch() {
        searchNext()
    }

    func focusEditor() {
        controller.window?.makeFirstResponder(activePane.facade.view)
    }

    // MARK: - Splitting

    @discardableResult
    func splitIntoSecondPane(orientation: SplitOrientation = .vertical) -> EditorPaneController {
        if isSplit {
            activePaneIndex = (activePaneIndex + 1) % panes.count
            return activePane
        }
        let second = makePane()
        second.bind(document: document, text: activePane.facade.text, preserveViewState: false)
        if let state = document.viewStates.values.first {
            second.applyViewState(state)
        }
        panes.append(second)

        splitOrientation = orientation
        let split = NSSplitView()
        // Vertical orientation places panes side by side; horizontal stacks them.
        split.isVertical = (orientation == .vertical)
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        for pane in panes {
            split.addArrangedSubview(pane.view)
        }

        rootStack.addArrangedSubview(split)
        split.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        splitView = split
        activePaneIndex = 1
        return second
    }

    func unsplit() {
        guard isSplit else { return }
        let keep = activePane
        let drop = panes.first { $0 !== keep }
        if let split = splitView {
            rootStack.removeArrangedSubview(split)
            split.removeFromSuperview()
        }
        panes = [keep]
        activePaneIndex = 0
        splitOrientation = .vertical
        drop?.view.removeFromSuperview()
        if let pane = panes.first {
            rootStack.insertArrangedSubview(pane.view, at: 0)
            pane.view.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }
        splitView = nil
    }

    func focusNextPane() {
        guard panes.count > 1 else { return }
        activePaneIndex = (activePaneIndex + 1) % panes.count
        controller.window?.makeFirstResponder(activePane.facade.view)
        delegate?.documentTabDidChangeSelection(self)
    }

    // MARK: - EditorPaneControllerDelegate

    func editorPaneDidChangeDirtyState(_ pane: EditorPaneController) {
        if pane === panes[0] {
            document.isDirty = pane.isDirty
        } else if pane.isDirty {
            document.isDirty = true
        }
        delegate?.documentTabDidChangeState(self)
    }

    func editorPaneDidUpdateUI(_ pane: EditorPaneController) {
        activePaneIndex = panes.firstIndex(where: { $0 === pane }) ?? activePaneIndex
        delegate?.documentTabDidChangeSelection(self)
    }

    func editorPane(_ pane: EditorPaneController, didApply modification: ScintillaModification) {
        guard panes.count > 1, !isSyncing else {
            delegate?.documentTabDidChangeContent(self)
            return
        }
        guard let other = panes.first(where: { $0 !== pane }) else { return }
        isSyncing = true
        defer {
            isSyncing = false
            delegate?.documentTabDidChangeContent(self)
        }

        if modification.isInsertText, let inserted = modification.insertedText {
            other.facade.isApplyingRemoteEdit = true
            other.facade.insert(text: inserted, at: modification.position)
            other.facade.isApplyingRemoteEdit = false
        } else if modification.isBeforeDelete, modification.length > 0 {
            other.facade.isApplyingRemoteEdit = true
            other.facade.deleteRange(location: modification.position, length: modification.length)
            other.facade.isApplyingRemoteEdit = false
        }
    }

    func editorPaneDidTypeCharacter(_ pane: EditorPaneController, byte: UInt8) {
        controller.coordinator.macroEngine.recordTypedByte(byte, tab: self)
        if byte == 0x0A {
            applySmartIndent(to: pane)
        }
    }

    /// Basic lexer-aware auto-indent: after pressing Return on a line that
    /// ends with an opening bracket, indent one extra level. The opener must
    /// not be inside a comment or string according to the language's style map.
    func applySmartIndent(to pane: EditorPaneController) {
        let facade = pane.facade
        let line = facade.line(from: facade.currentPosition)
        guard line > 0 else { return }
        let previousLine = line - 1
        var position = facade.lineEnd(previousLine) - 1
        let lineStart = facade.lineStart(previousLine)
        while position > lineStart {
            let byte = facade.character(at: position)
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                position -= 1
            } else {
                break
            }
        }
        guard position > lineStart || position == lineStart else { return }
        let opener = facade.character(at: position)
        guard opener == 0x7B || opener == 0x28 || opener == 0x5B else { return } // { ( [

        // Ignore openers inside comments or strings.
        let style = facade.send(SCI_GETSTYLEAT, w: position)
        let language = document.language
        if let semantic = language.styleMap[style] {
            switch semantic {
            case .comment, .docComment, .string, .character:
                return
            default:
                break
            }
        }

        let previousIndent = facade.send(SCI_GETLINEINDENTATION, w: previousLine)
        let indentWidth = Preferences.shared.tabWidth
        facade.send(SCI_SETLINEINDENTATION, w: line, l: previousIndent + indentWidth)
    }

    func editorPane(_ pane: EditorPaneController, didToggleBookmarkOn line: Int) {
        delegate?.documentTabDidChangeState(self)
    }

    // MARK: - Close

    func requestClose() {
        delegate?.documentTabRequestsClose(self)
    }
}
