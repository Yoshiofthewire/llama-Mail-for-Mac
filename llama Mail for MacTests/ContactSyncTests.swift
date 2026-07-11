//
//  ContactSyncTests.swift
//  llama Mail for MacTests
//
//  Phase 4 tests: reconciliation matching, cursor/tombstone stores, and the
//  full sync flow through a stub transport.
//

import Foundation
import Testing
@testable import llama_Mail_for_Mac

// MARK: - Helpers

private func stubClient(
    status: Int = 200,
    json: String = "{}",
    onRequest: (@Sendable (URLRequest) -> Void)? = nil
) -> HTTPClient {
    HTTPClient { request in
        onRequest?(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }
}

private func makeContact(
    uid: String? = nil,
    name: String,
    email: String = "",
    needsSync: Bool = false
) -> Contact {
    Contact(
        uid: uid,
        name: name,
        email: email,
        phone: "",
        avatarUrl: nil,
        createdAt: Date(),
        updatedAt: Date(),
        needsSync: needsSync
    )
}

// MARK: - Reconciliation

@Suite struct ContactSyncReconciliationTests {
    @Test func matchesByContentRegardlessOfOrder() {
        let local = [
            makeContact(name: "Ada", email: "ada@example.com"),
            makeContact(name: "Grace", email: "grace@example.com"),
        ]
        let response = [
            ContactDeltaDTO(uid: "srv-g", name: "Grace", email: "grace@example.com"),
            ContactDeltaDTO(uid: "srv-a", name: "Ada", email: "ada@example.com"),
        ]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseDelta: response
        )
        #expect(assignments.count == 2)
        #expect(assignments.first { $0.localId == local[0].localId }?.uid == "srv-a")
        #expect(assignments.first { $0.localId == local[1].localId }?.uid == "srv-g")
    }

    @Test func fallsBackToOrderForUnmatchedContent() {
        // Server normalized the names, so content matching fails.
        let local = [
            makeContact(name: "ada lovelace", email: "ada@example.com"),
            makeContact(name: "grace hopper", email: "grace@example.com"),
        ]
        let response = [
            ContactDeltaDTO(uid: "srv-1", name: "Ada Lovelace", email: "ada@example.com"),
            ContactDeltaDTO(uid: "srv-2", name: "Grace Hopper", email: "grace@example.com"),
        ]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseDelta: response
        )
        #expect(assignments.map(\.uid) == ["srv-1", "srv-2"])
        #expect(assignments.map(\.localId) == local.map(\.localId))
    }

    @Test func ignoresDeletedAndUidlessCandidatesAndLeavesExtrasPending() {
        let local = [
            makeContact(name: "Ada", email: "ada@example.com"),
            makeContact(name: "Grace", email: "grace@example.com"),
        ]
        let response = [
            ContactDeltaDTO(uid: "srv-x", name: "Someone", email: "x@example.com", deleted: true),
            ContactDeltaDTO(name: "No uid", email: "nouid@example.com"),
            ContactDeltaDTO(uid: "srv-a", name: "Ada", email: "ada@example.com"),
        ]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseDelta: response
        )
        // Only Ada matches; Grace stays pending for the next sync.
        #expect(assignments == [
            ContactSyncReconciliation.Assignment(localId: local[0].localId, uid: "srv-a")
        ])
    }

    @Test func alreadySyncedContactsAreNotReassigned() {
        let local = [makeContact(uid: "srv-existing", name: "Ada", email: "ada@example.com")]
        let response = [ContactDeltaDTO(uid: "srv-new", name: "Ada", email: "ada@example.com")]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseDelta: response
        )
        #expect(assignments.isEmpty)
    }
}

// MARK: - Stores

@Suite struct ContactStoresTests {
    @Test func cursorOnlyAdvancesForward() {
        let store = ContactCursorStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        #expect(store.lastCursor == 0)
        store.advance(to: 7)
        store.advance(to: 4)
        #expect(store.lastCursor == 7)
    }

    @Test func pendingDeletesDeduplicateAndClear() {
        let store = ContactPendingDeletesStore(
            defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        )
        store.add("srv-1")
        store.add("srv-1")
        store.add("srv-2")
        #expect(store.all() == ["srv-1", "srv-2"])
        store.clear()
        #expect(store.all().isEmpty)
    }
}

// MARK: - Repository

@Suite struct ContactSyncRepositoryTests {
    private struct Environment {
        var repository: ContactSyncRepository
        var dao: ContactDAO
        var cursorStore: ContactCursorStore
        var pendingDeletes: ContactPendingDeletesStore
    }

