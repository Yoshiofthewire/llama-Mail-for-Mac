//
//  ContactCursorStore.swift
//  llama Mail
//
//  Contact sync cursor + pending-delete tombstones (spec §4). Both are
//  UserDefaults-backed; like the notification cursor, the sync cursor only
//  ever advances.
//

import Foundation

final class ContactCursorStore {
    private static let key = "contacts.lastCursor"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var lastCursor: Int {
        defaults.integer(forKey: Self.key)
    }

    /// Advances the cursor; ignores values behind the current position.
    func advance(to cursor: Int) {
        guard cursor > lastCursor else { return }
        defaults.set(cursor, forKey: Self.key)
    }

    /// Discards the cursor after a `tooOld` response so the next sync is a
    /// full re-pull from 0 (Mobile_Contact_Sync.md).
    func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// Uids of contacts deleted locally while unsynced; included as
/// `{uid, deleted: true}` in the next sync request delta, then cleared.
final class ContactPendingDeletesStore {
    private static let key = "contacts.pendingDeletes"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func all() -> [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func add(_ uid: String) {
        var uids = all()
        guard !uids.contains(uid) else { return }
        uids.append(uid)
        defaults.set(uids, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
