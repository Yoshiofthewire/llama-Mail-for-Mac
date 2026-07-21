//
//  EmailDAO.swift
//  KyPost
//
//  Data access for cached emails (spec §8 EmailDAO). A @ModelActor so all
//  SwiftData work happens off the main thread.
//

import Foundation
import SwiftData

@ModelActor
actor EmailDAO {
    /// Replaces the cached snapshot of a folder with a fresh fetch result.
    func replaceFolderSnapshot(folder: String, emails: [Email]) throws {
        try modelContext.delete(
            model: EmailEntity.self,
            where: #Predicate { $0.folder == folder }
        )
        for email in emails {
            modelContext.insert(EmailEntity(from: email))
        }
        try modelContext.save()
    }

    /// Newest-first page of a folder.
    func getFolder(folder: String, limit: Int, offset: Int = 0) throws -> [Email] {
        var descriptor = FetchDescriptor<EmailEntity>(
            predicate: #Predicate { $0.folder == folder },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try modelContext.fetch(descriptor).map(\.toDomain)
    }

    func getEmail(serverId: String) throws -> Email? {
        var descriptor = FetchDescriptor<EmailEntity>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.toDomain
    }

    func updateEmail(serverId: String, read: Bool? = nil, starred: Bool? = nil) throws {
        var descriptor = FetchDescriptor<EmailEntity>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first else { return }
        if let read { entity.read = read }
        if let starred { entity.starred = starred }
        try modelContext.save()
    }

    /// Local cache search over subject, sender, and body.
    func search(folder: String, query: String) throws -> [Email] {
        let descriptor = FetchDescriptor<EmailEntity>(
            predicate: #Predicate {
                $0.folder == folder && (
                    $0.subject.localizedStandardContains(query)
                    || $0.senderName.localizedStandardContains(query)
                    || $0.body.localizedStandardContains(query)
                )
            },
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.toDomain)
    }
}
