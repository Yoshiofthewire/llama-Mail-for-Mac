//
//  SingletonGraph.swift
//  llama Mail
//
//  Dependency injection container (spec §Architecture). The app uses `.shared`;
//  tests build their own instance with an in-memory database and scratch
//  UserDefaults suite.
//

import Foundation

@MainActor
final class SingletonGraph {
    static let shared: SingletonGraph = {
        do {
            return try SingletonGraph()
        } catch {
            fatalError("Could not build dependency graph: \(error)")
        }
    }()

    // MARK: - Data

    let database: AppDatabase
    let keychain: KeychainStorage

    // MARK: - Storage

    let securePairingStore: SecurePairingStore
    let mailSettingsStore: MailSettingsStore
    let keywordSettingsStore: KeywordSettingsStore
    let notificationCursorStore: NotificationCursorStore

    // MARK: - DAOs

    lazy var emailDAO = EmailDAO(modelContainer: database.container)
    lazy var contactDAO = ContactDAO(modelContainer: database.container)
    lazy var pushNotificationDAO = PushNotificationDAO(modelContainer: database.container)

    init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainStorage = KeychainStorage(),
        database: AppDatabase? = nil
    ) throws {
        self.database = try database ?? AppDatabase()
        self.keychain = keychain
        securePairingStore = SecurePairingStore(keychain: keychain)
        mailSettingsStore = MailSettingsStore(defaults: userDefaults, keychain: keychain)
        keywordSettingsStore = KeywordSettingsStore(defaults: userDefaults)
        notificationCursorStore = NotificationCursorStore(defaults: userDefaults)
    }
}
