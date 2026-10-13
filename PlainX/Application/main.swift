//
//  main.swift
//  PlainX Editor
//
//  Programmatic AppKit entry point. PlainX has no main nib and no storyboard;
//  the application object, delegate, and activation policy are established
//  here before the main run loop starts.
//

import AppKit

/// Captured before AppKit starts so benchmark launch timing is accurate.
let plainXProcessStartTime = CFAbsoluteTimeGetCurrent()

let plainXApplication = NSApplication.shared
let plainXDelegate = AppDelegate()

// `plainx file.txt` / `PlainX.app/Contents/MacOS/PlainX file.txt`:
// command-line paths are opened once the app finishes launching.
plainXDelegate.commandLineURLs = CommandLine.arguments.dropFirst().compactMap { argument in
    guard !argument.hasPrefix("-") else { return nil }
    let url = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

plainXApplication.delegate = plainXDelegate
plainXApplication.setActivationPolicy(.regular)
plainXApplication.run()
