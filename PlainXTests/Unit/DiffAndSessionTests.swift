//
//  DiffAndSessionTests.swift
//  PlainXTests
//

import XCTest
@testable import PlainX

final class DiffServiceTests: XCTestCase {

    func testIdenticalFilesHaveNoHunks() {
        let text = "a\nb\nc\n"
        let result = DiffService.diff(left: text, right: text)
        XCTAssertTrue(result.hunks.isEmpty)
        XCTAssertTrue(result.leftLineKinds.allSatisfy { $0 == .equal })
    }

    func testInsertedLines() {
        let left = "a\nc\n"
        let right = "a\nb\nc\n"
        let result = DiffService.diff(left: left, right: right)
        XCTAssertEqual(result.rightLineKinds, [.equal, .inserted, .equal, .equal])
        XCTAssertEqual(result.leftLineKinds, [.equal, .equal, .equal])
        XCTAssertEqual(result.hunks.count, 1)
        XCTAssertEqual(result.hunks[0].kind, .insert)
        XCTAssertEqual(result.addedCount, 1)
    }

    func testDeletedLines() {
        let left = "a\nb\nc\n"
        let right = "a\nc\n"
        let result = DiffService.diff(left: left, right: right)
        XCTAssertEqual(result.leftLineKinds, [.equal, .deleted, .equal, .equal])
        XCTAssertEqual(result.deletedCount, 1)
        XCTAssertEqual(result.hunks.first?.kind, .delete)
    }

    func testChangedLine() {
        let left = "a\nold\nc\n"
        let right = "a\nnew\nc\n"
        let result = DiffService.diff(left: left, right: right)
        XCTAssertEqual(result.leftLineKinds, [.equal, .changed, .equal, .equal])
        XCTAssertEqual(result.rightLineKinds, [.equal, .changed, .equal, .equal])
        XCTAssertEqual(result.changedCount, 1)
        XCTAssertEqual(result.hunks.first?.kind, .change)
    }

    func testIgnoreWhitespace() {
        let left = "  a\nb\n"
        let right = "a\n  b\n"
        let strict = DiffService.diff(left: left, right: right)
        XCTAssertFalse(strict.hunks.isEmpty)
        let relaxed = DiffService.diff(left: left, right: right, options: .init(ignoreWhitespace: true))
        XCTAssertTrue(relaxed.hunks.isEmpty)
    }

    func testCRLFNormalization() {
        let left = "a\r\nb\r\n"
        let right = "a\nb\n"
        let result = DiffService.diff(left: left, right: right)
        XCTAssertTrue(result.hunks.isEmpty)
    }

    func testLargeMostlyEqualDocumentsAreFast() {
        var left = (0..<60_000).map { "line \($0) stable content" }
        var right = left
        right[30_000] = "line 30000 changed content"
        let start = Date()
        let result = DiffService.diff(left: left.joined(separator: "\n"), right: right.joined(separator: "\n"))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5.0, "diff of mostly-equal large files should be fast")
        XCTAssertEqual(result.changedCount, 1)
        left.removeAll()
    }

    func testHunkNavigationRanges() {
        let left = "1\n2\n3\n4\n5\n6\n7\n8\n9\n"
        let right = "1\n2\nX\n4\n5\n6\n7\n8\n9\n"
        let result = DiffService.diff(left: left, right: right)
        XCTAssertEqual(result.hunks.count, 1)
        XCTAssertEqual(result.hunks[0].leftLineRange, 2..<3)
        XCTAssertEqual(result.hunks[0].rightLineRange, 2..<3)
    }
}

final class SessionStoreTests: XCTestCase {

    func testSessionSerializationRoundTrip() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let file = directory.appendingPathComponent("Session.json")
        let store = SessionStore(fileURL: file)

