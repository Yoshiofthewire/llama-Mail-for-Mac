//
//  ContactSyncRepository.swift
//  llama Mail
//
//  Contact CRUD + sync against the backend, mirroring the Android reference
//  ContactSyncRepository.kt: pull when no local changes are queued, push
//  otherwise; reconcile server-assigned uids for local creates; handle
//  tooOld by discarding the cursor + cache for a full re-pull.
//

import Foundation

enum ContactSyncError: Error, Equatable {
    /// Contact sync uses relay auth; requires a stored pairing.
    case notPaired
}

struct ContactSyncSummary: Equatable, Sendable {
    var pushed: Int
    var applied: Int
    var newCursor: Int
}

final class ContactSyncRepository {
    private let client: ContactSyncClient
    private let contactDAO: ContactDAO
    private let cursorStore: ContactCursorStore
    private let pendingDeletesStore: ContactPendingDeletesStore
    private let securePairingStore: SecurePairingStore

    init(
        client: ContactSyncClient,
        contactDAO: ContactDAO,
        cursorStore: ContactCursorStore,
        pendingDeletesStore: ContactPendingDeletesStore,
        securePairingStore: SecurePairingStore
    ) {
        self.client = client
        self.contactDAO = contactDAO
        self.cursorStore = cursorStore
        self.pendingDeletesStore = pendingDeletesStore
        self.securePairingStore = securePairingStore
    }

    // MARK: - Local CRUD

    func contacts() async throws -> [Contact] {
        try await contactDAO.listAll()
    }

    /// Saves a local create/edit and marks it for the next sync.
    func saveContact(_ contact: Contact) async throws {
        var dirty = contact
        dirty.needsSync = true
        dirty.updatedAt = Date()
        try await contactDAO.upsert(contacts: [dirty])
    }

    /// Deletes locally now; synced contacts get a tombstone so the delete
    /// reaches the server with the next sync request.
    func deleteContact(_ contact: Contact) async throws {
        if let uid = contact.uid {
            try await contactDAO.delete(uid: uid)
            pendingDeletesStore.add(uid)
        } else {
            // Never reached the server; deleting locally is enough.
            try await contactDAO.deleteLocal(localId: contact.localId)
        }
    }

    // MARK: - Sync

    @discardableResult
    func sync() async throws -> ContactSyncSummary {
        guard let pairing = try securePairingStore.loadPairing() else {
            throw ContactSyncError.notPaired
        }
        let auth = RelayAuth(pairing: pairing)
        let cursor = cursorStore.lastCursor

        let pending = try await contactDAO.listPendingSync()
        let tombstones = pendingDeletesStore.all()
        let changes = pending.map(Self.toWireDTO)
            + tombstones.map { ContactDTO(uid: $0, rev: 0, deleted: true) }

        // Pull when nothing is queued, push otherwise (Android sync()).
        let response: ContactSyncPullResponse
        if changes.isEmpty {
            response = try await client.pull(serverUrl: pairing.srv, auth: auth, since: cursor)
        } else {
            response = try await client.push(
                serverUrl: pairing.srv,
                auth: auth,
                baseCursor: cursor,
                changes: changes
            )
        }

        if response.tooOld == true {
            // Cursor predates the server's history window: full re-pull next
            // sync. ponytail: unsynced local edits are wiped here — Android
            // keeps them in a separate change queue that survives the wipe.
            cursorStore.reset()
            pendingDeletesStore.clear()
            try await contactDAO.clearAll()
            return ContactSyncSummary(pushed: changes.count, applied: 0, newCursor: 0)
        }

        let changed = response.changed ?? []
        let deleted = response.deleted ?? []

        // Reconcile before applying so the server's copy of a local create
        // updates the existing row (matched by its new uid) instead of
        // inserting a duplicate.
        let creates = pending.filter { $0.uid == nil }
        for assignment in ContactSyncReconciliation.reconcile(
            localPending: creates,
            responseChanged: changed
        ) {
            try await contactDAO.assignUid(localId: assignment.localId, uid: assignment.uid)
        }

        var applied = 0
        for dto in changed {
            guard let uid = dto.uid, !uid.isEmpty else { continue }
            try await applyServerContact(uid: uid, dto: dto)
            applied += 1
        }
        for dto in deleted {
            guard let uid = dto.uid, !uid.isEmpty else { continue }
            try await contactDAO.delete(uid: uid)
            applied += 1
        }

        try await contactDAO.clearNeedsSync(localIds: pending.map(\.localId))
        pendingDeletesStore.clear()
        cursorStore.advance(to: response.cursor)

        return ContactSyncSummary(
            pushed: changes.count,
            applied: applied,
            newCursor: cursorStore.lastCursor
        )
    }

    // MARK: - Private

    /// Creates push with uid "" (Android contract); edits carry uid + rev.
    private static func toWireDTO(_ contact: Contact) -> ContactDTO {
        ContactDTO(
            uid: contact.uid ?? "",
            rev: contact.uid == nil ? 0 : contact.rev,
            deleted: nil,
            fn: contact.name,
            emails: contact.email.isEmpty
                ? [] : [ContactFieldDTO(label: nil, value: contact.email)],
            phones: contact.phone.isEmpty
                ? [] : [ContactFieldDTO(label: nil, value: contact.phone)]
        )
    }

    private func applyServerContact(uid: String, dto: ContactDTO) async throws {
        let now = Date()
        let existing = try await contactDAO.getContact(uid: uid)
        let contact = Contact(
            localId: existing?.localId ?? UUID(),
            uid: uid,
            rev: dto.rev ?? existing?.rev ?? 0,
            name: dto.fn ?? existing?.name ?? "",
            email: dto.emails?.first?.value ?? existing?.email ?? "",
            phone: dto.phones?.first?.value ?? existing?.phone ?? "",
            avatarUrl: existing?.avatarUrl,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            needsSync: false
        )
        try await contactDAO.upsert(contacts: [contact])
    }
}
