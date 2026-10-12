//
//  MainMenuBuilder.swift
//  PlainX Editor
//
//  Builds the whole menu bar from the command registry so menus, the command
//  palette, and macros stay in sync.
//

import AppKit

enum MainMenuBuilder {

    static func buildMainMenu(coordinator: AppCoordinator, dispatcher: CommandDispatcher) -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(appMenuItem(dispatcher))
        mainMenu.addItem(fileMenuItem(coordinator, dispatcher))
        mainMenu.addItem(editMenuItem(dispatcher))
        mainMenu.addItem(searchMenuItem(dispatcher))
        mainMenu.addItem(viewMenuItem(dispatcher))
        mainMenu.addItem(languageMenuItem(dispatcher))
        mainMenu.addItem(toolsMenuItem(dispatcher))
        mainMenu.addItem(macroMenuItem(coordinator, dispatcher))
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem(dispatcher))
        return mainMenu
    }

    private static func menuItem(_ id: String, _ dispatcher: CommandDispatcher) -> NSMenuItem {
        guard let command = CommandRegistry.shared.command(id: id) else {
            return NSMenuItem(title: "Missing: \(id)", action: nil, keyEquivalent: "")
        }
        return .commandItem(command, dispatcher: dispatcher)
    }

    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        for item in items {
            menu.addItem(item)
        }
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }

    private static func separator() -> NSMenuItem { .separator() }

    // MARK: - Menus

    private static func appMenuItem(_ dispatcher: CommandDispatcher) -> NSMenuItem {
        let appName = "PlainX"
        let menu = NSMenu(title: appName)
        menu.addItem(menuItem("app.about", dispatcher))
        menu.addItem(separator())
        menu.addItem(menuItem("app.preferences", dispatcher))
        menu.addItem(separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services
        menu.addItem(separator())
        let hideItem = NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(hideItem)
        menu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        menu.items.last?.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(separator())
        menu.addItem(menuItem("app.quit", dispatcher))
        let top = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }

    private static func fileMenuItem(_ coordinator: AppCoordinator, _ dispatcher: CommandDispatcher) -> NSMenuItem {
        var items: [NSMenuItem] = [
            menuItem("file.new", dispatcher),
            menuItem("file.newWindow", dispatcher),
            menuItem("file.open", dispatcher),
            menuItem("file.openFolder", dispatcher),
        ]

        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = RecentMenuDelegate.shared
        RecentMenuDelegate.shared.coordinator = coordinator
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        items.append(recentItem)

        items.append(separator())
        items.append(menuItem("file.closeTab", dispatcher))
        items.append(menuItem("file.closeWindow", dispatcher))
        items.append(menuItem("file.reopenClosedTab", dispatcher))
        items.append(separator())
        items.append(menuItem("file.save", dispatcher))
        items.append(menuItem("file.saveAs", dispatcher))
        items.append(menuItem("file.saveAll", dispatcher))
        items.append(separator())
        items.append(menuItem("file.rename", dispatcher))
        items.append(menuItem("file.revealInFinder", dispatcher))
        items.append(menuItem("file.copyPath", dispatcher))
        items.append(separator())
        items.append(menuItem("file.print", dispatcher))
        items.append(menuItem("file.hashFile", dispatcher))
        return submenu("File", items: items)
    }

    private static func editMenuItem(_ dispatcher: CommandDispatcher) -> NSMenuItem {
        var items: [NSMenuItem] = []

        // Standard edit actions go through the responder chain so they work in
        // any focused control (editor, find bar, search fields).
        items.append(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        items.append(redo)
        items.append(separator())
        items.append(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        items.append(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        items.append(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        items.append(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        items.append(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        items.append(separator())

        items.append(submenu("Line Operations", items: [
            menuItem("edit.duplicateLine", dispatcher),
            menuItem("edit.deleteLine", dispatcher),
            menuItem("edit.moveLineUp", dispatcher),
            menuItem("edit.moveLineDown", dispatcher),
            separator(),
            menuItem("edit.joinLines", dispatcher),
            menuItem("edit.splitLines", dispatcher),
            separator(),
            menuItem("edit.sortLinesAscending", dispatcher),
            menuItem("edit.sortLinesDescending", dispatcher),
            menuItem("edit.sortLinesCaseInsensitive", dispatcher),
            menuItem("edit.removeDuplicateLines", dispatcher),
            menuItem("edit.removeEmptyLines", dispatcher),
            menuItem("edit.reverseLines", dispatcher),
        ]))

        items.append(submenu("Whitespace", items: [
            menuItem("edit.trimTrailingWhitespace", dispatcher),
            menuItem("edit.trimLeadingWhitespace", dispatcher),
            separator(),
            menuItem("edit.convertTabsToSpaces", dispatcher),
            menuItem("edit.convertSpacesToTabs", dispatcher),
        ]))

        items.append(submenu("Case", items: [
            menuItem("edit.uppercase", dispatcher),
            menuItem("edit.lowercase", dispatcher),
            menuItem("edit.titleCase", dispatcher),
            menuItem("edit.sentenceCase", dispatcher),
            menuItem("edit.swapCase", dispatcher),
        ]))

        items.append(separator())
        items.append(menuItem("edit.toggleComment", dispatcher))
        items.append(menuItem("edit.indent", dispatcher))
        items.append(menuItem("edit.outdent", dispatcher))
        items.append(menuItem("edit.completeWord", dispatcher))
        items.append(separator())
        items.append(menuItem("edit.selectLine", dispatcher))
        items.append(menuItem("edit.selectWord", dispatcher))
        items.append(submenu("Multiple Carets", items: [
            menuItem("edit.addCaretAbove", dispatcher),
            menuItem("edit.addCaretBelow", dispatcher),
            menuItem("edit.selectNextOccurrence", dispatcher),
            menuItem("edit.selectAllOccurrences", dispatcher),
            separator(),
            menuItem("edit.toggleColumnSelection", dispatcher),
        ]))
        items.append(submenu("Bookmarks", items: [
            menuItem("edit.toggleBookmark", dispatcher),
            menuItem("edit.nextBookmark", dispatcher),
            menuItem("edit.previousBookmark", dispatcher),
            menuItem("edit.clearBookmarks", dispatcher),
        ]))
        return submenu("Edit", items: items)
    }

    private static func searchMenuItem(_ dispatcher: CommandDispatcher) -> NSMenuItem {
        submenu("Search", items: [
            menuItem("search.find", dispatcher),
            menuItem("search.findNext", dispatcher),
            menuItem("search.findPrevious", dispatcher),
            menuItem("search.replace", dispatcher),
            menuItem("search.useSelectionForFind", dispatcher),
            separator(),
            menuItem("search.findInFiles", dispatcher),
            separator(),
            menuItem("nav.goToLine", dispatcher),
        ])
    }

    private static func viewMenuItem(_ dispatcher: CommandDispatcher) -> NSMenuItem {
        submenu("View", items: [
            menuItem("view.zoomIn", dispatcher),
            menuItem("view.zoomOut", dispatcher),
            menuItem("view.zoomReset", dispatcher),
            separator(),
            menuItem("view.toggleWordWrap", dispatcher),
            menuItem("view.toggleLineNumbers", dispatcher),
            menuItem("view.toggleWhitespace", dispatcher),
            menuItem("view.toggleEOL", dispatcher),
            menuItem("view.toggleIndentGuides", dispatcher),
            menuItem("view.toggleCurrentLineHighlight", dispatcher),
            separator(),
            menuItem("view.splitView", dispatcher),
            menuItem("view.unsplit", dispatcher),
            menuItem("nav.focusNextPane", dispatcher),
            separator(),
            menuItem("view.foldAll", dispatcher),
            menuItem("view.unfoldAll", dispatcher),
            menuItem("view.foldCurrent", dispatcher),
            menuItem("view.unfoldCurrent", dispatcher),
            separator(),
            submenu("Appearance", items: [
                menuItem("view.themeSystem", dispatcher),
                menuItem("view.themeLight", dispatcher),
                menuItem("view.themeDark", dispatcher),
            ]),
            separator(),
            menuItem("palette.show", dispatcher),
            menuItem("view.toggleFullScreen", dispatcher),
        ])
    }

    private static func languageMenuItem(_ dispatcher: CommandDispatcher) -> NSMenuItem {
        let items = CommandRegistry.shared.commands(inCategory: "Language").map {
            NSMenuItem.commandItem($0, dispatcher: dispatcher)
        }
        return submenu("Language", items: items)
    }

    private static func toolsMenuItem(_ dispatcher: CommandDispatcher) -> NSMenuItem {
        let items: [NSMenuItem] = [
            menuItem("tools.formatJSON", dispatcher),
            menuItem("tools.minifyJSON", dispatcher),
            menuItem("tools.validateJSON", dispatcher),
            separator(),
            menuItem("tools.formatXML", dispatcher),
            menuItem("tools.validateXML", dispatcher),
            separator(),
            submenu("Encode / Decode", items: [
                menuItem("tools.base64Encode", dispatcher),
                menuItem("tools.base64Decode", dispatcher),
                separator(),
                menuItem("tools.urlEncode", dispatcher),
                menuItem("tools.urlDecode", dispatcher),
                separator(),
                menuItem("tools.htmlEscape", dispatcher),
                menuItem("tools.htmlUnescape", dispatcher),
            ]),
            submenu("Hash Selection", items: [
                menuItem("tools.hashSHA256", dispatcher),
                menuItem("tools.hashSHA512", dispatcher),
                separator(),
                menuItem("tools.hashSHA1", dispatcher),
                menuItem("tools.hashMD5", dispatcher),
            ]),
            separator(),
            menuItem("tools.insertTimestamp", dispatcher),
            separator(),
            menuItem("diff.compareWithFile", dispatcher),
            menuItem("diff.compareWithDisk", dispatcher),
            menuItem("diff.compareTwoFiles", dispatcher),
            separator(),
            menuItem("tools.copyDiagnostics", dispatcher),
        ]
        return submenu("Tools", items: items)
    }

    private static func macroMenuItem(_ coordinator: AppCoordinator, _ dispatcher: CommandDispatcher) -> NSMenuItem {
        var items: [NSMenuItem] = [
            menuItem("macro.startRecording", dispatcher),
            menuItem("macro.stopRecording", dispatcher),
            separator(),
            menuItem("macro.playLast", dispatcher),
            menuItem("macro.playLastMultiple", dispatcher),
        ]
        let savedMacros = coordinator.macroEngine.macros
        if !savedMacros.isEmpty {
            items.append(separator())
            for macro in savedMacros {
                let item = NSMenuItem(title: macro.name, action: #selector(MacroMenuTarget.playSavedMacro(_:)), keyEquivalent: "")
                item.target = MacroMenuTarget.shared
                item.representedObject = macro.id.uuidString
                items.append(item)
            }
        }
        return submenu("Macro", items: items)
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        menu.addItem(separator())
        // Next Window command from the registry would require the dispatcher;
        // the standard "Bring All to Front" keeps macOS behavior predictable.
        menu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        let top = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        top.submenu = menu
        NSApp.windowsMenu = menu
        return top
    }

    private static func helpMenuItem(_ dispatcher: CommandDispatcher) -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        menu.addItem(menuItem("help.shortcuts", dispatcher))
        menu.addItem(menuItem("help.releaseNotes", dispatcher))
        let top = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        top.submenu = menu
        NSApp.helpMenu = menu
        return top
    }
}

// MARK: - Dynamic menu delegates

final class RecentMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentMenuDelegate()
    weak var coordinator: AppCoordinator?

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let coordinator else { return }
        if coordinator.recentURLs.isEmpty {
            let empty = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for url in coordinator.recentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        coordinator?.open(urls: [url], in: nil)
    }

    @objc private func clearRecent() {
        coordinator?.clearRecentFiles()
    }
}

final class MacroMenuTarget: NSObject {
    static let shared = MacroMenuTarget()
    weak var coordinator: AppCoordinator?

    @objc func playSavedMacro(_ sender: NSMenuItem) {
        guard let coordinator,
              let idString = sender.representedObject as? String,
              let macro = coordinator.macroEngine.macros.first(where: { $0.id.uuidString == idString }) else { return }
        let window = NSApp.keyWindow?.windowController as? MainWindowController ?? coordinator.activeWindow
        guard let tab = window?.activeEditorTab else { return }
        coordinator.macroEngine.play(macro, times: 1, tab: tab, coordinator: coordinator)
        tab.markDirtyIfNeeded()
    }
}
