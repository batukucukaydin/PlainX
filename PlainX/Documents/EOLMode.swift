//
//  EOLMode.swift
//  PlainX Editor
//

import Foundation

enum EOLMode: String, Codable, CaseIterable {
    case lf
    case crlf
    case cr
    case mixed

    var displayName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        case .mixed: return "Mixed"
        }
    }

    var longDisplayName: String {
        switch self {
        case .lf: return "Unix (LF)"
        case .crlf: return "Windows (CRLF)"
        case .cr: return "Classic Mac (CR)"
        case .mixed: return "Mixed line endings"
        }
    }

    /// The dominant concrete line ending to use when saving a mixed document.
    var concreteFallback: EOLMode {
        self == .mixed ? .lf : self
    }

    var stringValue: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        case .mixed: return "\n"
        }
    }

    static func detect(in text: String) -> EOLMode {
        var lf = 0
        var crlf = 0
        var cr = 0
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            if scalar == "\r" {
                if previousWasCR { cr += 1 }
                previousWasCR = true
            } else if scalar == "\n" {
                if previousWasCR {
                    crlf += 1
                    previousWasCR = false
                } else {
                    lf += 1
                }
            } else {
                if previousWasCR {
                    cr += 1
                    previousWasCR = false
                }
            }
        }
        if previousWasCR { cr += 1 }

        let kinds = [lf, crlf, cr].filter { $0 > 0 }.count
        if kinds == 0 { return .lf }
        if kinds > 1 { return .mixed }
        if crlf > 0 { return .crlf }
        if cr > 0 { return .cr }
        return .lf
    }

    /// Detects line endings in raw bytes without decoding the whole file.
    static func detect(in data: Data) -> EOLMode {
        var lf = 0
        var crlf = 0
        var cr = 0
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x0D {
                let next = data.index(after: index)
                if next < data.endIndex && data[next] == 0x0A {
                    crlf += 1
                    index = next
                } else {
                    cr += 1
                }
            } else if byte == 0x0A {
                lf += 1
            }
            index = data.index(after: index)
        }
        let kinds = [lf, crlf, cr].filter { $0 > 0 }.count
        if kinds == 0 { return .lf }
        if kinds > 1 { return .mixed }
        if crlf > 0 { return .crlf }
        if cr > 0 { return .cr }
        return .lf
    }
}
