//
//  DiffService.swift
//  PlainX Editor
//
//  Line-level text diff. Myers O(ND) with common prefix/suffix trimming and a
//  safety cap so pathological inputs degrade gracefully instead of freezing.
//  Pure and deterministic; unit tested independently of the UI.
//

import Foundation

enum DiffLineKind: Equatable {
    case equal
    case inserted
    case deleted
    case changed
}

struct DiffHunk: Equatable {
    enum Kind: Equatable {
        case insert
        case delete
        case change
    }

    let kind: Kind
    let leftLineRange: Range<Int>
    let rightLineRange: Range<Int>
}

struct DiffResult: Equatable {
    let hunks: [DiffHunk]
    let leftLineKinds: [DiffLineKind]
    let rightLineKinds: [DiffLineKind]

    var addedCount: Int { rightLineKinds.filter { $0 == .inserted }.count }
    var deletedCount: Int { leftLineKinds.filter { $0 == .deleted }.count }
    var changedCount: Int { leftLineKinds.filter { $0 == .changed }.count }

    var leftLineCount: Int { leftLineKinds.count }
    var rightLineCount: Int { rightLineKinds.count }
}

enum DiffService {

    struct Options: Equatable {
        var ignoreWhitespace = false
        var ignoreCase = false
    }

    /// Differences beyond this edit distance fall back to a whole-block
    /// replacement, bounding worst-case memory and time.
    static let maximumEditDistance = 2000

    static func diff(left: String, right: String, options: Options = Options()) -> DiffResult {
        let leftLines = left.components(separatedBy: "\n")
        let rightLines = right.components(separatedBy: "\n")
        return diff(leftLines: leftLines, rightLines: rightLines, options: options)
    }

