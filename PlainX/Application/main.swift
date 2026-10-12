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
plainXApplication.delegate = plainXDelegate
plainXApplication.setActivationPolicy(.regular)
plainXApplication.run()
