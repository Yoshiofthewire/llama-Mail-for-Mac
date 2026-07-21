//
//  AppDatabase.swift
//  KyPost
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
        let configuration = ModelConfiguration(
            schema: Self.schema,
            isStoredInMemoryOnly: inMemory
        )
        container = try ModelContainer(
            for: Self.schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