    static func diff(leftLines: [String], rightLines: [String], options: Options = Options()) -> DiffResult {
        let leftKeys = leftLines.map { normalize($0, options: options) }
        let rightKeys = rightLines.map { normalize($0, options: options) }

        var leftKinds = [DiffLineKind](repeating: .equal, count: leftLines.count)
        var rightKinds = [DiffLineKind](repeating: .equal, count: rightLines.count)

        // Trim common prefix.
        var prefix = 0
        while prefix < leftKeys.count, prefix < rightKeys.count, leftKeys[prefix] == rightKeys[prefix] {
            prefix += 1
        }
        // Trim common suffix.
        var suffix = 0
        while suffix < (leftKeys.count - prefix), suffix < (rightKeys.count - prefix),
              leftKeys[leftKeys.count - 1 - suffix] == rightKeys[rightKeys.count - 1 - suffix] {
            suffix += 1
        }

        let leftMiddle = Array(leftKeys[prefix..<(leftKeys.count - suffix)])
        let rightMiddle = Array(rightKeys[prefix..<(rightKeys.count - suffix)])

        let middleHunks: [DiffHunk]
        let operations: [EditOperation]

        if leftMiddle.isEmpty && rightMiddle.isEmpty {
            operations = []
        } else if leftMiddle.isEmpty {
            operations = [.insert(leftRange: 0..<0, rightRange: 0..<rightMiddle.count)]
        } else if rightMiddle.isEmpty {
            operations = [.delete(leftRange: 0..<leftMiddle.count, rightRange: 0..<0)]
        } else {
            operations = myersOperations(left: leftMiddle, right: rightMiddle) ?? [
                .replace(leftRange: 0..<leftMiddle.count, rightRange: 0..<rightMiddle.count)
            ]
        }

        // Map operations back into document coordinates and fill line kinds.
        var hunks: [DiffHunk] = []
        var current: (leftStart: Int, leftEnd: Int, rightStart: Int, rightEnd: Int, kind: DiffHunk.Kind)?
        func flush() {
            guard let block = current else { return }
            hunks.append(DiffHunk(kind: block.kind,
                                  leftLineRange: block.leftStart..<block.leftEnd,
                                  rightLineRange: block.rightStart..<block.rightEnd))
            current = nil
        }

        for operation in operations {
            switch operation {
            case .equal(let leftRange, let rightRange, let length):
                flush()
                for offset in 0..<length {
                    let leftIndex = prefix + leftRange.lowerBound + offset
                    let rightIndex = prefix + rightRange.lowerBound + offset
                    if leftIndex < leftKinds.count { leftKinds[leftIndex] = .equal }
                    if rightIndex < rightKinds.count { rightKinds[rightIndex] = .equal }
                }
            case .insert(let leftRange, let rightRange):
                for offset in rightRange {
                    let rightIndex = prefix + offset
                    if rightIndex < rightKinds.count { rightKinds[rightIndex] = .inserted }
                }
                appendBlock(kind: .insert, leftRange: (prefix + leftRange.lowerBound)..<(prefix + leftRange.upperBound),
                            rightRange: (prefix + rightRange.lowerBound)..<(prefix + rightRange.upperBound),
                            current: &current, flush: flush)
            case .delete(let leftRange, let rightRange):
                for offset in leftRange {
                    let leftIndex = prefix + offset
                    if leftIndex < leftKinds.count { leftKinds[leftIndex] = .deleted }
                }
                appendBlock(kind: .delete, leftRange: (prefix + leftRange.lowerBound)..<(prefix + leftRange.upperBound),
                            rightRange: (prefix + rightRange.lowerBound)..<(prefix + rightRange.upperBound),
                            current: &current, flush: flush)
            case .replace(let leftRange, let rightRange):
                for offset in leftRange {
                    let leftIndex = prefix + offset
                    if leftIndex < leftKinds.count { leftKinds[leftIndex] = .changed }
                }
                for offset in rightRange {
                    let rightIndex = prefix + offset
                    if rightIndex < rightKinds.count { rightKinds[rightIndex] = .changed }
                }
                appendBlock(kind: .change, leftRange: (prefix + leftRange.lowerBound)..<(prefix + leftRange.upperBound),
                            rightRange: (prefix + rightRange.lowerBound)..<(prefix + rightRange.upperBound),
                            current: &current, flush: flush)
            }
        }
        flush()

        return DiffResult(hunks: hunks, leftLineKinds: leftKinds, rightLineKinds: rightKinds)
    }

    private static func appendBlock(kind: DiffHunk.Kind,
                                    leftRange: Range<Int>, rightRange: Range<Int>,
                                    current: inout (leftStart: Int, leftEnd: Int, rightStart: Int, rightEnd: Int, kind: DiffHunk.Kind)?,
                                    flush: () -> Void) {
        guard !leftRange.isEmpty || !rightRange.isEmpty else { return }
        if var existing = current {
            // Coalesce adjacent delete+insert into a change when they touch.
            let merges: Bool
            switch (existing.kind, kind) {
            case (.delete, .insert):
                merges = existing.rightEnd == rightRange.lowerBound && existing.leftEnd == leftRange.lowerBound
            case (.insert, .delete):
                merges = existing.rightEnd == rightRange.lowerBound && existing.leftEnd == leftRange.lowerBound
            case (.change, _), (_, .change):
                merges = existing.leftEnd == leftRange.lowerBound && existing.rightEnd == rightRange.lowerBound
            default:
                merges = existing.leftEnd == leftRange.lowerBound && existing.rightEnd == rightRange.lowerBound
            }
            if merges {
                existing.leftEnd = max(existing.leftEnd, leftRange.upperBound)
                existing.rightEnd = max(existing.rightEnd, rightRange.upperBound)
                if existing.kind != kind { existing.kind = .change }
                current = existing
                return
            }
            flush()
        }
        current = (leftRange.lowerBound, leftRange.upperBound,
                   rightRange.lowerBound, rightRange.upperBound, kind)
    }

    // MARK: - Operand types

