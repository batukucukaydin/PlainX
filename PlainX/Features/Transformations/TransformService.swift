//
//  TransformService.swift
//  PlainX Editor
//
//  Pure text transformations plus Scintilla-targeted application helpers.
//  Every string function is deterministic and unit tested.
//

import AppKit
import CryptoKit
import Foundation

enum TransformError: LocalizedError {
    case invalidJSON(String, line: Int, column: Int)
    case invalidXML(String)
    case invalidBase64
    case invalidURLPercentEncoding
    case noSelection

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail, let line, let column):
            return "Invalid JSON at line \(line), column \(column): \(detail)"
        case .invalidXML(let detail):
            return "Invalid XML: \(detail)"
        case .invalidBase64:
            return "The selection is not valid Base64."
        case .invalidURLPercentEncoding:
            return "The selection is not valid percent-encoded text."
        case .noSelection:
            return "Select some text first."
        }
    }
}

enum TransformService {

    // MARK: - Whitespace / lines

    static func trimTrailingWhitespace(in text: String) -> String {
        let hadFinalNewline = text.hasSuffix("\n") || text.hasSuffix("\r")
        var lines = text.components(separatedBy: .newlines)
        lines = lines.map { line in
            var result = line
            while let last = result.unicodeScalars.last, last == " " || last == "\t" {
                result.removeLast()
            }
            return result
        }
        var joined = lines.joined(separator: "\n")
        if hadFinalNewline && !joined.hasSuffix("\n") {
            joined += "\n"
        }
        // Preserve CR characters if the input used CR-only endings.
        if text.contains("\r") && !text.contains("\n") {
            return text.split(separator: "\r", omittingEmptySubsequences: false)
                .map { line in
                    var result = String(line)
                    while let last = result.unicodeScalars.last, last == " " || last == "\t" {
                        result.removeLast()
                    }
                    return result
                }
                .joined(separator: "\r")
        }
        return joined
    }

    static func trimLeadingWhitespace(in text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        lines = lines.map { line in
            var result = line
            while let first = result.unicodeScalars.first, first == " " || first == "\t" {
                result.removeFirst()
            }
            return result
        }
        return joinedPreservingFinalNewline(lines: lines, original: text)
    }

    static func sortLines(in text: String, ascending: Bool, caseInsensitive: Bool) -> String {
        var lines = text.components(separatedBy: "\n")
        let hadFinalNewline = lines.last == ""
        if hadFinalNewline { lines.removeLast() }
        let sorted = lines.sorted { lhs, rhs in
            let comparison: ComparisonResult
            if caseInsensitive {
                comparison = lhs.compare(rhs, options: [.caseInsensitive, .numeric])
            } else {
                comparison = lhs.compare(rhs, options: [.numeric])
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        var result = sorted.joined(separator: "\n")
        if hadFinalNewline { result += "\n" }
        return result
    }

    static func removeDuplicateLines(in text: String, keepFirst: Bool = true) -> String {
        var lines = text.components(separatedBy: "\n")
        let hadFinalNewline = lines.last == ""
        if hadFinalNewline { lines.removeLast() }
        var seen = Set<String>()
        var result: [String] = []
        if keepFirst {
            for line in lines {
                if seen.insert(line).inserted {
                    result.append(line)
                }
            }
        } else {
            for line in lines.reversed() {
                if seen.insert(line).inserted {
                    result.insert(line, at: 0)
                }
            }
        }
        var joined = result.joined(separator: "\n")
        if hadFinalNewline { joined += "\n" }
        return joined
    }

    static func removeEmptyLines(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let hadFinalNewline = lines.last == ""
        if hadFinalNewline { lines.removeLast() }
        let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var joined = filtered.joined(separator: "\n")
        if hadFinalNewline && !joined.isEmpty { joined += "\n" }
        return joined
    }

    static func reverseLines(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let hadFinalNewline = lines.last == ""
        if hadFinalNewline { lines.removeLast() }
        var joined = lines.reversed().joined(separator: "\n")
        if hadFinalNewline { joined += "\n" }
        return joined
    }

    static func joinLines(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let hadFinalNewline = lines.last == ""
        if hadFinalNewline { lines.removeLast() }
        var joined = lines.joined()
        if hadFinalNewline { joined += "\n" }
        return joined
    }

    static func splitLinesOnSeparator(_ separator: String, in text: String) -> String {
        guard !separator.isEmpty else { return text }
        return text.replacingOccurrences(of: separator, with: separator + "\n")
    }

    private static func joinedPreservingFinalNewline(lines: [String], original: String) -> String {
        let hadFinalNewline = original.hasSuffix("\n")
        var result = lines.joined(separator: "\n")
        if hadFinalNewline && !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    // MARK: - Case

    static func uppercase(_ text: String) -> String { text.uppercased() }
    static func lowercase(_ text: String) -> String { text.lowercased() }

    static func titleCase(_ text: String) -> String {
        text.components(separatedBy: " ")
            .map { word -> String in
                guard let first = word.unicodeScalars.first else { return word }
                return String(first).uppercased() + String(word.unicodeScalars.dropFirst())
            }
            .joined(separator: " ")
    }

    static func sentenceCase(_ text: String) -> String {
        guard let first = text.unicodeScalars.first else { return text }
        return String(first).uppercased() + text.unicodeScalars.dropFirst().map { String($0).lowercased() }.joined()
    }

    static func swapCase(_ text: String) -> String {
        text.map { character in
            let string = String(character)
            if string == string.uppercased() && string != string.lowercased() {
                return string.lowercased()
            }
            return string.uppercased()
        }.joined()
    }

    // MARK: - Indentation

    static func convertTabsToSpaces(in text: String, tabWidth: Int) -> String {
        let spaces = String(repeating: " ", count: max(1, tabWidth))
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var result = ""
                for character in line {
                    if character == "\t" {
                        result += spaces
                    } else {
                        result.append(character)
                    }
                }
                return result
            }
            .joined(separator: "\n")
    }

    static func convertSpacesToTabs(in text: String, tabWidth: Int) -> String {
        let width = max(1, tabWidth)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var prefixSpaces = 0
                var trimIndex = line.startIndex
                for character in line {
                    if character == " " {
                        prefixSpaces += 1
                        trimIndex = line.index(after: trimIndex)
                    } else if character == "\t" {
                        prefixSpaces += width
                        trimIndex = line.index(after: trimIndex)
                    } else {
                        break
                    }
                }
                let tabs = String(repeating: "\t", count: prefixSpaces / width)
                let remainder = String(repeating: " ", count: prefixSpaces % width)
                return tabs + remainder + line[trimIndex...]
            }
            .joined(separator: "\n")
    }

    // MARK: - JSON

    static func formatJSON(_ text: String) throws -> String {
        let data = Data(text.utf8)
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard JSONSerialization.isValidJSONObject(object) || object is String || object is NSNumber || object is NSNull else {
                throw TransformError.invalidJSON("Top-level value is not valid JSON", line: 1, column: 1)
            }
            let formatted = try JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            return String(decoding: formatted, as: UTF8.self)
        } catch let error as TransformError {
            throw error
        } catch {
            throw parseJSONError(error, in: text)
        }
    }

