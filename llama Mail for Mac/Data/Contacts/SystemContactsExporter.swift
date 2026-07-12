//
//  SystemContactsExporter.swift
//  llama Mail
//
//  One-way export of app contacts into the system Contacts database, gated by
//  the ContactsSettingsStore toggle. Identity is link-based (localId ->
//  CNContact identifier via SystemContactsLinkStore): the exporter only ever
//  updates or deletes cards it created itself. Best-effort: each card gets
//  its own CNSaveRequest so one failure never aborts the batch, and failed
//  items stay retriable on the next reconcile.
//

import Contacts
import Foundation

struct SystemContactsExportPlan: Equatable, Sendable {
    struct Update: Equatable, Sendable {
        var contact: Contact
        var cnIdentifier: String
    }

    struct Relink: Equatable, Sendable {
        var contact: Contact
        var link: SystemContactLink
    }

    /// Contacts with no link yet.
    var creates: [Contact] = []
    /// Linked contacts edited since their last export.
    var updates: [Update] = []
    /// Links whose contact is gone from the app; the only cards ever deleted.
    var deletes: [SystemContactLink] = []
    /// Links matched by server uid after a tooOld wipe replaced the localIds.
    var relinks: [Relink] = []
}

enum SystemContactsDiff {
    static func plan(
        contacts: [Contact],
        links: [SystemContactLink]
    ) -> SystemContactsExportPlan {
        var plan = SystemContactsExportPlan()
        let contactsByLocalId = Dictionary(
            contacts.map { ($0.localId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var matchedLocalIds = Set<UUID>()
        var orphanedLinks: [SystemContactLink] = []

        for link in links {
            guard let contact = contactsByLocalId[link.localId] else {
                orphanedLinks.append(link)
                continue
            }
            matchedLocalIds.insert(contact.localId)
            if contact.updatedAt > link.exportedUpdatedAt {
                plan.updates.append(.init(contact: contact, cnIdentifier: link.cnIdentifier))
            }
        }

        // Orphaned links first try their uid (post-tooOld re-pull kept the
        // server contact but gave it a fresh localId); only true orphans —
        // contacts really gone from the app — become deletes.
        for link in orphanedLinks {
            if let uid = link.uid,
               let contact = contacts.first(where: {
                   $0.uid == uid && !matchedLocalIds.contains($0.localId)
               }) {
                matchedLocalIds.insert(contact.localId)
                plan.relinks.append(.init(contact: contact, link: link))
            } else {
                plan.deletes.append(link)
            }
        }

        plan.creates = contacts.filter { !matchedLocalIds.contains($0.localId) }
        return plan
    }
}

actor SystemContactsExporter {
    struct Summary: Equatable, Sendable {
        var created = 0
        var updated = 0
        var deleted = 0
        var failed = 0
    }

    private let store: SystemContactStoring
    private let linkStore: SystemContactsLinkStore
    private let settings: ContactsSettingsStore
    private let contactDAO: ContactDAO

    init(
        store: SystemContactStoring,
        linkStore: SystemContactsLinkStore,
        settings: ContactsSettingsStore,
        contactDAO: ContactDAO
    ) {
        self.store = store
        self.linkStore = linkStore
        self.settings = settings
        self.contactDAO = contactDAO
    }

    // MARK: - Authorization

    var isAuthorized: Bool {
        store.authorizationStatus == .authorized
    }

    var isDenied: Bool {
        switch store.authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Prompts on first use; returns whether export may proceed.
    func requestAccessIfNeeded() async -> Bool {
        switch store.authorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            return (try? await store.requestAccess()) ?? false
        default:
            return false
        }
    }

    func hasExportedContacts() -> Bool {
        !linkStore.all().isEmpty
    }

    // MARK: - Export

    /// Full diff of app contacts against the link store; runs after every
    /// relay sync and on first enable.
    @discardableResult
    func reconcileAll() async -> Summary {
        var summary = Summary()
        guard settings.exportToSystemContactsEnabled, isAuthorized else { return summary }
        let contacts = (try? await contactDAO.listAll()) ?? []
        let plan = SystemContactsDiff.plan(contacts: contacts, links: linkStore.all())

        for link in plan.deletes {
            deleteLinked(link, summary: &summary)
        }
        for relink in plan.relinks {
            linkStore.remove(localId: relink.link.localId)
            upsertLinked(relink.contact, cnIdentifier: relink.link.cnIdentifier, summary: &summary)
        }
        for update in plan.updates {
            upsertLinked(update.contact, cnIdentifier: update.cnIdentifier, summary: &summary)
        }
        for contact in plan.creates {
            create(contact, summary: &summary)
        }

        if summary != Summary() {
            Log.sync.info("""
            System contacts export: \(summary.created) created, \
            \(summary.updated) updated, \(summary.deleted) deleted, \
            \(summary.failed) failed
            """)
        }
        return summary
    }

    /// Incremental hook for a single save from ContactSyncRepository.
    func exportUpsert(_ contact: Contact) async {
        guard settings.exportToSystemContactsEnabled, isAuthorized else { return }
        var summary = Summary()
        if let link = linkStore.link(localId: contact.localId) {
            upsertLinked(contact, cnIdentifier: link.cnIdentifier, summary: &summary)
        } else {
            create(contact, summary: &summary)
        }
    }

    /// Incremental hook for a single delete; only linked (app-created) cards.
    func exportDelete(localId: UUID) async {
        guard settings.exportToSystemContactsEnabled, isAuthorized else { return }
        guard let link = linkStore.link(localId: localId) else { return }
        var summary = Summary()
        deleteLinked(link, summary: &summary)
    }

    /// Destructive cleanup from Preferences: removes every card the app
    /// created and forgets the links. Works with the toggle off.
    @discardableResult
    func removeAllExported() async -> Int {
        guard isAuthorized else { return 0 }
        var summary = Summary()
        for link in linkStore.all() {
            deleteLinked(link, summary: &summary)
        }
        return summary.deleted
    }

    // MARK: - Private

    private func create(_ contact: Contact, summary: inout Summary) {
        let cn = SystemContactMapper.makeContact(from: contact)
        do {
            try store.add(cn)
            linkStore.upsert(SystemContactLink(
                localId: contact.localId,
                uid: contact.uid,
                cnIdentifier: cn.identifier,
                exportedUpdatedAt: contact.updatedAt
            ))
            summary.created += 1
        } catch {
            // No link written; retried as a create on the next reconcile.
            summary.failed += 1
            Log.sync.error("System contacts add failed: \(error.localizedDescription)")
        }
    }

    private func upsertLinked(_ contact: Contact, cnIdentifier: String, summary: inout Summary) {
        do {
            if let existing = try store.fetch(identifier: cnIdentifier),
               let mutable = existing.mutableCopy() as? CNMutableContact {
                SystemContactMapper.apply(contact, to: mutable)
                try store.update(mutable)
                linkStore.upsert(SystemContactLink(
                    localId: contact.localId,
                    uid: contact.uid,
                    cnIdentifier: cnIdentifier,
                    exportedUpdatedAt: contact.updatedAt
                ))
                summary.updated += 1
            } else {
                // Card deleted in Contacts.app: recreate and repair the link.
                linkStore.remove(localId: contact.localId)
                create(contact, summary: &summary)
            }
        } catch {
            summary.failed += 1
            Log.sync.error("System contacts update failed: \(error.localizedDescription)")
        }
    }

    private func deleteLinked(_ link: SystemContactLink, summary: inout Summary) {
        do {
            try store.delete(identifier: link.cnIdentifier)
            summary.deleted += 1
        } catch {
            summary.failed += 1
            Log.sync.error("System contacts delete failed: \(error.localizedDescription)")
        }
        // The app contact is gone either way; a failed delete against this
        // identifier would never succeed later, so drop the link too.
        linkStore.remove(localId: link.localId)
    }
}
