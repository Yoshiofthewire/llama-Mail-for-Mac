//
//  PushNotificationDAO.swift
//  KyPost
//
//  Data access for push notification history (spec §8 PushNotificationDAO).
//  De-duplicates by strictly-increasing seq (spec §3 pull mode).
//

import Foundation
import SwiftData

@ModelActor
actor PushNotificationDAO {
    /// Inserts a notification; skips duplicates (same seq).
    /// - Returns: false if an entry with that seq already existed.
    @discardableResult
    func insert(notification: PushNotification) throws -> Bool {
        let seq = notification.seq
        var descriptor = FetchDescriptor<PushNotificationEntity>(
            predicate: #Predicate { $0.seq == seq }
        )
        descriptor.fetchLimit = 1
        guard try modelContext.fetch(descriptor).isEmpty else { return false }
        modelContext.insert(PushNotificationEntity(from: notification))
        try modelContext.save()
        return true
    }

    /// Newest-first notification history. Sorted by receivedAt (seq as
    /// tiebreaker) because push-mode entries use synthesized seqs that don't
    /// share a scale with pull-mode server seqs.
    func listHistory(limit: Int) throws -> [PushNotification] {
        var descriptor = FetchDescriptor<PushNotificationEntity>(
            sortBy: [
                SortDescriptor(\.receivedAt, order: .reverse),
                SortDescriptor(\.seq, order: .reverse),
            ]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.toDomain)
    }

    func markRead(seq: Int) throws {
        var descriptor = FetchDescriptor<PushNotificationEntity>(
            predicate: #Predicate { $0.seq == seq }
        )
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        entity.read = true
        try modelContext.save()
    }
}
