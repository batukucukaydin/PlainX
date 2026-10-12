//
//  WordCompletion.swift
//  PlainX Editor
//
//  Document-local word completion (Control-Escape): collects candidate words
//  from the current document and inserts/cycles completions at the caret.
//

import AppKit

enum WordCompletion {
    private static var currentPrefix: String = ""
    private static var currentCandidates: [String] = []
    private static var currentIndex = 0
    private static var replaceRange: NSRange = NSRange(location: 0, length: 0)

    static func complete(pane: EditorPaneController) {
        let facade = pane.facade
        let caret = facade.currentPosition
        let line = facade.line(from: caret)
        let lineStart = facade.lineStart(line)
        let lineText = facade.text(inRange: NSRange(location: lineStart, length: caret - lineStart))

        let prefix: String
        if currentCandidates.isEmpty {
            prefix = trailingWord(of: lineText)
            replaceRange = NSRange(location: caret - prefix.utf8.count, length: prefix.utf8.count)
        } else {
            prefix = currentPrefix
        }
        guard !prefix.isEmpty else {
            NSSound.beep()
            return
        }

        if currentCandidates.isEmpty {
            currentPrefix = prefix
            currentCandidates = collectCandidates(in: facade.text, prefix: prefix)
            currentCandidates.sort { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            currentIndex = 0
        }
        guard !currentCandidates.isEmpty else {
            reset()
            NSSound.beep()
            return
        }

        let candidate = currentCandidates[currentIndex % currentCandidates.count]
        currentIndex += 1

        facade.beginUndoAction()
        facade.setSelection(anchor: replaceRange.location, caret: replaceRange.location + replaceRange.length)
        facade.replaceTarget(with: candidate, regex: false)
        facade.endUndoAction()
        let newLength = candidate.utf8.count
        replaceRange = NSRange(location: replaceRange.location, length: newLength)

        // Reset cycling on the next typed character.
        DispatchQueue.main.async {
            reset()
        }
    }

    private static func reset() {
        currentPrefix = ""
        currentCandidates = []
        currentIndex = 0
    }

    private static func trailingWord(of text: String) -> String {
        var result = ""
        for character in text.reversed() {
            if character.isLetter || character.isNumber || character == "_" || character == "$" {
                result.append(character)
            } else {
                break
            }
        }
        return String(result.reversed())
    }

    private static func collectCandidates(in text: String, prefix: String) -> [String] {
        var candidates = Set<String>()
        var current = ""
        current.reserveCapacity(32)
        let prefixLength = prefix.count
        for character in text {
            if character.isLetter || character.isNumber || character == "_" || character == "$" {
                current.append(character)
                if current.count > 64 {
                    current.removeFirst()
                }
            } else {
                if current.count > prefixLength, current.hasPrefix(prefix), current != prefix {
                    candidates.insert(current)
                    if candidates.count > 2000 { break }
                }
                current = ""
            }
        }
        if current.count > prefixLength, current.hasPrefix(prefix), current != prefix {
            candidates.insert(current)
        }
        return Array(candidates)
    }
}
