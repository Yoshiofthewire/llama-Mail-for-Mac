//
//  MacRootView.swift
//  llama Mail
//
//  macOS main window (spec Phase 7): NavigationSplitView with a themed
//  sidebar (inbox + keyword filters + contacts), list content column, and
//  detail pane. Settings live in the Preferences window (Cmd+,), not a tab.
//

#if os(macOS)
import SwiftUI

enum MacSection: Hashable {
    case inbox(keyword: String?)
    case contacts
}

struct MacRootView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(NavigationRouter.self) private var router

    private var inboxViewModel: InboxViewModel { SingletonGraph.shared.inboxViewModel }
    private var contactsViewModel: ContactsViewModel { SingletonGraph.shared.contactsViewModel }

    @State private var section: MacSection? = .inbox(keyword: nil)
    @State private var selectedEmail: Email?
    @State private var selectedContact: Contact?

    var body: some View {
        @Bindable var router = router
        let theme = themeManager.palette

        NavigationSplitView {
            sidebar(theme: theme)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } content: {
            contentColumn(theme: theme)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            detailPane(theme: theme)
        }
        .tint(theme.accent)
        .environment(\.theme, theme)
        .sheet(isPresented: $router.composeRequested) {
            ComposeView().environment(\.theme, theme)
        }
        .sheet(item: $router.pairingParams) { params in
            PushPairingView(initialParams: params).environment(\.theme, theme)
        }
        .sheet(item: $router.mfaRoute) { route in
            MfaApprovalView(challengeId: route.challengeId).environment(\.theme, theme)
        }
        .task {
            await inboxViewModel.load()
            inboxViewModel.startAutoRefresh()
            await contactsViewModel.load()
        }
        .onChange(of: router.pendingMessageId) {
            openPendingMessageIfNeeded()
        }
        .onChange(of: section) {
            if case .inbox(let keyword) = section {
                inboxViewModel.selectedTab = keyword
            }
        }
    }

    // MARK: - Sidebar

    private func sidebar(theme: ThemePalette) -> some View {
        List(selection: $section) {
            Section("Mail") {
                Label("Inbox", systemImage: "tray")
                    .tag(MacSection.inbox(keyword: nil))
                ForEach(inboxViewModel.tabs, id: \.name) { tab in
                    Label(tab.name, systemImage: "tag")
                        .badge(tab.count)
                        .tag(MacSection.inbox(keyword: tab.name))
                }
            }
            Section("People") {
                Label("Contacts", systemImage: "person.2")
                    .tag(MacSection.contacts)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
    }

    // MARK: - Content column

    @ViewBuilder
    private func contentColumn(theme: ThemePalette) -> some View {
        switch section ?? .inbox(keyword: nil) {
        case .inbox:
            emailList(theme: theme)
        case .contacts:
            contactList(theme: theme)
        }
    }

    private func emailList(theme: ThemePalette) -> some View {
        Group {
            if inboxViewModel.filteredEmails.isEmpty {
                EmptyStateView(
                    message: inboxViewModel.errorMessage
                        ?? "No emails yet — refresh with ⌘R.",
                    systemImage: "tray"
                )
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(inboxViewModel.filteredEmails, selection: $selectedEmail) { email in
                    EmailListRow(email: email)
                        .tag(email)
                        .listRowBackground(theme.bg)
                        .listRowSeparatorTint(theme.line)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bg)
        .navigationTitle(currentInboxTitle)
        .toolbar {
            ToolbarItem {
                Button {
                    router.composeRequested = true
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem {
                Button {
                    Task { await inboxViewModel.refresh() }
                } label: {
                    if inboxViewModel.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private func contactList(theme: ThemePalette) -> some View {
        Group {
            if contactsViewModel.contacts.isEmpty {
                EmptyStateView(
                    message: "No contacts yet — sync or add one.",
                    systemImage: "person.crop.circle.badge.plus"
                )
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(contactsViewModel.contacts, selection: $selectedContact) { contact in
                    HStack(spacing: 10) {
                        AvatarView(name: contact.name)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(AppFont.ui(14, weight: .medium))
                                .foregroundStyle(theme.inkStrong)
                            Text(contact.email)
                                .font(AppFont.mono(11))
                                .foregroundStyle(theme.ink.opacity(0.8))
                        }
                    }
                    .tag(contact)
                    .listRowBackground(theme.bg)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bg)
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await contactsViewModel.sync() }
                } label: {
                    if contactsViewModel.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private func detailPane(theme: ThemePalette) -> some View {
        switch section ?? .inbox(keyword: nil) {
        case .inbox:
            if let selectedEmail {
                EmailDetailView(email: selectedEmail, inboxViewModel: inboxViewModel)
            } else {
                EmptyStateView(message: "Select an email", systemImage: "envelope.open")
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.bg)
            }
        case .contacts:
            if let selectedContact {
                ContactDetailView(contact: selectedContact, viewModel: contactsViewModel)
                    .id(selectedContact.localId)
            } else {
                EmptyStateView(message: "Select a contact", systemImage: "person.crop.circle")
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.bg)
            }
        }
    }

    // MARK: - Helpers

    private var currentInboxTitle: String {
        if case .inbox(let keyword?) = section ?? .inbox(keyword: nil) {
            return keyword
        }
        return "Inbox"
    }

    private func openPendingMessageIfNeeded() {
        guard let messageId = router.pendingMessageId else { return }
        if let email = inboxViewModel.email(withServerId: messageId) {
            section = .inbox(keyword: nil)
            selectedEmail = email
            router.pendingMessageId = nil
        }
    }
}
#endif
