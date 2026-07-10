//
//  Item.swift
//  llama Mail for Mac
//
//  Created by Matthew Beacher on 7/10/26.
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
