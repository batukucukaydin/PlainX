//
//  AppCoordinator+MenuHandlers.swift
//  PlainX Editor
//
//  Small target/action handler objects used by the status-bar quick menus
//  (encoding, line endings, language, indentation). Split out of
//  AppCoordinator.swift to keep that file focused on orchestration.
//

import AppKit

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
