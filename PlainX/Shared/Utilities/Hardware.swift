//
//  Hardware.swift
//  PlainX Editor
//

import Foundation

enum Hardware {
    static func architectureString() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { buffer -> String in
            let bytes = buffer.prefix(while: { $0 != 0 })
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine
    }
}
