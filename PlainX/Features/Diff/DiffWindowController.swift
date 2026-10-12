//
//  DiffWindowController.swift
//  PlainX Editor
//
//  Side-by-side native text compare. Read-only Scintilla panes with
//  line-level background markers, synchronized scrolling, and change
//  navigation.
//

import AppKit

final class DiffWindowController: NSWindowController {
    private enum Side {
        case left
        case right
    }

    private let leftPane: EditorPaneController
    private let rightPane: EditorPaneController
    private var result: DiffResult
    private unowned let coordinator: AppCoordinator
    private var currentHunkIndex = -1
    private var isSyncingScroll = false
    private var ignoreWhitespace: Bool

    private let summaryLabel = NSTextField(labelWithString: "")
    private var ignoreWhitespaceButton: NSButton!

    static func present(leftTitle: String, leftText: String, rightTitle: String, rightText: String,
                        coordinator: AppCoordinator, in window: MainWindowController?) {
        DiffWindowController(leftTitle: leftTitle, leftText: leftText,
                             rightTitle: rightTitle, rightText: rightText,
                             coordinator: coordinator).showWindow(nil)
    }

    init(leftTitle: String, leftText: String, rightTitle: String, rightText: String,
         coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.ignoreWhitespace = false
        self.result = DiffService.diff(left: leftText, right: rightText, options: .init(ignoreWhitespace: false))
        let theme = coordinator.preferences.resolvedTheme(appearance: nil)
        self.leftPane = EditorPaneController(theme: theme)
        self.rightPane = EditorPaneController(theme: theme)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Compare: \(leftTitle) ↔ \(rightTitle)"
        window.setFrameAutosaveName("PlainXDiffWindow")
        super.init(window: window)

        setupUI(leftTitle: leftTitle, rightTitle: rightTitle)
        loadAndMark(leftText: leftText, rightText: rightText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupUI(leftTitle: String, rightTitle: String) {
        guard let window else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            contentView.addSubview(root)
            NSLayoutConstraint.activate([
                root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                root.topAnchor.constraint(equalTo: contentView.topAnchor),
                root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 10
        toolbar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)

        let previousButton = NSButton(title: "◀ Previous", target: self, action: #selector(previousChange))
        let nextButton = NSButton(title: "Next ▶", target: self, action: #selector(nextChange))
        previousButton.bezelStyle = .rounded
        nextButton.bezelStyle = .rounded
        previousButton.setAccessibilityLabel("Previous change")
        nextButton.setAccessibilityLabel("Next change")

        ignoreWhitespaceButton = NSButton(checkboxWithTitle: "Ignore whitespace", target: self, action: #selector(toggleIgnoreWhitespace))
        ignoreWhitespaceButton.state = .off

        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor

        toolbar.addArrangedSubview(previousButton)
        toolbar.addArrangedSubview(nextButton)
        toolbar.addArrangedSubview(ignoreWhitespaceButton)
        toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(summaryLabel)
        root.addArrangedSubview(toolbar)
        toolbar.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        let leftHeader = makeHeader(title: leftTitle)
        let rightHeader = makeHeader(title: rightTitle)
        let leftColumn = NSStackView(views: [leftHeader, leftPane.view])
        leftColumn.orientation = .vertical
        leftColumn.spacing = 0
        let rightColumn = NSStackView(views: [rightHeader, rightPane.view])
        rightColumn.orientation = .vertical
        rightColumn.spacing = 0
        split.addArrangedSubview(leftColumn)
        split.addArrangedSubview(rightColumn)
        root.addArrangedSubview(split)
        split.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        split.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        leftPane.facade.setReadOnly(true)
        rightPane.facade.setReadOnly(true)
        leftPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        rightPane.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        // Synchronized scrolling.
        leftPane.facade.view.scrollView?.contentView.postsBoundsChangedNotifications = true
        rightPane.facade.view.scrollView?.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(leftScrolled),
                                               name: NSView.boundsDidChangeNotification,
                                               object: leftPane.facade.view.scrollView?.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(rightScrolled),
                                               name: NSView.boundsDidChangeNotification,
                                               object: rightPane.facade.view.scrollView?.contentView)
        updateSummary()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func makeHeader(title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        let container = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func loadAndMark(leftText: String, rightText: String) {
        let language = LanguageRegistry.plainText
        leftPane.facade.setLanguage(language)
        rightPane.facade.setLanguage(language)
        leftPane.facade.text = leftText
        rightPane.facade.text = rightText
        leftPane.facade.setReadOnly(true)
        rightPane.facade.setReadOnly(true)
        applyMarkers()
    }

    private func applyMarkers() {
        let theme = coordinator.preferences.resolvedTheme(appearance: window?.effectiveAppearance)
        for pane in [leftPane, rightPane] {
            pane.facade.clearIndicators(.diffAdded)
            pane.facade.clearIndicators(.diffRemoved)
            pane.facade.clearIndicators(.diffChanged)
        }
        _ = theme

        for (line, kind) in result.leftLineKinds.enumerated() where kind != .equal {
            guard line < leftPane.facade.lineCount else { continue }
            let start = leftPane.facade.lineStart(line)
            let length = max(1, leftPane.facade.lineLength(line))
            let range = NSRange(location: start, length: length)
            switch kind {
            case .inserted: leftPane.facade.addIndicator(.diffAdded, range: range)
            case .deleted: leftPane.facade.addIndicator(.diffRemoved, range: range)
            case .changed: leftPane.facade.addIndicator(.diffChanged, range: range)
            case .equal: break
            }
        }
        for (line, kind) in result.rightLineKinds.enumerated() where kind != .equal {
            guard line < rightPane.facade.lineCount else { continue }
            let start = rightPane.facade.lineStart(line)
            let length = max(1, rightPane.facade.lineLength(line))
            let range = NSRange(location: start, length: length)
            switch kind {
            case .inserted: rightPane.facade.addIndicator(.diffAdded, range: range)
            case .deleted: rightPane.facade.addIndicator(.diffRemoved, range: range)
            case .changed: rightPane.facade.addIndicator(.diffChanged, range: range)
            case .equal: break
            }
        }
        updateSummary()
    }

    private func updateSummary() {
        let hunks = result.hunks.count
        summaryLabel.stringValue = hunks == 0
            ? "Files are identical"
            : "\(hunks) change\(hunks == 1 ? "" : "s")"
    }

    @objc private func nextChange() {
        guard !result.hunks.isEmpty else { return }
        currentHunkIndex = (currentHunkIndex + 1) % result.hunks.count
        scrollToCurrentHunk()
    }

    @objc private func previousChange() {
        guard !result.hunks.isEmpty else { return }
        currentHunkIndex = currentHunkIndex <= 0 ? result.hunks.count - 1 : currentHunkIndex - 1
        scrollToCurrentHunk()
    }

    private func scrollToCurrentHunk() {
        guard result.hunks.indices.contains(currentHunkIndex) else { return }
        let hunk = result.hunks[currentHunkIndex]
        let leftLine = hunk.leftLineRange.lowerBound
        let rightLine = hunk.rightLineRange.lowerBound
        leftPane.facade.scrollToLine(leftLine)
        rightPane.facade.scrollToLine(rightLine)
        isSyncingScroll = true
        leftPane.facade.setScrollState(firstVisibleLine: max(0, leftLine - 3), xOffset: 0)
        rightPane.facade.setScrollState(firstVisibleLine: max(0, rightLine - 3), xOffset: 0)
        isSyncingScroll = false
    }

    @objc private func toggleIgnoreWhitespace() {
        ignoreWhitespace = ignoreWhitespaceButton.state == .on
        result = DiffService.diff(left: leftPane.facade.text, right: rightPane.facade.text,
                                  options: .init(ignoreWhitespace: ignoreWhitespace))
        currentHunkIndex = -1
        applyMarkers()
    }

    @objc private func leftScrolled() {
        guard !isSyncingScroll else { return }
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        mirrorScroll(from: leftPane, to: rightPane)
    }

    @objc private func rightScrolled() {
        guard !isSyncingScroll else { return }
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        mirrorScroll(from: rightPane, to: leftPane)
    }

    private func mirrorScroll(from source: EditorPaneController, to target: EditorPaneController) {
        let sourceLines = max(1, source.facade.lineCount)
        let targetLines = max(1, target.facade.lineCount)
        let fraction = Double(source.facade.firstVisibleLine) / Double(sourceLines)
        let targetLine = Int(fraction * Double(targetLines))
        target.facade.setScrollState(firstVisibleLine: targetLine, xOffset: source.facade.xOffset)
    }
}
