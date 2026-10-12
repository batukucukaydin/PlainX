//
//  FindBarController.swift
//  PlainX Editor
//
//  Inline find/replace bar for the current document: literal or regex,
//  case/whole-word toggles, wrap, selection scope, match highlighting,
//  and Find All results.
//

import AppKit

final class FindBarController: NSObject {
    enum Mode {
        case find
        case replace
    }

    private(set) var mode: Mode
    private weak var tab: DocumentTabController?
    private let container = NSView()
    private let resultsPanel = NSView()
    private let resultsTable = NSTableView()
    private let resultsScroll = NSScrollView()

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let caseButton = NSButton()
    private let wordButton = NSButton()
    private let regexButton = NSButton()
    private let inSelectionButton = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let findAllButton = NSButton()
    private let closeButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "")
    private let replaceRow = NSStackView()
    private let resultsRow = NSView()

    private var results: [NSRange] = []
    private var resultsVisible = false
    private var lastSearchError: String?
    private var heightConstraint: NSLayoutConstraint?

    init(tab: DocumentTabController, mode: Mode) {
        self.tab = tab
        self.mode = mode
        super.init()
        buildUI()
    }

    var view: NSView { container }

    // MARK: - UI

    private func buildUI() {
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        findField.placeholderString = "Find"
        findField.translatesAutoresizingMaskIntoConstraints = false
        findField.delegate = self
        findField.sendsWholeSearchString = false
        findField.sendsSearchStringImmediately = true
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        replaceField.placeholderString = "Replace with"
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.delegate = self
        replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        configure(toggle: caseButton, title: "Aa", tooltip: "Match case")
        configure(toggle: wordButton, title: "\\b", tooltip: "Whole word")
        configure(toggle: regexButton, title: ".*", tooltip: "Regular expression")
        configure(toggle: inSelectionButton, title: "⌷", tooltip: "Search inside the current selection only")

        previousButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")
        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")
        for button in [previousButton, nextButton] {
            button.bezelStyle = .recessed
            button.isBordered = false
            button.target = self
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        previousButton.action = #selector(findPrevious)
        nextButton.action = #selector(findNext)

        replaceButton.title = "Replace"
        replaceButton.bezelStyle = .rounded
        replaceButton.controlSize = .small
        replaceButton.target = self
        replaceButton.action = #selector(replaceCurrent)

        replaceAllButton.title = "Replace All"
        replaceAllButton.bezelStyle = .rounded
        replaceAllButton.controlSize = .small
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll)

        findAllButton.title = "Find All"
        findAllButton.bezelStyle = .rounded
        findAllButton.controlSize = .small
        findAllButton.target = self
        findAllButton.action = #selector(findAllMatches)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close find bar")
        closeButton.bezelStyle = .recessed
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(close)

        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let findRow = NSStackView(views: [
            NSTextField(labelWithString: "Find:"), findField,
            countLabel, previousButton, nextButton,
            caseButton, wordButton, regexButton, inSelectionButton,
            findAllButton, closeButton,
        ])
        findRow.orientation = .horizontal
        findRow.spacing = 6
        findRow.translatesAutoresizingMaskIntoConstraints = false

        replaceRow.setViews([
            NSTextField(labelWithString: "Replace:"), replaceField,
            replaceButton, replaceAllButton, NSView(),
        ], in: .leading)
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 6
        replaceRow.translatesAutoresizingMaskIntoConstraints = false

        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.hasVerticalScroller = true
        resultsScroll.drawsBackground = false
        resultsTable.headerView = nil
        resultsTable.rowHeight = 18
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.target = self
        resultsTable.doubleAction = #selector(openResult)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("match"))
        resultsTable.addTableColumn(column)
        resultsScroll.documentView = resultsTable

        container.addSubview(separator)
        container.addSubview(findRow)
        container.addSubview(replaceRow)
        container.addSubview(resultsScroll)

        resultsScroll.isHidden = true
        replaceRow.isHidden = mode == .find

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: container.topAnchor),

            findRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            findRow.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -10),
            findRow.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),

            replaceRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            replaceRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            replaceRow.topAnchor.constraint(equalTo: findRow.bottomAnchor, constant: 4),

            resultsScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resultsScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            resultsScroll.topAnchor.constraint(equalTo: replaceRow.bottomAnchor, constant: 4),
            resultsScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        updateHeight()
    }

    private func configure(toggle: NSButton, title: String, tooltip: String) {
        toggle.title = title
        toggle.bezelStyle = .recessed
        toggle.setButtonType(.pushOnPushOff)
        toggle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        toggle.toolTip = tooltip
        toggle.target = self
        toggle.action = #selector(searchOptionsChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.widthAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func updateHeight() {
        var height: CGFloat = 34
        if mode == .replace { height += 26 }
        if resultsVisible { height += 150 }
        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let constraint = container.heightAnchor.constraint(equalToConstant: height)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }

    // MARK: - Presentation

    func focus() {
        container.window?.makeFirstResponder(findField)
        if let selection = tab?.activePane.facade.selectedText(), !selection.isEmpty, !selection.contains("\n") {
            findField.stringValue = selection
        }
        applyMode()
        performSearch(advance: false)
    }

    func useSelectionFromEditor() {
        if let selection = tab?.activePane.facade.selectedText(), !selection.isEmpty, !selection.contains("\n") {
            findField.stringValue = selection
            performSearch(advance: false)
        }
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        replaceRow.isHidden = newMode == .find
        updateHeight()
        if newMode == .replace {
            container.window?.makeFirstResponder(replaceField)
        }
    }

    private func applyMode() {
        replaceRow.isHidden = mode == .find
        updateHeight()
    }

    @objc private func close() {
        tab?.hideFindBar()
    }

    // MARK: - Searching

    private var options: DocumentSearchOptions {
        var options = DocumentSearchOptions()
        options.caseSensitive = caseButton.state == .on
        options.wholeWord = wordButton.state == .on
        options.regex = regexButton.state == .on
        options.inSelection = inSelectionButton.state == .on
        options.needle = findField.stringValue
        return options
    }

    @objc private func searchOptionsChanged() {
        performSearch(advance: false)
    }

    func performSearch(advance: Bool) {
        guard let pane = tab?.activePane else { return }
        let options = options
        lastSearchError = nil
        guard !options.needle.isEmpty else {
            pane.facade.clearIndicators(.searchMatch)
            pane.facade.clearIndicators(.currentMatch)
            countLabel.stringValue = ""
            results = []
            resultsTable.reloadData()
            return
        }
        let result = DocumentSearchService.shared.search(in: pane, options: options, advance: advance)
        if let error = result.errorMessage {
            lastSearchError = error
            countLabel.stringValue = error
            countLabel.textColor = .systemRed
            return
        }
        countLabel.textColor = .secondaryLabelColor
        results = result.matches
        let current = result.currentMatchIndex
        if results.isEmpty {
            countLabel.stringValue = "No results"
        } else if let current {
            countLabel.stringValue = "\(current + 1) of \(results.count)"
        } else {
            countLabel.stringValue = "\(results.count) matches"
        }
        if resultsVisible {
            resultsTable.reloadData()
        }
    }

    @objc func findNext() {
        performSearch(advance: true)
    }

    @objc func findPrevious() {
        performSearch(advance: true)
    }

    @objc private func findAllMatches() {
        guard let pane = tab?.activePane else { return }
        let options = options
        guard !options.needle.isEmpty else { return }
        let result = DocumentSearchService.shared.findAll(in: pane, options: options)
        results = result.matches
        countLabel.stringValue = result.errorMessage ?? "\(result.matches.count) matches"
        resultsVisible = true
        resultsScroll.isHidden = false
        resultsTable.reloadData()
        updateHeight()
    }

    @objc private func openResult() {
        if let pane = tab?.activePane, results.indices.contains(resultsTable.clickedRow) {
            let range = results[resultsTable.clickedRow]
            pane.facade.setSelection(anchor: range.location, caret: range.upperBound)
            pane.facade.scrollCaret()
        }
    }

    @objc private func replaceCurrent() {
        guard let pane = tab?.activePane else { return }
        let options = options
        guard !options.needle.isEmpty else { return }
        let replacement = replaceField.stringValue
        DocumentSearchService.shared.replaceCurrent(in: pane, options: options, replacement: replacement)
        performSearch(advance: true)
        tab?.markDirtyIfNeeded()
    }

    @objc private func replaceAll() {
        guard let pane = tab?.activePane else { return }
        let options = options
        guard !options.needle.isEmpty else { return }
        let replacement = replaceField.stringValue
        let replaced = DocumentSearchService.shared.replaceAll(in: pane, options: options, replacement: replacement)
        countLabel.stringValue = replaced == 0 ? "No results" : "Replaced \(replaced) match\(replaced == 1 ? "" : "es")"
        if replaced > 0 {
            tab?.markDirtyIfNeeded()
        }
        performSearch(advance: false)
    }
}

