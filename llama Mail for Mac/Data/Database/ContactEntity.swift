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
    var name: String
    var email: String
    var phone: String
    var avatarUrl: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        localId: UUID,
        uid: String?,
        name: String,
        email: String,
        phone: String,
        avatarUrl: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.localId = localId
        self.uid = uid
        self.name = name
        self.email = email
        self.phone = phone
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Mapping (ContactMapper equivalent)

extension ContactEntity {
    convenience init(from contact: Contact) {
        self.init(
            localId: contact.localId,
            uid: contact.uid,
            name: contact.name,
            email: contact.email,
            phone: contact.phone,
            avatarUrl: contact.avatarUrl,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt
        )
    }

    var toDomain: Contact {
        Contact(
            localId: localId,
            uid: uid,
            name: name,
            email: email,
            phone: phone,
            avatarUrl: avatarUrl,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
