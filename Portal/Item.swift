//
//  Item.swift
//  Portal
//
//  Created by 松岡周平 on 2025/12/29.
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