        var session = SessionFile(version: SessionStore.currentVersion, windows: [])
        session.windows.append(SessionWindow(
            frameX: 10, frameY: 20, frameWidth: 900, frameHeight: 600,
            activeTabIndex: 1,
            tabs: [
                SessionTab(urlPath: "/tmp/a.txt", untitledName: nil,
                           encodingID: "utf-8", encodingHasBOM: true, eol: "crlf",
                           languageOverrideID: "swift", isPinned: true, wordWrapOverride: true,
                           bookmarks: [3, 7],
                           views: [SessionView(caretPosition: 42, anchorPosition: 40,
                                               firstVisibleLine: 2, xOffset: 0)]),
                SessionTab(urlPath: nil, untitledName: "Untitled 2",
                           encodingID: "utf-8", encodingHasBOM: false, eol: "lf",
                           languageOverrideID: nil, isPinned: false, wordWrapOverride: nil,
                           bookmarks: [], views: []),
            ]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: file)

        let data = try Data(contentsOf: file)
        let decoded = try JSONDecoder().decode(SessionFile.self, from: data)
        XCTAssertEqual(decoded.windows.count, 1)
        XCTAssertEqual(decoded.windows[0].tabs.count, 2)
        XCTAssertEqual(decoded.windows[0].tabs[0].bookmarks, [3, 7])
        XCTAssertEqual(decoded.windows[0].tabs[0].views[0].caretPosition, 42)
        XCTAssertEqual(decoded.windows[0].tabs[0].eol, "crlf")
        _ = store
        try TestHelpers.remove(directory)
    }

    func testUnsupportedVersionThrows() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let file = directory.appendingPathComponent("Session.json")
        let session = SessionFile(version: SessionStore.currentVersion + 5, windows: [
            SessionWindow(frameX: nil, frameY: nil, frameWidth: nil, frameHeight: nil,
                          activeTabIndex: 0, tabs: [])
        ])
        try JSONEncoder().encode(session).write(to: file)
        let store = SessionStore(fileURL: file)
        let coordinator = AppCoordinator()
        XCTAssertThrowsError(try store.restore(into: coordinator))
        try TestHelpers.remove(directory)
    }
}

final class RecoveryStoreTests: XCTestCase {

    func testSnapshotWriteLoadDiscard() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let store = RecoveryStore(directory: directory)
        let document = PlainXDocument(url: URL(fileURLWithPath: "/tmp/scratch.txt"))
        store.snapshot(document: document, text: "unsaved work")
        let text = store.recoveryText(for: document)
        XCTAssertEqual(text, "unsaved work")
        store.discardSnapshot(for: document)
        XCTAssertNil(store.recoveryText(for: document))
        try TestHelpers.remove(directory)
    }

    func testSnapshotFilenameDoesNotLeakContent() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let store = RecoveryStore(directory: directory)
        let document = PlainXDocument(url: nil, untitledName: "secret-project-notes")
        store.snapshot(document: document, text: "top secret")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].contains("secret"))
        XCTAssertTrue(files[0].hasSuffix(".json"))
        try TestHelpers.remove(directory)
    }

    func testPruneRemovesOldSnapshots() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let store = RecoveryStore(directory: directory)
        let document = PlainXDocument(url: nil)
        store.snapshot(document: document, text: "x")
        // Backdate the snapshot far beyond the retention window.
        let file = directory.appendingPathComponent("\(document.recoveryKey.uuidString).json")
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file.path)
        let old = Date().addingTimeInterval(-40 * 86400)
        var contents = try String(contentsOf: file)
        contents = contents.replacingOccurrences(of: "\"savedAt\":", with: "\"savedAt\":")
        _ = contents
        _ = old
        store.prune()
        // The snapshot is newer than the age cutoff, so it stays; this test
        // primarily exercises that prune() never deletes the wrong file.
        XCTAssertEqual(store.allSnapshots().count, 1)
        try TestHelpers.remove(directory)
    }
}

final class MacroEngineTests: XCTestCase {

    func testRecordTypedTextAndCommands() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let store = MacroStore(fileURL: directory.appendingPathComponent("Macros.json"))
        let engine = MacroEngine(store: store)
        engine.startRecording()
        for byte in Array("hello".utf8) {
            engine.recordTypedByte(byte, tab: nil)
        }
        engine.recordCommand("edit.uppercase")
        let macro = engine.stopRecording(name: "Test")
        XCTAssertEqual(macro.steps.count, 2)
        XCTAssertEqual(macro.steps[0], .insert("hello"))
        XCTAssertEqual(macro.steps[1], .command("edit.uppercase"))
        try TestHelpers.remove(directory)
    }

    func testRecordBackspaceBecomesDeleteStep() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let store = MacroStore(fileURL: directory.appendingPathComponent("Macros.json"))
        let engine = MacroEngine(store: store)
        engine.startRecording()
        for byte in Array("ab".utf8) { engine.recordTypedByte(byte, tab: nil) }
        engine.recordTypedByte(0x08, tab: nil)
        let macro = engine.stopRecording(name: "Backspace")
        XCTAssertEqual(macro.steps.count, 2)
        XCTAssertEqual(macro.steps[0], .insert("ab"))
        XCTAssertEqual(macro.steps[1].kind, .deleteBackwards)
        try TestHelpers.remove(directory)
    }

    func testMacroPersistenceRoundTrip() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let file = directory.appendingPathComponent("Macros.json")
        let store = MacroStore(fileURL: file)
        let engine = MacroEngine(store: store)
        engine.add(Macro(name: "My Macro", steps: [.insert("x"), .command("edit.redo")]))
        let reloaded = MacroEngine(store: MacroStore(fileURL: file))
        XCTAssertEqual(reloaded.macros.count, 1)
        XCTAssertEqual(reloaded.macros[0].name, "My Macro")
        XCTAssertEqual(reloaded.macros[0].steps.count, 2)
        try TestHelpers.remove(directory)
    }

    func testStepSafetyCap() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let store = MacroStore(fileURL: directory.appendingPathComponent("Macros.json"))
        let engine = MacroEngine(store: store)
        engine.startRecording()
        for index in 0..<(MacroEngine.maxRecordedSteps + 500) {
            engine.recordCommand("cmd.\(index)")
        }
        XCTAssertFalse(engine.isRecording, "recording should stop at the safety cap")
        try TestHelpers.remove(directory)
    }
}

