//
//  ContactEntity.swift
//  llama Mail
//
//  SwiftData entity for the contacts table (spec §8).
//

import Foundation
import SwiftData

@Model
final class ContactEntity {
    @Attribute(.unique) var localId: UUID
    /// Server-assigned UID from sync; nil until reconciliation assigns one.
    /// Uniqueness of non-nil uids is enforced by upsert logic, not the schema
    /// (SwiftData unique attributes don't allow multiple nils).
    var uid: String?
    /// Server revision for sync conflict detection; 0 until first sync.
    var rev: Int = 0
    var name: String
    var email: String
    var phone: String
    var avatarUrl: String?
    var createdAt: Date
    var updatedAt: Date
    /// Local create/edit not yet pushed to the server.
    var needsSync: Bool

    init(
        localId: UUID,
        uid: String?,
        rev: Int = 0,
        name: String,
        email: String,
        phone: String,
        avatarUrl: String?,
        createdAt: Date,
        updatedAt: Date,
        needsSync: Bool = false
    ) {
        self.localId = localId
        self.uid = uid
        self.rev = rev
        self.name = name
        self.email = email
        self.phone = phone
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.needsSync = needsSync
    }
}

// MARK: - Mapping (ContactMapper equivalent)

extension ContactEntity {
    convenience init(from contact: Contact) {
        self.init(
            localId: contact.localId,
            uid: contact.uid,
            rev: contact.rev,
            name: contact.name,
            email: contact.email,
            phone: contact.phone,
            avatarUrl: contact.avatarUrl,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt,
            needsSync: contact.needsSync
        )
    }

    var toDomain: Contact {
        Contact(
            localId: localId,
            uid: uid,
            rev: rev,
            name: name,
            email: email,
            phone: phone,
            avatarUrl: avatarUrl,
            createdAt: createdAt,
            updatedAt: updatedAt,
            needsSync: needsSync
        )
    }
}
