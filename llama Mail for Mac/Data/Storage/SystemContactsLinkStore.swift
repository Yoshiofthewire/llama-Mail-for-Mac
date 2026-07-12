//
//  SystemContactsLinkStore.swift
//  llama Mail
//
//  Mapping between app contacts and the CNContact cards the app created in
//  the system Contacts database. UserDefaults-backed (not a ContactEntity
//  field) so the mapping survives the SwiftData wipe on a tooOld re-pull;
//  `uid` lets contacts re-link after the re-pull assigns new localIds.
//

import Foundation

struct SystemContactLink: Codable, Equatable, Sendable {
    var localId: UUID
    /// Server uid at export time; used to re-link after a tooOld wipe.
    var uid: String?
    /// Identifier of the CNContact this app created.
    var cnIdentifier: String
    /// `updatedAt` of the contact when last exported; unchanged contacts skip.
    var exportedUpdatedAt: Date
}

final class SystemContactsLinkStore {
    private static let key = "contacts.systemLinks"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func all() -> [SystemContactLink] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([SystemContactLink].self, from: data)) ?? []
    }

    func link(localId: UUID) -> SystemContactLink? {
        all().first { $0.localId == localId }
    }

    func upsert(_ link: SystemContactLink) {
        var links = all()
        if let index = links.firstIndex(where: { $0.localId == link.localId }) {
            links[index] = link
        } else {
            links.append(link)
        }
        save(links)
    }

    func remove(localId: UUID) {
        save(all().filter { $0.localId != localId })
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ links: [SystemContactLink]) {
        guard let data = try? JSONEncoder().encode(links) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
