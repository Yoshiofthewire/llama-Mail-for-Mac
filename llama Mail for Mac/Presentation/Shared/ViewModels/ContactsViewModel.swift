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
        await performSync()
    }

    /// Asks the server to merge duplicates, then syncs to pull the merges in.
    func dedupe() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let report = try await repository.dedupe()
            let message = Self.dedupeMessage(for: report)
            // The follow-up sync is what actually removes the absorbed
            // contacts locally; it overwrites statusMessage, so the report
            // is re-asserted afterwards as the outcome worth reading.
            await performSync()
            statusMessage = message
        } catch ContactSyncError.notPaired {
            statusMessage = "Pair this device to sync contacts."
        } catch NetworkError.unauthorized {
            // The endpoint takes pairing auth (backend withMailAuth), so a 401
            // is a credentials problem rather than a missing feature.
            statusMessage = "Couldn't merge duplicates — try pairing this device again."
        } catch {
            statusMessage = "Find Duplicates failed: \(error.localizedDescription)"
        }
    }

    private static func dedupeMessage(for report: ContactDedupeReport) -> String {
        let groups = report.groups ?? []
        guard report.mergedCount > 0 else { return "No duplicates found" }
        return "Merged \(report.mergedCount) duplicate contacts into \(groups.count) groups"
    }

    /// Shared by `sync()` and `dedupe()`'s follow-up pass — calling `sync()`
    /// from `dedupe()` would hit the `isSyncing` guard and silently no-op.
    private func performSync() async {
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