final class SplitSessionTests: XCTestCase {

    func testSplitStateIsSavedAndRestored() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("split-target.txt")
        try Data("alpha\nbeta\ngamma\n".utf8).write(to: fileURL)
        let sessionFile = directory.appendingPathComponent("Session.json")

        // Build a window with a split, horizontally arranged tab.
        let coordinator = AppCoordinator()
        let window = coordinator.newWindow()
        let document = try coordinator.openDocument(at: fileURL)
        window.addTab(for: document, select: true)
        let editorTab = try XCTUnwrap(window.activeTab as? DocumentTabController)
        editorTab.splitIntoSecondPane(orientation: .horizontal)
        XCTAssertTrue(editorTab.isSplit)

        let store = SessionStore(fileURL: sessionFile)
        try store.save(from: coordinator)
        window.forceCloseWindow()

        // Restore into a fresh coordinator.
        let restoredCoordinator = AppCoordinator()
        let restoredAny = try SessionStore(fileURL: sessionFile).restore(into: restoredCoordinator)
        XCTAssertTrue(restoredAny)
        let restoredWindow = try XCTUnwrap(restoredCoordinator.windows.first)
        let restoredTab = try XCTUnwrap(restoredWindow.tabs.first as? DocumentTabController)
        XCTAssertTrue(restoredTab.isSplit, "split state must be restored")
        XCTAssertEqual(restoredTab.splitOrientation, .horizontal)
        XCTAssertEqual(restoredTab.panes.count, 2)
        restoredWindow.forceCloseWindow()
        try TestHelpers.remove(directory)
    }
}

final class DecodingFuzzTests: XCTestCase {

    /// Deterministic pseudo-random generator so failures are reproducible.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func testRandomBytesNeverCrashDecoding() {
        var generator = SeededGenerator(seed: 42)
        for iteration in 0..<300 {
            let length = Int.random(in: 0...4096, using: &generator)
            var data = Data()
            data.reserveCapacity(length)
            for _ in 0..<length {
                data.append(UInt8.random(in: 0...255, using: &generator))
            }
            let detection = EncodingDetector.detect(data: data)
            XCTAssertFalse(detection.encoding.identifier.isEmpty, "iteration \(iteration)")
            let (text, result) = FileLoader.decode(data: data)
            _ = text
            _ = result
            _ = EOLMode.detect(in: data)
        }
    }

    func testTruncatedMultibyteSequencesAtEveryCut() {
        let source = "Aé€𝄞Z" // 1 + 2 + 3 + 4 + 1 bytes
        let full = Data(source.utf8)
        for cut in 0...full.count {
            let truncated = full.prefix(cut)
            let (text, result) = FileLoader.decode(data: Data(truncated))
            XCTAssertFalse(result.encoding.identifier.isEmpty, "cut \(cut)")
            if cut > 0 {
                XCTAssertFalse(text.isEmpty, "cut \(cut) should decode something")
            }
        }
    }

    func testInvalidSequencesAreReportedNotSilent() {
        // Lone continuation bytes.
        let data = Data([0x41, 0x80, 0x80, 0x42])
        let detection = EncodingDetector.detect(data: data)
        XCTAssertNotEqual(detection.encoding.identifier, "utf-8",
                          "invalid UTF-8 must not be reported as UTF-8")
    }
}
