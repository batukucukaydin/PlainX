//
//  FuzzyMatcher.swift
//  PlainX Editor
//
//  Subsequence fuzzy matcher used by the command palette. Returns a score and
//  matched character positions for highlighting.
//

import Foundation

enum FuzzyMatcher {
    struct Match {
        let score: Int
        let matchedIndices: [Int]
    }

    /// Returns nil when `query` is not a subsequence of `candidate`.
    static func match(query: String, candidate: String) -> Match? {
        guard !query.isEmpty else { return Match(score: 0, matchedIndices: []) }
        let queryCharacters = Array(query.lowercased())
        let candidateCharacters = Array(candidate.lowercased())
        guard candidateCharacters.count >= queryCharacters.count else { return nil }

        var matchedIndices: [Int] = []
        var queryIndex = 0
        var score = 0
        var previousMatchIndex = -1
        var currentStreak = 0

        for (index, character) in candidateCharacters.enumerated() {
            guard queryIndex < queryCharacters.count else { break }
            if character == queryCharacters[queryIndex] {
                matchedIndices.append(index)
                // Consecutive matches and word-boundary matches score higher.
                if index == previousMatchIndex + 1 {
                    currentStreak += 1
                    score += 8 + currentStreak * 2
                } else {
                    currentStreak = 0
                    score += 4
                }
                if index == 0 {
                    score += 12
                } else {
                    let previous = candidateCharacters[index - 1]
                    if previous == " " || previous == "-" || previous == "/" || previous == "." {
                        score += 8
                    }
                }
                previousMatchIndex = index
                queryIndex += 1
            }
        }

        guard queryIndex == queryCharacters.count else { return nil }
        // Prefer shorter candidates and earlier matches.
        score -= candidateCharacters.count / 4
        return Match(score: score, matchedIndices: matchedIndices)
    }
}
