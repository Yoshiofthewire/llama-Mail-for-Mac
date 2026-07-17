//
//  SettingsViewModel.swift
//  llama Mail
//
//  Settings state: relay pairing status, desktop session, notifications,
//  keyword visibility. Mail flows exclusively through the paired relay.
//

import Foundation
import Observation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@Observable
@MainActor
final class SettingsViewModel {
    private let securePairingStore: SecurePairingStore
    private let pushSettingsStore: PushSettingsStore
    private let desktopSessionStore: DesktopSessionStore
    private let mailRepository: MailRepository
    private let keywordRepository: KeywordRepository
    private let contactsSettingsStore: ContactsSettingsStore
    private let systemContactsExporter: SystemContactsExporter

    var systemNotificationsEnabled: Bool {
        didSet { pushSettingsStore.systemNotificationsEnabled = systemNotificationsEnabled }
    }

    /// "Export to Apple Contacts" toggle. Enabling prompts for Contacts
    /// access first; when denied the toggle flips back with guidance.
    var exportContactsToSystem: Bool {
        didSet {
            guard !suppressExportToggle, exportContactsToSystem != oldValue else { return }
            Task { await handleExportToggleChanged(exportContactsToSystem) }
        }
    }
    /// Re-entrancy guard so flipping the toggle back after a denial doesn't
    /// trigger another handleExportToggleChanged pass.
    @ObservationIgnored private var suppressExportToggle = false
    private(set) var contactsExportDenied = false
    private(set) var hasExportedContacts = false

    private(set) var statusMessage: String?
    private(set) var keywordSettings: [KeywordSetting] = []

    init(
        securePairingStore: SecurePairingStore,
        pushSettingsStore: PushSettingsStore,
        desktopSessionStore: DesktopSessionStore,
        mailRepository: MailRepository,
        keywordRepository: KeywordRepository,
        contactsSettingsStore: ContactsSettingsStore,
        systemContactsExporter: SystemContactsExporter
    ) {
        self.securePairingStore = securePairingStore
        self.pushSettingsStore = pushSettingsStore
        self.desktopSessionStore = desktopSessionStore
        self.mailRepository = mailRepository
        self.keywordRepository = keywordRepository
        self.contactsSettingsStore = contactsSettingsStore
        self.systemContactsExporter = systemContactsExporter
        systemNotificationsEnabled = pushSettingsStore.systemNotificationsEnabled
        exportContactsToSystem = contactsSettingsStore.exportToSystemContactsEnabled
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

    // MARK: - Apple Contacts export

    func refreshContactsExportState() {
        contactsExportDenied = systemContactsExporter.isDenied
        hasExportedContacts = systemContactsExporter.hasExportedContacts()
    }

    /// "Re-export Missing Contacts": runs a full reconcile pass, which
    /// recreates cards that were deleted outside the app (removed in
    /// Contacts.app, or lost with an account change).
    func reexportMissingContacts() async {
        let summary = await systemContactsExporter.reconcileAll()
        hasExportedContacts = systemContactsExporter.hasExportedContacts()
        statusMessage = "Re-exported \(summary.created + summary.updated) contact(s) to Apple Contacts"
    }

    /// Removes every card the app created in Apple Contacts and forgets the
    /// links; separate from the toggle, which keeps exported cards.
    func removeExportedContacts() {
        let removed = systemContactsExporter.removeAllExported()
        hasExportedContacts = systemContactsExporter.hasExportedContacts()
        statusMessage = "Removed \(removed) exported contact(s) from Apple Contacts"
    }

    func openContactsPrivacySettings() {
        #if os(macOS)
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        ) else { return }
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func handleExportToggleChanged(_ enabled: Bool) async {
        guard enabled else {
            contactsSettingsStore.exportToSystemContactsEnabled = false
            statusMessage = "Contacts export turned off — exported cards were kept."
            return
        }
        guard await systemContactsExporter.requestAccessIfNeeded() else {
            suppressExportToggle = true
            exportContactsToSystem = false
            suppressExportToggle = false
            contactsExportDenied = true
            statusMessage = "Contacts access is denied. Allow KyPost under "
                + "System Settings > Privacy & Security > Contacts."
            return
        }
        contactsExportDenied = false
        contactsSettingsStore.exportToSystemContactsEnabled = true
        let summary = await systemContactsExporter.reconcileAll()
        hasExportedContacts = systemContactsExporter.hasExportedContacts()
        statusMessage = "Exported \(summary.created + summary.updated) contact(s) to Apple Contacts"
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
