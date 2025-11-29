//
//  Item.swift
//  VoiceInk-ios
//
//  Created by Taafa D on 12/08/2025.
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
