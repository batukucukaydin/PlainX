//
//  GlobMatcher.swift
//  PlainX Editor
//
//  Small shell-style glob matcher used by Find in Files include/exclude
//  patterns ("*.swift;*.json", "build*", "?ata.txt").
//

import Foundation

enum GlobMatcher {

    /// Splits a user pattern list on ';' or ',' and matches the name against
    /// any of the patterns (case-insensitive on APFS by default).
    static func matchesAny(of patterns: [String], name: String, caseSensitive: Bool = false) -> Bool {
        for patternList in patterns {
            for pattern in split(patternList) where matches(pattern: pattern, name: name, caseSensitive: caseSensitive) {
                return true
            }
        }
        return false
    }

    static func split(_ patternList: String) -> [String] {
        patternList
            .split(whereSeparator: { $0 == ";" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func matches(pattern: String, name: String, caseSensitive: Bool = false) -> Bool {
        guard !pattern.isEmpty else { return false }
        let regex = regexForGlob(pattern)
        var options: NSRegularExpression.Options = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        guard let expression = try? NSRegularExpression(pattern: regex, options: options) else {
            // Fall back to substring matching for malformed patterns.
            return name.localizedCaseInsensitiveContains(pattern)
        }
        let range = NSRange(location: 0, length: name.utf16.count)
        return expression.firstMatch(in: name, options: [], range: range) != nil
    }

    /// Translates a glob into an anchored regular expression supporting
    /// '*', '?', and '[...]' character classes.
    static func regexForGlob(_ glob: String) -> String {
        var regex = "^"
        var index = glob.startIndex
        var insideClass = false
        while index < glob.endIndex {
            let character = glob[index]
            switch character {
            case "*":
                regex += insideClass ? "*" : ".*"
            case "?":
                regex += insideClass ? "?" : "."
            case "[":
                insideClass = true
                regex += "["
                let next = glob.index(after: index)
                if next < glob.endIndex, glob[next] == "!" || glob[next] == "^" {
                    regex += "^"
                    index = next
                }
            case "]":
                insideClass = false
                regex += "]"
            case "\\":
                let next = glob.index(after: index)
                if next < glob.endIndex {
                    regex += NSRegularExpression.escapedPattern(for: String(glob[next]))
                    index = next
                } else {
                    regex += "\\\\"
                }
            default:
                if insideClass {
                    regex.append(character)
                } else {
                    regex += NSRegularExpression.escapedPattern(for: String(character))
                }
            }
            index = glob.index(after: index)
        }
        regex += "$"
        return regex
    }
}
