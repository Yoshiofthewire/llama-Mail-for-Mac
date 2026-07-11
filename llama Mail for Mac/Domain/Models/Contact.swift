//
//  Contact.swift
//  llama Mail
//
//  Domain model for a synced contact (spec §4, §8 contacts table).
//

import Foundation

struct Contact: Identifiable, Hashable, Sendable {
    /// Stable local identity; contacts created locally have no server `uid`
    /// until ContactSyncReconciliation assigns one (spec §4).
    var localId: UUID = UUID()
    /// Server-assigned UID from sync; nil for locally-created, not-yet-reconciled contacts.
    var uid: String?
    /// Server revision, echoed back on pushes for conflict detection
    /// (Mobile_Contact_Sync.md); 0 until the first sync assigns one.
    var rev: Int = 0
    var name: String
    var email: String
    var phone: String
    var avatarUrl: String?
    var createdAt: Date
    var updatedAt: Date
    /// True for local creates/edits not yet pushed to the server (spec §4).
    var needsSync: Bool = false

    var id: UUID { localId }
}
