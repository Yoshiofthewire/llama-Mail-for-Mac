//
//  KeywordEntity.swift
//  KyPost
//
//  SwiftData entity for the keywords table (spec §8). Caches keywords observed
//  on messages so tabs persist across launches; visibility toggles live in
//  KeywordSettingsStore (UserDefaults) per spec §1.
//

import Foundation
import SwiftData

@Model
final class KeywordEntity {
    @Attribute(.unique) var name: String
    var visible: Bool
    var createdAt: Date

    init(name: String, visible: Bool = true, createdAt: Date = Date()) {
        self.name = name
        self.visible = visible
        self.createdAt = createdAt
    }
}
