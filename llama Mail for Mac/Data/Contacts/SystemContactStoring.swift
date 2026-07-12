//
//  SystemContactStoring.swift
//  llama Mail
//
//  Thin seam over CNContactStore so SystemContactsExporter is unit-testable:
//  the real store is TCC-gated and can't run in tests.
//

import Contacts
import Foundation

protocol SystemContactStoring {
    var authorizationStatus: CNAuthorizationStatus { get }
    func requestAccess() async throws -> Bool
    /// Returns nil when the card no longer exists (deleted in Contacts.app).
    func fetch(identifier: String) throws -> CNContact?
    /// Every card visible to the app, fetched with `SystemContactMapper.keysToFetch`.
    func listAll() throws -> [CNContact]
    /// Caller reads `contact.identifier` afterwards to record the link.
    func add(_ contact: CNMutableContact) throws
    func update(_ contact: CNMutableContact) throws
    /// No-op when the card is already gone.
    func delete(identifier: String) throws
}

final class LiveSystemContactStore: SystemContactStoring {
    private let store = CNContactStore()

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    func fetch(identifier: String) throws -> CNContact? {
        do {
            return try store.unifiedContact(
                withIdentifier: identifier,
                keysToFetch: SystemContactMapper.keysToFetch
            )
        } catch let error as CNError where error.code == .recordDoesNotExist {
            return nil
        }
    }

    func listAll() throws -> [CNContact] {
        let request = CNContactFetchRequest(keysToFetch: SystemContactMapper.keysToFetch)
        var cards: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            cards.append(contact)
        }
        return cards
    }

    func add(_ contact: CNMutableContact) throws {
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
    }

    func update(_ contact: CNMutableContact) throws {
        let request = CNSaveRequest()
        request.update(contact)
        try store.execute(request)
    }

    func delete(identifier: String) throws {
        guard let existing = try fetch(identifier: identifier),
              let mutable = existing.mutableCopy() as? CNMutableContact else { return }
        let request = CNSaveRequest()
        request.delete(mutable)
        try store.execute(request)
    }
}
