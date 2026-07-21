//
//  KeywordSettings.swift
//  KyPost
//
//  Per-keyword visibility for inbox tabs (spec §2 Keyword Settings).
//

import Foundation

struct KeywordSetting: Identifiable, Hashable, Sendable {
    var name: String
    /// Whether the keyword's tab is shown in the inbox tab bar. Defaults to visible.
    var visible: Bool = true

    var id: String { name }
}
