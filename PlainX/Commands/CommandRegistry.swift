//
//  CommandRegistry.swift
//  PlainX Editor
//
//  Single source of truth for every user-invokable command. Menus, the
//  command palette, macros and future plugins all dispatch through here.
//

import AppKit

struct KeyBinding: Equatable {
    var key: String            // lowercase character or special key token
    var modifiers: NSEvent.ModifierFlags
    var displayString: String

    static func cmd(_ key: String) -> KeyBinding {
        KeyBinding(key: key, modifiers: .command, displayString: "⌘" + key.uppercased())
    }

    static func cmdShift(_ key: String) -> KeyBinding {
        KeyBinding(key: key, modifiers: [.command, .shift], displayString: "⇧⌘" + key.uppercased())
    }

    static func cmdOption(_ key: String) -> KeyBinding {
        KeyBinding(key: key, modifiers: [.command, .option], displayString: "⌥⌘" + key.uppercased())
    }

    static func cmdControl(_ key: String) -> KeyBinding {
        KeyBinding(key: key, modifiers: [.command, .control], displayString: "⌃⌘" + key.uppercased())
    }
}

struct Command {
    let id: String
    var title: String
    var category: String
    var keyBinding: KeyBinding?
    var alternateKeyBinding: KeyBinding?
    /// Commands recorded by the macro engine as semantic operations.
    var isRecordable: Bool = true
    var keywords: [String] = []
    var isEnabled: (CommandContext) -> Bool = { _ in true }
    var isChecked: ((CommandContext) -> Bool)?
    var action: (CommandContext) -> Void
}

/// Everything a command may need to run, resolved at invocation time.
final class CommandContext {
    weak var coordinator: AppCoordinator?
    weak var window: MainWindowController?
    /// Active tab as an editor tab; nil for Large File tabs or no window.
    var tab: DocumentTabController? { window?.activeTab as? DocumentTabController }
    var activeTab: (any DocumentTab)? { window?.activeTab }
    var document: PlainXDocument? { window?.activeTab?.document }
    var pane: EditorPaneController? { tab?.activePane }

    init(coordinator: AppCoordinator?, window: MainWindowController?) {
        self.coordinator = coordinator
        self.window = window
    }

    static var empty: CommandContext { CommandContext(coordinator: nil, window: nil) }
}

final class CommandRegistry {
    static let shared = CommandRegistry()

    private(set) var commands: [Command] = []
    private var index: [String: Command] = [:]
    private var order: [String: Int] = [:]

    private init() {}

    func register(_ command: Command) {
        if let existingIndex = order[command.id] {
            commands[existingIndex] = command
        } else {
            order[command.id] = commands.count
            commands.append(command)
        }
        index[command.id] = command
    }

    func register(_ newCommands: [Command]) {
        for command in newCommands {
            register(command)
        }
    }

    func command(id: String) -> Command? {
        index[id]
    }

    func commands(inCategory category: String) -> [Command] {
        commands.filter { $0.category == category }
    }

    var categories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for command in commands where !seen.contains(command.category) {
            seen.insert(command.category)
            result.append(command.category)
        }
        return result
    }

    func isEnabled(_ id: String, context: CommandContext) -> Bool {
        guard let command = index[id] else { return false }
        return command.isEnabled(context)
    }

    func perform(_ id: String, context: CommandContext) {
        guard let command = index[id], command.isEnabled(context) else { return }
        command.action(context)
    }
}

/// Objective-C target that all dynamically generated menu items point at.
/// Menu items carry the command identifier in `representedObject`.
final class CommandDispatcher: NSObject {
    weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator?) {
        self.coordinator = coordinator
        super.init()
    }

    @objc func performCommand(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem,
              let commandID = menuItem.representedObject as? String else { return }
        let window = NSApp.keyWindow?.windowController as? MainWindowController
            ?? NSApp.mainWindow?.windowController as? MainWindowController
        let context = CommandContext(coordinator: coordinator, window: window)
        CommandRegistry.shared.perform(commandID, context: context)
    }

    @objc func performCommandReplyingToSender(_ sender: Any?) {
        performCommand(sender)
    }

    func validate(_ menuItem: NSMenuItem) -> Bool {
        guard let commandID = menuItem.representedObject as? String else { return true }
        let window = NSApp.keyWindow?.windowController as? MainWindowController
            ?? NSApp.mainWindow?.windowController as? MainWindowController
        let context = CommandContext(coordinator: coordinator, window: window)
        guard let command = CommandRegistry.shared.command(id: commandID) else { return false }
        if let isChecked = command.isChecked {
            menuItem.state = isChecked(context) ? .on : .off
        }
        return command.isEnabled(context)
    }
}

extension KeyBinding {
    /// Converts the binding to an NSMenuItem key equivalent pair.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        (key, modifiers)
    }
}

extension NSMenuItem {
    static func commandItem(_ command: Command, dispatcher: CommandDispatcher) -> NSMenuItem {
        let item = NSMenuItem(title: command.title,
                              action: #selector(CommandDispatcher.performCommand(_:)),
                              keyEquivalent: command.keyBinding?.key ?? "")
        if let binding = command.keyBinding {
            item.keyEquivalentModifierMask = binding.modifiers
        }
        item.representedObject = command.id
        item.target = dispatcher
        return item
    }
}
