//
//  TextEncoding.swift
//  PlainX Editor
//
//  Encoding model and conservative detection. Detection never silently
//  discards bytes: if confidence is low the loader reports a diagnostic so
//  the UI can ask the user.
//

import Foundation

struct TextEncoding: Equatable, Codable {
    /// Stable identifier persisted in sessions ("utf-8", "utf-16le", ...).
    let identifier: String
    let displayName: String
    /// String.Encoding raw value.
    let foundationValue: UInt
    let hasBOM: Bool

    var stringEncoding: String.Encoding {
        String.Encoding(rawValue: foundationValue)
    }

    static let utf8 = TextEncoding(identifier: "utf-8", displayName: "UTF-8",
                                   foundationValue: String.Encoding.utf8.rawValue, hasBOM: false)
    static let utf8BOM = TextEncoding(identifier: "utf-8", displayName: "UTF-8 with BOM",
                                      foundationValue: String.Encoding.utf8.rawValue, hasBOM: true)
    static let utf16LE = TextEncoding(identifier: "utf-16le", displayName: "UTF-16 LE",
                                      foundationValue: String.Encoding.utf16LittleEndian.rawValue, hasBOM: false)
    static let utf16LEBOM = TextEncoding(identifier: "utf-16le", displayName: "UTF-16 LE with BOM",
                                         foundationValue: String.Encoding.utf16LittleEndian.rawValue, hasBOM: true)
    static let utf16BE = TextEncoding(identifier: "utf-16be", displayName: "UTF-16 BE",
                                      foundationValue: String.Encoding.utf16BigEndian.rawValue, hasBOM: false)
    static let utf16BEBOM = TextEncoding(identifier: "utf-16be", displayName: "UTF-16 BE with BOM",
                                         foundationValue: String.Encoding.utf16BigEndian.rawValue, hasBOM: true)
    static let ascii = TextEncoding(identifier: "ascii", displayName: "ASCII",
                                    foundationValue: String.Encoding.ascii.rawValue, hasBOM: false)
    static let isoLatin1 = TextEncoding(identifier: "iso-8859-1", displayName: "ISO-8859-1 (Latin-1)",
                                        foundationValue: String.Encoding.isoLatin1.rawValue, hasBOM: false)
    static let windows1252 = TextEncoding(identifier: "windows-1252", displayName: "Windows-1252",
                                          foundationValue: String.Encoding.windowsCP1252.rawValue, hasBOM: false)
    static let macRoman = TextEncoding(identifier: "macroman", displayName: "Mac Roman",
                                       foundationValue: String.Encoding.macOSRoman.rawValue, hasBOM: false)

    static let selectable: [TextEncoding] = [
        .utf8, .utf8BOM, .utf16LE, .utf16LEBOM, .utf16BE, .utf16BEBOM,
        .ascii, .windows1252, .isoLatin1, .macRoman,
    ]

    static func == (lhs: TextEncoding, rhs: TextEncoding) -> Bool {
        lhs.identifier == rhs.identifier && lhs.hasBOM == rhs.hasBOM
    }

    /// Builds an encoding from a CFString conversion identifier, used for the
    /// broader system-supplied encoding list.
    init?(cfIdentifier: String) {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(cfIdentifier as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        self.identifier = cfIdentifier.lowercased()
        self.displayName = cfIdentifier
        self.foundationValue = nsEncoding
        self.hasBOM = false
    }

    init(identifier: String, displayName: String, foundationValue: UInt, hasBOM: Bool) {
        self.identifier = identifier
        self.displayName = displayName
        self.foundationValue = foundationValue
        self.hasBOM = hasBOM
    }
}

struct EncodingDetectionResult {
    let encoding: TextEncoding
    let confidence: Double
    /// Non-nil when byte sequences could not be decoded with the chosen
    /// encoding and lossy conversion was used.
    let hadInvalidSequences: Bool
    let diagnostic: String?
}

enum EncodingDetector {

    /// Conservative detection order:
    /// 1. BOM
    /// 2. strict UTF-8 validation
    /// 3. ASCII subset
    /// 4. legacy single-byte heuristics (Windows-1252, ISO-8859-1)
    /// 5. lossy UTF-8 fallback flagged with a diagnostic
    static func detect(data: Data, preferredEncoding: TextEncoding? = nil) -> EncodingDetectionResult {
        if data.isEmpty {
            return EncodingDetectionResult(encoding: preferredEncoding ?? .utf8, confidence: 1.0,
                                           hadInvalidSequences: false, diagnostic: nil)
        }

        if let bomResult = detectBOM(data) {
            return bomResult
        }

        if let validUTF8 = validateUTF8(data) {
            if validUTF8.isASCII {
                return EncodingDetectionResult(encoding: .ascii, confidence: 0.95,
                                               hadInvalidSequences: false, diagnostic: nil)
            }
            return EncodingDetectionResult(encoding: .utf8, confidence: 1.0,
                                           hadInvalidSequences: false, diagnostic: nil)
        }

        // Not valid UTF-8 and no BOM: try UTF-16 without BOM heuristically.
        if let utf16 = detectUTF16WithoutBOM(data) {
            return utf16
        }

        // Single-byte legacy encodings: prefer the caller's preference, then
        // Windows-1252 which is a superset of Latin-1 for common files.
        if let preferred = preferredEncoding, !preferred.hasBOM, preferred.identifier != "utf-8" {
            return EncodingDetectionResult(encoding: preferred, confidence: 0.6,
                                           hadInvalidSequences: false,
                                           diagnostic: "File is not valid UTF-8. Opened with \(preferred.displayName).")
        }

        let windows1252Lossy = String(data: data, encoding: .windowsCP1252)
        if windows1252Lossy != nil {
            return EncodingDetectionResult(
                encoding: .windows1252, confidence: 0.55, hadInvalidSequences: false,
                diagnostic: "File is not valid UTF-8. Opened as Windows-1252; use “Reopen with Encoding” if this is wrong."
            )
        }

        return EncodingDetectionResult(
            encoding: .windows1252, confidence: 0.3, hadInvalidSequences: true,
            diagnostic: "File contains byte sequences that are not valid text in any common encoding. Some characters may display incorrectly."
        )
    }

