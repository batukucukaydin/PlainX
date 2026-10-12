//
//  StandardCommands.swift
//  PlainX Editor
//
//  Registration of every built-in command. Menus, the command palette, and
//  the macro engine all consume these definitions.
//

import AppKit

enum StandardCommands {

    static func registerAll(coordinator: AppCoordinator) {
        let registry = CommandRegistry.shared
        registry.register(fileCommands(coordinator))
        registry.register(editCommands(coordinator))
        registry.register(navigationCommands(coordinator))
        registry.register(searchCommands(coordinator))
        registry.register(viewCommands(coordinator))
        registry.register(toolCommands(coordinator))
        registry.register(diffCommands(coordinator))
        registry.register(macroCommands(coordinator))
        registry.register(windowCommands(coordinator))
        registry.register(appCommands(coordinator))
        registry.register(languageCommands())
        registry.register(helpCommands())
    }

    // MARK: - File

    private static func fileCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "file.new", title: "New", category: "File", keyBinding: .cmd("n"),
                    keywords: ["untitled", "tab"]) { context in
                context.coordinator?.newDocument(in: context.window)
            },
            Command(id: "file.newWindow", title: "New Window", category: "File", keyBinding: .cmdShift("n"),
                    keywords: ["window"]) { context in
                let window = context.coordinator?.newWindow()
                window?.addTab(for: PlainXDocument(url: nil), select: true)
            },
            Command(id: "file.open", title: "Open…", category: "File", keyBinding: .cmd("o"),
                    keywords: ["file", "folder"]) { context in
                context.coordinator?.showOpenPanel(in: context.window)
            },
            Command(id: "file.openFolder", title: "Open Folder for Search…", category: "File",
                    keywords: ["folder", "directory", "find in files"]) { context in
                context.coordinator?.showOpenFolderPanel(in: context.window)
            },
            Command(id: "file.save", title: "Save", category: "File", keyBinding: .cmd("s"),
                    isEnabled: { $0.document != nil }) { context in
                guard let document = context.document else { return }
                context.coordinator?.save(document: document, tab: context.tab, force: false)
            },
            Command(id: "file.saveAs", title: "Save As…", category: "File", keyBinding: .cmdShift("s"),
                    isEnabled: { $0.document != nil }) { context in
                guard let document = context.document else { return }
                context.coordinator?.saveAs(document: document, tab: context.tab)
            },
            Command(id: "file.saveAll", title: "Save All", category: "File", keyBinding: .cmdOption("s"),
                    isEnabled: { $0.window != nil }) { context in
                guard let window = context.window else { return }
                context.coordinator?.saveAll(in: window)
            },
            Command(id: "file.closeTab", title: "Close Tab", category: "File", keyBinding: .cmd("w"),
                    isEnabled: { $0.activeTab != nil }) { context in
                guard let tab = context.activeTab else { return }
                context.window?.closeTab(id: tab.id)
            },
            Command(id: "file.closeWindow", title: "Close Window", category: "File", keyBinding: .cmdShift("w"),
                    isEnabled: { $0.window != nil }) { context in
                guard let window = context.window else { return }
                context.coordinator?.closeWindow(window)
            },
            Command(id: "file.reopenClosedTab", title: "Reopen Closed Tab", category: "File", keyBinding: .cmdShift("t"),
                    keywords: ["undo close"]) { context in
                guard let window = context.window ?? context.coordinator?.activeWindow else { return }
                context.coordinator?.reopenLastClosedTab(in: window)
            },
            Command(id: "file.rename", title: "Rename…", category: "File",
                    isEnabled: { $0.document?.url != nil }) { context in
                context.coordinator?.promptRename(tab: context.tab)
            },
            Command(id: "file.revealInFinder", title: "Reveal in Finder", category: "File",
                    isEnabled: { $0.document?.url != nil }) { context in
                if let url = context.document?.url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            Command(id: "file.copyPath", title: "Copy File Path", category: "File",
                    isEnabled: { $0.document?.url != nil }) { context in
                guard let document = context.document else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(document.pathDisplayName, forType: .string)
            },
            Command(id: "file.print", title: "Print…", category: "File", keyBinding: .cmd("p"),
                    isEnabled: { $0.tab != nil }) { context in
                context.coordinator?.printDocument(tab: context.tab)
            },
            Command(id: "file.hashFile", title: "Hash Open File (SHA-256)…", category: "File",
                    isEnabled: { $0.document?.url != nil }) { context in
                context.coordinator?.hashOpenFile(tab: context.tab)
            },
        ]
    }

    // MARK: - Edit

    private static func editCommands(_ coordinator: AppCoordinator) -> [Command] {
        var commands: [Command] = [
            Command(id: "edit.undo", title: "Undo", category: "Edit", keyBinding: .cmd("z"),
                    isEnabled: { $0.pane?.facade.canUndo ?? false }) { context in
                context.pane?.facade.undo()
            },
            Command(id: "edit.redo", title: "Redo", category: "Edit", keyBinding: .cmdShift("z"),
                    isEnabled: { $0.pane?.facade.canRedo ?? false }) { context in
                context.pane?.facade.redo()
            },
            Command(id: "edit.duplicateLine", title: "Duplicate Line or Selection", category: "Edit",
                    keyBinding: .cmdShift("d"), keywords: ["copy line"]) { context in
                guard let pane = context.pane else { return }
                let selections = pane.facade.allSelections()
                pane.facade.beginUndoAction()
                for selection in selections.reversed() {
                    let firstLine = pane.facade.line(from: selection.lowerBound)
                    let lastLine = pane.facade.line(from: selection.upperBound)
                    let start = pane.facade.lineStart(firstLine)
                    let end = pane.facade.lineEnd(lastLine)
                    let text = pane.facade.text(inRange: NSRange(location: start, length: end - start))
                    let suffix = pane.facade.character(at: end) == 0x0A ? "" : "\n"
                    pane.facade.insert(text: suffix + text, at: end)
                    pane.facade.setSelection(anchor: end + suffix.count, caret: end + suffix.count + text.count)
                }
                pane.facade.endUndoAction()
            },
            Command(id: "edit.deleteLine", title: "Delete Line", category: "Edit", keyBinding: .cmdShift("k"),
                    keywords: ["remove line"]) { context in
                guard let pane = context.pane else { return }
                pane.facade.beginUndoAction()
                for selection in pane.facade.allSelections().reversed() {
                    let firstLine = pane.facade.line(from: selection.lowerBound)
                    let lastLine = pane.facade.line(from: selection.upperBound)
                    let start = pane.facade.lineStart(firstLine)
                    var end = pane.facade.lineEnd(lastLine)
                    if pane.facade.character(at: end) == 0x0A { end += 1 }
                    if pane.facade.character(at: end) == 0x0D { end += 1 }
                    if pane.facade.character(at: end) == 0x0A { end += 1 }
                    pane.facade.deleteRange(location: start, length: end - start)
                }
                pane.facade.endUndoAction()
            },
            Command(id: "edit.moveLineUp", title: "Move Line Up", category: "Edit", keyBinding: .cmdOption("↑")) { context in
                context.pane?.facade.send(SCI_MOVESELECTEDLINESUP)
            },
            Command(id: "edit.moveLineDown", title: "Move Line Down", category: "Edit", keyBinding: .cmdOption("↓")) { context in
                context.pane?.facade.send(SCI_MOVESELECTEDLINESDOWN)
            },
            Command(id: "edit.joinLines", title: "Join Lines", category: "Edit", keyBinding: .cmdControl("j"),
                    keywords: ["merge lines"]) { context in
                guard let pane = context.pane, let tab = context.tab else { return }
                let selection = pane.facade.mainSelection
                let firstLine = pane.facade.line(from: selection.lowerBound)
                let lastLine = pane.facade.line(from: selection.isEmpty ? firstLine + 1 : pane.facade.line(from: selection.upperBound))
                guard lastLine > firstLine else { return }
                let start = pane.facade.lineStart(firstLine)
                let end = pane.facade.lineEnd(lastLine)
                let text = pane.facade.text(inRange: NSRange(location: start, length: end - start))
                let joined = TransformService.joinLines(in: text)
                pane.facade.beginUndoAction()
                pane.facade.replace(range: NSRange(location: start, length: end - start), with: joined)
                pane.facade.endUndoAction()
                tab.markClean()
                _ = coordinator
            },
            Command(id: "edit.splitLines", title: "Split Lines at Delimiter…", category: "Edit",
                    keywords: ["split"]) { context in
                context.coordinator?.promptSplitLines(tab: context.tab)
            },
            Command(id: "edit.sortLinesAscending", title: "Sort Lines Ascending", category: "Edit",
                    isRecordable: true, keywords: ["order"]) { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.sortLines(in: $0, ascending: true, caseInsensitive: false) }
            },
            Command(id: "edit.sortLinesDescending", title: "Sort Lines Descending", category: "Edit",
                    keywords: ["order"]) { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.sortLines(in: $0, ascending: false, caseInsensitive: false) }
            },
            Command(id: "edit.sortLinesCaseInsensitive", title: "Sort Lines (Case-Insensitive)", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.sortLines(in: $0, ascending: true, caseInsensitive: true) }
            },
            Command(id: "edit.removeDuplicateLines", title: "Remove Duplicate Lines", category: "Edit",
                    keywords: ["dedupe", "unique"]) { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.removeDuplicateLines(in: $0) }
            },
            Command(id: "edit.removeEmptyLines", title: "Remove Empty Lines", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.removeEmptyLines(in: $0) }
            },
            Command(id: "edit.reverseLines", title: "Reverse Lines", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.reverseLines(in: $0) }
            },
            Command(id: "edit.trimTrailingWhitespace", title: "Trim Trailing Whitespace", category: "Edit",
                    keywords: ["cleanup"]) { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.trimTrailingWhitespace(in: $0) }
            },
            Command(id: "edit.trimLeadingWhitespace", title: "Trim Leading Whitespace", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.trimLeadingWhitespace(in: $0) }
            },
            Command(id: "edit.uppercase", title: "Convert to UPPERCASE", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.uppercase($0) }
            },
            Command(id: "edit.lowercase", title: "Convert to lowercase", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.lowercase($0) }
            },
            Command(id: "edit.titleCase", title: "Convert to Title Case", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.titleCase($0) }
            },
            Command(id: "edit.sentenceCase", title: "Convert to Sentence case", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.sentenceCase($0) }
            },
            Command(id: "edit.swapCase", title: "Swap Case", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.apply(to: pane) { TransformService.swapCase($0) }
            },
            Command(id: "edit.toggleComment", title: "Toggle Comment", category: "Edit", keyBinding: .cmd("/"),
                    keywords: ["comment"]) { context in
                context.coordinator?.toggleComment(tab: context.tab)
            },
            Command(id: "edit.indent", title: "Increase Indent", category: "Edit", keyBinding: .cmd("]"),
                    keywords: ["tab"]) { context in
                context.pane?.facade.indentSelection(by: 1)
            },
            Command(id: "edit.outdent", title: "Decrease Indent", category: "Edit", keyBinding: .cmd("[")) { context in
                context.pane?.facade.indentSelection(by: -1)
            },
            Command(id: "edit.convertTabsToSpaces", title: "Convert Tabs to Spaces", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.convertTabsToSpaces(pane: pane, tabWidth: Preferences.shared.tabWidth)
            },
            Command(id: "edit.convertSpacesToTabs", title: "Convert Spaces to Tabs", category: "Edit") { context in
                guard let pane = context.pane else { return }
                TransformService.convertSpacesToTabs(pane: pane, tabWidth: Preferences.shared.tabWidth)
            },
            Command(id: "edit.selectLine", title: "Select Line", category: "Edit") { context in
                guard let pane = context.pane else { return }
                let line = pane.currentLine
                let start = pane.facade.lineStart(line)
                let end = pane.facade.lineEnd(line)
                pane.facade.setSelection(anchor: start, caret: end)
            },
            Command(id: "edit.selectWord", title: "Select Word", category: "Edit") { context in
                context.pane?.facade.send(SCI_WORDLEFT, w: context.pane?.facade.currentPosition ?? 0)
                context.pane?.facade.send(SCI_WORDRIGHTEXTEND)
            },
            Command(id: "edit.addCaretAbove", title: "Add Caret Above", category: "Edit", keyBinding: .cmdControl("↑"),
                    keywords: ["multi cursor"]) { context in
                context.pane?.facade.addCaretAbove()
            },
            Command(id: "edit.addCaretBelow", title: "Add Caret Below", category: "Edit", keyBinding: .cmdControl("↓"),
                    keywords: ["multi cursor"]) { context in
                context.pane?.facade.addCaretBelow()
            },
            Command(id: "edit.selectNextOccurrence", title: "Select Next Occurrence", category: "Edit",
                    keyBinding: .cmd("d"), keywords: ["multi cursor", "add next"]) { context in
                context.pane?.facade.selectNextOccurrence()
            },
            Command(id: "edit.selectAllOccurrences", title: "Select All Occurrences", category: "Edit",
                    keyBinding: .cmdControl("d"), keywords: ["multi cursor"]) { context in
                context.pane?.facade.selectAllOccurrences()
            },
            Command(id: "edit.toggleColumnSelection", title: "Toggle Column (Rectangular) Selection", category: "Edit",
                    keyBinding: .cmdShift("8"),
                    keywords: ["block select"],
                    isChecked: { $0.pane?.facade.isRectangleSelection ?? false }) { context in
                guard let pane = context.pane else { return }
                pane.facade.setSelectionModeRectangle(!pane.facade.isRectangleSelection)
            },
            Command(id: "edit.toggleBookmark", title: "Toggle Bookmark", category: "Edit", keyBinding: .cmd("f2"),
                    keywords: ["marker"]) { context in
                guard let pane = context.pane else { return }
                pane.toggleBookmark(at: pane.currentLine)
            },
            Command(id: "edit.nextBookmark", title: "Next Bookmark", category: "Edit", keyBinding: KeyBinding(key: "f2", modifiers: [], displayString: "F2")) { context in
                guard let pane = context.pane, let line = pane.nextBookmark(from: pane.currentLine) else { return }
                pane.facade.gotoLine(line)
                pane.facade.scrollToLine(line)
            },
            Command(id: "edit.previousBookmark", title: "Previous Bookmark", category: "Edit",
                    keyBinding: KeyBinding(key: "f2", modifiers: [.shift], displayString: "⇧F2")) { context in
                guard let pane = context.pane, let line = pane.previousBookmark(from: pane.currentLine) else { return }
                pane.facade.gotoLine(line)
                pane.facade.scrollToLine(line)
            },
            Command(id: "edit.clearBookmarks", title: "Clear All Bookmarks", category: "Edit") { context in
                context.pane?.clearBookmarks()
            },
            Command(id: "edit.completeWord", title: "Complete Word from Document", category: "Edit") { context in
                guard let pane = context.pane else { return }
                WordCompletion.complete(pane: pane)
            },
        ]
        return commands
    }

    // MARK: - Navigation

    private static func navigationCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "nav.goToLine", title: "Go to Line…", category: "Navigate", keyBinding: .cmd("l"),
                    keywords: ["line number"]) { context in
                if let window = context.window {
                    context.coordinator?.promptGoToLine(in: window)
                }
            },
            Command(id: "nav.nextTab", title: "Next Tab", category: "Navigate", keyBinding: .cmdControl("→"),
                    keywords: ["switch tab"]) { context in
                guard let window = context.window, !window.tabs.isEmpty else { return }
                let next = (window.activeTabIndex + 1) % window.tabs.count
                window.selectTab(at: next)
            },
            Command(id: "nav.previousTab", title: "Previous Tab", category: "Navigate", keyBinding: .cmdControl("←")) { context in
                guard let window = context.window, !window.tabs.isEmpty else { return }
                let previous = (window.activeTabIndex - 1 + window.tabs.count) % window.tabs.count
                window.selectTab(at: previous)
            },
            Command(id: "nav.focusNextPane", title: "Focus Other Split Pane", category: "Navigate", keyBinding: .cmdOption("`")) { context in
                context.tab?.focusNextPane()
            },
        ]
    }

    // MARK: - Search

    private static func searchCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "search.find", title: "Find…", category: "Search", keyBinding: .cmd("f")) { context in
                context.tab?.showFindBar(mode: .find)
            },
            Command(id: "search.findNext", title: "Find Next", category: "Search", keyBinding: .cmd("g")) { context in
                context.tab?.searchNext()
            },
            Command(id: "search.findPrevious", title: "Find Previous", category: "Search", keyBinding: .cmdShift("g")) { context in
                context.tab?.searchPrevious()
            },
            Command(id: "search.replace", title: "Replace…", category: "Search", keyBinding: .cmdOption("f")) { context in
                context.tab?.showFindBar(mode: .replace)
            },
            Command(id: "search.useSelectionForFind", title: "Use Selection for Find", category: "Search", keyBinding: .cmd("e")) { context in
                context.tab?.showFindBar(mode: .find)
                context.tab?.findBarController?.useSelectionFromEditor()
            },
            Command(id: "search.findInFiles", title: "Find in Files…", category: "Search", keyBinding: .cmdShift("f"),
                    keywords: ["folder search", "grep"]) { context in
                context.coordinator?.promptFindInFiles(root: nil)
            },
            Command(id: "search.findInFilesSelection", title: "Find Selection in Files", category: "Search") { context in
                context.coordinator?.promptFindInFiles(root: nil)
            },
            Command(id: "search.searchResultsPanel", title: "Search Results Panel", category: "Search") { context in
                context.coordinator?.promptFindInFiles(root: nil)
            },
            Command(id: "search.jumpToNextSearchMatch", title: "Select Next Search Match", category: "Search") { context in
                context.tab?.selectNextHighlightedMatch()
            },
        ]
    }

    // MARK: - View

    private static func viewCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "view.zoomIn", title: "Zoom In", category: "View", keyBinding: .cmd("+"),
                    keywords: ["font size"]) { context in
                guard let pane = context.pane else { return }
                pane.facade.zoom += 1
            },
            Command(id: "view.zoomOut", title: "Zoom Out", category: "View", keyBinding: .cmd("-")) { context in
                context.pane?.facade.zoom -= 1
            },
            Command(id: "view.zoomReset", title: "Actual Size", category: "View", keyBinding: .cmd("0"),
                    keywords: ["reset zoom"]) { context in
                context.pane?.facade.zoom = 0
            },
            Command(id: "view.toggleWordWrap", title: "Toggle Word Wrap", category: "View",
                    keyBinding: .cmdOption("w"),
                    keywords: ["wrap"],
                    isChecked: { $0.pane?.facade.wrapModeEnabled ?? false }) { context in
                guard let pane = context.pane, let tab = context.tab else { return }
                let newValue = !pane.facade.wrapModeEnabled
                pane.facade.setWrapMode(newValue)
                tab.document.wordWrapOverride = newValue
            },
            Command(id: "view.toggleLineNumbers", title: "Toggle Line Numbers", category: "View",
                    isChecked: { _ in Preferences.shared.showLineNumbers }) { context in
                Preferences.shared.showLineNumbers.toggle()
                logViewCommand(context)
            },
            Command(id: "view.toggleWhitespace", title: "Show Whitespace", category: "View",
                    keywords: ["spaces", "tabs"],
                    isChecked: { _ in Preferences.shared.showWhitespace }) { context in
                Preferences.shared.showWhitespace.toggle()
                logViewCommand(context)
            },
            Command(id: "view.toggleEOL", title: "Show End-of-Line Characters", category: "View",
                    keywords: ["crlf", "lf"],
                    isChecked: { _ in Preferences.shared.showEOL }) { context in
                Preferences.shared.showEOL.toggle()
                logViewCommand(context)
            },
            Command(id: "view.toggleIndentGuides", title: "Show Indent Guides", category: "View",
                    isChecked: { _ in Preferences.shared.showIndentGuides }) { context in
                Preferences.shared.showIndentGuides.toggle()
                logViewCommand(context)
            },
            Command(id: "view.toggleCurrentLineHighlight", title: "Highlight Current Line", category: "View",
                    isChecked: { _ in Preferences.shared.highlightCurrentLine }) { context in
                Preferences.shared.highlightCurrentLine.toggle()
                logViewCommand(context)
            },
            Command(id: "view.splitView", title: "Split View", category: "View", keyBinding: .cmdOption("s"),
                    keywords: ["pane"]) { context in
                context.tab?.splitIntoSecondPane()
                context.window?.updateWindowTitle()
            },
            Command(id: "view.unsplit", title: "Unsplit View", category: "View",
                    isEnabled: { $0.tab?.isSplit ?? false }) { context in
                context.tab?.unsplit()
                context.window?.updateWindowTitle()
            },
            Command(id: "view.foldAll", title: "Fold All", category: "View", keyBinding: .cmdOption("0"),
                    keywords: ["collapse"]) { context in
                context.pane?.facade.foldAction(.contractAll, line: 0)
            },
            Command(id: "view.unfoldAll", title: "Unfold All", category: "View", keyBinding: .cmdOption("9"),
                    keywords: ["expand"]) { context in
                context.pane?.facade.foldAction(.expandAll, line: 0)
            },
            Command(id: "view.foldCurrent", title: "Fold Current Block", category: "View") { context in
                guard let pane = context.pane else { return }
                pane.facade.foldAction(.contract, line: pane.currentLine)
            },
            Command(id: "view.unfoldCurrent", title: "Unfold Current Block", category: "View") { context in
                guard let pane = context.pane else { return }
                pane.facade.foldAction(.expand, line: pane.currentLine)
            },
            Command(id: "view.themeSystem", title: "Appearance: Match System", category: "View",
                    isChecked: { _ in Preferences.shared.themeChoice == .system }) { context in
                Preferences.shared.themeChoice = .system
                context.window?.applyThemeChange()
            },
            Command(id: "view.themeLight", title: "Appearance: Light", category: "View",
                    isChecked: { _ in Preferences.shared.themeChoice == .light }) { context in
                Preferences.shared.themeChoice = .light
                context.window?.applyThemeChange()
            },
            Command(id: "view.themeDark", title: "Appearance: Dark", category: "View",
                    isChecked: { _ in Preferences.shared.themeChoice == .dark }) { context in
                Preferences.shared.themeChoice = .dark
                context.window?.applyThemeChange()
            },
            Command(id: "view.toggleFullScreen", title: "Enter Full Screen", category: "View",
                    keyBinding: .cmdControl("f")) { context in
                context.window?.window?.toggleFullScreen(nil)
            },
        ]
    }

    private static func logViewCommand(_ context: CommandContext) {
        context.window?.updateStatusBar()
        for tab in context.window?.tabs ?? [] {
            guard let editorTab = tab as? DocumentTabController else { continue }
            for pane in editorTab.panes {
                pane.applyEditorPreferences()
            }
        }
    }

    // MARK: - Tools

    private static func toolCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "tools.formatJSON", title: "Format / Pretty-Print JSON", category: "Tools",
                    keywords: ["json", "beautify"]) { context in
                context.coordinator?.runTransform(context: context, name: "Format JSON") {
                    try TransformService.formatJSON($0)
                }
            },
            Command(id: "tools.minifyJSON", title: "Minify JSON", category: "Tools", keywords: ["json"]) { context in
                context.coordinator?.runTransform(context: context, name: "Minify JSON") {
                    try TransformService.minifyJSON($0)
                }
            },
            Command(id: "tools.validateJSON", title: "Validate JSON", category: "Tools") { context in
                context.coordinator?.reportValidation(context: context, name: "JSON") {
                    try TransformService.validateJSON($0)
                }
            },
            Command(id: "tools.formatXML", title: "Format XML", category: "Tools") { context in
                context.coordinator?.runTransform(context: context, name: "Format XML") {
                    try TransformService.formatXML($0)
                }
            },
            Command(id: "tools.validateXML", title: "Validate XML", category: "Tools") { context in
                context.coordinator?.reportValidation(context: context, name: "XML") {
                    try TransformService.validateXML($0)
                }
            },
            Command(id: "tools.base64Encode", title: "Base64 Encode", category: "Tools") { context in
                context.coordinator?.runTransform(context: context, name: "Base64 Encode") {
                    TransformService.base64Encode($0)
                }
            },
            Command(id: "tools.base64Decode", title: "Base64 Decode", category: "Tools") { context in
                context.coordinator?.runTransform(context: context, name: "Base64 Decode") {
                    try TransformService.base64Decode($0)
                }
            },
            Command(id: "tools.urlEncode", title: "URL Encode", category: "Tools") { context in
                context.coordinator?.runTransform(context: context, name: "URL Encode") {
                    TransformService.urlEncode($0)
                }
            },
            Command(id: "tools.urlDecode", title: "URL Decode", category: "Tools") { context in
                context.coordinator?.runTransform(context: context, name: "URL Decode") {
                    try TransformService.urlDecode($0)
                }
            },
            Command(id: "tools.htmlEscape", title: "HTML Escape", category: "Tools", keywords: ["entities"]) { context in
                context.coordinator?.runTransform(context: context, name: "HTML Escape") {
                    TransformService.htmlEscape($0)
                }
            },
            Command(id: "tools.htmlUnescape", title: "HTML Unescape", category: "Tools") { context in
                context.coordinator?.runTransform(context: context, name: "HTML Unescape") {
                    TransformService.htmlUnescape($0)
                }
            },
            Command(id: "tools.hashSHA256", title: "SHA-256 of Selection", category: "Tools", keywords: ["hash", "checksum"]) { context in
                context.coordinator?.runTransformReplacing(context: context, name: "SHA-256") {
                    TransformService.hash($0, algorithm: .sha256)
                }
            },
            Command(id: "tools.hashSHA512", title: "SHA-512 of Selection", category: "Tools") { context in
                context.coordinator?.runTransformReplacing(context: context, name: "SHA-512") {
                    TransformService.hash($0, algorithm: .sha512)
                }
            },
            Command(id: "tools.hashSHA1", title: "SHA-1 of Selection (legacy, non-security)", category: "Tools") { context in
                context.coordinator?.runTransformReplacing(context: context, name: "SHA-1 (legacy)") {
                    TransformService.hash($0, algorithm: .sha1)
                }
            },
            Command(id: "tools.hashMD5", title: "MD5 of Selection (legacy, non-security)", category: "Tools") { context in
                context.coordinator?.runTransformReplacing(context: context, name: "MD5 (legacy)") {
                    TransformService.hash($0, algorithm: .md5)
                }
            },
            Command(id: "tools.insertTimestamp", title: "Insert Current Date/Time", category: "Tools") { context in
                guard let pane = context.pane else { return }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                pane.facade.insert(text: formatter.string(from: Date()), at: pane.facade.currentPosition)
            },
            Command(id: "tools.copyDiagnostics", title: "Copy Diagnostics to Clipboard", category: "Tools") { context in
                context.coordinator?.copyDiagnostics()
            },
        ]
    }

    // MARK: - Diff

    private static func diffCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "diff.compareWithFile", title: "Compare With File…", category: "Diff",
                    isEnabled: { $0.document != nil }) { context in
                context.coordinator?.promptCompareWithFile(tab: context.tab)
            },
            Command(id: "diff.compareWithDisk", title: "Compare With Saved Version", category: "Diff",
                    isEnabled: { $0.document?.url != nil }) { context in
                guard let document = context.document, let tab = context.tab else { return }
                context.coordinator?.compareWithDisk(document: document, tab: tab)
            },
            Command(id: "diff.compareTwoFiles", title: "Compare Two Files…", category: "Diff") { context in
                context.coordinator?.promptCompareTwoFiles(in: context.window)
            },
        ]
    }

    // MARK: - Macros

    private static func macroCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "macro.startRecording", title: "Start Recording", category: "Macro", isRecordable: false,
                    isEnabled: { $0.coordinator?.macroEngine.isRecording == false }) { context in
                context.coordinator?.startMacroRecording(window: context.window)
            },
            Command(id: "macro.stopRecording", title: "Stop Recording", category: "Macro", isRecordable: false,
                    isEnabled: { $0.coordinator?.macroEngine.isRecording == true }) { context in
                context.coordinator?.stopMacroRecording(window: context.window)
            },
            Command(id: "macro.playLast", title: "Play Last Macro", category: "Macro",
                    keyBinding: KeyBinding(key: "j", modifiers: [.command, .shift], displayString: "⇧⌘J"),
                    isRecordable: false,
                    isEnabled: { $0.coordinator?.macroEngine.lastMacro != nil }) { context in
                context.coordinator?.playLastMacro(times: 1, window: context.window)
            },
            Command(id: "macro.playLastMultiple", title: "Play Last Macro Multiple Times…", category: "Macro", isRecordable: false,
                    isEnabled: { $0.coordinator?.macroEngine.lastMacro != nil }) { context in
                context.coordinator?.promptPlayLastMacro(window: context.window)
            },
        ]
    }

    // MARK: - Window

    private static func windowCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "window.minimize", title: "Minimize", category: "Window", keyBinding: .cmd("m")) { context in
                context.window?.window?.miniaturize(nil)
            },
            Command(id: "window.zoom", title: "Zoom", category: "Window") { context in
                context.window?.window?.zoom(nil)
            },
            Command(id: "window.nextWindow", title: "Next Window", category: "Window", keyBinding: .cmd("`")) { context in
                guard let coordinator = context.coordinator, coordinator.windows.count > 1 else { return }
                let windows = coordinator.windows
                guard let currentIndex = windows.firstIndex(where: { $0 === context.window }) else { return }
                let next = windows[(currentIndex + 1) % windows.count]
                next.window?.makeKeyAndOrderFront(nil)
            },
        ]
    }

    // MARK: - App

    private static func appCommands(_ coordinator: AppCoordinator) -> [Command] {
        [
            Command(id: "app.preferences", title: "Settings…", category: "PlainX", keyBinding: .cmd(",")) { context in
                context.coordinator?.showPreferences()
            },
            Command(id: "app.about", title: "About PlainX Editor", category: "PlainX") { context in
                context.coordinator?.showAbout()
            },
            Command(id: "app.quit", title: "Quit PlainX", category: "PlainX", keyBinding: .cmd("q")) { context in
                NSApp.terminate(nil)
            },
            Command(id: "palette.show", title: "Command Palette…", category: "PlainX", keyBinding: .cmdShift("p"),
                    isRecordable: false, keywords: ["commands", "actions"]) { context in
                context.coordinator?.showCommandPalette(in: context.window ?? context.coordinator?.activeWindow)
            },
        ]
    }

    // MARK: - Language

    private static func languageCommands() -> [Command] {
        var commands: [Command] = [
            Command(id: "language.auto", title: "Auto-detect Language", category: "Language", isRecordable: false,
                    isChecked: { $0.document?.languageOverrideID == nil }) { context in
                guard let tab = context.tab else { return }
                tab.document.languageOverrideID = nil
                tab.activePane.setLanguage(LanguageRegistry.language(for: tab.document.url))
                context.window?.updateStatusBar()
            },
        ]
        for language in LanguageRegistry.all where language.id != "plain" {
            let languageID = language.id
            commands.append(Command(
                id: "language.set.\(languageID)",
                title: language.displayName,
                category: "Language",
                isRecordable: false,
                keywords: [languageID, "syntax"],
                isEnabled: { _ in true },
                isChecked: { $0.document?.languageOverrideID == languageID },
                action: { context in
                    guard let tab = context.tab else { return }
                    tab.document.languageOverrideID = languageID
                    tab.activePane.setLanguage(LanguageRegistry.language(withID: languageID))
                    context.window?.updateStatusBar()
                }
            ))
        }
        return commands
    }

    // MARK: - Help

    private static func helpCommands() -> [Command] {
        [
            Command(id: "help.shortcuts", title: "Keyboard Shortcuts", category: "Help", isRecordable: false) { context in
                context.coordinator?.showShortcutsHelp()
            },
            Command(id: "help.releaseNotes", title: "Release Notes", category: "Help", isRecordable: false) { context in
                context.coordinator?.showReleaseNotes()
            },
        ]
    }
}
