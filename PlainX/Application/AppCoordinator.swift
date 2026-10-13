//
//  AppCoordinator.swift
//  PlainX Editor
//
//  Application-level orchestration: window lifecycle, document open/save/
//  close flows, dialogs, recent files, session wiring. Pure file/format logic
//  lives in the service types (FileLoader, FileSaver, DiffService, ...).
//

import AppKit

final class AppCoordinator {
    let preferences = Preferences.shared
    let macroEngine = MacroEngine()
    let recoveryStore = RecoveryStore()
    private(set) var sessionStore = SessionStore()

    private(set) var windows: [MainWindowController] = []
    weak var activeWindow: MainWindowController?
    private(set) var recentURLs: [URL] = []
    private(set) var sessionRestoreFailed = false

    var onRecentListChanged: (() -> Void)?

    private var recentKey = "app.recentFiles"

    init() {
        loadRecentFiles()
    }

    // MARK: - Windows

    @discardableResult
    func newWindow() -> MainWindowController {
        let controller = MainWindowController(coordinator: self)
        windows.append(controller)
        activeWindow = controller
        controller.showWindow(nil)
        return controller
    }

    func noteActiveWindow(_ window: MainWindowController) {
        activeWindow = window
    }

    func windowDidClose(_ window: MainWindowController) {
        windows.removeAll { $0 === window }
        scheduleSessionSave()
        if windows.isEmpty, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            NSApp.terminate(nil)
        }
    }

    func windowDidEmpty(_ window: MainWindowController) {
        // Keep a window alive with a fresh untitled document.
        let document = makeUntitledDocument()
        window.addTab(for: document, select: true)
    }

    // MARK: - New / open

    func newDocument(in window: MainWindowController?) {
        let target = window ?? activeWindow ?? newWindow()
        target.addTab(for: makeUntitledDocument(), select: true)
    }

    private func makeUntitledDocument() -> PlainXDocument {
        let document = PlainXDocument(url: nil)
        document.encoding = preferences.defaultEncoding
        document.eolMode = preferences.defaultEOL.concreteFallback
        return document
    }

    func open(urls: [URL], in window: MainWindowController?) {
        let target = window ?? activeWindow ?? newWindow()
        var lastOpened: PlainXDocument?
        for url in urls {
            if let existing = findOpenDocument(url: url) {
                focus(document: existing)
                continue
            }
            do {
                let document = try openDocument(at: url)
                target.addTab(for: document, select: true)
                lastOpened = document
            } catch {
                presentError(error, in: target)
            }
        }
        if lastOpened != nil {
            target.focusEditor()
        }
    }

    func openDroppedItems(_ urls: [URL], in window: MainWindowController?) {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                // Folders become the search root (Find in Files).
                activeWindow?.showBanner(
                    message: "Added “\(url.lastPathComponent)” as a search folder.",
                    actions: [
                        .init(title: "Find in Files…", handler: { [weak self] in
                            self?.promptFindInFiles(root: url)
                        }),
                    ],
                    style: .info
                )
                UserDefaults.standard.set(url.path, forKey: "search.lastRoot")
            } else {
                files.append(url)
            }
        }
        if !files.isEmpty {
            open(urls: files, in: window)
        }
    }

    /// Loads a document (encoding detection, EOL detection, metadata).
    /// Hidden files, binary-looking files, and huge files are handled with
    /// safe fallbacks rather than failing.
    func openDocument(at url: URL) throws -> PlainXDocument {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw FileLoaderError.notARegularFile(url)
        }

        let document = PlainXDocument(url: url)
        if let metadata = FileLoader.metadata(for: url) {
            document.lastKnownMetadata = metadata
        }

        // Large-file decision happens before any content is read.
        let size = document.lastKnownMetadata?.fileSize ?? 0
        let bypassLargeFile = bypassLargeFileURLs.contains(url.standardizedFileURL)
        if !bypassLargeFile, size >= preferences.largeFileThresholdBytes {
            switch preferences.largeFileOpenMode {
            case .automatic, .ask:
                if let backing = try? LargeFileBacking(url: url) {
                    document.isLargeFileMode = true
                    document.encoding = textEncoding(for: backing.encoding)
                    document.eolMode = .lf
                    pendingLargeFileBackings[document.id] = backing
                    addRecentFile(url)
                    return document
                }
                // Encoding is not compatible with Large File Mode (e.g. UTF-16):
                // fall through to a regular open and explain why.
                document.loadDiagnostic = "This file is larger than \(preferences.largeFileThresholdMB) MB but is not in a text encoding Large File Mode can show, so it was opened in the regular editor."
            case .alwaysRegular:
                break
            }
        }

        let loaded = try FileLoader.load(url: url)
        document.encoding = loaded.encoding
        document.eolMode = loaded.eolMode
        document.lastKnownMetadata = loaded.metadata
        document.loadDiagnostic = loaded.diagnostic

        // The tab loads content; keep loaded text alongside the document until
        // the tab pulls it (large files and regular files share this path).
        pendingLoads[document.id] = loaded
        addRecentFile(url)
        return document
    }

    private func textEncoding(for largeFileEncoding: LargeFileTextEncoding) -> TextEncoding {
        switch largeFileEncoding {
        case .utf8(let hasBOM): return hasBOM ? .utf8BOM : .utf8
        case .windows1252: return .windows1252
        }
    }

    private var pendingLargeFileBackings: [UUID: LargeFileBacking] = [:]
    /// URLs the user explicitly chose to open in the regular editor.
    private var bypassLargeFileURLs: Set<URL> = []

    func consumePendingLargeFileBacking(for document: PlainXDocument) -> LargeFileBacking? {
        pendingLargeFileBackings.removeValue(forKey: document.id)
    }

    func setPendingLargeFileBacking(_ backing: LargeFileBacking, for document: PlainXDocument) {
        pendingLargeFileBackings[document.id] = backing
    }

    /// Opens a large file in the regular editor anyway (user override).
    func openNormally(document: PlainXDocument, in window: MainWindowController?) {
        guard let url = document.url, let target = window ?? activeWindow else { return }
        bypassLargeFileURLs.insert(url.standardizedFileURL)
        let confirmation = NSAlert()
        confirmation.messageText = "Open “\(document.displayName)” in the regular editor?"
        confirmation.informativeText = "The whole file will be loaded into memory (it is about \(document.lastKnownMetadata?.summary ?? "large")). This may be slow or use a lot of memory."
        confirmation.alertStyle = .warning
        confirmation.addButton(withTitle: "Open Normally")
        confirmation.addButton(withTitle: "Cancel")
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            if let index = target.tabs.firstIndex(where: { $0.document === document }) {
                target.closeTab(id: target.tabs[index].id, force: true)
            }
            do {
                let reloaded = try self.openDocument(at: url)
                reloaded.isLargeFileMode = false
                target.addTab(for: reloaded, select: true)
            } catch {
                self.presentError(error, in: target)
            }
        }
        if let win = target.window {
            confirmation.beginSheetModal(for: win, completionHandler: handler)
        } else {
            handler(confirmation.runModal())
        }
    }

    private var pendingLoads: [UUID: LoadedFile] = [:]

    func consumePendingLoad(for document: PlainXDocument) -> LoadedFile? {
        pendingLoads.removeValue(forKey: document.id)
    }

    func setPendingLoad(_ loaded: LoadedFile, for document: PlainXDocument) {
        pendingLoads[document.id] = loaded
    }

    func allOpenDocumentIDs() -> [UUID] {
        windows.flatMap { $0.tabs.map { $0.document.id } }
    }

    func recoverDocument(from snapshot: RecoverySnapshot, in window: MainWindowController) {
        let document = PlainXDocument(url: snapshot.originalPath.map { URL(fileURLWithPath: $0) },
                                      untitledName: snapshot.displayName)
        if let encoding = TextEncoding.selectable.first(where: {
            $0.identifier == snapshot.encodingID && $0.hasBOM == snapshot.encodingHasBOM
        }) {
            document.encoding = encoding
        }
        document.eolMode = EOLMode(rawValue: snapshot.eol) ?? .lf
        document.languageOverrideID = snapshot.languageOverrideID
        document.isDirty = true
        if let recoveryID = UUID(uuidString: snapshot.documentID) {
            document.recoveryID = recoveryID
        }
        let loaded = LoadedFile(text: snapshot.text, encoding: document.encoding, eolMode: document.eolMode,
                                metadata: FileMetadata(modificationDate: Date(), fileSize: 0, fileIdentifier: nil),
                                diagnostic: "Recovered unsaved changes from a previous session.",
                                hadInvalidSequences: false)
        setPendingLoad(loaded, for: document)
        window.addTab(for: document, select: true)
    }

    // MARK: - Recovery timer

    private var recoveryTimer: Timer?

    func startRecoveryTimer() {
        guard preferences.recoveryEnabled else { return }
        recoveryTimer?.invalidate()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: preferences.recoveryInterval,
                                             repeats: true) { [weak self] _ in
            self?.takeRecoverySnapshotNow()
        }
    }

    func takeRecoverySnapshotNow() {
        guard preferences.recoveryEnabled else { return }
        recoveryStore.prune()
        for window in windows {
            for tab in window.tabs where tab.document.isDirty {
                guard let editorTab = tab as? DocumentTabController else { continue }
                recoveryStore.snapshot(document: tab.document, text: editorTab.activePane.facade.text)
            }
        }
    }

    func findOpenDocument(url: URL) -> PlainXDocument? {
        let standardized = url.standardizedFileURL
        for window in windows {
            for tab in window.tabs where tab.document.url?.standardizedFileURL == standardized {
                return tab.document
            }
        }
        return nil
    }

    func focus(document: PlainXDocument) {
        for window in windows {
            if let tab = window.tabs.first(where: { $0.document === document }) {
                window.selectTab(id: tab.id)
                window.window?.makeKeyAndOrderFront(nil)
                return
            }
        }
    }

    func tab(for document: PlainXDocument) -> (MainWindowController, DocumentTabController)? {
        for window in windows {
            if let tab = window.tabs.first(where: { $0.document === document }) as? DocumentTabController {
                return (window, tab)
            }
        }
        return nil
    }

    func documentDidClose(_ document: PlainXDocument) {
        pendingLoads.removeValue(forKey: document.id)
        pendingLargeFileBackings.removeValue(forKey: document.id)
        recoveryStore.discardSnapshot(for: document)
    }

    // MARK: - Recent files

    private func loadRecentFiles() {
        let paths = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        recentURLs = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func persistRecentFiles() {
        UserDefaults.standard.set(recentURLs.map(\.path), forKey: recentKey)
        NSDocumentController.shared.clearRecentDocuments(nil)
        onRecentListChanged?()
    }

    func addRecentFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        recentURLs.removeAll { $0.standardizedFileURL == standardized }
        recentURLs.insert(standardized, at: 0)
        if recentURLs.count > 20 {
            recentURLs = Array(recentURLs.prefix(20))
        }
        persistRecentFiles()
    }

    func clearRecentFiles() {
        recentURLs = []
        persistRecentFiles()
    }

    // MARK: - Save

    func save(document: PlainXDocument, tab: DocumentTabController?, force: Bool,
              completion: @escaping (Bool) -> Void = { _ in }) {
        guard let tab else {
            completion(false)
            return
        }
        guard let url = document.url else {
            saveAs(document: document, tab: tab, completion: completion)
            return
        }
        performWrite(document: document, tab: tab, url: url, force: force,
                     checkExternal: !force, completion: completion)
    }

    func saveAs(document: PlainXDocument, tab: DocumentTabController?,
                completion: @escaping (Bool) -> Void = { _ in }) {
        guard let tab else {
            completion(false)
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.isUntitled ? document.displayName : document.url?.lastPathComponent ?? document.displayName
        if let directory = document.url?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }
        let window = tab.controller.window
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            let previousURL = document.url
            document.rename(to: url)
            self.performWrite(document: document, tab: tab, url: url, force: true,
                              checkExternal: false) { success in
                if !success {
                    if let previousURL { document.rename(to: previousURL) }
                } else {
                    self.addRecentFile(url)
                    if let languageOverride = document.languageOverrideID {
                        tab.activePane.setLanguage(LanguageRegistry.language(withID: languageOverride))
                    } else {
                        tab.activePane.setLanguage(LanguageRegistry.language(for: url))
                    }
                    tab.controller.startWatching(document)
                    tab.controller.updateTabStrip()
                }
                completion(success)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private func performWrite(document: PlainXDocument, tab: DocumentTabController, url: URL,
                              force: Bool, checkExternal: Bool,
                              completion: @escaping (Bool) -> Void) {
        var text = tab.activePane.facade.text
        if preferences.trimTrailingWhitespaceOnSave {
            text = TransformService.trimTrailingWhitespace(in: text)
        }
        if preferences.ensureFinalNewlineOnSave, !text.isEmpty, !text.hasSuffix("\n") {
            text += document.eolMode.concreteFallback.stringValue
        }

        do {
            let result = try FileSaver.save(
                text: text,
                to: url,
                encoding: document.encoding,
                lastKnownMetadata: document.lastKnownMetadata,
                checkExternalModification: checkExternal,
                force: force
            )
            document.lastKnownMetadata = result.metadata
            document.hasExternalChange = false
            tab.replaceDocumentText(text, markDirty: false)
            tab.markClean()
            tab.controller.clearBanners()
            tab.controller.updateTabStrip()
            tab.controller.updateWindowTitle()
            recoveryStore.discardSnapshot(for: document)
            Log.fileIO.info("Saved document to disk (\(document.displayName, privacy: .public))")
            completion(true)
        } catch FileSaverError.externalModification {
            presentExternalConflict(document: document, tab: tab)
            completion(false)
        } catch FileSaverError.encodingFailure(let encoding, _) {
            presentEncodingFailure(document: document, tab: tab, encoding: encoding)
            completion(false)
        } catch {
            presentWriteFailure(error, document: document, tab: tab)
            completion(false)
        }
    }

    private func presentExternalConflict(document: PlainXDocument, tab: DocumentTabController) {
        let alert = NSAlert()
        alert.messageText = "“\(document.displayName)” changed on disk after you opened it."
        alert.informativeText = "Reload it, save your version anyway, or save a copy."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Cancel")
        if let window = tab.controller.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    self.save(document: document, tab: tab, force: true)
                case .alertSecondButtonReturn:
                    self.reload(document: document, tab: tab)
                case .alertThirdButtonReturn:
                    self.saveAs(document: document, tab: tab)
                default:
                    break
                }
            }
        }
    }

    private func presentEncodingFailure(document: PlainXDocument, tab: DocumentTabController, encoding: TextEncoding) {
        let alert = NSAlert()
        alert.messageText = "This document contains characters that cannot be saved as \(encoding.displayName)."
        alert.informativeText = "Change the document encoding (for example to UTF-8), then save again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Change to UTF-8")
        alert.addButton(withTitle: "Cancel")
        if let window = tab.controller.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.convertEncoding(document: document, tab: tab, to: .utf8)
            }
        }
    }

    private func presentWriteFailure(_ error: Error, document: PlainXDocument, tab: DocumentTabController) {
        let alert = NSAlert()
        alert.messageText = error.localizedDescription
        alert.informativeText = "Your changes are still in the editor; nothing was written to disk."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Save As…")
        if let window = tab.controller.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertSecondButtonReturn {
                    self?.saveAs(document: document, tab: tab)
                }
            }
        }
    }

    func saveAll(in window: MainWindowController, completion: @escaping () -> Void = {}) {
        let dirtyTabs = window.tabs.compactMap { $0 as? DocumentTabController }.filter { $0.document.isDirty }
        guard !dirtyTabs.isEmpty else {
            completion()
            return
        }
        var remaining = dirtyTabs.count
        var failed = false
        for tab in dirtyTabs {
            save(document: tab.document, tab: tab, force: false) { success in
                remaining -= 1
                failed = failed || !success
                if remaining == 0 {
                    _ = failed
                    completion()
                }
            }
        }
    }

    // MARK: - Reload / external changes

    func reload(document: PlainXDocument, tab: DocumentTabController) {
        guard let url = document.url else { return }
        do {
            tab.saveViewStates()
            let loaded = try FileLoader.load(url: url, preferredEncoding: document.encoding.hasBOM ? document.encoding : nil)
            tab.replaceDocumentText(loaded.text, markDirty: false)
            document.encoding = loaded.encoding
            document.eolMode = loaded.eolMode
            document.lastKnownMetadata = loaded.metadata
            document.hasExternalChange = false
            document.loadDiagnostic = loaded.diagnostic
            tab.activePane.facade.eolMode = document.eolMode.concreteFallback
            if let state = document.viewStates[tab.activePane.paneID] {
                tab.activePane.applyViewState(state)
            }
            tab.activePane.restoreBookmarks(from: document)
            tab.markClean()
            tab.controller.clearBanners()
            tab.controller.updateTabStrip()
            tab.controller.updateStatusBar()
            recoveryStore.discardSnapshot(for: document)
        } catch {
            presentError(error, in: tab.controller)
        }
    }

    /// Reloads the active tab from disk (regular editor or Large File viewer).
    func reloadActiveTab(in window: MainWindowController) {
        guard let tab = window.activeTab, let url = tab.document.url else { return }
        if let editorTab = tab as? DocumentTabController {
            reload(document: tab.document, tab: editorTab)
            return
        }
        if let largeTab = tab as? LargeFileTabController {
            guard FileManager.default.fileExists(atPath: url.path) else {
                presentError(FileLoaderError.unreadable(url, CocoaError(.fileNoSuchFile)), in: window)
                return
            }
            largeTab.viewer.reloadFromDisk()
            window.clearBanners()
            window.updateTabStrip()
        }
    }

    func locateMissingFile(for document: PlainXDocument, tab: DocumentTabController) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Locate “\(document.displayName)”"
        if let window = tab.controller.window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self, response == .OK, let url = panel.url else { return }
                document.rename(to: url)
                if let metadata = FileLoader.metadata(for: url) {
                    document.lastKnownMetadata = metadata
                }
                document.hasExternalChange = false
                tab.controller.startWatching(document)
                tab.controller.updateTabStrip()
                tab.controller.updateWindowTitle()
                self.reload(document: document, tab: tab)
            }
        }
    }

    func compareWithDisk(document: PlainXDocument, tab: DocumentTabController) {
        guard let url = document.url, let diskText = try? FileLoader.load(url: url).text else { return }
        presentDiff(leftTitle: "On Disk", leftText: diskText,
                    rightTitle: "Editor: \(document.displayName)", rightText: tab.activePane.facade.text,
                    in: tab.controller)
    }

    // MARK: - Close flows

    func closeOtherTabs(_ tabID: UUID, in window: MainWindowController) {
        for tab in window.tabs where tab.id != tabID && !tab.document.isPinned {
            _ = window.closeTab(id: tab.id)
        }
    }

    func closeTabsToRight(of tabID: UUID, in window: MainWindowController) {
        guard let index = window.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        for tab in window.tabs.dropFirst(index + 1).reversed() where !tab.document.isPinned {
            _ = window.closeTab(id: tab.id)
        }
    }

    func closeAllTabs(in window: MainWindowController) {
        for tab in window.tabs.reversed() {
            _ = window.closeTab(id: tab.id)
        }
    }

    func closeWindow(_ window: MainWindowController) {
        if window.window?.windowController === window {
            window.window?.performClose(nil)
        }
    }

    func reopenLastClosedTab(in window: MainWindowController) {
        guard let url = closedTabs.popLast() else {
            NSSound.beep()
            return
        }
        open(urls: [url], in: window)
    }

    private var closedTabs: [URL] = []

    func noteClosedTab(_ url: URL?) {
        if let url, !url.path.isEmpty {
            closedTabs.append(url)
            if closedTabs.count > 20 { closedTabs.removeFirst() }
        }
    }

    // MARK: - Duplicate

    func duplicateDocumentInNewTab(_ tab: DocumentTabController) {
        let document = PlainXDocument(url: nil, untitledName: "\(tab.document.displayName) copy")
        document.encoding = tab.document.encoding
        document.eolMode = tab.document.eolMode
        document.languageOverrideID = tab.document.languageOverrideID
        let loaded = LoadedFile(text: tab.activePane.facade.text, encoding: document.encoding,
                                eolMode: document.eolMode,
                                metadata: FileMetadata(modificationDate: Date(), fileSize: 0, fileIdentifier: nil),
                                diagnostic: nil, hadInvalidSequences: false)
        pendingLoads[document.id] = loaded
        tab.controller.addTab(for: document, select: true)
    }

    // MARK: - Encoding / EOL / language menus

    func convertEncoding(document: PlainXDocument, tab: DocumentTabController, to encoding: TextEncoding) {
        // The Scintilla buffer is always UTF-8 internally; changing the
        // document encoding only changes how it will be written.
        document.encoding = encoding
        tab.markDirtyIfNeeded()
        tab.controller.updateStatusBar()
        tab.controller.updateTabStrip()
    }

    func reopenWithEncoding(document: PlainXDocument, tab: DocumentTabController, encoding: TextEncoding) {
        guard let url = document.url else { return }
        do {
            let loaded = try FileLoader.load(url: url, preferredEncoding: encoding)
            document.encoding = loaded.encoding
            document.eolMode = loaded.eolMode
            tab.replaceDocumentText(loaded.text, markDirty: false)
            tab.activePane.facade.eolMode = document.eolMode.concreteFallback
            document.lastKnownMetadata = loaded.metadata
            tab.markClean()
            tab.controller.updateStatusBar()
        } catch {
            presentError(error, in: tab.controller)
        }
    }

    func convertLineEndings(document: PlainXDocument, tab: DocumentTabController, to mode: EOLMode) {
        tab.performSyncedEdit { pane in
            pane.facade.convertEOLs(to: mode)
        }
        document.eolMode = mode
        document.isDirty = true
        tab.controller.updateStatusBar()
        tab.controller.updateTabStrip()
    }

    func showEncodingMenu(for tab: DocumentTabController?, relativeTo anchor: NSView, in window: MainWindowController) {
        guard let tab else { return }
        let menu = NSMenu()
        let changeHeader = NSMenuItem(title: "Change Encoding (on save)", action: nil, keyEquivalent: "")
        menu.addItem(changeHeader)
        for encoding in TextEncoding.selectable {
            let item = NSMenuItem(title: encoding.displayName, action: #selector(EncodingMenuHandler.changeEncoding(_:)), keyEquivalent: "")
            item.target = encodingMenuHandler
            item.representedObject = encoding
            item.state = (encoding == tab.document.encoding) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reopen with Encoding…", action: nil, keyEquivalent: "")
        for encoding in TextEncoding.selectable where tab.document.url != nil {
            let item = NSMenuItem(title: encoding.displayName, action: #selector(EncodingMenuHandler.reopenWithEncoding(_:)), keyEquivalent: "")
            item.target = encodingMenuHandler
            item.representedObject = encoding
            menu.addItem(item)
        }
        encodingMenuHandler.tab = tab
        encodingMenuHandler.window = window
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 2), in: anchor)
    }

    func showEOLMenu(for tab: DocumentTabController?, relativeTo anchor: NSView, in window: MainWindowController) {
        guard let tab else { return }
        let menu = NSMenu()
        for mode in [EOLMode.lf, .crlf, .cr] {
            let item = NSMenuItem(title: "Convert to \(mode.longDisplayName)", action: #selector(EOLMenuHandler.convert(_:)), keyEquivalent: "")
            item.target = eolMenuHandler
            item.representedObject = mode.rawValue
            menu.addItem(item)
        }
        if tab.document.eolMode == .mixed {
            let note = NSMenuItem(title: "Document currently has mixed line endings", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(.separator())
            menu.addItem(note)
        }
        eolMenuHandler.tab = tab
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 2), in: anchor)
    }

    func showLanguageMenu(for tab: DocumentTabController?, relativeTo anchor: NSView, in window: MainWindowController) {
        guard let tab else { return }
        let menu = makeLanguageMenu(tab: tab)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 2), in: anchor)
    }

    func makeLanguageMenu(tab: DocumentTabController) -> NSMenu {
        let menu = NSMenu()
        let auto = NSMenuItem(title: "Auto-detect", action: #selector(LanguageMenuHandler.setAuto(_:)), keyEquivalent: "")
        auto.target = languageMenuHandler
        auto.state = tab.document.languageOverrideID == nil ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        let languages = LanguageRegistry.all.sorted { $0.displayName < $1.displayName }
        for language in languages {
            let item = NSMenuItem(title: language.displayName, action: #selector(LanguageMenuHandler.setLanguage(_:)), keyEquivalent: "")
            item.target = languageMenuHandler
            item.representedObject = language.id
            item.state = tab.document.languageOverrideID == language.id ? .on : .off
            menu.addItem(item)
        }
        languageMenuHandler.tab = tab
        return menu
    }

    func showIndentationMenu(relativeTo anchor: NSView, in window: MainWindowController) {
        let menu = NSMenu()
        for width in [2, 4, 8] {
            let item = NSMenuItem(title: "Width: \(width)", action: #selector(IndentationMenuHandler.setWidth(_:)), keyEquivalent: "")
            item.target = indentationMenuHandler
            item.representedObject = width
            item.state = preferences.tabWidth == width ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let tabsItem = NSMenuItem(title: "Indent Using Tabs", action: #selector(IndentationMenuHandler.useTabs(_:)), keyEquivalent: "")
        tabsItem.target = indentationMenuHandler
        tabsItem.state = preferences.useTabs ? .on : .off
        menu.addItem(tabsItem)
        let spacesItem = NSMenuItem(title: "Indent Using Spaces", action: #selector(IndentationMenuHandler.useSpaces(_:)), keyEquivalent: "")
        spacesItem.target = indentationMenuHandler
        spacesItem.state = preferences.useTabs ? .off : .on
        menu.addItem(spacesItem)
        menu.addItem(.separator())
        let convertToSpaces = NSMenuItem(title: "Convert Indentation to Spaces", action: #selector(IndentationMenuHandler.convertToSpaces(_:)), keyEquivalent: "")
        convertToSpaces.target = indentationMenuHandler
        menu.addItem(convertToSpaces)
        let convertToTabs = NSMenuItem(title: "Convert Indentation to Tabs", action: #selector(IndentationMenuHandler.convertToTabs(_:)), keyEquivalent: "")
        convertToTabs.target = indentationMenuHandler
        menu.addItem(convertToTabs)
        indentationMenuHandler.window = window
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 2), in: anchor)
    }

    func promptGoToLine(in window: MainWindowController) {
        guard let tab = window.activeTab else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter a line number (and optional column, e.g. 42:10)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Line[:Column]"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        if let window = window.window {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                let parts = field.stringValue.split(separator: ":")
                if let lineNumber = Int(parts.first ?? "") {
                    var column = 0
                    if parts.count > 1, let parsedColumn = Int(parts[1]) { column = max(0, parsedColumn - 1) }
                    guard let tab = tab as? DocumentTabController else { return }
                    tab.activePane.facade.gotoLine(lineNumber - 1, column: column)
                    tab.activePane.facade.scrollCaret()
                }
            }
        }
    }

    private(set) lazy var encodingMenuHandler = EncodingMenuHandler(coordinator: self)
    private(set) lazy var eolMenuHandler = EOLMenuHandler(coordinator: self)
    private(set) lazy var languageMenuHandler = LanguageMenuHandler(coordinator: self)
    private(set) lazy var indentationMenuHandler = IndentationMenuHandler(coordinator: self)

    // MARK: - Find in Files entry point (implemented in SearchInFilesPanel)

    func promptFindInFiles(root: URL?) {
        SearchInFilesPanelController.shared.present(coordinator: self, root: root, in: activeWindow)
    }

    func presentDiff(leftTitle: String, leftText: String, rightTitle: String, rightText: String,
                     in window: MainWindowController?) {
        DiffWindowController.present(leftTitle: leftTitle, leftText: leftText,
                                     rightTitle: rightTitle, rightText: rightText,
                                     coordinator: self, in: window)
    }

    // MARK: - Session

    func scheduleSessionSave() {
        guard preferences.sessionRestoreEnabled else { return }
        SessionSaver.shared.scheduleSave(coordinator: self)
    }

    var hasUnsavedDocuments: Bool {
        windows.contains { window in
            window.tabs.contains { $0.document.isDirty }
        }
    }

    func saveSessionNow() {
        guard preferences.sessionRestoreEnabled else { return }
        do {
            try sessionStore.save(from: self)
        } catch {
            Log.session.error("Session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func restoreSession() {
        guard preferences.sessionRestoreEnabled else {
            newWindow().addTab(for: makeUntitledDocument(), select: true)
            return
        }
        do {
            let restored = try sessionStore.restore(into: self)
            if !restored {
                newWindow().addTab(for: makeUntitledDocument(), select: true)
            }
        } catch {
            Log.session.error("Session restore failed: \(error.localizedDescription, privacy: .public)")
            sessionRestoreFailed = true
            newWindow().addTab(for: makeUntitledDocument(), select: true)
        }
        recoveryStore.restoreUnclaimedSnapshots(into: self)
    }

    // MARK: - Errors

    func presentError(_ error: Error, in window: MainWindowController?) {
        let alert = NSAlert()
        alert.messageText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = window?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

// MARK: - Menu action handlers

final class EncodingMenuHandler: NSObject {
    weak var coordinator: AppCoordinator?
    weak var tab: DocumentTabController?
    weak var window: MainWindowController?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    @objc func changeEncoding(_ sender: NSMenuItem) {
        guard let coordinator, let tab, let encoding = sender.representedObject as? TextEncoding else { return }
        coordinator.convertEncoding(document: tab.document, tab: tab, to: encoding)
    }

    @objc func reopenWithEncoding(_ sender: NSMenuItem) {
        guard let coordinator, let tab, let encoding = sender.representedObject as? TextEncoding else { return }
        coordinator.reopenWithEncoding(document: tab.document, tab: tab, encoding: encoding)
    }
}

final class EOLMenuHandler: NSObject {
    weak var coordinator: AppCoordinator?
    weak var tab: DocumentTabController?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    @objc func convert(_ sender: NSMenuItem) {
        guard let coordinator, let tab, let raw = sender.representedObject as? String,
              let mode = EOLMode(rawValue: raw) else { return }
        coordinator.convertLineEndings(document: tab.document, tab: tab, to: mode)
    }
}

final class LanguageMenuHandler: NSObject {
    weak var coordinator: AppCoordinator?
    weak var tab: DocumentTabController?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    @objc func setAuto(_ sender: NSMenuItem) {
        guard let tab else { return }
        tab.document.languageOverrideID = nil
        tab.activePane.setLanguage(LanguageRegistry.language(for: tab.document.url))
        tab.controller.updateStatusBar()
    }

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let tab, let languageID = sender.representedObject as? String else { return }
        tab.document.languageOverrideID = languageID
        tab.activePane.setLanguage(LanguageRegistry.language(withID: languageID))
        tab.controller.updateStatusBar()
    }
}

final class IndentationMenuHandler: NSObject {
    weak var coordinator: AppCoordinator?
    weak var window: MainWindowController?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    private var activePane: EditorPaneController? { window?.activeEditorTab?.activePane }

    @objc func setWidth(_ sender: NSMenuItem) {
        guard let width = sender.representedObject as? Int else { return }
        Preferences.shared.tabWidth = width
        activePane?.facade.setTabWidth(width)
        window?.updateStatusBar()
    }

    @objc func useTabs(_ sender: NSMenuItem) {
        Preferences.shared.useTabs = true
        activePane?.facade.setUseTabs(true)
        window?.updateStatusBar()
    }

    @objc func useSpaces(_ sender: NSMenuItem) {
        Preferences.shared.useTabs = false
        activePane?.facade.setUseTabs(false)
        window?.updateStatusBar()
    }

    @objc func convertToSpaces(_ sender: NSMenuItem) {
        guard let window, let tab = window.activeEditorTab else { return }
        let width = Preferences.shared.tabWidth
        tab.performSyncedEdit { pane in
            TransformService.convertTabsToSpaces(pane: pane, tabWidth: width)
        }
        tab.controller.updateTabStrip()
    }

    @objc func convertToTabs(_ sender: NSMenuItem) {
        guard let window, let tab = window.activeEditorTab else { return }
        let width = Preferences.shared.tabWidth
        tab.performSyncedEdit { pane in
            TransformService.convertSpacesToTabs(pane: pane, tabWidth: width)
        }
        tab.controller.updateTabStrip()
    }
}