    private static func detectBOM(_ data: Data) -> EncodingDetectionResult? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return EncodingDetectionResult(encoding: .utf8BOM, confidence: 1.0,
                                           hadInvalidSequences: false, diagnostic: nil)
        }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return EncodingDetectionResult(
                encoding: TextEncoding(identifier: "utf-32le", displayName: "UTF-32 LE",
                                       foundationValue: String.Encoding.utf32LittleEndian.rawValue, hasBOM: true),
                confidence: 1.0, hadInvalidSequences: false, diagnostic: nil)
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return EncodingDetectionResult(
                encoding: TextEncoding(identifier: "utf-32be", displayName: "UTF-32 BE",
                                       foundationValue: String.Encoding.utf32BigEndian.rawValue, hasBOM: true),
                confidence: 1.0, hadInvalidSequences: false, diagnostic: nil)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return EncodingDetectionResult(encoding: .utf16LEBOM, confidence: 1.0,
                                           hadInvalidSequences: false, diagnostic: nil)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return EncodingDetectionResult(encoding: .utf16BEBOM, confidence: 1.0,
                                           hadInvalidSequences: false, diagnostic: nil)
        }
        return nil
    }

    struct UTF8ValidationResult {
        let isASCII: Bool
    }

    /// Strict UTF-8 validation compatible with what String(data:encoding:) accepts.
    static func validateUTF8(_ data: Data) -> UTF8ValidationResult? {
        var isASCII = true
        var index = 0
        let bytes = [UInt8](data)
        let count = bytes.count
        while index < count {
            let byte = bytes[index]
            if byte < 0x80 {
                index += 1
                continue
            }
            isASCII = false
            var sequenceLength = 0
            var lowerBound: UInt8 = 0
            var upperBound: UInt8 = 0
            switch byte {
            case 0xC2...0xDF:
                sequenceLength = 2
                lowerBound = 0x80
                upperBound = 0xBF
            case 0xE0:
                sequenceLength = 3
                lowerBound = 0xA0
                upperBound = 0xBF
            case 0xE1...0xEC, 0xEE...0xEF:
                sequenceLength = 3
                lowerBound = 0x80
                upperBound = 0xBF
            case 0xED:
                sequenceLength = 3
                lowerBound = 0x80
                upperBound = 0x9F
            case 0xF0:
                sequenceLength = 4
                lowerBound = 0x90
                upperBound = 0xBF
            case 0xF1...0xF3:
                sequenceLength = 4
                lowerBound = 0x80
                upperBound = 0xBF
            case 0xF4:
                sequenceLength = 4
                lowerBound = 0x80
                upperBound = 0x8F
            default:
                return nil
            }
            guard index + sequenceLength <= count else { return nil }
            let second = bytes[index + 1]
            guard second >= lowerBound && second <= upperBound else { return nil }
            for offset in 2..<sequenceLength {
                let continuation = bytes[index + offset]
                guard continuation >= 0x80 && continuation <= 0xBF else { return nil }
            }
            index += sequenceLength
        }
        return UTF8ValidationResult(isASCII: isASCII)
    }

    private static func detectUTF16WithoutBOM(_ data: Data) -> EncodingDetectionResult? {
        // Heuristic: count NUL bytes in even/odd positions.
        guard data.count >= 8, data.count % 2 == 0 else { return nil }
        var evenNuls = 0
        var oddNuls = 0
        let sampleCount = min(data.count, 4096)
        var index = data.startIndex
        var position = 0
        while position < sampleCount {
            if data[index] == 0 {
                if position % 2 == 0 { evenNuls += 1 } else { oddNuls += 1 }
            }
            index = data.index(after: index)
            position += 1
        }
        let half = sampleCount / 2
        if oddNuls > half / 2 && evenNuls < half / 10 {
            return EncodingDetectionResult(encoding: .utf16LE, confidence: 0.7,
                                           hadInvalidSequences: false,
                                           diagnostic: "Detected UTF-16 LE without byte order mark.")
        }
        if evenNuls > half / 2 && oddNuls < half / 10 {
            return EncodingDetectionResult(encoding: .utf16BE, confidence: 0.7,
                                           hadInvalidSequences: false,
                                           diagnostic: "Detected UTF-16 BE without byte order mark.")
        }
        return nil
    }
}
