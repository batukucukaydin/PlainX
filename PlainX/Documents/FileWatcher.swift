//
//  FileWatcher.swift
//  PlainX Editor
//
//  Watches a single file for external modification using a dispatch file
//  system event source. Append events are reported separately so Log Mode can
//  distinguish "tail grew" from "file replaced".
//

import Foundation
import os

final class FileWatcher {
    enum Event {
        case changed
        case appended(newSize: UInt64)
        case deleted
        case renamed
    }

    private let url: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.batukucukaydin.plainx.filewatcher")
    private var lastKnownSize: UInt64 = 0
    private var lastEventTime: Date = .distantPast
    private var coalesceInterval: TimeInterval = 0.25

    var onEvent: ((Event) -> Void)?
    /// Events are delivered on the main queue.
    var deliverOnMain = true

    init(url: URL) {
        self.url = url
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        lastKnownSize = FileLoader.metadata(for: url)?.fileSize ?? 0

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.fileIO.error("FileWatcher could not open \(self.url.lastPathComponent, privacy: .public)")
            return
        }
        fileDescriptor = descriptor

        let mask: DispatchSource.FileSystemEvent = [.write, .delete, .rename, .extend, .attrib]
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.handle(flags: flags)
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// Resumes watching after the file was replaced (log rotation or
    /// atomic-save by another program).
    func restart() {
        start()
    }

    private func handle(flags: DispatchSource.FileSystemEvent) {
        let now = Date()

        var event: Event?
        if flags.contains(.delete) || flags.contains(.rename) {
            event = flags.contains(.rename) ? .renamed : .deleted
        } else if flags.contains(.extend) || flags.contains(.write) || flags.contains(.attrib) {
            let currentSize = FileLoader.metadata(for: url)?.fileSize ?? 0
            if currentSize > lastKnownSize {
                event = .appended(newSize: currentSize)
            } else {
                event = .changed
            }
            lastKnownSize = currentSize
        }

        guard let event else { return }
        // Coalesce bursts of filesystem events.
        if now.timeIntervalSince(lastEventTime) < coalesceInterval, case .changed = event {
            return
        }
        lastEventTime = now

        if deliverOnMain {
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        } else {
            onEvent?(event)
        }
    }
}
