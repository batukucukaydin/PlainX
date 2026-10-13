//
//  SessionStore.swift
//  PlainX Editor
//
//  Session persistence: open windows, tabs, per-view caret/scroll state.
//  Versioned JSON in Application Support. Never stores file contents; unsaved
//  work is covered by RecoveryStore.
//

import AppKit

struct SessionFile: Codable {
    var version: Int
    var windows: [SessionWindow]
}

struct SessionWindow: Codable {
    var frameX: Double?
    var frameY: Double?
    var frameWidth: Double?
    var frameHeight: Double?
    var activeTabIndex: Int
    var tabs: [SessionTab]
}

struct SessionTab: Codable {
    var urlPath: String?
    var untitledName: String?
    var encodingID: String
    var encodingHasBOM: Bool
    var eol: String
    var languageOverrideID: String?
    var isPinned: Bool
    var wordWrapOverride: Bool?
    var bookmarks: [Int]
    var views: [SessionView]
    /// "vertical" (side by side) or "horizontal" (stacked); nil when unsplit.
    var splitOrientation: String?
}

struct SessionView: Codable {
    var caretPosition: Int
    var anchorPosition: Int
    var firstVisibleLine: Int
    var xOffset: Int
}

enum SessionStoreError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Saved session uses a newer format (version \(version))."
        }
    }
}

