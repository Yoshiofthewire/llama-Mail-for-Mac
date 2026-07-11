//
//  ContactsViewModel.swift
//  llama Mail
//
//  Contact list + editing + sync trigger (spec §4).
//

import Foundation
import Observation

@Observable
@MainActor
final class ContactsViewModel {
    private let repository: ContactSyncRepository

    private(set) var contacts: [Contact] = []
    private(set) var isSyncing = false
    private(set) var statusMessage: String?

    init(repository: ContactSyncRepository) {
        self.repository = repository
    }

    func load() async {
        contacts = (try? await repository.contacts()) ?? []
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let summary = try await repository.sync()
            statusMessage = "Synced — pushed \(summary.pushed), received \(summary.applied)"
            await load()
        } catch ContactSyncError.notPaired {
            statusMessage = "Pair this device to sync contacts."
        } catch {
            statusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    func save(_ contact: Contact) async {
        try? await repository.saveContact(contact)
        await load()
    }

    func delete(_ contact: Contact) async {
        try? await repository.deleteContact(contact)
        await load()
    }
}