    static func minifyJSON(_ text: String) throws -> String {
        let data = Data(text.utf8)
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let minified = try JSONSerialization.data(withJSONObject: object,
                                                      options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            return String(decoding: minified, as: UTF8.self)
        } catch {
            throw parseJSONError(error, in: text)
        }
    }

    static func validateJSON(_ text: String) throws {
        _ = try formatJSON(text)
    }

    private static func parseJSONError(_ error: Error, in text: String) -> TransformError {
        let nsError = error as NSError
        var detail = nsError.localizedDescription
        var line = 1
        var column = 1
        let description = (nsError.userInfo["NSDebugDescription"] as? String) ?? detail
        detail = description
        // Apple reports positions as either "line N, column M" or "character N".
        if let lineRange = description.range(of: #"line (\d+)"#, options: .regularExpression),
           let numberRange = Int(description[lineRange].split(separator: " ").last ?? "") {
            line = numberRange
        }
        if let columnRange = description.range(of: #"column (\d+)"#, options: .regularExpression),
           let numberRange = Int(description[columnRange].split(separator: " ").last ?? "") {
            column = numberRange
        }
        if let charRange = description.range(of: #"character (\d+)"#, options: .regularExpression),
           let offset = Int(description[charRange].split(separator: " ").last ?? ""), offset >= 0 {
            let prefix = text.prefix(offset)
            line = prefix.filter { $0 == "\n" }.count + 1
            if let lastNewline = prefix.lastIndex(of: "\n") {
                column = prefix.distance(from: prefix.index(after: lastNewline), to: prefix.endIndex) + 1
            } else {
                column = offset + 1
            }
        }
        return TransformError.invalidJSON(detail, line: max(1, line), column: max(1, column))
    }

    // MARK: - XML

    /// Validates well-formedness with a local parser. External entities are
    /// never resolved (no network access, no local file expansion).
    static func validateXML(_ text: String) throws {
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        if !parser.parse() {
            let error = parser.parserError
            let line = parser.lineNumber
            let column = parser.columnNumber
            let detail = error?.localizedDescription ?? "well-formedness error"
            throw TransformError.invalidXML("\(detail) (line \(line), column \(column))")
        }
    }

    static func formatXML(_ text: String) throws -> String {
        try validateXML(text)
        return XMLPrettyPrinter.prettyPrint(text)
    }

    // MARK: - Encodings

    static func base64Encode(_ text: String, lineLength: Int = 0) -> String {
        let encoded = Data(text.utf8).base64EncodedString()
        guard lineLength > 0 else { return encoded }
        return stride(from: 0, to: encoded.count, by: lineLength).map { offset in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(start, offsetBy: min(lineLength, encoded.count - offset))
            return String(encoded[start..<end])
        }.joined(separator: "\n")
    }

    static func base64Decode(_ text: String) throws -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]) else {
            throw TransformError.invalidBase64
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func urlEncode(_ text: String, formStyle: Bool = false) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+ ")
        if formStyle {
            // application/x-www-form-urlencoded: spaces become '+'.
            return text.components(separatedBy: " ")
                .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
                .joined(separator: "+")
        }
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func urlDecode(_ text: String, formStyle: Bool = false) throws -> String {
        let prepared = formStyle ? text.replacingOccurrences(of: "+", with: " ") : text
        guard let decoded = prepared.removingPercentEncoding else {
            throw TransformError.invalidURLPercentEncoding
        }
        return decoded
    }

    static func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func htmlUnescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Hashes

    enum HashAlgorithm: String, CaseIterable {
        case sha256
        case sha512
        case sha1
        case md5

        var displayName: String {
            switch self {
            case .sha256: return "SHA-256"
            case .sha512: return "SHA-512"
            case .sha1: return "SHA-1 (legacy)"
            case .md5: return "MD5 (legacy)"
            }
        }

        var isLegacy: Bool { self == .sha1 || self == .md5 }
    }

    static func hash(_ text: String, algorithm: HashAlgorithm) -> String {
        let data = Data(text.utf8)
        switch algorithm {
        case .sha256:
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha512:
            return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha1:
            return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .md5:
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    static func hash(fileAt url: URL, algorithm: HashAlgorithm) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = StreamingHasher(algorithm: algorithm)
        while autoreleasepool(invoking: { () -> Bool in
            let chunk = handle.readData(ofLength: 1024 * 1024)
            guard !chunk.isEmpty else { return false }
            hasher.update(chunk)
            return true
        }) {}
        return hasher.finalize()
    }

    struct StreamingHasher {
        let algorithm: HashAlgorithm
        private enum State {
            case sha256(SHA256)
            case sha512(SHA512)
            case sha1(Insecure.SHA1)
            case md5(Insecure.MD5)
        }
        private var state: State

        init(algorithm: HashAlgorithm) {
            self.algorithm = algorithm
            switch algorithm {
            case .sha256: state = .sha256(SHA256())
            case .sha512: state = .sha512(SHA512())
            case .sha1: state = .sha1(Insecure.SHA1())
            case .md5: state = .md5(Insecure.MD5())
            }
        }

        mutating func update(_ data: Data) {
            switch state {
            case .sha256(var hasher): hasher.update(data: data); state = .sha256(hasher)
            case .sha512(var hasher): hasher.update(data: data); state = .sha512(hasher)
            case .sha1(var hasher): hasher.update(data: data); state = .sha1(hasher)
            case .md5(var hasher): hasher.update(data: data); state = .md5(hasher)
            }
        }

        mutating func finalize() -> String {
            switch state {
            case .sha256(let hasher):
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            case .sha512(let hasher):
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            case .sha1(let hasher):
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            case .md5(let hasher):
                return hasher.finalize().map { String(format: "%02x", $0) }.joined()
            }
        }
    }

    // MARK: - Pane-targeted helpers

    /// Applies a transform to the current selection or the whole document,
    /// preserving undo grouping and adjusting the selection.
    static func apply(to pane: EditorPaneController, wholeDocumentIfNoSelection: Bool = true,
                      transform: (String) throws -> String) rethrows {
        let facade = pane.facade
        let selection = facade.mainSelection
        if !selection.isEmpty {
            let selected = facade.text(inRange: NSRange(location: selection.lowerBound, length: selection.length))
            let transformed = try transform(selected)
            facade.beginUndoAction()
            facade.setSelection(anchor: selection.lowerBound, caret: selection.upperBound)
            facade.replace(range: NSRange(location: selection.lowerBound, length: selection.length), with: transformed)
            facade.endUndoAction()
            facade.setSelection(anchor: selection.lowerBound, caret: selection.lowerBound + transformed.utf8.count)
        } else if wholeDocumentIfNoSelection {
            let text = facade.text
            let transformed = try transform(text)
            facade.beginUndoAction()
            let caret = facade.currentPosition
            facade.text = transformed
            facade.gotoPosition(min(caret, facade.length))
            facade.endUndoAction()
        }
    }

    static func convertTabsToSpaces(pane: EditorPaneController, tabWidth: Int) {
        apply(to: pane) { convertTabsToSpaces(in: $0, tabWidth: tabWidth) }
    }

    static func convertSpacesToTabs(pane: EditorPaneController, tabWidth: Int) {
        apply(to: pane) { convertSpacesToTabs(in: $0, tabWidth: tabWidth) }
    }
}
