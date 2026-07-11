//
//  ContactSyncReconciliation.swift
//  llama Mail
//
//  Reconciles locally-created contacts with server-assigned uids after a sync
//  (spec §4, Android ContactSyncReconciliation.kt). There is no correlation ID
//  in v1: matching is by content first, then by order among the leftovers.
//

import Foundation

enum ContactSyncReconciliation {
    struct Assignment: Equatable, Sendable {
        var localId: UUID
        var uid: String
    }

    /// Matches locally-created contacts (`uid == nil`) against response delta
    /// entries that carry a server uid.
    ///
    /// Pass 1 pairs entries whose name and email both match; pass 2 pairs the
    /// remaining contacts and entries in order. Each response entry is used at
    /// most once; unmatched local contacts stay pending for the next sync.
    static func reconcile(
        localPending: [Contact],
        responseDelta: [ContactDeltaDTO]
    ) -> [Assignment] {
        var candidates = responseDelta.filter { $0.uid != nil && $0.deleted != true }
        var unmatchedLocal: [Contact] = []
        var assignments: [Assignment] = []

        for contact in localPending where contact.uid == nil {
            if let index = candidates.firstIndex(where: {
                $0.name == contact.name && $0.email == contact.email
            }) {
                assignments.append(Assignment(localId: contact.localId, uid: candidates[index].uid!))
                candidates.remove(at: index)
            } else {
                unmatchedLocal.append(contact)
            }
        }

        for (contact, candidate) in zip(unmatchedLocal, candidates) {
            assignments.append(Assignment(localId: contact.localId, uid: candidate.uid!))
        }

        return assignments
    }
}
