//
//  MainWindowController.swift
//  PlainX Editor
//
//  A document window: tab strip, editor container, status bar, banners.
//

import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    unowned let coordinator: AppCoordinator

    private(set) var tabs: [any DocumentTab] = []
    private(set) var activeTabIndex: Int = 0
    var activeTab: (any DocumentTab)? {
        guard tabs.indices.contains(activeTabIndex) else { return tabs.first }
        return tabs[activeTabIndex]
    }
    /// The active tab when it is a regular editor tab (nil for Large File tabs).
    var activeEditorTab: DocumentTabController? { activeTab as? DocumentTabController }

    let tabStrip = TabStripView()
    let statusBar = StatusBarView()
    private let bannerContainer = NSStackView()
    private let contentContainer = NSView()
    private var banners: [BannerView] = []

    private var currentTabView: NSView?

    private(set) var documentWatchers: [UUID: FileWatcher] = [:]

    var currentTheme: EditorTheme {
        coordinator.preferences.resolvedTheme(appearance: window?.effectiveAppearance)
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PlainX"
        window.minSize = NSSize(width: 420, height: 260)
        window.setFrameAutosaveName("PlainXMainWindow")
        window.tabbingMode = .disallowed
        // Tabs live in the titlebar band: transparent chrome, no title text,
        // no separator line (Safari/Xcode-style header).
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        super.init(window: window)
        window.delegate = self
        window.center()

        setupLayout()
        updateTabStrip()

        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: Preferences.didChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLayout() {
        guard let window, let contentView = window.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false

        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.orientation = .vertical
        bannerContainer.spacing = 0
        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        tabStrip.delegate = self
        statusBar.delegate = self

        contentView.addSubview(root)
        root.addArrangedSubview(tabStrip)
        root.addArrangedSubview(bannerContainer)
        root.addArrangedSubview(contentContainer)
        root.addArrangedSubview(statusBar)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tabStrip.widthAnchor.constraint(equalTo: root.widthAnchor),
            bannerContainer.widthAnchor.constraint(equalTo: root.widthAnchor),
            contentContainer.widthAnchor.constraint(equalTo: root.widthAnchor),
            statusBar.widthAnchor.constraint(equalTo: root.widthAnchor),
            contentContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
        contentContainer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let dropView = FileDropView()
        dropView.coordinator = coordinator
        dropView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(dropView)
        NSLayoutConstraint.activate([
            dropView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            dropView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            dropView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        dropHost = dropView
    }

    private var dropHost: FileDropView?

    // MARK: - Tabs

    /// Inserts a prebuilt tab (Welcome screen, future tab kinds).
    func addTab(_ tab: any DocumentTab, select: Bool, at index: Int? = nil) {
        let insertionIndex = min(max(0, index ?? tabs.count), tabs.count)
        tab.tabDelegate = self
        tabs.insert(tab, at: insertionIndex)
        finishAddingTab(select: select, insertionIndex: insertionIndex)
    }

    func addTab(for document: PlainXDocument, select: Bool, at index: Int? = nil) {
        let insertionIndex = min(max(0, index ?? tabs.count), tabs.count)

        if let backing = coordinator.consumePendingLargeFileBacking(for: document) {
            let largeTab = LargeFileTabController(document: document, backing: backing, theme: currentTheme)
            largeTab.viewer.delegate = self
            largeTab.tabDelegate = self
            tabs.insert(largeTab, at: insertionIndex)
            document.loadDiagnostic = nil
            finishAddingTab(select: select, insertionIndex: insertionIndex)
            return
        }

        let tab = DocumentTabController(document: document, controller: self)
        tab.delegate = self
        tabs.insert(tab, at: insertionIndex)

        if let loaded = coordinator.consumePendingLoad(for: document) {
            tab.loadInitialContent(from: loaded)
            if let diagnostic = loaded.diagnostic {
                showBanner(message: diagnostic, actions: [], style: loaded.hadInvalidSequences ? .warning : .info)
            }
        } else if document.url == nil {
            tab.replaceDocumentText("", markDirty: false)
        }
        if document.isDirty {
            tab.markDirtyIfNeeded()
        }
        if document.hasExternalChange, let url = document.url,
           !FileManager.default.fileExists(atPath: url.path) {
            showBanner(message: "“\(document.displayName)” could not be found at its previous location.", actions: [
                .init(title: "Locate…", handler: { [weak self] in
                    self?.coordinator.locateMissingFile(for: document, tab: tab)
                }),
                .init(title: "Remove Tab", handler: { [weak self] in
                    self?.closeTab(id: tab.id, force: true)
                }),
            ])
        }

        if select {
            activeTabIndex = insertionIndex
        } else if insertionIndex <= activeTabIndex {
            activeTabIndex += 1
        }
        updateTabStrip()
        updateStatusBar()
        updateWindowTitle()
        if select {
            showActiveTab()
            focusEditor()
        }
        startWatching(document)
    }

    private func finishAddingTab(select: Bool, insertionIndex: Int) {        if select {
            activeTabIndex = insertionIndex
        } else if insertionIndex <= activeTabIndex {
            activeTabIndex += 1
        }
        updateTabStrip()
        updateStatusBar()
        updateWindowTitle()
        if select {
            showActiveTab()
            focusEditor()
        }
        if let document = activeTab?.document {
            startWatching(document)
        }
    }

    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectTab(at: index)
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTab?.saveViewStates()
        activeTabIndex = index
        updateTabStrip()
        updateStatusBar()
        updateWindowTitle()
        showActiveTab()
        focusEditor()
    }

    @discardableResult
    func closeTab(id: UUID, force: Bool = false) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return true }
        let tab = tabs[index]
        if tab.isWelcome && tabs.count == 1 {
            NSSound.beep()
            return false
        }
        if !force && tab.document.isDirty {
            promptSaveIfNeeded(document: tab.document, tab: tab) { [weak self] proceed in
                guard let self, proceed else { return }
                self.closeTab(id: id, force: true)
            }
            return false
        }
        tab.saveViewStates()
        tabs.remove(at: index)
        coordinator.noteClosedTab(tab.document.url)
        stopWatching(tab.document)
        coordinator.documentDidClose(tab.document)
        if tabs.isEmpty {
            activeTabIndex = 0
            showActiveTab()
            updateTabStrip()
            updateStatusBar()
            updateWindowTitle()
            coordinator.windowDidEmpty(self)
        } else {
            activeTabIndex = min(index, tabs.count - 1)
            showActiveTab()
            updateTabStrip()
            updateStatusBar()
            updateWindowTitle()
            focusEditor()
        }
        return true
    }

    func moveTab(id: UUID, toIndex destination: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        var destination = destination
        if destination > index { destination -= 1 }
        destination = min(max(0, destination), tabs.count)
        tabs.insert(tab, at: destination)
        if let newIndex = tabs.firstIndex(where: { $0.id == id }) {
            activeTabIndex = newIndex
        }
        updateTabStrip()
    }

    func reorderPinnedFirst() {
        let pinned = tabs.filter { $0.document.isPinned }
        let unpinned = tabs.filter { !$0.document.isPinned }
        tabs = pinned + unpinned
        updateTabStrip()
    }

    private func showActiveTab() {
        currentTabView?.removeFromSuperview()
        guard let tab = activeTab, let container = dropHost else { return }
        let tabView = tab.tabContentView
        tabView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: container.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        currentTabView = tabView
        tab.focusContent()
    }

    func focusEditor() {
        activeTab?.focusContent()
    }

    // MARK: - Chrome updates

    func updateTabStrip() {
        let items = tabs.map { tab -> TabStripView.TabItem in
            let doc = tab.document
            return TabStripView.TabItem(
                id: tab.id,
                title: tab.isWelcome ? "Welcome" : doc.displayName,
                isDirty: doc.isDirty,
                isPinned: doc.isPinned,
                tooltip: doc.pathDisplayName,
                hasExternalChange: doc.hasExternalChange
            )
        }
        tabStrip.update(items: items, selectedID: activeTab?.id)
    }

    func updateWindowTitle() {
        guard let tab = activeTab, !tab.isWelcome else {
            window?.title = "PlainX"
            window?.subtitle = ""
            window?.representedURL = nil
            window?.isDocumentEdited = false
            return
        }
        let doc = tab.document
        window?.title = doc.isUntitled ? doc.displayName : doc.url?.lastPathComponent ?? doc.displayName
        window?.subtitle = tab.isSplit ? "Split view" : (doc.isUntitled ? "" : doc.url?.deletingLastPathComponent().path ?? "")
        window?.isDocumentEdited = doc.isDirty
        window?.representedURL = doc.url
    }

    func updateStatusBar() {
        guard let tab = activeTab else {
            statusBar.update(state: .init(encodingName: "", encodingTooltip: "", eolName: "", eolTooltip: "",
                                          languageName: "", languageTooltip: "", indentationName: "",
                                          line: 0, column: 0, selectionSummary: "", fileSizeSummary: "",
                                          modeSummary: ""))
            return
        }
        statusBar.update(state: tab.statusSnapshot())
    }

    // MARK: - Banners

    func showBanner(message: String, actions: [BannerView.Action], style: BannerView.Style = .warning) {
        let banner = BannerView()
        banner.show(message: message, actions: actions, style: style)
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.onDismiss = { [weak self, weak banner] in
            guard let self, let banner else { return }
            self.removeBanner(banner)
        }
        banners.append(banner)
        bannerContainer.addArrangedSubview(banner)
        banner.widthAnchor.constraint(equalTo: bannerContainer.widthAnchor).isActive = true
    }

    func removeBanner(_ banner: BannerView) {
        banners.removeAll { $0 === banner }
        bannerContainer.removeArrangedSubview(banner)
        banner.removeFromSuperview()
    }

    func clearBanners() {
        for banner in banners {
            bannerContainer.removeArrangedSubview(banner)
            banner.removeFromSuperview()
        }
        banners.removeAll()
    }

    // MARK: - File watching

    func startWatching(_ document: PlainXDocument) {
        guard let url = document.url else { return }
        let watcher = FileWatcher(url: url)
        watcher.onEvent = { [weak self] event in
            self?.handleFileEvent(event, document: document)
        }
        watcher.start()
        documentWatchers[document.id] = watcher
    }

    func stopWatching(_ document: PlainXDocument) {
        documentWatchers[document.id]?.stop()
        documentWatchers.removeValue(forKey: document.id)
    }

    private func handleFileEvent(_ event: FileWatcher.Event, document: PlainXDocument) {
        guard let tab = tabs.first(where: { $0.document === document }) else { return }
        if document.isLargeFileMode {
            // The Large File viewer manages its own follow/rotation banner.
            return
        }
        guard let editorTab = tab as? DocumentTabController else { return }
        switch event {
        case .changed:
            handleExternalChange(document: document, tab: editorTab)
        case .appended:
            handleExternalChange(document: document, tab: editorTab)
        case .deleted, .renamed:
            document.hasExternalChange = true
            updateTabStrip()
            showBanner(message: "“\(document.displayName)” was moved, renamed, or deleted on disk.",
                       actions: [
                        .init(title: "Keep Editing", handler: {}),
                        .init(title: "Locate…", handler: { [weak self] in
                            guard let self else { return }
                            self.coordinator.locateMissingFile(for: document, tab: editorTab)
                        }),
                        .init(title: "Close Tab", handler: { [weak self] in
                            self?.closeTab(id: tab.id, force: true)
                        }),
                       ])
        }
    }

    private func handleExternalChange(document: PlainXDocument, tab: DocumentTabController) {
        guard let url = document.url else { return }
        let currentMetadata = FileLoader.metadata(for: url)
        guard let currentMetadata else { return }
        if let known = document.lastKnownMetadata,
           FileSaver.isSameFileContentState(known, currentMetadata) {
            return
        }
        document.hasExternalChange = true
        updateTabStrip()

        if !document.isDirty {
            showBanner(message: "“\(document.displayName)” changed on disk.", actions: [
                .init(title: "Reload", handler: { [weak self] in
                    self?.coordinator.reload(document: document, tab: tab)
                }),
                .init(title: "Keep Mine", handler: { [weak self] in
                    guard let self else { return }
                    document.hasExternalChange = false
                    document.lastKnownMetadata = currentMetadata
                    self.updateTabStrip()
                }),
            ])
        } else {
            showBanner(message: "“\(document.displayName)” changed on disk while you have unsaved changes.", actions: [
                .init(title: "Compare…", handler: { [weak self] in
                    guard let self else { return }
                    self.coordinator.compareWithDisk(document: document, tab: tab)
                }),
                .init(title: "Reload, Discard Mine", handler: { [weak self] in
                    self?.coordinator.reload(document: document, tab: tab)
                }, isDestructive: true),
                .init(title: "Save Anyway…", handler: { [weak self] in
                    self?.coordinator.save(document: document, tab: tab, force: true)
                }),
            ])
        }
    }

    // MARK: - Save prompts

    func promptSaveIfNeeded(document: PlainXDocument, tab: (any DocumentTab)?, completion: @escaping (Bool) -> Void) {
        guard document.isDirty else {
            completion(true)
            return
        }
        guard let editorTab = tab as? DocumentTabController else {
            // Large File tabs are read-only; nothing to save.
            completion(true)
            return
        }
        guard let window else {
            completion(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to “\(document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.coordinator.save(document: document, tab: editorTab, force: false, completion: { success in
                    completion(success)
                })
            case .alertSecondButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let window else { return true }
        for tab in tabs {
            if tab.document.isDirty {
                promptSaveIfNeeded(document: tab.document, tab: tab) { [weak self] proceed in
                    guard let self, proceed else { return }
                    self.forceCloseWindow()
                }
                return false
            }
        }
        _ = window
        return true
    }

    func forceCloseWindow() {
        for tab in tabs {
            tab.saveViewStates()
            stopWatching(tab.document)
            coordinator.documentDidClose(tab.document)
        }
        tabs.removeAll()
        coordinator.windowDidClose(self)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        coordinator.windowDidClose(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        coordinator.noteActiveWindow(self)
        AppDelegate.reportFirstUsableEditorIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        updateStatusBar()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        tabStrip.setTrafficLightInset(8)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        tabStrip.setTrafficLightInset(78)
    }

    @objc private func preferencesChanged() {
        for tab in tabs {
            if let editorTab = tab as? DocumentTabController {
                for pane in editorTab.panes {
                    pane.applyEditorPreferences()
                }
            }
        }
        updateStatusBar()
    }

    // MARK: - Actions for status bar quick menus

    func applyThemeChange() {
        clearBanners()
        for tab in tabs {
            if let editorTab = tab as? DocumentTabController {
                for pane in editorTab.panes {
                    pane.applyTheme(currentTheme)
                }
            } else if let largeTab = tab as? LargeFileTabController {
                largeTab.applyTheme(currentTheme)
            }
        }
        window?.appearance = nil
    }
}

// MARK: - TabStripViewDelegate

extension MainWindowController: TabStripViewDelegate {
    func tabStripDidSelectTab(_ tabID: UUID) {
        selectTab(id: tabID)
    }

    func tabStripDidRequestClose(_ tabID: UUID) {
        closeTab(id: tabID)
    }

    func tabStripDidRequestCloseOthers(_ tabID: UUID) {
        coordinator.closeOtherTabs(tabID, in: self)
    }

    func tabStripDidRequestCloseToRight(_ tabID: UUID) {
        coordinator.closeTabsToRight(of: tabID, in: self)
    }

    func tabStripDidRequestCloseAll() {
        coordinator.closeAllTabs(in: self)
    }

    func tabStripDidRequestTogglePin(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        tab.document.isPinned.toggle()
        reorderPinnedFirst()
    }

    func tabStripDidRequestRevealInFinder(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }), let url = tab.document.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func tabStripDidRequestCopyPath(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(tab.document.pathDisplayName, forType: .string)
    }

    func tabStripDidRequestNewDocument() {
        coordinator.newDocument(in: self)
    }

    func tabStripDidRequestDuplicateInNewTab(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) as? DocumentTabController else { return }
        coordinator.duplicateDocumentInNewTab(tab)
    }

    func tabStripDidMoveTab(_ tabID: UUID, toIndex index: Int) {
        moveTab(id: tabID, toIndex: index)
    }
}

// MARK: - StatusBarViewDelegate

extension MainWindowController: StatusBarViewDelegate {
    func statusBarDidRequestEncodingMenu(_ statusBar: StatusBarView, anchor: NSView) {
        guard let tab = activeEditorTab else { return }
        coordinator.showEncodingMenu(for: tab, relativeTo: anchor, in: self)
    }

    func statusBarDidRequestEOLMenu(_ statusBar: StatusBarView, anchor: NSView) {
        guard let tab = activeEditorTab else { return }
        coordinator.showEOLMenu(for: tab, relativeTo: anchor, in: self)
    }

    func statusBarDidRequestLanguageMenu(_ statusBar: StatusBarView, anchor: NSView) {
        guard let tab = activeEditorTab else { return }
        coordinator.showLanguageMenu(for: tab, relativeTo: anchor, in: self)
    }

    func statusBarDidRequestIndentationMenu(_ statusBar: StatusBarView, anchor: NSView) {
        coordinator.showIndentationMenu(relativeTo: anchor, in: self)
    }

    func statusBarDidRequestGoToLine(_ statusBar: StatusBarView) {
        coordinator.promptGoToLine(in: self)
    }
}

// MARK: - DocumentTabControllerDelegate

extension MainWindowController: DocumentTabControllerDelegate {
    func documentTabDidChangeState(_ tab: DocumentTabController) {
        if tab === activeTab {
            updateWindowTitle()
        }
        updateTabStrip()
    }

    func documentTabDidChangeContent(_ tab: DocumentTabController) {
        updateStatusBar()
        updateTabStrip()
    }

    func documentTabDidChangeSelection(_ tab: DocumentTabController) {
        if tab === activeTab {
            updateStatusBar()
        }
    }

    func documentTabRequestsClose(_ tab: DocumentTabController) {
        closeTab(id: tab.id)
    }
}

// MARK: - File drop

final class FileDropView: NSView {    weak var coordinator: AppCoordinator?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let pasteboard = sender.draggingPasteboard
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = urls(from: sender)
        guard !dropped.isEmpty else { return false }
        let window = self.window?.windowController as? MainWindowController
        coordinator?.openDroppedItems(dropped, in: window)
        return true
    }
}

// MARK: - LargeFileViewControllerDelegate

extension MainWindowController: LargeFileViewControllerDelegate {
    func largeFileViewDidRequestOpenNormally(_ controller: LargeFileViewController) {
        guard let largeTab = tabs.compactMap({ $0 as? LargeFileTabController })
            .first(where: { $0.viewer === controller }) else { return }
        coordinator.openNormally(document: largeTab.document, in: self)
    }

    func largeFileViewDidRequestRevealInFinder(_ controller: LargeFileViewController) {
        guard let largeTab = tabs.compactMap({ $0 as? LargeFileTabController })
            .first(where: { $0.viewer === controller }), let url = largeTab.document.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