final class SessionStore {
    static let currentVersion = 1

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = base.appendingPathComponent("PlainX", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("Session.json")
        }
    }

    func save(from coordinator: AppCoordinator) throws {
        var windows: [SessionWindow] = []
        for window in coordinator.windows {
            let frame = window.window?.frame
            var tabs: [SessionTab] = []
            for tab in window.tabs {
                guard !tab.isWelcome else { continue }
                tab.saveViewStates()
                let document = tab.document
                let views = (tab as? DocumentTabController)?.panes.compactMap { pane -> SessionView? in
                    guard let state = document.viewStates[pane.paneID] else { return nil }
                    return SessionView(caretPosition: state.caretPosition,
                                       anchorPosition: state.anchorPosition,
                                       firstVisibleLine: state.firstVisibleLine,
                                       xOffset: state.xOffset)
                } ?? []
                var splitOrientation: String?
                if let editorTab = tab as? DocumentTabController, editorTab.isSplit {
                    splitOrientation = editorTab.splitOrientation == .horizontal ? "horizontal" : "vertical"
                }
                let sessionTab = SessionTab(
                    urlPath: document.url?.path,
                    untitledName: document.isUntitled ? document.untitledName : nil,
                    encodingID: document.encoding.identifier,
                    encodingHasBOM: document.encoding.hasBOM,
                    eol: document.eolMode.rawValue,
                    languageOverrideID: document.languageOverrideID,
                    isPinned: document.isPinned,
                    wordWrapOverride: document.wordWrapOverride,
                    bookmarks: document.bookmarks.sorted(),
                    views: views,
                    splitOrientation: splitOrientation
                )
                tabs.append(sessionTab)
            }
            // A window showing only the Welcome screen has nothing to
            // restore; persisting it as a zero-tab window would make the next
            // launch open and immediately close every window.
            guard !tabs.isEmpty else { continue }
            windows.append(SessionWindow(
                frameX: frame.map { Double($0.origin.x) }, frameY: frame.map { Double($0.origin.y) },
                frameWidth: frame.map { Double($0.width) }, frameHeight: frame.map { Double($0.height) },
                activeTabIndex: window.tabs.firstIndex(where: { $0 === window.activeTab }) ?? 0,
                tabs: tabs
            ))
        }
        let session = SessionFile(version: SessionStore.currentVersion, windows: windows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Restores the saved session. Returns true when at least one window was
    /// restored.
    @discardableResult
    func restore(into coordinator: AppCoordinator) throws -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let session = try JSONDecoder().decode(SessionFile.self, from: data)
        guard session.version <= SessionStore.currentVersion else {
            throw SessionStoreError.unsupportedVersion(session.version)
        }
        guard !session.windows.isEmpty else { return false }

        var restoredAny = false
        for windowSession in session.windows {
            let window = coordinator.newWindow()
            if let x = windowSession.frameX, let y = windowSession.frameY,
               let width = windowSession.frameWidth, let height = windowSession.frameHeight {
                window.window?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
            }
            var didAddTab = false
            for tabSession in windowSession.tabs {
                if let document = makeDocument(from: tabSession, into: coordinator) {
                    window.addTab(for: document, select: false)
                    if let editorTab = window.tabs.last as? DocumentTabController {
                        if tabSession.views.count > 1 {
                            let orientation: SplitOrientation =
                                tabSession.splitOrientation == "horizontal" ? .horizontal : .vertical
                            editorTab.splitIntoSecondPane(orientation: orientation)
                        }
                        for (index, view) in tabSession.views.enumerated() where index < editorTab.panes.count {
                            apply(viewState: view, to: editorTab.panes[index])
                        }
                    }
                    didAddTab = true
                }
            }
            if didAddTab {
                window.selectTab(at: min(windowSession.activeTabIndex, window.tabs.count - 1))
                restoredAny = true
            } else {
                // Nothing restorable in this window: show the Welcome screen
                // rather than closing it (closing the last window would quit
                // the app on launch).
                coordinator.showWelcome(in: window)
                restoredAny = true
            }
        }
        return restoredAny
    }

    private func makeDocument(from tabSession: SessionTab, into coordinator: AppCoordinator) -> PlainXDocument? {
        if let path = tabSession.urlPath {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                // Missing file: open an empty tab that offers Locate/Remove.
                let document = PlainXDocument(url: url)
                document.hasExternalChange = true
                document.loadDiagnostic = "This file could not be found at its previous location."
                return document
            }
            do {
                let document = try coordinator.openDocument(at: url)
                configure(document: document, from: tabSession)
                return document
            } catch {
                Log.session.error("Session restore failed for one file: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        } else {
            let document = PlainXDocument(url: nil, untitledName: tabSession.untitledName ?? "Untitled")
            configure(document: document, from: tabSession)
            if let recovered = coordinator.recoveryStore.recoveryText(for: document) {
                let loaded = LoadedFile(text: recovered, encoding: document.encoding, eolMode: document.eolMode,
                                        metadata: FileMetadata(modificationDate: Date(), fileSize: 0, fileIdentifier: nil),
                                        diagnostic: "Restored unsaved changes from a recovery snapshot.",
                                        hadInvalidSequences: false)
                coordinator.setPendingLoad(loaded, for: document)
                document.isDirty = true
            }
            return document
        }
    }

    private func configure(document: PlainXDocument, from tabSession: SessionTab) {
        if let encoding = TextEncoding.selectable.first(where: {
            $0.identifier == tabSession.encodingID && $0.hasBOM == tabSession.encodingHasBOM
        }) {
            document.encoding = encoding
        }
        document.eolMode = EOLMode(rawValue: tabSession.eol) ?? .lf
        document.languageOverrideID = tabSession.languageOverrideID
        document.isPinned = tabSession.isPinned
        document.wordWrapOverride = tabSession.wordWrapOverride
        document.bookmarks = Set(tabSession.bookmarks)
    }

    private func apply(viewState: SessionView?, to pane: EditorPaneController) {
        guard let viewState else { return }
        pane.applyViewState(EditorViewState(
            caretPosition: viewState.caretPosition,
            anchorPosition: viewState.anchorPosition,
            firstVisibleLine: viewState.firstVisibleLine,
            xOffset: viewState.xOffset,
            selections: []
        ))
        if let document = pane.document {
            pane.restoreBookmarks(from: document)
        }
    }
}

/// Debounced session writer used by AppCoordinator.
final class SessionSaver {
    static let shared = SessionSaver()
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue.main

    func scheduleSave(coordinator: AppCoordinator) {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak coordinator] in
            coordinator?.saveSessionNow()
        }
        pendingWorkItem = work
        queue.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
