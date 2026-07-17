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
    func fetch(identifier: String) async throws -> CNContact?
    /// Every card visible to the app, fetched with `SystemContactMapper.keysToFetch`.
    func listAll() async throws -> [CNContact]
    /// Caller reads `contact.identifier` afterwards to record the link.
    func add(_ contact: CNMutableContact) async throws
    func update(_ contact: CNMutableContact) async throws
    /// No-op when the card is already gone.
    func delete(identifier: String) async throws
}

final class LiveSystemContactStore: SystemContactStoring {
    private let store = CNContactStore()
    /// All store traffic runs here, off the caller's thread. CNContactStore's
    /// synchronous calls block on XPC replies serviced by background-QoS
    /// threads, so calling them from a higher-QoS thread trips the
    /// priority-inversion runtime issue; the queue matches that QoS and the
    /// async callers suspend instead of blocking. Serial so save requests
    /// never interleave.
    private let queue = DispatchQueue(
        label: "LiveSystemContactStore",
        qos: .background
    )

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    /// CNContactStore and CNContact are documented thread-safe but carry no
    /// Sendable annotation, hence the unsafe markers to cross the hop.
    private func onQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        nonisolated(unsafe) let work = work
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func fetch(identifier: String) async throws -> CNContact? {
        nonisolated(unsafe) let store = self.store
        return try await onQueue {
            do {
                return try store.unifiedContact(
                    withIdentifier: identifier,
                    keysToFetch: SystemContactMapper.keysToFetch
                )
            } catch let error as CNError where error.code == .recordDoesNotExist {
                return nil
            }
        }
    }

    func listAll() async throws -> [CNContact] {
        nonisolated(unsafe) let store = self.store
        return try await onQueue {
            let request = CNContactFetchRequest(keysToFetch: SystemContactMapper.keysToFetch)
            var cards: [CNContact] = []
            try store.enumerateContacts(with: request) { contact, _ in
                cards.append(contact)
            }
            return cards
        }
    }

    func add(_ contact: CNMutableContact) async throws {
        nonisolated(unsafe) let store = self.store
        nonisolated(unsafe) let contact = contact
        try await onQueue {
            let request = CNSaveRequest()
            request.add(contact, toContainerWithIdentifier: nil)
            try store.execute(request)
        }
    }

    func update(_ contact: CNMutableContact) async throws {
        nonisolated(unsafe) let store = self.store
        nonisolated(unsafe) let contact = contact
        try await onQueue {
            let request = CNSaveRequest()
            request.update(contact)
            try store.execute(request)
        }
    }

    func delete(identifier: String) async throws {
        guard let existing = try await fetch(identifier: identifier),
              let copy = existing.mutableCopy() as? CNMutableContact else { return }
        nonisolated(unsafe) let store = self.store
        nonisolated(unsafe) let mutable = copy
        try await onQueue {
            let request = CNSaveRequest()
            request.delete(mutable)
            try store.execute(request)
        }
    }
}
