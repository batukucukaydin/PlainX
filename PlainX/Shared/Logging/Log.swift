//
//  Log.swift
//  PlainX Editor
//
//  Unified-logging categories used across the application.
//  Document/clipboard/selection contents must never be logged.
//

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.batukucukaydin.plainx"

    static let appLifecycle = Logger(subsystem: subsystem, category: "app")
    static let fileIO = Logger(subsystem: subsystem, category: "fileio")
    static let document = Logger(subsystem: subsystem, category: "document")
    static let search = Logger(subsystem: subsystem, category: "search")
    static let largeFile = Logger(subsystem: subsystem, category: "largefile")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let recovery = Logger(subsystem: subsystem, category: "recovery")
    static let update = Logger(subsystem: subsystem, category: "update")
    static let performance = Logger(subsystem: subsystem, category: "performance")
}
