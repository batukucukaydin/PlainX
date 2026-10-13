//
//  DocumentTab.swift
//  PlainX Editor
//
//  Content abstraction shared by editor tabs and the Large File viewer tab.
//

import AppKit

protocol DocumentTab: AnyObject {
    var id: UUID { get }
    var document: PlainXDocument { get }
    /// Root view shown in the window's content container.
    var tabContentView: NSView { get }
    var isSplit: Bool { get }
    var isLargeFileViewer: Bool { get }
    /// The Welcome screen shown on first launch and when the last tab closes.
    var isWelcome: Bool { get }
    /// State snapshot for the window status bar.
    func statusSnapshot() -> StatusBarView.State
    func saveViewStates()
    func markClean()
    func markDirtyIfNeeded()
    func focusContent()
    /// Receives change notifications routed to the owning window.
    var tabDelegate: DocumentTabControllerDelegate? { get set }
}

extension DocumentTab {
    var isWelcome: Bool { false }
}

/// Large File Mode tab: owns a read-only viewer for one huge file.
final class LargeFileTabController: DocumentTab {
    let id = UUID()
    let document: PlainXDocument
    let viewer: LargeFileViewController
    weak var tabDelegate: DocumentTabControllerDelegate?

    var tabContentView: NSView { viewer.view }
    var isSplit: Bool { false }
    var isLargeFileViewer: Bool { true }

    init(document: PlainXDocument, backing: LargeFileBacking, theme: EditorTheme) {
        self.document = document
        self.viewer = LargeFileViewController(backing: backing, theme: theme)
        document.isLargeFileMode = true
    }

    func statusSnapshot() -> StatusBarView.State {
        viewer.statusSnapshot()
    }

    func saveViewStates() {}

    func markClean() {
        document.isDirty = false
    }

    func markDirtyIfNeeded() {}

    func focusContent() {
        viewer.focusContent()
    }

    func applyTheme(_ theme: EditorTheme) {
        viewer.applyTheme(theme)
    }
}