// MARK: - Field delegates

extension FindBarController: NSSearchFieldDelegate, NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSView) === findField {
            performSearch(advance: false)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === findField {
                performSearch(advance: true)
            } else if control === replaceField {
                replaceCurrent()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            close()
            return true
        }
        return false
    }
}

// MARK: - Results table

extension FindBarController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let pane = tab?.activePane, results.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("matchCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            cell.identifier = identifier
            return cell
        }()
        let range = results[row]
        let line = pane.facade.line(from: range.location)
        let column = pane.facade.column(of: range.location)
        let lineText = pane.facade.lineText(line).trimmingCharacters(in: .whitespaces)
        let preview = lineText.count > 120 ? String(lineText.prefix(120)) + "…" : lineText
        cell.textField?.stringValue = "\(line + 1):\(column + 1)  \(preview)"
        return cell
    }
}

// MARK: - Document search service

struct DocumentSearchOptions {
    var needle: String = ""
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var regex: Bool = false
    var inSelection: Bool = false
    var wrap: Bool = true
}

struct DocumentSearchResult {
    var matches: [NSRange] = []
    var currentMatchIndex: Int?
    var errorMessage: String?
}

/// Search within one document using Scintilla's search engine. UI-free and
/// independently testable for range mapping correctness.
final class DocumentSearchService {
    static let shared = DocumentSearchService()

