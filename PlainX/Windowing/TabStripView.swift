//
//  TabStripView.swift
//  PlainX Editor
//
//  macOS-native document tab strip: scrollable, reorderable, with dirty
//  indicators, pinning, middle-click close, and a context menu.
//

import AppKit

protocol TabStripViewDelegate: AnyObject {
    func tabStripDidSelectTab(_ tabID: UUID)
    func tabStripDidRequestClose(_ tabID: UUID)
    func tabStripDidRequestCloseOthers(_ tabID: UUID)
    func tabStripDidRequestCloseToRight(_ tabID: UUID)
    func tabStripDidRequestCloseAll()
    func tabStripDidRequestTogglePin(_ tabID: UUID)
    func tabStripDidRequestRevealInFinder(_ tabID: UUID)
    func tabStripDidRequestCopyPath(_ tabID: UUID)
    func tabStripDidMoveTab(_ tabID: UUID, toIndex index: Int)
    func tabStripDidRequestNewDocument()
    func tabStripDidRequestDuplicateInNewTab(_ tabID: UUID)
}

final class TabStripView: NSView {
    struct TabItem {
        let id: UUID
        var title: String
        var isDirty: Bool
        var isPinned: Bool
        var tooltip: String
        var hasExternalChange: Bool
    }

    weak var delegate: TabStripViewDelegate?
    private(set) var items: [TabItem] = []
    var selectedID: UUID?

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let newTabButton = NSButton()
    private var itemViews: [UUID: TabItemView] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        scrollView.documentView = stackView

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.bezelStyle = .recessed
        newTabButton.isBordered = false
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.toolTip = "New Tab (⌘N)"

        addSubview(scrollView)
        addSubview(newTabButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            newTabButton.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 2),
            newTabButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 24),
            newTabButton.heightAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    func update(items: [TabItem], selectedID: UUID?) {
        self.items = items
        self.selectedID = selectedID

        let existingIDs = Set(itemViews.keys)
        let newIDs = Set(items.map(\.id))

        for removed in existingIDs.subtracting(newIDs) {
            if let view = itemViews.removeValue(forKey: removed) {
                stackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }

        for (index, item) in items.enumerated() {
            let itemView: TabItemView
            if let existing = itemViews[item.id] {
                itemView = existing
            } else {
                itemView = TabItemView(itemID: item.id)
                itemView.delegate = self
                itemViews[item.id] = itemView
            }
            itemView.update(item: item, isSelected: item.id == selectedID)
            if stackView.arrangedSubviews.firstIndex(of: itemView) != index {
                if stackView.arrangedSubviews.contains(itemView) {
                    stackView.removeArrangedSubview(itemView)
                }
                stackView.insertArrangedSubview(itemView, at: min(index, stackView.arrangedSubviews.count))
            }
        }

        if let selectedID, let selectedView = itemViews[selectedID] {
            scrollView.contentView.scrollToVisible(selectedView.frame.insetBy(dx: -24, dy: 0))
        }
    }

    @objc private func handleNewTab() {
        delegate?.tabStripDidRequestNewDocument()
    }
}

extension TabStripView: TabItemViewDelegate {
    func tabItemDidSelect(_ itemID: UUID) {
        delegate?.tabStripDidSelectTab(itemID)
    }

    func tabItemDidRequestClose(_ itemID: UUID) {
        delegate?.tabStripDidRequestClose(itemID)
    }

    func tabItem(_ itemID: UUID, didDragTo index: Int) {
        delegate?.tabStripDidMoveTab(itemID, toIndex: index)
    }

    func tabItemDidRequestCloseOthers(_ itemID: UUID) {
        delegate?.tabStripDidRequestCloseOthers(itemID)
    }

    func tabItemDidRequestCloseToRight(_ itemID: UUID) {
        delegate?.tabStripDidRequestCloseToRight(itemID)
    }

    func tabItemDidRequestCloseAll() {
        delegate?.tabStripDidRequestCloseAll()
    }

    func tabItemDidRequestTogglePin(_ itemID: UUID) {
        delegate?.tabStripDidRequestTogglePin(itemID)
    }

    func tabItemDidRequestRevealInFinder(_ itemID: UUID) {
        delegate?.tabStripDidRequestRevealInFinder(itemID)
    }

    func tabItemDidRequestCopyPath(_ itemID: UUID) {
        delegate?.tabStripDidRequestCopyPath(itemID)
    }

    func tabItemDidRequestDuplicateInNewTab(_ itemID: UUID) {
        delegate?.tabStripDidRequestDuplicateInNewTab(itemID)
    }
}

// MARK: - Tab item view

protocol TabItemViewDelegate: AnyObject {
    func tabItemDidSelect(_ itemID: UUID)
    func tabItemDidRequestClose(_ itemID: UUID)
    func tabItem(_ itemID: UUID, didDragTo index: Int)
    func tabItemDidRequestCloseOthers(_ itemID: UUID)
    func tabItemDidRequestCloseToRight(_ itemID: UUID)
    func tabItemDidRequestCloseAll()
    func tabItemDidRequestTogglePin(_ itemID: UUID)
    func tabItemDidRequestRevealInFinder(_ itemID: UUID)
    func tabItemDidRequestCopyPath(_ itemID: UUID)
    func tabItemDidRequestDuplicateInNewTab(_ itemID: UUID)
}

