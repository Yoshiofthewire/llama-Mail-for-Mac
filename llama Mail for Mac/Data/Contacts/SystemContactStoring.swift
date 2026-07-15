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
    /// Async so the live store can enumerate off the main thread (the Contacts
    /// framework raises a runtime issue for main-thread enumeration).
    func listAll() async throws -> [CNContact]
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

    func listAll() async throws -> [CNContact] {
        // CNContactStore and CNContact are documented thread-safe but carry no
        // Sendable annotation, hence the unsafe markers to cross the hop.
        nonisolated(unsafe) let store = self.store
        nonisolated(unsafe) let keysToFetch = SystemContactMapper.keysToFetch
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                    var cards: [CNContact] = []
                    try store.enumerateContacts(with: request) { contact, _ in
                        cards.append(contact)
                    }
                    continuation.resume(returning: cards)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
