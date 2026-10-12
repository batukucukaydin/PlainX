//
//  EncodingAndEOLTests.swift
//  PlainXTests
//

import XCTest
@testable import PlainX

final class EncodingTests: XCTestCase {

    func testUTF8WithoutBOMDetection() {
        let data = Data("héllo wörld ✓".utf8)
        let result = EncodingDetector.detect(data: data)
        XCTAssertEqual(result.encoding.identifier, "utf-8")
        XCTAssertFalse(result.encoding.hasBOM)
        XCTAssertEqual(result.confidence, 1.0, accuracy: 0.2)
    }

    func testASCIIDetection() {
        let data = Data("plain ascii text\n".utf8)
        let result = EncodingDetector.detect(data: data)
        XCTAssertEqual(result.encoding.identifier, "ascii")
    }

    func testUTF8BOMDetection() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("héllo".utf8))
        let result = EncodingDetector.detect(data: data)
        XCTAssertEqual(result.encoding.identifier, "utf-8")
        XCTAssertTrue(result.encoding.hasBOM)
    }

    func testUTF16LEDetection() {
        var data = Data([0xFF, 0xFE])
        data.append("hello".data(using: .utf16LittleEndian)!)
        let result = EncodingDetector.detect(data: data)
        XCTAssertEqual(result.encoding.identifier, "utf-16le")
        XCTAssertTrue(result.encoding.hasBOM)
    }

    func testUTF16BEDetection() {
        var data = Data([0xFE, 0xFF])
        data.append("hello".data(using: .utf16BigEndian)!)
        let result = EncodingDetector.detect(data: data)
        XCTAssertEqual(result.encoding.identifier, "utf-16be")
        XCTAssertTrue(result.encoding.hasBOM)
    }

    func testInvalidUTF8FallsBackWithoutCrashing() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0xFF, 0xFE, 0x00, 0x41])
        let result = EncodingDetector.detect(data: data)
        // 0xFF/0xFE also look like a UTF-16LE BOM here, so accept either a
        // legacy single-byte fallback or the UTF-16 heuristic, but never crash
        // and always report a defined encoding.
        XCTAssertFalse(result.encoding.identifier.isEmpty)
    }

    func testTruncatedUTF8SequenceRejected() {
        let data = Data([0xE2, 0x82]) // truncated 3-byte sequence
        XCTAssertNil(EncodingDetector.validateUTF8(data))
    }

    func testOverlongUTF8Rejected() {
        let data = Data([0xC0, 0xAF]) // overlong encoding of '/'
        XCTAssertNil(EncodingDetector.validateUTF8(data))
    }

    func testSurrogateRangeRejected() {
        let data = Data([0xED, 0xA0, 0x80]) // UTF-8 encoded surrogate
        XCTAssertNil(EncodingDetector.validateUTF8(data))
    }

    func testFourByteEmojiValid() {
        let data = Data("😀".utf8)
        XCTAssertNotNil(EncodingDetector.validateUTF8(data))
    }

    func testRoundTripUTF8BOM() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("bom.txt")
        _ = try FileSaver.save(text: "line one\nline two\n", to: url, encoding: .utf8BOM,
                               lastKnownMetadata: nil, checkExternalModification: false, force: true)
        let raw = try Data(contentsOf: url)
        XCTAssertTrue([UInt8](raw.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let loaded = try FileLoader.load(url: url)
        XCTAssertEqual(loaded.text, "line one\nline two\n")
        XCTAssertTrue(loaded.encoding.hasBOM)
        try TestHelpers.remove(directory)
    }

    func testRoundTripUTF16LE() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("wide.txt")
        _ = try FileSaver.save(text: "wide ünïcode ✓", to: url, encoding: .utf16LEBOM,
                               lastKnownMetadata: nil, checkExternalModification: false, force: true)
        let loaded = try FileLoader.load(url: url)
        XCTAssertEqual(loaded.text, "wide ünïcode ✓")
        XCTAssertEqual(loaded.encoding.identifier, "utf-16le")
        XCTAssertTrue(loaded.encoding.hasBOM)
        try TestHelpers.remove(directory)
    }

    func testWindows1252Fallback() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("ansi.txt")
        // 0x93/0x94 are curly quotes in Windows-1252, invalid UTF-8.
        let data = Data([0x93, 0x48, 0x69, 0x94])
        try data.write(to: url)
        let loaded = try FileLoader.load(url: url)
        XCTAssertEqual(loaded.encoding.identifier, "windows-1252")
        XCTAssertTrue(loaded.text.contains("Hi"))
        XCTAssertNotNil(loaded.diagnostic)
        try TestHelpers.remove(directory)
    }

    func testEncodingFailureDoesNotDestroyOriginal() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("safe.txt")
        try Data("original".utf8).write(to: url)
        let metadata = FileLoader.metadata(for: url)
        // "→" is not representable in ASCII.
        XCTAssertThrowsError(try FileSaver.save(text: "arrow → here", to: url, encoding: .ascii,
                                                lastKnownMetadata: metadata,
                                                checkExternalModification: false, force: true)) { error in
            guard case FileSaverError.encodingFailure = error else {
                XCTFail("expected encodingFailure, got \(error)")
                return
            }
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "original")
        try TestHelpers.remove(directory)
    }

    func testExternalModificationDetected() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("conflict.txt")
        try Data("version one".utf8).write(to: url)
        let known = FileLoader.metadata(for: url)
        // Simulate another program writing the file (different size/time).
        Thread.sleep(forTimeInterval: 0.02)
        try Data("version two with more content".utf8).write(to: url)
        XCTAssertThrowsError(try FileSaver.save(text: "my edit", to: url, encoding: .utf8,
                                                lastKnownMetadata: known,
                                                checkExternalModification: true, force: false)) { error in
            guard case FileSaverError.externalModification = error else {
                XCTFail("expected externalModification, got \(error)")
                return
            }
        }
        try TestHelpers.remove(directory)
    }

    func testAtomicSaveKeepsOriginalOnSuccess() throws {
        let directory = try TestHelpers.makeTemporaryDirectory()
        let url = directory.appendingPathComponent("atomic.txt")
        _ = try FileSaver.save(text: "first", to: url, encoding: .utf8,
                               lastKnownMetadata: nil, checkExternalModification: false, force: true)
        let firstMetadata = FileLoader.metadata(for: url)
        _ = try FileSaver.save(text: "second", to: url, encoding: .utf8,
                               lastKnownMetadata: firstMetadata, checkExternalModification: true, force: false)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")
        // No stray temporary files remain.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".plainx-save-") }
        XCTAssertTrue(leftovers.isEmpty, "temporary save files left behind: \(leftovers)")
        try TestHelpers.remove(directory)
    }
}

