//
//  SettingsViewModel.swift
//  llama Mail
//
//  Settings state: relay pairing status, desktop session, notifications,
//  keyword visibility. Mail flows exclusively through the paired relay.
//

import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    private let securePairingStore: SecurePairingStore
    private let pushSettingsStore: PushSettingsStore
    private let desktopSessionStore: DesktopSessionStore
    private let mailRepository: MailRepository
    private let keywordRepository: KeywordRepository

    var systemNotificationsEnabled: Bool {
        didSet { pushSettingsStore.systemNotificationsEnabled = systemNotificationsEnabled }
    }

    private(set) var statusMessage: String?
    private(set) var keywordSettings: [KeywordSetting] = []

    init(
        securePairingStore: SecurePairingStore,
        pushSettingsStore: PushSettingsStore,
        desktopSessionStore: DesktopSessionStore,
        mailRepository: MailRepository,
        keywordRepository: KeywordRepository
    ) {
        self.securePairingStore = securePairingStore
        self.pushSettingsStore = pushSettingsStore
        self.desktopSessionStore = desktopSessionStore
        self.mailRepository = mailRepository
        self.keywordRepository = keywordRepository
        systemNotificationsEnabled = pushSettingsStore.systemNotificationsEnabled
    }

    // MARK: - Pairing status

    var isPaired: Bool { securePairingStore.isPaired }

    var pairedServerHost: String? {
        guard let pairing = try? securePairingStore.loadPairing() else { return nil }
        return URL(string: pairing.srv)?.host() ?? pairing.srv
    }

    var pairedDeviceId: String? {
        (try? securePairingStore.loadPairing())?.lastDeviceId
    }

    var deliveryMode: String {
        pushSettingsStore.deliveryMode?.rawValue.capitalized ?? "Push"
    }

    func unpair() {
        try? securePairingStore.clear()
        statusMessage = "Pairing removed"
    }

    func testConnection() async {
        statusMessage = "Testing…"
        do {
            let folders = try await mailRepository.listFolders()
            statusMessage = "Connected — \(folders.count) folder(s)"
        } catch MailSourceError.notPaired {
            statusMessage = "Not paired — pair this device first."
        } catch {
            statusMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Desktop pairing (Desktop Pairing guide)

    /// Active desktop session, if any; expired sessions read as nil.
    var desktopSession: DesktopSession? {
        desktopSessionStore.activeSession()
    }

    /// "Forget This Computer" (guide checklist): clears the stored session token.
    func forgetDesktopPairing() {
        try? desktopSessionStore.clear()
        statusMessage = "Desktop pairing removed"
    }

    // MARK: - Keyword visibility (spec §9 KeywordSettingsView)

    func loadKeywordSettings() async {
        let cached = (try? await mailRepository.cachedFolder(
            Config.defaultFolder,
            limit: 200
        )) ?? []
        keywordSettings = keywordRepository.allSettings(from: cached)
    }

    func setKeywordVisible(_ visible: Bool, for keyword: String) {
        keywordRepository.setVisible(visible, for: keyword)
        if let index = keywordSettings.firstIndex(where: { $0.name == keyword }) {
            keywordSettings[index].visible = visible
        }
    }
}
