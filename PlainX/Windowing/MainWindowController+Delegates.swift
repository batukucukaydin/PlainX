//
//  MainWindowController+Delegates.swift
//  PlainX Editor
//
//  Delegate conformances for the window: tab strip, status bar, document
//  tabs, and the Large File viewer. Split out of MainWindowController.swift.
//

import AppKit

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