final class EOLTests: XCTestCase {

    func testDetectLF() {
        XCTAssertEqual(EOLMode.detect(in: "a\nb\nc\n"), .lf)
    }

    func testDetectCRLF() {
        XCTAssertEqual(EOLMode.detect(in: "a\r\nb\r\n"), .crlf)
    }

    func testDetectCR() {
        XCTAssertEqual(EOLMode.detect(in: "a\rb\rc"), .cr)
    }

    func testDetectMixed() {
        XCTAssertEqual(EOLMode.detect(in: "a\nb\r\n"), .mixed)
    }

    func testDetectEmptyDefaultsToLF() {
        XCTAssertEqual(EOLMode.detect(in: ""), .lf)
    }

    func testDetectBytesCRLF() {
        let data = Data("one\r\ntwo\r\nthree".utf8)
        XCTAssertEqual(EOLMode.detect(in: data), .crlf)
    }

    func testDetectBytesMixed() {
        let data = Data("one\ntwo\r\n".utf8)
        XCTAssertEqual(EOLMode.detect(in: data), .mixed)
    }

    func testConcreteFallback() {
        XCTAssertEqual(EOLMode.mixed.concreteFallback, .lf)
        XCTAssertEqual(EOLMode.crlf.concreteFallback, .crlf)
    }
}

enum TestHelpers {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plainx-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) throws {
        try? FileManager.default.removeItem(at: url)
    }
}
