//
//  ContactsSettingsStore.swift
//  KyPost
//
//  UserDefaults-backed contacts preferences: the "export to Apple Contacts"
//  toggle read by SystemContactsExporter before every export.
//

import Foundation

final class ContactsSettingsStore {
    private enum Key {
        static let exportToSystemEnabled = "contacts.exportToSystemEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// User toggle from Preferences; when on, contact changes are mirrored to
    /// the system Contacts database after syncs and local edits.
    var exportToSystemContactsEnabled: Bool {
        get { defaults.object(forKey: Key.exportToSystemEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.exportToSystemEnabled) }
    }
}
