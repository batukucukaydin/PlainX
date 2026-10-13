//
//  LargeFileViewController.swift
//  PlainX Editor
//
//  Read-only Large File Mode: toolbar (follow, search, filter), scrollable
//  text viewport, progress, and status summary. The whole file is never
//  loaded into memory.
//

import AppKit

protocol LargeFileViewControllerDelegate: AnyObject {
    func largeFileViewDidRequestOpenNormally(_ controller: LargeFileViewController)
    func largeFileViewDidRequestRevealInFinder(_ controller: LargeFileViewController)
}

final class LargeFileViewController: NSViewController {
    let backing: LargeFileBacking
    weak var delegate: LargeFileViewControllerDelegate?

    let textView: LargeFileTextView
    private let scrollView = NSScrollView()
    private let toolbar = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let followCheckbox = NSButton(checkboxWithTitle: "Follow", target: nil, action: nil)
    private let searchField = NSSearchField()
    private let filterField = NSTextField()
    private let matchLabel = NSTextField(labelWithString: "")
    private let nextMatchButton = NSButton(title: "Next", target: nil, action: nil)
    private let previousMatchButton = NSButton(title: "Previous", target: nil, action: nil)

    private var watcher: FileWatcher?
    private var searchService: StreamingSearch
    private var searchTask: Task<Void, Never>?
    private var matchLines: [Int] = []
    private var currentMatchIndex: Int = -1
    private weak var tabDelegate: DocumentTabControllerDelegate?

    private let theme: EditorTheme

    init(backing: LargeFileBacking, theme: EditorTheme) {
        self.backing = backing
        self.theme = theme
        self.textView = LargeFileTextView(backing: backing, theme: theme)
        self.searchService = StreamingSearch(reader: backing.reader, encoding: backing.encoding)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        watcher?.stop()
        searchService.cancel()
    }

    override func loadView() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false

        buildToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background
        scrollView.documentView = textView

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let statusRow = NSView()
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusRow.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: statusRow.centerYAnchor),
            statusRow.heightAnchor.constraint(equalToConstant: 22),
        ])

        root.addArrangedSubview(toolbar)
        root.addArrangedSubview(scrollView)
        root.addArrangedSubview(statusRow)
        toolbar.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scrollView.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        statusRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        view = root
        updateStatus()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        backing.onIndexProgress = { [weak self] progress in
            guard let self else { return }
            self.progressIndicator.doubleValue = progress
            self.progressIndicator.isHidden = progress >= 1
            self.updateStatus()
            if progress >= 1 {
                self.textView.resetHeightCache()
            }
        }
        backing.onIndexReady = { [weak self] in
            guard let self else { return }
            self.progressIndicator.isHidden = true
            self.textView.resetHeightCache()
            self.updateStatus()
        }
        if !backing.isIndexComplete {
            backing.startIndexing()
        }
        progressIndicator.doubleValue = backing.indexProgress
        progressIndicator.isHidden = backing.isIndexComplete
        startFollowingIfNeeded()
    }

    // MARK: - Toolbar

    private func buildToolbar() {
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        followCheckbox.target = self
        followCheckbox.action = #selector(toggleFollow)
        followCheckbox.state = .off
        followCheckbox.toolTip = "Tail the file: new lines appear automatically when you are at the bottom"

        searchField.placeholderString = "Find in file"
        searchField.target = self
        searchField.action = #selector(runSearch)
        searchField.sendsWholeSearchString = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        filterField.placeholderString = "Filter: ERROR WARN (space separated)"
        filterField.target = self
        filterField.action = #selector(applyFilter)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        filterField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        nextMatchButton.target = self
        nextMatchButton.action = #selector(nextMatch)
        nextMatchButton.bezelStyle = .rounded
        nextMatchButton.controlSize = .small
        nextMatchButton.setAccessibilityLabel("Next search match")

        previousMatchButton.target = self
        previousMatchButton.action = #selector(previousMatch)
        previousMatchButton.bezelStyle = .rounded
        previousMatchButton.controlSize = .small
        previousMatchButton.setAccessibilityLabel("Previous search match")

        matchLabel.font = NSFont.systemFont(ofSize: 11)
        matchLabel.textColor = .secondaryLabelColor

        let openNormally = NSButton(title: "Open Normally…", target: self, action: #selector(openNormally))
        openNormally.bezelStyle = .rounded
        openNormally.controlSize = .small
        openNormally.toolTip = "Open this file in the regular editor (loads it fully into memory)"

        let reveal = NSButton(title: "Reveal in Finder", target: self, action: #selector(revealInFinder))
        reveal.bezelStyle = .rounded
        reveal.controlSize = .small

        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.widthAnchor.constraint(equalToConstant: 90).isActive = true

        toolbar.addArrangedSubview(followCheckbox)
        toolbar.addArrangedSubview(searchField)
        toolbar.addArrangedSubview(previousMatchButton)
        toolbar.addArrangedSubview(nextMatchButton)
        toolbar.addArrangedSubview(matchLabel)
        toolbar.addArrangedSubview(filterField)
        toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(progressIndicator)
        toolbar.addArrangedSubview(openNormally)
        toolbar.addArrangedSubview(reveal)
    }

    // MARK: - Follow

    private func startFollowingIfNeeded() {
        guard followCheckbox.state == .on else { return }
        watcher?.stop()
        let watcher = FileWatcher(url: backing.url)
        watcher.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .appended, .changed:
                let wasAtBottom = self.textView.isAtBottom
                if self.backing.handleAppend() {
                    self.textView.resetHeightCache()
                    if wasAtBottom {
                        self.textView.scrollToBottom()
                    }
                    self.updateStatus()
                } else if self.backing.wasRotatedOrTruncated {
                    self.showRotationBanner()
                }
            case .deleted, .renamed:
                self.backing.markRotated()
                self.showRotationBanner()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    @objc private func toggleFollow() {
        if followCheckbox.state == .on {
            startFollowingIfNeeded()
            if textView.isAtBottom {
                textView.scrollToBottom()
            }
        } else {
            watcher?.stop()
            watcher = nil
        }
        updateStatus()
    }

    private func showRotationBanner() {
        guard let window = view.window?.windowController as? MainWindowController else { return }
        window.showBanner(message: "“\(backing.url.lastPathComponent)” was truncated or rotated on disk.", actions: [
            .init(title: "Reload", handler: { [weak self] in
                guard let self else { return }
                try? self.backing.reloadFromDisk()
                self.backing.startIndexing()
                self.textView.resetHeightCache()
                window.clearBanners()
            }),
            .init(title: "Keep Viewing", handler: { window.clearBanners() }),
        ])
    }

    // MARK: - Search

    @objc private func runSearch() {
        let pattern = searchField.stringValue
        guard !pattern.isEmpty else {
            searchService.cancel()
            searchTask?.cancel()
            textView.searchMatches = [:]
            textView.currentSearchLine = nil
            textView.needsDisplay = true
            matchLabel.stringValue = ""
            return
        }
        searchService.cancel()
        searchTask?.cancel()
        matchLines = []
        currentMatchIndex = -1
        matchLabel.stringValue = "Searching…"
        var query = LargeFileSearchQuery(pattern: pattern)
        query.isRegex = false
        query.caseSensitive = false
        query.maxResults = 20_000

        let stream = searchService.search(query)
        searchTask = Task { [weak self] in
            var matches: [Int: NSRange] = [:]
            for await event in stream {
                guard let self else { return }
                switch event {
                case .match(let match):
                    self.matchLines.append(match.lineNumber)
                    if self.matchLines.count <= 500, let range = match.previewRange, match.lineText.count <= 400 {
                        matches[match.lineNumber] = range
                    }
                case .progress:
                    break
                case .finished(let total, let cancelled, let reachedCap):
                    self.textView.searchMatches = matches
                    self.textView.needsDisplay = true
                    var summary = cancelled ? "Cancelled — \(total) matches so far" : "\(total) matches"
                    if reachedCap { summary += " (result cap reached)" }
                    self.matchLabel.stringValue = summary
                    if self.currentMatchIndex >= 0 {
                        self.jumpToCurrentMatch()
                    }
                case .failed(let message):
                    self.matchLabel.stringValue = message
                }
            }
        }
    }

    @objc private func nextMatch() {
        guard !matchLines.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchLines.count
        jumpToCurrentMatch()
    }

    @objc private func previousMatch() {
        guard !matchLines.isEmpty else { return }
        currentMatchIndex = currentMatchIndex <= 0 ? matchLines.count - 1 : currentMatchIndex - 1
        jumpToCurrentMatch()
    }

    private func jumpToCurrentMatch() {
        guard matchLines.indices.contains(currentMatchIndex) else { return }
        let line = matchLines[currentMatchIndex]
        textView.currentSearchLine = line
        textView.filteredLines = nil
        textView.scrollToLine(line)
        textView.needsDisplay = true
        matchLabel.stringValue = "\(currentMatchIndex + 1) of \(matchLines.count)"
    }

    // MARK: - Filter

    @objc private func applyFilter() {
        let tokens = filterField.stringValue
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map { $0.uppercased() }
        guard !tokens.isEmpty else {
            textView.filteredLines = nil
            textView.resetHeightCache()
            updateStatus()
            return
        }
        statusLabel.stringValue = "Filtering…"
        let backing = self.backing
        let lineCount = backing.lineCount
        Task.detached(priority: .userInitiated) { [weak self] in
            var matching: [Int] = []
            let cap = 500_000
            for line in 0..<lineCount {
                if Task.isCancelled { break }
                let text = backing.lineText(at: line).uppercased()
                if tokens.contains(where: { text.contains($0) }) {
                    matching.append(line)
                    if matching.count >= cap { break }
                }
                if line % 20_000 == 0 {
                    await MainActor.run { [weak self] in
                        self?.statusLabel.stringValue = "Filtering… \(line / max(1, lineCount / 100))%"
                    }
                }
            }
            let result = matching
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.textView.filteredLines = result
                self.textView.resetHeightCache()
                self.updateStatus()
            }
        }
    }

    // MARK: - Actions

    @objc private func openNormally() {
        delegate?.largeFileViewDidRequestOpenNormally(self)
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([backing.url])
    }

    // MARK: - Status

    func updateStatus() {
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        let sizeText = sizeFormatter.string(fromByteCount: Int64(backing.fileSize))
        let lines = backing.isIndexReady ? "\(backing.lineCount) lines" : "indexing \(Int(backing.indexProgress * 100))%"
        var summary = "Large File Mode — read-only · \(backing.encoding.displayName) · \(sizeText) · \(lines)"
        if textView.filteredLines != nil {
            summary += " · filtered to \(textView.filteredLines?.count ?? 0) lines"
        }
        if followCheckbox.state == .on {
            summary += " · following"
        }
        statusLabel.stringValue = summary
    }

    /// Re-reads the file from disk (used by File → Reload from Disk).
    func reloadFromDisk() {
        searchService.cancel()
        searchTask?.cancel()
        matchLines = []
        currentMatchIndex = -1
        matchLabel.stringValue = ""
        textView.searchMatches = [:]
        textView.currentSearchLine = nil
        textView.filteredLines = nil
        filterField.stringValue = ""
        do {
            try backing.reloadFromDisk()
        } catch {
            Log.largeFile.error("Large file reload failed: \(error.localizedDescription, privacy: .public)")
        }
        backing.startIndexing()
        progressIndicator.doubleValue = 0
        progressIndicator.isHidden = false
        textView.resetHeightCache()
        updateStatus()
    }

    func applyTheme(_ theme: EditorTheme) {
        textView.theme = theme
        scrollView.backgroundColor = theme.background
        textView.needsDisplay = true
    }

    func statusSnapshot() -> StatusBarView.State {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return StatusBarView.State(
            encodingName: backing.encoding.displayName,
            encodingTooltip: "Detected by Large File Mode",
            eolName: "—",
            eolTooltip: "",
            languageName: "Plain Text",
            languageTooltip: "Large File Mode is read-only",
            indentationName: "",
            line: 0,
            column: 0,
            selectionSummary: textView.selectedLineRange.map { range in
                range.lowerBound == range.upperBound
                    ? "Line \(range.lowerBound + 1)"
                    : "\(range.upperBound - range.lowerBound + 1) lines"
            } ?? "",
            fileSizeSummary: formatter.string(fromByteCount: Int64(backing.fileSize)),
            modeSummary: "Large File Mode"
        )
    }

    func focusContent() {
        view.window?.makeFirstResponder(textView)
    }
}
