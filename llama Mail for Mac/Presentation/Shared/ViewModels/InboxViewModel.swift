//
//  InboxViewModel.swift
//  llama Mail
//
//  Inbox state: cached-first load, server refresh, keyword tab filtering,
//  and the 90-second foreground refresh cadence (spec §2).
//

import Foundation
import Observation

@Observable
@MainActor
final class InboxViewModel {
    private let mailRepository: MailRepository
    private let keywordRepository: KeywordRepository

    private(set) var folder = Config.defaultFolder
    private(set) var emails: [Email] = []
    private(set) var tabs: [KeywordTab] = []
    /// Server-side children of Inbox and Archive, for folder navigation.
    private(set) var inboxSubfolders: [MailFolder] = []
    private(set) var archiveSubfolders: [MailFolder] = []
    var selectedTab: String?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    private var refreshTask: Task<Void, Never>?

    init(mailRepository: MailRepository, keywordRepository: KeywordRepository) {
        self.mailRepository = mailRepository
        self.keywordRepository = keywordRepository
    }

    var filteredEmails: [Email] {
        guard let selectedTab else { return emails }
        return emails.filter { $0.keywords.contains(selectedTab) }
    }

    var folderDisplayName: String {
        StandardFolder.displayName(folder)
    }

    /// Switches to another server folder (Junk, Trash, Archive/…) and reloads,
    /// optionally landing on a keyword tab.
    func selectFolder(_ name: String, tab: String? = nil) async {
        guard folder != name else {
            selectedTab = tab
            return
        }
        folder = name
        selectedTab = tab
        emails = []
        tabs = []
        errorMessage = nil
        await load()
    }

    /// Best-effort fetch of Inbox and Archive children (paths come back full,
    /// e.g. "INBOX/Receipts", ready to use as the fetch mailbox).
    func loadSubfolders() async {
        if let folders = try? await mailRepository.listFolders(parent: StandardFolder.inbox) {
            inboxSubfolders = folders
        }
        if let folders = try? await mailRepository.listFolders(parent: StandardFolder.archive) {
            archiveSubfolders = folders
        }
    }

    /// Moves emails to another folder (drag & drop), then re-syncs the list.
    func move(serverIds: [String], to targetFolder: String) async {
        guard !serverIds.isEmpty, targetFolder != folder else { return }
        emails.removeAll { serverIds.contains($0.serverId) }
        tabs = keywordRepository.visibleTabs(from: emails)
        do {
            try await mailRepository.move(messageIds: serverIds, from: folder, to: targetFolder)
            await refresh()
        } catch {
            errorMessage = "Could not move: \(error.localizedDescription)"
            await refresh()
        }
    }

    /// Instant display from the local cache, then a server refresh.
    func load() async {
        if let cached = try? await mailRepository.cachedFolder(folder), !cached.isEmpty {
            apply(emails: cached)
        }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            apply(emails: try await mailRepository.refreshFolder(folder))
            errorMessage = nil
        } catch MailSourceError.notPaired {
            errorMessage = "Pair this device (Settings → Connection) to load mail."
        } catch {
            errorMessage = "Could not refresh: \(error.localizedDescription)"
        }
    }

    /// Best-effort 90s refresh while the inbox is in the foreground (spec §2).
    func startAutoRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Config.foregroundRefreshInterval))
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func markRead(_ email: Email) async {
        try? await mailRepository.markRead(serverId: email.serverId)
        if let index = emails.firstIndex(where: { $0.serverId == email.serverId }) {
            emails[index].read = true
        }
    }

    /// Resolves a notification tap's messageId to a cached email.
    func email(withServerId serverId: String) -> Email? {
        emails.first { $0.serverId == serverId }
    }

    private func apply(emails newEmails: [Email]) {
        emails = newEmails
        tabs = keywordRepository.visibleTabs(from: newEmails)
        if let selectedTab, !tabs.contains(where: { $0.name == selectedTab }) {
            self.selectedTab = nil
        }
    }
}
