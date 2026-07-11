//
//  PushNotificationDAO.swift
//  llama Mail
//
//  Data access for push notification history (spec §8 PushNotificationDAO).
//  De-duplicates by strictly-increasing seq (spec §3 pull mode).
//

import Foundation
import SwiftData

@ModelActor
actor PushNotificationDAO {
    /// Inserts a notification; silently skips duplicates (same seq).
    func insert(notification: PushNotification) throws {
        let seq = notification.seq
        var descriptor = FetchDescriptor<PushNotificationEntity>(
            predicate: #Predicate { $0.seq == seq }
        )
        descriptor.fetchLimit = 1
        guard try modelContext.fetch(descriptor).isEmpty else { return }
        modelContext.insert(PushNotificationEntity(from: notification))
        try modelContext.save()
    }

    /// Newest-first notification history.
    func listHistory(limit: Int) throws -> [PushNotification] {
        var descriptor = FetchDescriptor<PushNotificationEntity>(
            sortBy: [SortDescriptor(\.seq, order: .reverse)]
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
