//
//  SearchIntegrationTests.swift
//  PlainXTests
//
//  Integration coverage for in-document search (Scintilla target search via
//  DocumentSearchService) and folder search (FileSearchService) against
//  generated fixtures.
//

import XCTest
@testable import PlainX

final class DocumentSearchServiceTests: XCTestCase {

    private func makePane(text: String) -> EditorPaneController {
        let pane = EditorPaneController(theme: .systemLight)
        _ = pane.view
        pane.facade.text = text
        return pane
    }

    func testFindAllLiteral() {
        let pane = makePane(text: "alpha beta alpha gamma alpha")
        var options = DocumentSearchOptions()
        options.needle = "alpha"
        let result = DocumentSearchService.shared.findAll(in: pane, options: options)
        XCTAssertEqual(result.matches.count, 3)
        XCTAssertEqual(result.matches.map(\.location), [0, 11, 23])
    }

    func testFindAllCaseSensitive() {
        let pane = makePane(text: "Alpha alpha ALPHA")
        var options = DocumentSearchOptions()
        options.needle = "alpha"
        options.caseSensitive = true
        XCTAssertEqual(DocumentSearchService.shared.findAll(in: pane, options: options).matches.count, 1)
        options.caseSensitive = false
        XCTAssertEqual(DocumentSearchService.shared.findAll(in: pane, options: options).matches.count, 3)
    }

    func testFindAllWholeWord() {
        let pane = makePane(text: "cat catalog cat")
        var options = DocumentSearchOptions()
        options.needle = "cat"
        options.wholeWord = true
        let result = DocumentSearchService.shared.findAll(in: pane, options: options)
        XCTAssertEqual(result.matches.count, 2)
    }

    func testFindAllRegex() {
        let pane = makePane(text: "id=1 id=22 id=333")
        var options = DocumentSearchOptions()
        options.needle = "id=[0-9]+"
        options.regex = true
        let result = DocumentSearchService.shared.findAll(in: pane, options: options)
        XCTAssertEqual(result.matches.count, 3)
    }

    func testInvalidRegexReportsError() {
        let pane = makePane(text: "anything")
        var options = DocumentSearchOptions()
        options.needle = "([unclosed"
        options.regex = true
        let result = DocumentSearchService.shared.findAll(in: pane, options: options)
        XCTAssertNotNil(result.errorMessage)
    }

    func testFindInSelectionOnly() {
        let pane = makePane(text: "one two one two one")
        pane.facade.setSelection(anchor: 4, caret: 11) // "two one"
        var options = DocumentSearchOptions()
        options.needle = "one"
        options.inSelection = true
        let result = DocumentSearchService.shared.findAll(in: pane, options: options)
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.matches[0].location, 8)
    }

    func testAdvanceMovesToNextMatchAndWraps() {
        let pane = makePane(text: "bbb aaa bbb aaa bbb")
        var options = DocumentSearchOptions()
        options.needle = "bbb"
        options.wrap = true
        let first = DocumentSearchService.shared.search(in: pane, options: options, advance: true)
        XCTAssertEqual(first.currentMatchIndex, 0)
        XCTAssertEqual(pane.facade.mainSelection.lowerBound, 0)
        let second = DocumentSearchService.shared.search(in: pane, options: options, advance: true)
        XCTAssertEqual(second.currentMatchIndex, 1)
        let third = DocumentSearchService.shared.search(in: pane, options: options, advance: true)
        XCTAssertEqual(third.currentMatchIndex, 2)
        // Wraps to the first match.
        let wrapped = DocumentSearchService.shared.search(in: pane, options: options, advance: true)
        XCTAssertEqual(wrapped.currentMatchIndex, 0)
    }

    func testReplaceAllCountAndContent() {
        let pane = makePane(text: "foo bar foo baz foo")
        var options = DocumentSearchOptions()
        options.needle = "foo"
        let replaced = DocumentSearchService.shared.replaceAll(in: pane, options: options, replacement: "FOO")
        XCTAssertEqual(replaced, 3)
        XCTAssertEqual(pane.facade.text, "FOO bar FOO baz FOO")
    }

    func testReplaceAllRegexWithBackreference() {
        let pane = makePane(text: "hello world")
        var options = DocumentSearchOptions()
        options.needle = "([a-z]+) ([a-z]+)"
        options.regex = true
        let replaced = DocumentSearchService.shared.replaceAll(in: pane, options: options, replacement: "\\2 \\1")
        XCTAssertEqual(replaced, 1)
        XCTAssertEqual(pane.facade.text, "world hello")
    }

    func testReplaceAllInSelectionOnly() {
        let pane = makePane(text: "x x x x")
        pane.facade.setSelection(anchor: 0, caret: 4)
        var options = DocumentSearchOptions()
        options.needle = "x"
        options.inSelection = true
        let replaced = DocumentSearchService.shared.replaceAll(in: pane, options: options, replacement: "y")
        XCTAssertEqual(replaced, 2)
        XCTAssertEqual(pane.facade.text, "y y x x")
    }

    func testUnicodeSearchRanges() {
        let pane = makePane(text: "café ☕ café")
        var options = DocumentSearchOptions()
        options.needle = "café"
        let result = DocumentSearchService.shared.findAll(in: pane, options: options)
        XCTAssertEqual(result.matches.count, 2)
        // Byte offsets, not character offsets.
        XCTAssertEqual(result.matches[0].location, 0)
        XCTAssertEqual(result.matches[1].location, "café ☕ ".utf8.count)
    }
}

