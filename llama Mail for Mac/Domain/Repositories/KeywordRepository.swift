//
//  KeywordRepository.swift
//  llama Mail
//
//  Derives inbox tabs from email keywords (spec §2 Inbox Tabs): IMAP mode
//  computes them from user flags, relay mode from server tab/label fields —
//  both arrive on Email.keywords, so one computation serves both. Visibility
//  toggles come from KeywordSettingsStore. The 90-second foreground refresh
//  is driven by the inbox view model (Phase 6) on Config.foregroundRefreshInterval.
//

import Foundation

/// One inbox tab with the number of emails carrying its keyword.
struct KeywordTab: Equatable, Sendable {
    var name: String
    var count: Int
}

final class KeywordRepository {
    private let settingsStore: KeywordSettingsStore

    init(settingsStore: KeywordSettingsStore) {
        self.settingsStore = settingsStore
    }

    /// All keywords present in the given emails, alphabetical with counts.
    static func computeTabs(from emails: [Email]) -> [KeywordTab] {
        var counts: [String: Int] = [:]
        for email in emails {
            for keyword in email.keywords where !keyword.isEmpty {
                counts[keyword, default: 0] += 1
            }
        }
        return counts
            .map { KeywordTab(name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Tabs to show in the inbox tab bar (hidden keywords filtered out).
    func visibleTabs(from emails: [Email]) -> [KeywordTab] {
        Self.computeTabs(from: emails).filter { settingsStore.isVisible($0.name) }
    }

    /// All keywords with their visibility, for KeywordSettingsView.
    func allSettings(from emails: [Email]) -> [KeywordSetting] {
        Self.computeTabs(from: emails).map {
            KeywordSetting(name: $0.name, visible: settingsStore.isVisible($0.name))
        }
    }

    func setVisible(_ visible: Bool, for keyword: String) {
        settingsStore.setVisible(visible, for: keyword)
    }
}
