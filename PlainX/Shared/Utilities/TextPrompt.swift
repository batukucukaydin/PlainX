//
//  TextPrompt.swift
//  PlainX Editor
//
//  Small modal text-input sheet used by rename, split-lines, and macro naming.
//

import AppKit

enum TextPrompt {
    static func present(title: String, message: String, initialValue: String,
                        in window: NSWindow?, completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initialValue
        alert.accessoryView = field
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            completion(field.stringValue)
        }
        DispatchQueue.main.async {
            if let window {
                alert.beginSheetModal(for: window, completionHandler: handler)
                alert.window.makeFirstResponder(field)
            } else {
                alert.window.makeFirstResponder(field)
                handler(alert.runModal())
            }
        }
    }
}
