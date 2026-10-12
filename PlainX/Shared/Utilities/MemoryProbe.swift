//
//  MemoryProbe.swift
//  PlainX Editor
//
//  Lightweight resident-memory probing used by the developer benchmarks
//  (never sent anywhere; printed to stdout only in benchmark mode).
//

import Foundation

enum MemoryProbe {
    /// Resident set size in bytes for the current process.
    static func currentRSSBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    static func formattedRSS() -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(currentRSSBytes()))
    }
}
