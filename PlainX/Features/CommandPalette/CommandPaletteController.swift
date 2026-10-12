//
//  CommandPaletteController.swift
//  PlainX Editor
//
//  Command-Shift-P palette: fuzzy search over every registered command with
//  its shortcut shown inline.
//

import AppKit

final class CommandPaletteController: NSWindowController {
    static let shared = CommandPaletteController()

    private unowned var coordinator: AppCoordinator?
    private weak var targetWindow: MainWindowController?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    private struct Entry {
        let command: Command
        let score: Int
        let matchedIndices: [Int]
    }

    private var entries: [Entry] = []

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 400),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        super.init(window: panel)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Type a command…"
        searchField.delegate = self
        searchField.font = NSFont.systemFont(ofSize: 16)

        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(runSelected)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        tableView.addTableColumn(column)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false

        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 36),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    func show(coordinator: AppCoordinator, window: MainWindowController?) {
        self.coordinator = coordinator
        self.targetWindow = window
        let context = CommandContext(coordinator: coordinator, window: window)
        let all = CommandRegistry.shared.commands
            .filter { $0.isEnabled(context) }
            .map { Entry(command: $0, score: 0, matchedIndices: []) }
        entries = all.sorted { $0.command.category < $1.command.category }
        searchField.stringValue = ""
        tableView.reloadData()
        if !entries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        positionWindow(relativeTo: window?.window)
        showWindow(nil)
        window?.window?.addChildWindow(self.window!, ordered: .above)
        self.window?.makeKeyAndOrderFront(nil)
        self.window?.makeFirstResponder(searchField)
    }

    private func positionWindow(relativeTo parent: NSWindow?) {
        guard let parent, let window else { return }
        let parentFrame = parent.frame
        let size = window.frame.size
        let origin = NSPoint(x: parentFrame.midX - size.width / 2,
                             y: parentFrame.maxY - size.height - 140)
        window.setFrameOrigin(origin)
    }

    override func close() {
        if let window, let parent = window.parent {
            parent.removeChildWindow(window)
        }
        super.close()
    }

    private func updateEntries(query: String) {
        guard let coordinator, let targetWindow else { return }
        let context = CommandContext(coordinator: coordinator, window: targetWindow)
        let commands = CommandRegistry.shared.commands.filter { $0.isEnabled(context) }
        if query.isEmpty {
            entries = commands
                .sorted { ($0.category, $0.title) < ($1.category, $1.title) }
                .map { Entry(command: $0, score: 0, matchedIndices: []) }
        } else {
            var scored: [Entry] = []
            for command in commands {
                let haystack = "\(command.category) \(command.title) \(command.keywords.joined(separator: " "))"
                if let match = FuzzyMatcher.match(query: query, candidate: haystack) {
                    scored.append(Entry(command: command, score: match.score, matchedIndices: match.matchedIndices))
                }
            }
            entries = scored.sorted {
                $0.score != $1.score ? $0.score > $1.score : $0.command.title < $1.command.title
            }
        }
        tableView.reloadData()
        if !entries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    @objc private func runSelected() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : tableView.clickedRow
        guard entries.indices.contains(row) else { return }
        let command = entries[row].command
        close()
        let context = CommandContext(coordinator: coordinator, window: targetWindow)
        coordinator?.macroEngine.recordCommand(command.id)
        CommandRegistry.shared.perform(command.id, context: context)
    }
}

extension CommandPaletteController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateEntries(query: searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            runSelected()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        let current = tableView.selectedRow
        let next = max(0, min(entries.count - 1, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

extension CommandPaletteController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let identifier = NSUserInterfaceItemIdentifier("commandCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? CommandCellView ?? {
            let cell = CommandCellView()
            cell.identifier = identifier
            return cell
        }()
        cell.configure(command: entry.command, matchedIndices: entry.matchedIndices)
        return cell
    }
}

final class CommandCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let categoryLabel = NSTextField(labelWithString: "")
    private let highlight = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        highlight.layer?.cornerRadius = 4
        highlight.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryLabel.font = NSFont.systemFont(ofSize: 11)
        categoryLabel.textColor = .secondaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = .tertiaryLabelColor

        addSubview(highlight)
        addSubview(titleLabel)
        addSubview(categoryLabel)
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            categoryLabel.leadingAnchor.constraint(equalTo: highlight.leadingAnchor, constant: 8),
            categoryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            categoryLabel.widthAnchor.constraint(equalToConstant: 86),

            titleLabel.leadingAnchor.constraint(equalTo: categoryLabel.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            shortcutLabel.trailingAnchor.constraint(equalTo: highlight.trailingAnchor, constant: -8),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(command: Command, matchedIndices: [Int]) {
        categoryLabel.stringValue = command.category
        shortcutLabel.stringValue = command.keyBinding?.displayString ?? ""
        highlight.isHidden = true
        titleLabel.stringValue = command.title
        titleLabel.textColor = .labelColor
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            highlight.isHidden = backgroundStyle != .emphasized
        }
    }
}
