//
//  AppDatabase.swift
//  llama Mail
//
//  Owns the SwiftData ModelContainer for the local cache (spec §8).
//

import Foundation
import SwiftData

final class AppDatabase: Sendable {
    static let schema = Schema([
        EmailEntity.self,
        ContactEntity.self,
        PushNotificationEntity.self,
        KeywordEntity.self,
    ])

    let container: ModelContainer

    /// - Parameter inMemory: true for tests; no data is written to disk.
    init(inMemory: Bool = false) throws {
        // ponytail: no SchemaMigrationPlan yet — add a VersionedSchema +
        // migration plan when the first schema change lands.
        let configuration = ModelConfiguration(
            schema: Self.schema,
            isStoredInMemoryOnly: inMemory
        )
        container = try ModelContainer(
            for: Self.schema,
            configurations: [configuration]
        )
    }
}
