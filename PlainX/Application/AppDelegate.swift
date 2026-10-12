//
//  AppDelegate.swift
//  PlainX Editor
//

import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var coordinator: AppCoordinator!
    private var dispatcher: CommandDispatcher!
    private var pendingOpenURLs: [URL] = []

    static var benchmarkStart: CFAbsoluteTime { plainXProcessStartTime }
    static var isBenchmarkMode: Bool {
        ProcessInfo.processInfo.environment["PLAINX_BENCHMARK"] == "1"
    }

    private static let launchSignpost = OSSignposter(subsystem: "com.batukucukaydin.plainx", category: "launch")
    private var launchState: OSSignpostIntervalState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Benchmark output is redirected to a file; keep it unbuffered so
        // results are visible even if the process is interrupted.
        setvbuf(stdout, nil, _IONBF, 0)
        launchState = Self.launchSignpost.beginInterval("launch")
        coordinator = AppCoordinator()
        dispatcher = CommandDispatcher(coordinator: coordinator)
        MacroMenuTarget.shared.coordinator = coordinator
        RecentMenuDelegate.shared.coordinator = coordinator
        StandardCommands.registerAll(coordinator: coordinator)
        NSApp.mainMenu = MainMenuBuilder.buildMainMenu(coordinator: coordinator, dispatcher: dispatcher)
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When running under XCTest, do not touch the user's session or
        // recovery data; tests construct their own windows.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            if let state = launchState {
                Self.launchSignpost.endInterval("launch", state)
                launchState = nil
            }
            return
        }
        if Self.isBenchmarkMode {
            // Benchmarks always start from a clean, predictable state.
            let window = coordinator.newWindow()
            window.addTab(for: PlainXDocument(url: nil), select: true)
        } else if !pendingOpenURLs.isEmpty {
            // Finder launch with documents: restore the session first, then
            // open the requested files on top so nothing is lost.
            coordinator.restoreSession()
            coordinator.open(urls: pendingOpenURLs, in: coordinator.activeWindow)
            pendingOpenURLs.removeAll()
            coordinator.startRecoveryTimer()
        } else {
            coordinator.restoreSession()
            coordinator.startRecoveryTimer()
        }
        NSApp.activate(ignoringOtherApps: false)

        if let state = launchState {
            Self.launchSignpost.endInterval("launch", state)
            launchState = nil
        }

        if Self.isBenchmarkMode {
            let elapsed = (CFAbsoluteTimeGetCurrent() - Self.benchmarkStart) * 1000
            print(String(format: "[benchmark] launch_ms=%.1f", elapsed))
            print("[benchmark] did_finish_launching=1")
            print("[benchmark] windows=\(NSApp.windows.filter { $0.isVisible }.count)")
            if let openPath = ProcessInfo.processInfo.environment["PLAINX_BENCHMARK_OPEN_FILE"] {
                benchmarkOpenFile(path: openPath)
            } else {
                print("[benchmark] blank_rss=\(MemoryProbe.currentRSSBytes())")
            }
            if let exitAfter = ProcessInfo.processInfo.environment["PLAINX_BENCHMARK_EXIT_AFTER"],
               let seconds = Double(exitAfter) {
                print("[benchmark] scheduling_exit_after=\(seconds)")
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    print("[benchmark] terminating")
                    NSApp.terminate(nil)
                }
            }
        }
        Log.performance.debug("Launch completed")
    }

    /// Benchmark helper: opens a file and prints timing/RSS once the tab is
    /// ready (for Large File tabs, when the index finished).
    private func benchmarkOpenFile(path: String) {
        let url = URL(fileURLWithPath: path)
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let document = try coordinator.openDocument(at: url)
            let window = coordinator.activeWindow ?? coordinator.newWindow()
            window.addTab(for: document, select: true)
            if let largeTab = window.tabs.last as? LargeFileTabController {
                largeTab.viewer.backing.onIndexReady = { [weak self] in
                    _ = self
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    print(String(format: "[benchmark] large_file_index_ms=%.1f", elapsed))
                    print("[benchmark] large_file_rss=\(MemoryProbe.currentRSSBytes())")
                    print("[benchmark] large_file_lines=\(largeTab.viewer.backing.lineCount)")
                }
                if largeTab.viewer.backing.isIndexComplete {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    print(String(format: "[benchmark] large_file_index_ms=%.1f", elapsed))
                    print("[benchmark] large_file_rss=\(MemoryProbe.currentRSSBytes())")
                    print("[benchmark] large_file_lines=\(largeTab.viewer.backing.lineCount)")
                }
            } else {
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                print(String(format: "[benchmark] file_open_ms=%.1f", elapsed))
                print("[benchmark] file_open_rss=\(MemoryProbe.currentRSSBytes())")
            }
        } catch {
            print("[benchmark] file_open_error=\(error.localizedDescription)")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if coordinator == nil || coordinator.windows.isEmpty {
            pendingOpenURLs.append(contentsOf: urls)
            // applicationDidFinishLaunching has not run yet; it will open them.
            if coordinator != nil && NSApp.isRunning {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.pendingOpenURLs.isEmpty else { return }
                    self.coordinator.open(urls: self.pendingOpenURLs, in: self.coordinator.activeWindow)
                    self.pendingOpenURLs.removeAll()
                }
            }
            return
        }
        coordinator.open(urls: urls, in: coordinator.activeWindow)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        // Quitting with no unsaved work is synchronous and always allowed.
        guard coordinator.hasUnsavedDocuments else {
            coordinator.saveSessionNow()
            return .terminateNow
        }
        coordinator.prepareForTermination { shouldTerminate in
            // reply(toApplicationShouldTerminate:) must not be called
            // synchronously from within this delegate method.
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.takeRecoverySnapshotNow()
        coordinator.saveSessionNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never auto-quit the test host when a unit test closes its window.
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    /// Called by the first window when it becomes key; used to report the
    /// "usable editor" launch metric in benchmark mode.
    static func reportFirstUsableEditorIfNeeded() {
        guard isBenchmarkMode, !didReportUsable else { return }
        didReportUsable = true
        let elapsed = (CFAbsoluteTimeGetCurrent() - benchmarkStart) * 1000
        print(String(format: "[benchmark] usable_ms=%.1f", elapsed))
    }

    private static var didReportUsable = false

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