    static let maximumHighlightedMatches = 20_000

    private func searchBounds(_ pane: EditorPaneController, options: DocumentSearchOptions) -> (Int, Int) {
        if options.inSelection {
            let selection = pane.facade.mainSelection
            if !selection.isEmpty {
                return (selection.lowerBound, selection.upperBound)
            }
        }
        return (0, pane.facade.length)
    }

    func findAll(in pane: EditorPaneController, options: DocumentSearchOptions) -> DocumentSearchResult {
        var result = DocumentSearchResult()
        guard !options.needle.isEmpty else { return result }
        let facade = pane.facade
        facade.setSearchFlags(caseSensitive: options.caseSensitive,
                              wholeWord: options.wholeWord, regex: options.regex)
        let (lower, upper) = searchBounds(pane, options: options)
        var position = lower
        var matches: [NSRange] = []
        var expressionError: String?
        while position <= upper, matches.count < Self.maximumHighlightedMatches {
            guard let found = facade.searchInTarget(options.needle, from: position, to: upper) else {
                if options.regex, expressionError == nil {
                    // Scintilla returns -1 for both "no match" and invalid patterns.
                    expressionError = validateRegex(options.needle, caseSensitive: options.caseSensitive)
                }
                break
            }
            if found.length == 0 {
                position = found.location + 1
                continue
            }
            matches.append(found)
            position = found.upperBound
        }
        result.matches = matches
        result.errorMessage = expressionError
        return result
    }

    func search(in pane: EditorPaneController, options: DocumentSearchOptions, advance: Bool) -> DocumentSearchResult {
        var result = DocumentSearchResult()
        guard !options.needle.isEmpty else { return result }
        let facade = pane.facade
        facade.setSearchFlags(caseSensitive: options.caseSensitive,
                              wholeWord: options.wholeWord, regex: options.regex)

        let all = findAll(in: pane, options: options)
        result.errorMessage = all.errorMessage
        if all.errorMessage != nil {
            facade.clearIndicators(.searchMatch)
            facade.clearIndicators(.currentMatch)
            return result
        }
        result.matches = all.matches

        // Highlight all matches (bounded), current match distinctly.
        facade.clearIndicators(.searchMatch)
        facade.clearIndicators(.currentMatch)
        for range in all.matches.prefix(Self.maximumHighlightedMatches) {
            facade.addIndicator(.searchMatch, range: range)
        }

        var currentIndex: Int?
        let caret = facade.currentPosition
        if advance {
            let selection = facade.mainSelection
            var found: NSRange?
            if selection.isEmpty {
                // Prefer the match the caret is already inside.
                found = all.matches.first { $0.location <= caret && caret < $0.upperBound }
                    ?? all.matches.first { $0.location > caret }
            } else {
                found = all.matches.first { $0.location >= selection.upperBound }
                    ?? all.matches.first { $0.location > selection.lowerBound }
            }
            if found == nil, options.wrap {
                found = all.matches.first
            }
            if let found {
                facade.setSelection(anchor: found.location, caret: found.upperBound)
                facade.scrollCaret()
                currentIndex = all.matches.firstIndex(of: found)
            }
        } else {
            currentIndex = all.matches.firstIndex { $0.contains(caret) || $0.location == caret }
        }
        if let currentIndex, all.matches.indices.contains(currentIndex) {
            facade.addIndicator(.currentMatch, range: all.matches[currentIndex])
        }
        result.currentMatchIndex = currentIndex
        return result
    }

