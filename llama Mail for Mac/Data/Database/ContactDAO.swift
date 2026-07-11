//
//  ContactDAO.swift
//  llama Mail
//
//  Data access for synced contacts (spec §8 ContactDAO).
//

import Foundation
import SwiftData

@ModelActor
actor ContactDAO {
    /// Inserts new contacts or updates existing ones, matched by localId first,
    /// then by server uid (sync deltas reference contacts by uid).
    func upsert(contacts: [Contact]) throws {
        for contact in contacts {
            if let existing = try fetchEntity(localId: contact.localId)
                ?? fetchEntity(uid: contact.uid) {
                existing.uid = contact.uid ?? existing.uid
                existing.rev = contact.rev
                existing.name = contact.name
                existing.email = contact.email
                existing.phone = contact.phone
                existing.avatarUrl = contact.avatarUrl
                existing.updatedAt = contact.updatedAt
                existing.needsSync = contact.needsSync
            } else {
                modelContext.insert(ContactEntity(from: contact))
            }
        }
        try modelContext.save()
    }

    // MARK: - Sync support (spec §4)

    /// Local creates/edits waiting to be pushed.
    func listPendingSync() throws -> [Contact] {
        let descriptor = FetchDescriptor<ContactEntity>(
            predicate: #Predicate { $0.needsSync },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).map(\.toDomain)
    }

    /// Reconciliation result: attach the server-assigned uid to a local contact.
    func assignUid(localId: UUID, uid: String) throws {
        guard let entity = try fetchEntity(localId: localId) else { return }
        entity.uid = uid
        entity.needsSync = false
        try modelContext.save()
    }

    func clearNeedsSync(localIds: [UUID]) throws {
        for localId in localIds {
            try fetchEntity(localId: localId)?.needsSync = false
        }
        try modelContext.save()
    }

    func delete(uid: String) throws {
        try modelContext.delete(
            model: ContactEntity.self,
            where: #Predicate { $0.uid == uid }
        )
        try modelContext.save()
    }

    /// Removes a contact that never reached the server (no uid yet).
    func deleteLocal(localId: UUID) throws {
        try modelContext.delete(
            model: ContactEntity.self,
            where: #Predicate { $0.localId == localId }
        )
        try modelContext.save()
    }

    /// Full wipe for a tooOld re-pull (Mobile_Contact_Sync.md).
    func clearAll() throws {
        try modelContext.delete(model: ContactEntity.self)
        try modelContext.save()
    }

    func listAll() throws -> [Contact] {
        let descriptor = FetchDescriptor<ContactEntity>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor).map(\.toDomain)
    }

    func getContact(uid: String) throws -> Contact? {
        try fetchEntity(uid: uid)?.toDomain
    }

    // MARK: - Private

    private func fetchEntity(localId: UUID) throws -> ContactEntity? {
        var descriptor = FetchDescriptor<ContactEntity>(
            predicate: #Predicate { $0.localId == localId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchEntity(uid: String?) throws -> ContactEntity? {
        guard let uid else { return nil }
        var descriptor = FetchDescriptor<ContactEntity>(
            predicate: #Predicate { $0.uid == uid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
