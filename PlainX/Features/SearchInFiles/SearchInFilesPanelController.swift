//
//  SearchInFilesPanelController.swift
//  PlainX Editor
//
//  Find in Files / Replace in Files. Streaming results, cancellable search,
//  glob include/exclude filters, and review-before-replace file writes.
//

import AppKit

final class SearchInFilesPanelController: NSWindowController {
    static let shared = SearchInFilesPanelController()

    private unowned var coordinator: AppCoordinator!

    private let rootPathControl = NSPathControl()
    private let findField = NSSearchField()
    private let includeField = NSTextField()
    private let excludeField = NSTextField()
    private let replaceField = NSTextField()
    private let regexToggle = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
    private let caseToggle = NSButton(checkboxWithTitle: "Case", target: nil, action: nil)
    private let wholeWordToggle = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    private let searchButton = NSButton(title: "Search", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "Replace All…", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let resultsTable = NSTableView()
    private let resultsScroll = NSScrollView()

    private let service = FileSearchService()
    private var rows: [ResultRow] = []
    private var searchTask: Task<Void, Never>?
    private var lastQuery: FileSearchQuery?

    private enum ResultRow {
        case file(URL, matchCount: Int)
        case match(FileSearchMatch)
        case info(String)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Find in Files"
        window.setFrameAutosaveName("PlainXSearchInFilesWindow")
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }

        rootPathControl.pathStyle = .standard
        rootPathControl.target = self
        rootPathControl.action = #selector(rootPathChanged)
        rootPathControl.translatesAutoresizingMaskIntoConstraints = false

        findField.placeholderString = "Find"
        includeField.placeholderString = "Include: *.swift;*.json (empty = all text files)"
        excludeField.placeholderString = "Exclude: *.min.js;build/*"
        replaceField.placeholderString = "Replace with (optional)"
        for field in [findField, includeField, excludeField, replaceField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.delegate = self
        }
        findField.sendsSearchStringImmediately = true

        searchButton.target = self
        searchButton.action = #selector(startSearch)
        searchButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelSearch)
        cancelButton.isEnabled = false
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll)
        replaceAllButton.isEnabled = false

        let rootRow = NSStackView(views: [NSTextField(labelWithString: "Folder:"), rootPathControl, searchButton, cancelButton])
        rootRow.orientation = .horizontal
        rootRow.spacing = 8

        let togglesRow = NSStackView(views: [regexToggle, caseToggle, wholeWordToggle, NSView(), replaceField, replaceAllButton])
        togglesRow.orientation = .horizontal
        togglesRow.spacing = 10

        let topStack = NSStackView(views: [rootRow, findField, togglesRow, includeField, excludeField])
        topStack.orientation = .vertical
        topStack.spacing = 6
        topStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topStack.setHuggingPriority(.defaultHigh, for: .vertical)

        resultsTable.headerView = nil
        resultsTable.rowHeight = 20
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.target = self
        resultsTable.doubleAction = #selector(openSelectedResult)
        resultsTable.style = .inset
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.title = "Results"
        resultsTable.addTableColumn(column)
        resultsScroll.documentView = resultsTable
        resultsScroll.hasVerticalScroller = true
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = window.contentView else { return }
        contentView.addSubview(topStack)
        contentView.addSubview(resultsScroll)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            topStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            resultsScroll.topAnchor.constraint(equalTo: topStack.bottomAnchor),
            resultsScroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            resultsScroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            resultsScroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    func present(coordinator: AppCoordinator, root: URL?, in window: MainWindowController?) {
        self.coordinator = coordinator
        if let root {
            rootPathControl.url = root
        } else if rootPathControl.url == nil {
            if let saved = UserDefaults.standard.string(forKey: "search.lastRoot") {
                rootPathControl.url = URL(fileURLWithPath: saved)
            } else if let activeURL = window?.activeTab?.document.url {
                rootPathControl.url = activeURL.deletingLastPathComponent()
            } else {
                rootPathControl.url = FileManager.default.homeDirectoryForCurrentUser
            }
        }
        if let selection = window?.activeEditorTab?.activePane.facade.selectedText(), !selection.isEmpty,
           !selection.contains("\n") {
            findField.stringValue = selection
        }
        showWindow(nil)
        window?.window?.makeKeyAndOrderFront(nil)
        self.window?.makeKey()
        findField.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func rootPathChanged() {}

    @objc private func startSearch() {
        guard let root = rootPathControl.url else {
            statusLabel.stringValue = "Choose a folder to search."
            return
        }
        let pattern = findField.stringValue
        guard !pattern.isEmpty else {
            statusLabel.stringValue = "Enter something to find."
            return
        }
        UserDefaults.standard.set(root.path, forKey: "search.lastRoot")

        let query = FileSearchQuery(
            root: root,
            pattern: pattern,
            isRegex: regexToggle.state == .on,
            caseSensitive: caseToggle.state == .on,
            wholeWord: wholeWordToggle.state == .on,
            includeGlobs: GlobMatcher.split(includeField.stringValue),
            excludeGlobs: GlobMatcher.split(excludeField.stringValue),
            excludedDirectories: coordinator.preferences.searchExcludedDirectories,
            maxResults: coordinator.preferences.searchMaxResults
        )
        lastQuery = query

        rows = []
        resultsTable.reloadData()
        searchButton.isEnabled = false
        cancelButton.isEnabled = true
        replaceAllButton.isEnabled = false
        statusLabel.stringValue = "Searching…"

        let stream = service.search(query)
        searchTask = Task { [weak self] in
            var currentFileRowIndex: Int?
            var totalMatches = 0
            for await event in stream {
                guard let self else { return }
                switch event {
                case .fileStarted(let url):
                    self.rows.append(.file(url, matchCount: 0))
                    currentFileRowIndex = self.rows.count - 1
                    self.resultsTable.insertRows(at: IndexSet(integer: self.rows.count - 1), withAnimation: [])
                case .match(let match):
                    totalMatches += 1
                    self.rows.append(.match(match))
                    self.resultsTable.insertRows(at: IndexSet(integer: self.rows.count - 1), withAnimation: [])
                    if let currentFileRowIndex, case .file(let url, let count) = self.rows[currentFileRowIndex] {
                        self.rows[currentFileRowIndex] = .file(url, matchCount: count + 1)
                        self.resultsTable.reloadData(forRowIndexes: IndexSet(integer: currentFileRowIndex),
                                                     columnIndexes: IndexSet(integer: 0))
                    }
                    self.statusLabel.stringValue = "\(totalMatches) matches…"
                case .fileFinished:
                    break
                case .warning(let message):
                    self.rows.append(.info(message))
                    self.resultsTable.insertRows(at: IndexSet(integer: self.rows.count - 1), withAnimation: [])
                case .finished(let filesScanned, let matchesFound, let wasCancelled):
                    self.searchButton.isEnabled = true
                    self.cancelButton.isEnabled = false
                    self.replaceAllButton.isEnabled = matchesFound > 0 && !replaceField.stringValue.isEmpty
                    self.statusLabel.stringValue = wasCancelled
                        ? "Cancelled after \(matchesFound) matches in \(filesScanned) files."
                        : "\(matchesFound) matches in \(filesScanned) files."
                    self.searchTask = nil
                }
            }
        }
    }

    @objc private func cancelSearch() {
        service.cancel()
        searchTask?.cancel()
        searchTask = nil
        searchButton.isEnabled = true
        cancelButton.isEnabled = false
        statusLabel.stringValue = "Cancelled."
    }

    var matches: [FileSearchMatch] {
        rows.compactMap { row in
            if case .match(let match) = row { return match }
            return nil
        }
    }

    @objc private func openSelectedResult() {
        let row = resultsTable.clickedRow >= 0 ? resultsTable.clickedRow : resultsTable.selectedRow
        guard rows.indices.contains(row), case .match(let match) = rows[row] else { return }
        open(match: match)
    }

    private func open(match: FileSearchMatch) {
        coordinator.open(urls: [match.url], in: nil)
        guard let document = coordinator.findOpenDocument(url: match.url),
              let (window, tab) = coordinator.tab(for: document) else { return }
        window.window?.makeKeyAndOrderFront(nil)
        let facade = tab.activePane.facade
        let lineStart = facade.lineStart(match.lineNumber)
        let caret = min(facade.length, lineStart + match.column)
        let end = min(facade.length, caret + match.matchLength)
        facade.setSelection(anchor: caret, caret: end)
        facade.scrollToLine(match.lineNumber)
        facade.view.window?.makeFirstResponder(facade.view)
        facade.view.window?.makeKey()
    }

    // MARK: - Replace in files

    @objc private func replaceAll() {
        guard let query = lastQuery else { return }
        let replacement = replaceField.stringValue
        let found = matches
        guard !found.isEmpty else { return }

        // Group matches per file for a single read/write per file.
        var byFile: [URL: [FileSearchMatch]] = [:]
        for match in found {
            byFile[match.url, default: []].append(match)
        }
        _ = query

        let alert = NSAlert()
        alert.messageText = "Replace \(found.count) matches in \(byFile.count) files?"
        alert.informativeText = "Files are written atomically. This cannot be undone from PlainX (use your version control system for safety)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace All")
        alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.performReplace(byFile: byFile, replacement: replacement, query: query)
        }
    }

    private func performReplace(byFile: [URL: [FileSearchMatch]], replacement: String, query: FileSearchQuery) {
        statusLabel.stringValue = "Replacing…"
        replaceAllButton.isEnabled = false
        let matcher = LineMatcher(query: query)

        Task.detached(priority: .userInitiated) { [weak self] in
            var changedFiles = 0
            var changedMatches = 0
            var failures: [String] = []

            for (url, _) in byFile {
                if Task.isCancelled { break }
                autoreleasepool {
                    do {
                        let loaded = try FileLoader.load(url: url)
                        var lines = loaded.text.components(separatedBy: "\n")
                        var fileChanged = false
                        for (lineIndex, line) in lines.enumerated() {
                            let lineMatches = matcher.matches(in: line)
                            if lineMatches.isEmpty { continue }
                            let pattern = query.isRegex
                                ? query.pattern
                                : NSRegularExpression.escapedPattern(for: query.pattern)
                            let flags: NSRegularExpression.Options = query.caseSensitive ? [] : [.caseInsensitive]
                            let expression = try? NSRegularExpression(pattern: pattern, options: flags)
                            // Replace only the requested lines, preserving
                            // everything else byte-for-byte.
                            if let expression {
                                let range = NSRange(location: 0, length: (line as NSString).length)
                                let replaced = expression.stringByReplacingMatches(in: line, options: [], range: range,
                                                                                   withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
                                if replaced != line {
                                    lines[lineIndex] = replaced
                                    fileChanged = true
                                    changedMatches += lineMatches.count
                                }
                            }
                        }
                        guard fileChanged else { return }
                        let newText = lines.joined(separator: "\n")
                        _ = try FileSaver.save(
                            text: newText,
                            to: url,
                            encoding: loaded.encoding,
                            lastKnownMetadata: loaded.metadata,
                            checkExternalModification: true,
                            force: false
                        )
                        changedFiles += 1
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                var summary = "Updated \(changedMatches) matches in \(changedFiles) files."
                if !failures.isEmpty {
                    summary += " \(failures.count) file(s) failed."
                }
                self.statusLabel.stringValue = summary
                self.replaceAllButton.isEnabled = true
                if !failures.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "Some files could not be updated"
                    alert.informativeText = failures.prefix(10).joined(separator: "\n")
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                // Reload any open documents that were changed.
                for (url, _) in byFile where changedFiles > 0 {
                    if let document = self.coordinator?.findOpenDocument(url: url),
                       let (_, tab) = self.coordinator?.tab(for: document) {
                        self.coordinator?.reload(document: document, tab: tab)
                    }
                }
            }
        }
    }
}

// MARK: - Table view

extension SearchInFilesPanelController: NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("resultCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            cell.identifier = identifier
            return cell
        }()

        switch rows[row] {
        case .file(let url, let count):
            cell.textField?.stringValue = "\(url.lastPathComponent)  —  \(count) match\(count == 1 ? "" : "es")"
            cell.textField?.font = NSFont.boldSystemFont(ofSize: 12)
            cell.textField?.textColor = .labelColor
            cell.toolTip = url.path
        case .match(let match):
            let preview = match.lineText.trimmingCharacters(in: .whitespaces)
            let truncated = preview.count > 200 ? String(preview.prefix(200)) + "…" : preview
            cell.textField?.stringValue = "\(match.lineNumber + 1):  \(truncated)"
            cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textField?.textColor = .labelColor
            cell.toolTip = "\(match.url.path):\(match.lineNumber + 1)"
        case .info(let message):
            cell.textField?.stringValue = message
            cell.textField?.font = NSFont.systemFont(ofSize: 11)
            cell.textField?.textColor = .secondaryLabelColor
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if rows.indices.contains(row), case .match = rows[row] { return true }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === findField {
            cancelSearch()
        }
    }
}
