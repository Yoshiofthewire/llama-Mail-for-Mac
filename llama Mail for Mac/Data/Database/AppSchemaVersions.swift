//
//  AppSchemaVersions.swift
//  llama Mail
//
//  Versioned SwiftData schemas + migration plan. V1 is the shipped shape
//  (single email/phone strings on ContactEntity); V2 adds full contactPayload
//  parity (Client_Contact_Update.md). The stage is lightweight: V2 renames
//  email/phone to legacyEmail/legacyPhone via originalName and adds every new
//  field with a default. The legacy→array data copy happens in app code
//  (ContactDAO.migrateLegacyFields), not in the migration machinery.
//

import Foundation
import SwiftData

enum AppSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [EmailEntity.self, ContactEntity.self, PushNotificationEntity.self, KeywordEntity.self]
    }

    /// Snapshot of ContactEntity as shipped before field parity. The nested
    /// class keeps the entity name "ContactEntity" so migration identity
    /// matches the live model.
    @Model
    final class ContactEntity {
        @Attribute(.unique) var localId: UUID
        var uid: String?
        var rev: Int = 0
        var name: String
        var email: String
        var phone: String
        var avatarUrl: String?
        var createdAt: Date
        var updatedAt: Date
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
}

enum AppSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        // ContactEntity here is the live top-level model (ContactEntity.swift).
        [EmailEntity.self, ContactEntity.self, PushNotificationEntity.self, KeywordEntity.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self)]
    }
}
