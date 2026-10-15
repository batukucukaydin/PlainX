//
//  FileDropView.swift
//  PlainX Editor
//
//  Accepts dragged files and folders on the editor area.
//

import AppKit

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
