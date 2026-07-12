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

private func makeDTO(
    uid: String? = nil,
    fn: String,
    email: String,
    deleted: Bool? = nil
) -> ContactDTO {
    ContactDTO(
        uid: uid,
        rev: 1,
        deleted: deleted,
        fn: fn,
        emails: [ContactFieldDTO(label: nil, value: email)],
        phones: []
    )
}

@Suite struct ContactSyncReconciliationTests {
    @Test func matchesByContentRegardlessOfOrder() {
        let local = [
            makeContact(name: "Ada", email: "ada@example.com"),
            makeContact(name: "Grace", email: "grace@example.com"),
        ]
        let response = [
            makeDTO(uid: "srv-g", fn: "Grace", email: "grace@example.com"),
            makeDTO(uid: "srv-a", fn: "Ada", email: "ada@example.com"),
        ]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseChanged: response
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
            makeDTO(uid: "srv-1", fn: "Ada Lovelace", email: "ada@example.com"),
            makeDTO(uid: "srv-2", fn: "Grace Hopper", email: "grace@example.com"),
        ]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseChanged: response
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
            makeDTO(uid: "srv-x", fn: "Someone", email: "x@example.com", deleted: true),
            makeDTO(fn: "No uid", email: "nouid@example.com"),
            makeDTO(uid: "srv-a", fn: "Ada", email: "ada@example.com"),
        ]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseChanged: response
        )
        // Only Ada matches; Grace stays pending for the next sync.
        #expect(assignments == [
            ContactSyncReconciliation.Assignment(localId: local[0].localId, uid: "srv-a")
        ])
    }

    @Test func alreadySyncedContactsAreNotReassigned() {
        let local = [makeContact(uid: "srv-existing", name: "Ada", email: "ada@example.com")]
        let response = [makeDTO(uid: "srv-new", fn: "Ada", email: "ada@example.com")]
        let assignments = ContactSyncReconciliation.reconcile(
            localPending: local,
            responseChanged: response
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

    @Test func concurrentSyncsPushPendingContactOnlyOnce() async throws {
        final class MethodLog: @unchecked Sendable {
            private let lock = NSLock()
            private var value: [String] = []
            func append(_ method: String) { lock.lock(); value.append(method); lock.unlock() }
            var methods: [String] { lock.lock(); defer { lock.unlock() }; return value }
        }
        let log = MethodLog()
        let env = try makeEnvironment(client: stubClient(json: #"{"cursor": 1}"#) { request in
            log.append(request.httpMethod ?? "")
        })
        try await env.repository.saveContact(makeContact(name: "Ada", email: "ada@example.com"))

        async let first = env.repository.sync()
        async let second = env.repository.sync()
        _ = try await [first, second]

        // Serialized: the first sync pushes the pending create; the second
        // runs after it and has nothing queued, so it pulls. Overlapping
        // syncs would push the same contact twice (server-side duplicate).
        #expect(log.methods == ["POST", "GET"])
    }

    @Test func fullSyncAssignsUidWithoutDuplicating() async throws {
        let json = """
        {
          "cursor": 456,
          "changed": [
            {
              "uid": "srv-ada",
              "rev": 1,
              "fn": "Ada",
              "emails": [{ "value": "ada@example.com" }]
            }
          ],
          "deleted": []
        }
        """
        let client = stubClient(json: json) { request in
            #expect(
                request.url!.absoluteString
                    .hasPrefix("https://relay.example.com/api/contacts/sync?")
            )
            // Queued local changes go out as a push (POST {baseCursor, changes});
            // creates carry an empty uid (Android contract).
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""baseCursor":0"#))
            #expect(body.contains(#""fn":"Ada""#))
            #expect(body.contains(#""uid":"""#))
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

    @Test func serverDeleteRemovesLocalContactViaPull() async throws {
        let json = #"{"cursor": 2, "changed": [], "deleted": [{"uid": "srv-1", "deleted": true}]}"#
        let env = try makeEnvironment(client: stubClient(json: json) { request in
            // Nothing queued locally, so the sync is a pull (GET ...&since=).
            #expect(request.httpMethod == "GET")
            #expect(request.url!.absoluteString.contains("since=0"))
        })
        try await env.dao.upsert(contacts: [makeContact(uid: "srv-1", name: "Old")])

        try await env.repository.sync()
        #expect(try await env.dao.listAll().isEmpty)
    }

    @Test func localDeleteOfSyncedContactSendsTombstone() async throws {
        let client = stubClient(json: #"{"cursor": 3, "changed": [], "deleted": []}"#) { request in
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
        let env = try makeEnvironment(client: stubClient(json: #"{"cursor": 1}"#))
        let contact = makeContact(name: "Draft Person", needsSync: true)
        try await env.dao.upsert(contacts: [contact])

        try await env.repository.deleteContact(contact)
        #expect(try await env.dao.listAll().isEmpty)
        #expect(env.pendingDeletes.all().isEmpty)
    }

    @Test func serverEditUpdatesExistingContact() async throws {
        let json = """
        {
          "cursor": 9,
          "changed": [
            { "uid": "srv-1", "rev": 4, "fn": "Ada L.", "phones": [{ "value": "555" }] }
          ]
        }
        """
        let env = try makeEnvironment(client: stubClient(json: json))
        try await env.dao.upsert(contacts: [
            makeContact(uid: "srv-1", name: "Ada", email: "ada@example.com"),
        ])

        try await env.repository.sync()
        let all = try await env.dao.listAll()
        #expect(all.count == 1)
        #expect(all.first?.name == "Ada L.")
        #expect(all.first?.phone == "555")
        #expect(all.first?.rev == 4)
        // Fields absent from the delta keep their local values.
        #expect(all.first?.email == "ada@example.com")
    }

    @Test func tooOldResetsCursorAndCache() async throws {
        let env = try makeEnvironment(client: stubClient(json: #"{"cursor": 0, "tooOld": true}"#))
        env.cursorStore.advance(to: 99)
        try await env.dao.upsert(contacts: [makeContact(uid: "srv-1", name: "Stale")])

        let summary = try await env.repository.sync()
        #expect(summary.newCursor == 0)
        #expect(env.cursorStore.lastCursor == 0)
        #expect(try await env.dao.listAll().isEmpty)
    }
}