final class LineMatcherTests: XCTestCase {

    func testLiteralMatching() {
        var query = FileSearchQuery(root: URL(fileURLWithPath: "/tmp"), pattern: "needle")
        query.caseSensitive = false
        let matcher = LineMatcher(query: query)
        let ranges = matcher.matches(in: "a Needle in hay")
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].location, 2)
        XCTAssertEqual(ranges[0].length, 6)
    }

    func testWholeWordRegexMatching() {
        var query = FileSearchQuery(root: URL(fileURLWithPath: "/tmp"), pattern: "cat")
        query.wholeWord = true
        let matcher = LineMatcher(query: query)
        XCTAssertEqual(matcher.matches(in: "cat catalog").count, 1)
    }

    func testRegexMatching() {
        var query = FileSearchQuery(root: URL(fileURLWithPath: "/tmp"), pattern: "v[0-9]+")
        query.isRegex = true
        query.caseSensitive = true
        let matcher = LineMatcher(query: query)
        let ranges = matcher.matches(in: "release v12 and v3")
        XCTAssertEqual(ranges.count, 2)
    }

    func testMultipleMatchesOnOneLine() {
        let query = FileSearchQuery(root: URL(fileURLWithPath: "/tmp"), pattern: "ab")
        let matcher = LineMatcher(query: query)
        XCTAssertEqual(matcher.matches(in: "ab ab ab").count, 3)
    }
}

final class FileSearchServiceTests: XCTestCase {

    private func makeFixtureTree() throws -> URL {
        let root = try TestHelpers.makeTemporaryDirectory()
        try Data("let alpha = 1\nlet beta = 2\n".utf8)
            .write(to: root.appendingPathComponent("Main.swift"))
        let nested = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("alpha alpha alpha\n".utf8)
            .write(to: nested.appendingPathComponent("Second.swift"))
        try Data("alpha in a text file\n".utf8)
            .write(to: nested.appendingPathComponent("notes.txt"))
        try Data("çğü alpha unicode name\n".utf8)
            .write(to: nested.appendingPathComponent("türkçe-dosya.txt"))
        // Binary file with NUL bytes and a matching token.
        var binary = Data([0x00, 0x01, 0x02])
        binary.append(Data("alpha".utf8))
        try binary.write(to: nested.appendingPathComponent("binary.bin"))
        // Excluded directory.
        let ignored = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
        try Data("alpha in git\n".utf8)
            .write(to: ignored.appendingPathComponent("config"))
        return root
    }

    private func collect(_ query: FileSearchQuery) async -> [FileSearchEvent] {
        var events: [FileSearchEvent] = []
        for await event in FileSearchService().search(query) {
            events.append(event)
        }
        return events
    }

    private func matches(from events: [FileSearchEvent]) -> [FileSearchMatch] {
        events.compactMap { event in
            if case .match(let match) = event { return match }
            return nil
        }
    }