    func replaceCurrent(in pane: EditorPaneController, options: DocumentSearchOptions, replacement: String) {
        let facade = pane.facade
        facade.setSearchFlags(caseSensitive: options.caseSensitive,
                              wholeWord: options.wholeWord, regex: options.regex)
        facade.beginUndoAction()
        defer { facade.endUndoAction() }
        let selection = facade.mainSelection
        if !selection.isEmpty {
            let selected = facade.text(inRange: NSRange(location: selection.lowerBound, length: selection.length))
            if selectedMatches(selected, options: options, regex: options.regex) {
                facade.setSelection(anchor: selection.lowerBound, caret: selection.upperBound)
                facade.replaceTarget(with: replacement, regex: options.regex)
                return
            }
        }
        let (lower, upper) = searchBounds(pane, options: options)
        let from = selection.isEmpty ? facade.currentPosition : selection.upperBound
        if let found = facade.searchInTarget(options.needle, from: from, to: upper) {
            facade.replaceTarget(with: replacement, regex: options.regex)
            _ = found
        } else if options.wrap, lower != upper, let found = facade.searchInTarget(options.needle, from: lower, to: upper) {
            facade.replaceTarget(with: replacement, regex: options.regex)
            _ = found
        }
    }

    @discardableResult
    func replaceAll(in pane: EditorPaneController, options: DocumentSearchOptions, replacement: String) -> Int {
        let facade = pane.facade
        facade.setSearchFlags(caseSensitive: options.caseSensitive,
                              wholeWord: options.wholeWord, regex: options.regex)
        let (lower, upper) = searchBounds(pane, options: options)
        var position = lower
        var count = 0
        facade.beginUndoAction()
        defer {
            facade.endUndoAction()
            facade.clearIndicators(.searchMatch)
            facade.clearIndicators(.currentMatch)
        }
        while position <= upper {
            guard let found = facade.searchInTarget(options.needle, from: position, to: upper) else { break }
            if found.length == 0 {
                position = found.location + 1
                continue
            }
            facade.replaceTarget(with: replacement, regex: options.regex)
            count += 1
            let replacedLength = (options.regex
                ? (facade.text(inRange: NSRange(location: facade.targetStart,
                                                length: facade.targetEnd - facade.targetStart)).utf8.count)
                : replacement.utf8.count)
            position = facade.targetStart + replacedLength
            if found.length == 0 && replacement.isEmpty { position += 1 }
            if count > 500_000 { break }
        }
        return count
    }

    private func selectedMatches(_ selected: String, options: DocumentSearchOptions, regex: Bool) -> Bool {
        if regex {
            var pattern = options.needle
            if options.wholeWord { pattern = "\\b(?:\(pattern))\\b" }
            var flags: NSRegularExpression.Options = []
            if !options.caseSensitive { flags.insert(.caseInsensitive) }
            guard let expression = try? NSRegularExpression(pattern: pattern, options: flags) else { return false }
            let range = NSRange(location: 0, length: selected.utf16.count)
            let matches = expression.matches(in: selected, options: [.anchored], range: range)
            return matches.first?.range == range
        }
        if options.caseSensitive {
            return selected == options.needle
        }
        return selected.caseInsensitiveCompare(options.needle) == .orderedSame
    }

    private func validateRegex(_ pattern: String, caseSensitive: Bool) -> String? {
        var flags: NSRegularExpression.Options = []
        if !caseSensitive { flags.insert(.caseInsensitive) }
        do {
            _ = try NSRegularExpression(pattern: pattern, options: flags)
            return nil
        } catch {
            return "Invalid regular expression: \(error.localizedDescription)"
        }
    }
}