    private enum EditOperation {
        case equal(leftRange: Range<Int>, rightRange: Range<Int>, length: Int)
        case insert(leftRange: Range<Int>, rightRange: Range<Int>)
        case delete(leftRange: Range<Int>, rightRange: Range<Int>)
        case replace(leftRange: Range<Int>, rightRange: Range<Int>)
    }

    /// Myers O(ND) diff producing edit operations. Returns nil when the edit
    /// distance exceeds the safety cap.
    private static func myersOperations(left: [String], right: [String]) -> [EditOperation]? {
        let n = left.count
        let m = right.count
        let maxDistance = min(n + m, maximumEditDistance)
        let offset = maxDistance + 1
        let size = 2 * maxDistance + 3
        var v = [Int](repeating: 0, count: size)
        var trace: [[Int]] = []

        var finalDistance: Int?
        outer: for distance in 0...maxDistance {
            trace.append(v)
            var k = -distance
            while k <= distance {
                let index = k + offset
                var x: Int
                if k == -distance || (k != distance && v[index - 1] < v[index + 1]) {
                    x = v[index + 1]
                } else {
                    x = v[index - 1] + 1
                }
                var y = x - k
                while x < n, y < m, left[x] == right[y] {
                    x += 1
                    y += 1
                }
                v[index] = x
                if x >= n, y >= m {
                    finalDistance = distance
                    break outer
                }
                k += 2
            }
        }

        guard let distance = finalDistance else { return nil }

        // Backtrack the traced V arrays into edit operations.
        var operations: [EditOperation] = []
        var x = n
        var y = m
        var d = distance
        while d >= 0 {
            let vPrevious = trace[d]
            let k = x - y
            let index = k + offset
            let previousK: Int
            if k == -d || (k != d && vPrevious[index - 1] < vPrevious[index + 1]) {
                previousK = k + 1
            } else {
                previousK = k - 1
            }
            let previousX = vPrevious[previousK + offset]
            let previousY = previousX - previousK

            // Emit equal lines (the diagonal run).
            var equalSteps = 0
            while x > previousX, y > previousY {
                x -= 1
                y -= 1
                equalSteps += 1
            }
            if equalSteps > 0 {
                operations.append(.equal(leftRange: x..<(x + equalSteps),
                                         rightRange: y..<(y + equalSteps),
                                         length: equalSteps))
            }
            if d > 0 {
                if x == previousX {
                    operations.append(.insert(leftRange: x..<x, rightRange: (y - 1)..<y))
                } else {
                    operations.append(.delete(leftRange: (x - 1)..<x, rightRange: y..<y))
                }
                x = previousX
                y = previousY
            }
            d -= 1
        }

        operations.reverse()
        return coalesce(operations)
    }

    /// Merges adjacent delete+insert operand pairs into replace operations so
    /// that side-by-side views classify them as changes.
    private static func coalesce(_ operations: [EditOperation]) -> [EditOperation] {
        var result: [EditOperation] = []
        var index = 0
        while index < operations.count {
            if case .delete(let leftRange, _) = operations[index],
               index + 1 < operations.count,
               case .insert(_, let rightRange) = operations[index + 1] {
                result.append(.replace(leftRange: leftRange, rightRange: rightRange))
                index += 2
            } else if case .insert(let rightRange, _) = operations[index],
                      index + 1 < operations.count,
                      case .delete(let leftRange, _) = operations[index + 1] {
                result.append(.replace(leftRange: leftRange, rightRange: rightRange))
                index += 2
            } else {
                result.append(operations[index])
                index += 1
            }
        }
        return result
    }

    private static func normalize(_ line: String, options: Options) -> String {
        var line = line
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        if options.ignoreWhitespace {
            line = line.trimmingCharacters(in: .whitespaces)
            line = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        }
        if options.ignoreCase {
            line = line.lowercased()
        }
        return line
    }
}
