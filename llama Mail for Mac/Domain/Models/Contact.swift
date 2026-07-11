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
    var name: String
    var email: String
    var phone: String
    var avatarUrl: String?
    var createdAt: Date
    var updatedAt: Date

    var id: UUID { localId }
}
