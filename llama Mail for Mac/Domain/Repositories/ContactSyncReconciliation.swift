//
//  ContactSyncReconciliation.swift
//  llama Mail
//
//  Reconciles locally-created contacts with server-assigned uids after a sync
//  (spec §4, Android ContactSyncReconciliation.kt). There is no correlation ID
//  in v1: matching is by content only — fn, org, and the full email/phone
//  value lists — claiming the first unclaimed exact match per pending create,
//  like the Android reference. There is deliberately NO positional fallback:
//  a push response carries every change since baseCursor (other devices'
//  edits included), so pairing leftovers by order stamps an unrelated
//  contact's uid onto a local create and duplicates that contact locally.
//

import Foundation

enum ContactSyncReconciliation {
    struct Assignment: Equatable, Sendable {
        var localId: UUID
        var uid: String
    }

    /// Matches locally-created contacts (`uid == nil`) against `changed`
    /// entries that carry a server uid. Each response entry is claimed at
    /// most once; unmatched local contacts stay pending for the next sync.
    static func reconcile(
        localPending: [Contact],
        responseChanged: [ContactDTO]
    ) -> [Assignment] {
        var assignments: [Assignment] = []
        var claimed = Set<Int>()

        for contact in localPending where contact.uid == nil {
            let match = responseChanged.indices.first { index in
                guard !claimed.contains(index) else { return false }
                let candidate = responseChanged[index]
                return candidate.uid?.isEmpty == false
                    && candidate.deleted != true
                    && contentMatches(contact, candidate)
            }
            guard let match else { continue }
            claimed.insert(match)
            assignments.append(
                Assignment(localId: contact.localId, uid: responseChanged[match].uid!)
            )
        }
        return assignments
    }

    /// Exact equality on the fields a create round-trips verbatim (Android
    /// contentMatches): fn, org, and the ordered email/phone values.
    private static func contentMatches(_ contact: Contact, _ candidate: ContactDTO) -> Bool {
        (candidate.fn ?? "") == contact.name
            && (candidate.org ?? "") == contact.org
            && (candidate.emails ?? []).map(\.value) == contact.emails.map(\.value)
            && (candidate.phones ?? []).map(\.value) == contact.phones.map(\.value)
    }
}
