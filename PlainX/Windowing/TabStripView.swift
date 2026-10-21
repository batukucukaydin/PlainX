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

    private let scrollView = PXTabScrollView()
    private let stackView = NSStackView()
    private let newTabButton = NSButton()
    private var itemViews: [UUID: TabItemView] = [:]
    /// Leading inset that keeps tabs clear of the window traffic lights.
    private var leadingInsetConstraint: NSLayoutConstraint?

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
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Document tabs")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 2
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

        let leadingInset = scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 78)
        leadingInsetConstraint = leadingInset
        NSLayoutConstraint.activate([
            leadingInset,
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            newTabButton.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 4),
            newTabButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 24),
            newTabButton.heightAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    /// Space reserved for the traffic lights while the tabs sit in the
    /// titlebar band; collapses when the window is full screen.
    func setTrafficLightInset(_ inset: CGFloat) {
        leadingInsetConstraint?.constant = inset
    }

    override var mouseDownCanMoveWindow: Bool { true }

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

    func focusAdjacentTab(from itemID: UUID, offset: Int) {
        guard !items.isEmpty,
              let currentIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        let nextIndex = (currentIndex + offset + items.count) % items.count
        focusTab(at: nextIndex)
    }

    func focusTab(at index: Int) {
        guard items.indices.contains(index),
              let tabView = itemViews[items[index].id] else { return }
        window?.makeFirstResponder(tabView)
        delegate?.tabStripDidSelectTab(items[index].id)
        scrollView.contentView.scrollToVisible(tabView.frame.insetBy(dx: -24, dy: 0))
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
    private let accentBar = NSView()
    private var isHovered = false
    private var isSelected = false
    private var isKeyboardFocused = false
    private var hasExternalChange = false
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
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.clear.cgColor

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

        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.wantsLayer = true
        accentBar.layer?.cornerRadius = 1
        accentBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        accentBar.isHidden = true

        addSubview(titleLabel)
        addSubview(dirtyDot)
        addSubview(pinImage)
        addSubview(closeButton)
        addSubview(accentBar)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            accentBar.heightAnchor.constraint(equalToConstant: 2),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            accentBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
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

        // Expose each tab as its own accessible element so VoiceOver and
        // keyboard-only navigation can enumerate and select tabs.
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isKeyboardFocused = true
        updateBorderAppearance()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isKeyboardFocused = false
        updateBorderAppearance()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let strip = tabStripAncestor else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123: // Left arrow
            strip.focusAdjacentTab(from: itemID, offset: -1)
        case 124: // Right arrow
            strip.focusAdjacentTab(from: itemID, offset: 1)
        case 115: // Home
            strip.focusTab(at: 0)
        case 119: // End
            strip.focusTab(at: strip.items.count - 1)
        case 36, 49: // Return or Space
            delegate?.tabItemDidSelect(itemID)
        default:
            super.keyDown(with: event)
        }
    }

    private var tabStripAncestor: TabStripView? {
        var ancestor = superview
        while let view = ancestor {
            if let strip = view as? TabStripView { return strip }
            ancestor = view.superview
        }
        return nil
    }

    override func accessibilityLabel() -> String? {
        titleLabel.stringValue
    }

    override func accessibilityValue() -> Any? {
        isSelected ? 1 : 0
    }

    override func accessibilityHelp() -> String? {
        let keyboardHelp = "Use Left or Right Arrow to select another tab. Use Home or End to select the first or last tab. Middle-click to close this tab."
        guard let toolTip, !toolTip.isEmpty else { return keyboardHelp }
        return "\(toolTip). \(keyboardHelp)"
    }

    override func accessibilityPerformPress() -> Bool {
        delegate?.tabItemDidSelect(itemID)
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let close = NSAccessibilityCustomAction(name: "Close Tab") { [weak self] in
            guard let self else { return false }
            self.delegate?.tabItemDidRequestClose(self.itemID)
            return true
        }
        return [close]
    }

    func update(item: TabStripView.TabItem, isSelected: Bool) {
        self.isSelected = isSelected
        hasExternalChange = item.hasExternalChange
        titleLabel.stringValue = item.title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        dirtyDot.isHidden = !item.isDirty
        pinImage.isHidden = !item.isPinned
        closeButton.isHidden = !isSelected && !item.isDirty
        closeButton.setAccessibilityLabel("Close \(item.title)")
        toolTip = item.tooltip
        setAccessibilityLabel(item.title)
        accentBar.isHidden = !isSelected

        if item.hasExternalChange {
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(isSelected ? 0.18 : 0.10).cgColor
        } else if isSelected {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        updateBorderAppearance()
    }

    private func updateBorderAppearance() {
        layer?.borderWidth = isKeyboardFocused ? 2 : 1
        if isKeyboardFocused {
            layer?.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
        } else if hasExternalChange {
            layer?.borderColor = NSColor.systemOrange.cgColor
        } else if isSelected {
            layer?.borderColor = NSColor.separatorColor.cgColor
        } else {
            layer?.borderColor = NSColor.clear.cgColor
        }
    }

    private var dragOrigin: NSPoint?

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        window?.makeFirstResponder(self)
        delegate?.tabItemDidSelect(itemID)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let stack = superview else { return }
        let horizontalTravel = abs(event.locationInWindow.x - origin.x)
        guard horizontalTravel > 12 else { return }
        let pointInStack = stack.convert(event.locationInWindow, from: nil)
        var targetIndex = 0
        for sibling in stack.subviews where sibling !== self {
            if pointInStack.x > sibling.frame.midX {
                targetIndex += 1
            }
        }
        delegate?.tabItem(self.itemID, didDragTo: targetIndex)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
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
        isHovered = true
        closeButton.isHidden = false
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshCloseButtonVisibility()
        refreshBackground()
    }

    private func refreshBackground() {
        guard !isSelected else { return }
        if isHovered {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func refreshCloseButtonVisibility() {
        closeButton.isHidden = !isSelected && dirtyDot.isHidden
    }
}


/// Scroll view used by the tab strip: clicks on empty tab-bar space drag the
/// window (the strip lives in the titlebar band), clicks on tabs do not.
final class PXTabScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { true }
}
