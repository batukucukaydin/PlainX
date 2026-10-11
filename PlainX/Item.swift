//
//  Item.swift
//  PlainX
//
//  Created by Batuhan Kucukaydın on 11.10.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
