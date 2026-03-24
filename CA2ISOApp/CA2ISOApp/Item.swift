//
//  Item.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
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