final class TabItemView: NSView {
    let itemID: UUID
    weak var delegate: TabItemViewDelegate?

    private let titleLabel = NSTextField(labelWithString: "")
    private let dirtyDot = NSView()
    private let pinImage = NSImageView()
    private let closeButton = NSButton()
    private var isSelected = false
    private var dragStartIndex: Int?

    private static let minWidth: CGFloat = 110
    private static let maxWidth: CGFloat = 220

    init(itemID: UUID) {
        self.itemID = itemID
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        dirtyDot.wantsLayer = true
        dirtyDot.layer?.cornerRadius = 3
        dirtyDot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor

        pinImage.translatesAutoresizingMaskIntoConstraints = false
        pinImage.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pinImage.contentTintColor = .tertiaryLabelColor
        pinImage.isHidden = true

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .recessed
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(handleClose)

        addSubview(titleLabel)
        addSubview(dirtyDot)
        addSubview(pinImage)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minWidth),
            widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth),

            pinImage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pinImage.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinImage.widthAnchor.constraint(equalToConstant: 10),

            dirtyDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            dirtyDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dirtyDot.widthAnchor.constraint(equalToConstant: 6),
            dirtyDot.heightAnchor.constraint(equalToConstant: 6),

            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: dirtyDot.trailingAnchor, constant: 5),

            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        updateTrackingAreas()
        toolTip = "Middle-click to close"
    }

    func update(item: TabStripView.TabItem, isSelected: Bool) {
        self.isSelected = isSelected
        titleLabel.stringValue = item.title
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        dirtyDot.isHidden = !item.isDirty
        pinImage.isHidden = !item.isPinned
        closeButton.isHidden = !isSelected && !item.isDirty
        toolTip = item.tooltip

        // Bookmark dot / external change tint
        if item.hasExternalChange {
            layer?.borderColor = NSColor.systemOrange.cgColor
            layer?.backgroundColor = isSelected
                ? NSColor.controlBackgroundColor.cgColor
                : NSColor.systemOrange.withAlphaComponent(0.12).cgColor
        } else {
            layer?.borderColor = isSelected
                ? NSColor.separatorColor.cgColor
                : NSColor.clear.cgColor
            layer?.backgroundColor = isSelected
                ? NSColor.controlBackgroundColor.cgColor
                : NSColor.clear.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .leftMouseDown && event.clickCount == 2 {
            // Double click selects; nothing extra required.
        }
        delegate?.tabItemDidSelect(itemID)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            delegate?.tabItemDidRequestClose(itemID)
        }
    }

    private enum ContextAction: Int {
        case close
        case closeOthers
        case closeToRight
        case closeAll
        case togglePin
        case duplicate
        case reveal
        case copyPath
    }

    private func contextMenuItem(_ title: String, _ action: ContextAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(handleContextAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = action.rawValue
        return item
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(contextMenuItem("Close Tab", .close))
        menu.addItem(contextMenuItem("Close Other Tabs", .closeOthers))
        menu.addItem(contextMenuItem("Close Tabs to the Right", .closeToRight))
        menu.addItem(contextMenuItem("Close All Tabs", .closeAll))
        menu.addItem(.separator())
        menu.addItem(contextMenuItem("Pin / Unpin Tab", .togglePin))
        menu.addItem(contextMenuItem("Duplicate in New Tab", .duplicate))
        menu.addItem(.separator())
        menu.addItem(contextMenuItem("Reveal in Finder", .reveal))
        menu.addItem(contextMenuItem("Copy Path", .copyPath))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleContextAction(_ sender: NSMenuItem) {
        guard let action = ContextAction(rawValue: sender.tag) else { return }
        switch action {
        case .close:
            delegate?.tabItemDidRequestClose(itemID)
        case .closeOthers:
            delegate?.tabItemDidRequestCloseOthers(itemID)
        case .closeToRight:
            delegate?.tabItemDidRequestCloseToRight(itemID)
        case .closeAll:
            delegate?.tabItemDidRequestCloseAll()
        case .togglePin:
            delegate?.tabItemDidRequestTogglePin(itemID)
        case .duplicate:
            delegate?.tabItemDidRequestDuplicateInNewTab(itemID)
        case .reveal:
            delegate?.tabItemDidRequestRevealInFinder(itemID)
        case .copyPath:
            delegate?.tabItemDidRequestCopyPath(itemID)
        }
    }

    @objc private func handleClose() {
        delegate?.tabItemDidRequestClose(itemID)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        refreshCloseButtonVisibility()
    }

    private func refreshCloseButtonVisibility() {
        closeButton.isHidden = !isSelected && dirtyDot.isHidden
    }
}