    private func makeEnvironment(client: HTTPClient, paired: Bool = true) throws -> Environment {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let keychain = KeychainStorage(service: "com.urlxl.mail.tests.\(UUID().uuidString)")
        let pairingStore = SecurePairingStore(keychain: keychain)
        if paired {
            try pairingStore.savePairing(Pairing(
                sub: "u1", hash: "h1", srv: "https://relay.example.com",
                registrationUrl: nil, pairingToken: "pt", lastDeviceId: nil, pairedAt: Date()
            ))
        }
        let db = try AppDatabase(inMemory: true)
        let dao = ContactDAO(modelContainer: db.container)
        let cursorStore = ContactCursorStore(defaults: defaults)
        let pendingDeletes = ContactPendingDeletesStore(defaults: defaults)
        let repository = ContactSyncRepository(
            client: ContactSyncClient(httpClient: client),
            contactDAO: dao,
            cursorStore: cursorStore,
            pendingDeletesStore: pendingDeletes,
            securePairingStore: pairingStore
        )
        return Environment(
            repository: repository,
            dao: dao,
            cursorStore: cursorStore,
            pendingDeletes: pendingDeletes
        )
    }

    @Test func syncWithoutPairingThrows() async throws {
        let env = try makeEnvironment(client: stubClient(), paired: false)
        await #expect(throws: ContactSyncError.notPaired) {
            try await env.repository.sync()
        }
    }

    @Test func saveContactMarksPending() async throws {
        let env = try makeEnvironment(client: stubClient())
        try await env.repository.saveContact(makeContact(name: "Ada", email: "ada@example.com"))
        let pending = try await env.dao.listPendingSync()
        #expect(pending.count == 1)
        #expect(pending.first?.needsSync == true)
    }

    @Test func fullSyncAssignsUidWithoutDuplicating() async throws {
        let json = """
        {
          "delta": [
            { "uid": "srv-ada", "name": "Ada", "email": "ada@example.com" }
          ],
          "cursor": 456
        }
        """
        let client = stubClient(json: json) { request in
            #expect(
                request.url!.absoluteString
                    .hasPrefix("https://relay.example.com/api/contacts/sync?")
            )
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""name":"Ada""#))
            #expect(body.contains(#""cursor":0"#))
        }
        let env = try makeEnvironment(client: client)
        try await env.repository.saveContact(makeContact(name: "Ada", email: "ada@example.com"))

        let summary = try await env.repository.sync()
        #expect(summary.pushed == 1)
        #expect(summary.applied == 1)
        #expect(summary.newCursor == 456)

        let all = try await env.dao.listAll()
        #expect(all.count == 1) // reconciled in place, not duplicated
        #expect(all.first?.uid == "srv-ada")
        #expect(all.first?.needsSync == false)
        #expect(try await env.dao.listPendingSync().isEmpty)
        #expect(env.cursorStore.lastCursor == 456)
    }

    @Test func serverDeleteRemovesLocalContact() async throws {
        let json = #"{"delta": [{"uid": "srv-1", "deleted": true}], "cursor": 2}"#
        let env = try makeEnvironment(client: stubClient(json: json))
        try await env.dao.upsert(contacts: [makeContact(uid: "srv-1", name: "Old")])

        try await env.repository.sync()
        #expect(try await env.dao.listAll().isEmpty)
    }

    @Test func localDeleteOfSyncedContactSendsTombstone() async throws {
        let client = stubClient(json: #"{"delta": [], "cursor": 3}"#) { request in
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""uid":"srv-9""#))
            #expect(body.contains(#""deleted":true"#))
        }
        let env = try makeEnvironment(client: client)
        let contact = makeContact(uid: "srv-9", name: "Grace")
        try await env.dao.upsert(contacts: [contact])

        try await env.repository.deleteContact(contact)
        #expect(try await env.dao.listAll().isEmpty)
        #expect(env.pendingDeletes.all() == ["srv-9"])

        try await env.repository.sync()
        #expect(env.pendingDeletes.all().isEmpty) // tombstone cleared after push
    }

    @Test func unsyncedLocalDeleteLeavesNoTombstone() async throws {
        let env = try makeEnvironment(client: stubClient(json: #"{"delta": [], "cursor": 1}"#))
        let contact = makeContact(name: "Draft Person", needsSync: true)
        try await env.dao.upsert(contacts: [contact])

        try await env.repository.deleteContact(contact)
        #expect(try await env.dao.listAll().isEmpty)
        #expect(env.pendingDeletes.all().isEmpty)
    }

    @Test func serverEditUpdatesExistingContact() async throws {
        let json = #"{"delta": [{"uid": "srv-1", "name": "Ada L.", "phone": "555"}], "cursor": 9}"#
        let env = try makeEnvironment(client: stubClient(json: json))
        try await env.dao.upsert(contacts: [
            makeContact(uid: "srv-1", name: "Ada", email: "ada@example.com"),
        ])

        try await env.repository.sync()
        let all = try await env.dao.listAll()
        #expect(all.count == 1)
        #expect(all.first?.name == "Ada L.")
        #expect(all.first?.phone == "555")
        // Fields absent from the delta keep their local values.
        #expect(all.first?.email == "ada@example.com")
    }
}