    func testStreamsMatchesAndSkipsBinaryAndHidden() async throws {
        let root = try makeFixtureTree()
        defer { try? TestHelpers.remove(root) }
        var query = FileSearchQuery(root: root, pattern: "alpha")
        query.excludedDirectories = [".git"]
        let events = await collect(query)
        let found = matches(from: events)
        let names = Set(found.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("Main.swift"))
        XCTAssertTrue(names.contains("Second.swift"))
        XCTAssertTrue(names.contains("türkçe-dosya.txt"))
        XCTAssertFalse(names.contains("binary.bin"), "binary files must be skipped")
        XCTAssertFalse(names.contains("config"), "excluded directories must be skipped")
        XCTAssertEqual(found.count, 1 + 3 + 1 + 1) // Main, Second x3, notes, türkçe
    }

    func testIncludeGlobFilters() async throws {
        let root = try makeFixtureTree()
        defer { try? TestHelpers.remove(root) }
        var query = FileSearchQuery(root: root, pattern: "alpha")
        query.includeGlobs = ["*.txt"]
        query.excludedDirectories = [".git"]
        let found = matches(from: await collect(query))
        XCTAssertTrue(found.allSatisfy { $0.url.pathExtension == "txt" })
        XCTAssertFalse(found.isEmpty)
    }

    func testExcludeGlobFilters() async throws {
        let root = try makeFixtureTree()
        defer { try? TestHelpers.remove(root) }
        var query = FileSearchQuery(root: root, pattern: "alpha")
        query.excludeGlobs = ["*.txt"]
        query.excludedDirectories = [".git"]
        let found = matches(from: await collect(query))
        XCTAssertTrue(found.allSatisfy { $0.url.pathExtension != "txt" })
    }

    func testRegexFolderSearch() async throws {
        let root = try makeFixtureTree()
        defer { try? TestHelpers.remove(root) }
        var query = FileSearchQuery(root: root, pattern: "let [a-z]+")
        query.isRegex = true
        query.excludedDirectories = [".git"]
        let found = matches(from: await collect(query))
        XCTAssertEqual(found.count, 2)
    }

    func testMaxResultsCap() async throws {
        let root = try TestHelpers.makeTemporaryDirectory()
        defer { try? TestHelpers.remove(root) }
        let lines = (0..<500).map { "alpha line \($0)" }.joined(separator: "\n")
        try Data(lines.utf8).write(to: root.appendingPathComponent("many.txt"))
        var query = FileSearchQuery(root: root, pattern: "alpha")
        query.maxResults = 100
        let found = matches(from: await collect(query))
        XCTAssertEqual(found.count, 100)
    }

    func testCancellationStopsEarly() async throws {
        let root = try TestHelpers.makeTemporaryDirectory()
        defer { try? TestHelpers.remove(root) }
        for index in 0..<40 {
            let lines = (0..<200).map { "needle \(index)-\($0)" }.joined(separator: "\n")
            try Data(lines.utf8).write(to: root.appendingPathComponent("file\(index).txt"))
        }
        let service = FileSearchService()
        var query = FileSearchQuery(root: root, pattern: "needle")
        query.maxFileSizeBytes = 1024 * 1024
        let stream = service.search(query)
        var task: Task<Void, Never>?
        var matchCount = 0
        task = Task {
            for await event in stream {
                if case .match = event { matchCount += 1 }
                if matchCount >= 50 { service.cancel() }
            }
        }
        _ = await task?.value
        XCTAssertLessThan(matchCount, 8000, "cancellation must stop the search before completion")
    }

    func testFinishedEventReportsCounts() async throws {
        let root = try makeFixtureTree()
        defer { try? TestHelpers.remove(root) }
        var query = FileSearchQuery(root: root, pattern: "alpha")
        query.excludedDirectories = [".git"]
        let events = await collect(query)
        var finished: (files: Int, matches: Int, cancelled: Bool)?
        for event in events {
            if case .finished(let files, let found, let cancelled) = event {
                finished = (files, found, cancelled)
            }
        }
        XCTAssertNotNil(finished)
        XCTAssertEqual(finished?.matches, 6)
        XCTAssertFalse(finished?.cancelled ?? true)
    }
}
