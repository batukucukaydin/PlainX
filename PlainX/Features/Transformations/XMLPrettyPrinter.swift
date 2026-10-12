//
//  XMLPrettyPrinter.swift
//  PlainX Editor
//
//  Minimal well-formed XML pretty printer. It runs only after XMLParser
//  validated the document; it never resolves entities or fetches anything.
//

import Foundation

enum XMLPrettyPrinter {

    static func prettyPrint(_ text: String, indentUnit: String = "    ") -> String {
        let characters = Array(text)
        var output = ""
        var depth = 0
        var index = 0
        var textRun = ""
        var pendingTextRun = ""

        func flushTextRun(inline: Bool) {
            let trimmed = textRun.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                textRun = ""
                return
            }
            if inline {
                output += trimmed
            } else {
                output += String(repeating: indentUnit, count: depth) + trimmed + "\n"
            }
            textRun = ""
        }

        while index < characters.count {
            let character = characters[index]
            if character == "<" {
                // Comment or declaration?
                if matches(characters, at: index, prefix: "<!--") {
                    if let end = find(characters, from: index, sequence: "-->") {
                        flushTextRun(inline: false)
                        let comment = String(characters[index...(end + 2)])
                        output += String(repeating: indentUnit, count: depth) + comment + "\n"
                        index = end + 3
                        continue
                    }
                }
                if matches(characters, at: index, prefix: "<![CDATA[") {
                    if let end = find(characters, from: index, sequence: "]]>") {
                        flushTextRun(inline: true)
                        let cdata = String(characters[index...(end + 2)])
                        output += cdata
                        output += "\n"
                        pendingTextRun = ""
                        index = end + 3
                        continue
                    }
                }
                if matches(characters, at: index, prefix: "<?") {
                    if let end = find(characters, from: index, sequence: "?>") {
                        flushTextRun(inline: false)
                        let instruction = String(characters[index...(end + 1)])
                        output += String(repeating: indentUnit, count: depth) + instruction + "\n"
                        index = end + 2
                        continue
                    }
                }
                if matches(characters, at: index, prefix: "<!") {
                    // DOCTYPE or similar; copy verbatim until '>' at depth 0.
                    if let end = findDocumentTypeEnd(characters, from: index) {
                        flushTextRun(inline: false)
                        let declaration = String(characters[index...end])
                        output += declaration + "\n"
                        index = end + 1
                        continue
                    }
                }

                guard let tagEnd = findTagEnd(characters, from: index) else {
                    // Malformed tail: append the rest unchanged.
                    flushTextRun(inline: false)
                    output += String(characters[index...])
                    break
                }
                let tag = String(characters[index...tagEnd])
                let isClosing = tag.hasPrefix("</")
                let isSelfClosing = tag.hasSuffix("/>")

                if isClosing {
                    depth = max(0, depth - 1)
                    flushTextRun(inline: false)
                    output += String(repeating: indentUnit, count: depth) + tag + "\n"
                } else if isSelfClosing {
                    flushTextRun(inline: false)
                    output += String(repeating: indentUnit, count: depth) + tag + "\n"
                } else {
                    flushTextRun(inline: false)
                    output += String(repeating: indentUnit, count: depth) + tag
                    // Look ahead: if the element contains only text until the
                    // next tag, keep it on one line.
                    var lookahead = tagEnd + 1
                    var innerText = ""
                    var onlyText = true
                    while lookahead < characters.count && characters[lookahead] != "<" {
                        innerText.append(characters[lookahead])
                        lookahead += 1
                    }
                    let inlineCandidate = innerText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inlineCandidate.isEmpty && lookahead < characters.count
                        && matches(characters, at: lookahead, prefix: "</") {
                        if let closeEnd = findTagEnd(characters, from: lookahead) {
                            let closeTag = String(characters[lookahead...closeEnd])
                            if closeTag.dropFirst(2).hasPrefix(rootName(of: tag)) {
                                output += inlineCandidate + closeTag + "\n"
                                index = closeEnd + 1
                                continue
                            }
                        }
                    }
                    output += "\n"
                    depth += 1
                }
                pendingTextRun = ""
                index = tagEnd + 1
            } else {
                textRun.append(character)
                index += 1
            }
        }

        flushTextRun(inline: false)
        // Collapse excessive blank lines that can appear at EOF.
        while output.hasSuffix("\n\n") {
            output.removeLast()
        }
        return output
    }

    private static func rootName(of tag: String) -> String {
        var name = tag.dropFirst()
        if let spaceIndex = name.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }) {
            name = name[..<spaceIndex]
        }
        return String(name)
    }

    private static func matches(_ characters: [Character], at index: Int, prefix: String) -> Bool {
        let prefixChars = Array(prefix)
        guard index + prefixChars.count <= characters.count else { return false }
        for offset in 0..<prefixChars.count where characters[index + offset] != prefixChars[offset] {
            return false
        }
        return true
    }

    private static func find(_ characters: [Character], from index: Int, sequence: String) -> Int? {
        let sequenceChars = Array(sequence)
        guard !sequenceChars.isEmpty else { return nil }
        var position = index
        while position + sequenceChars.count <= characters.count {
            var matched = true
            for offset in 0..<sequenceChars.count where characters[position + offset] != sequenceChars[offset] {
                matched = false
                break
            }
            if matched { return position }
            position += 1
        }
        return nil
    }

    /// Finds the closing '>' of a tag, skipping quoted attribute values.
    private static func findTagEnd(_ characters: [Character], from index: Int) -> Int? {
        var position = index + 1
        var quote: Character?
        while position < characters.count {
            let character = characters[position]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return position
            }
            position += 1
        }
        return nil
    }

    /// Finds the end of a <!DOCTYPE ...> declaration which can contain an
    /// internal subset with '>' characters inside brackets.
    private static func findDocumentTypeEnd(_ characters: [Character], from index: Int) -> Int? {
        var position = index + 2
        var bracketDepth = 0
        while position < characters.count {
            let character = characters[position]
            if character == "[" {
                bracketDepth += 1
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
            } else if character == ">" && bracketDepth == 0 {
                return position
            }
            position += 1
        }
        return nil
    }
}
