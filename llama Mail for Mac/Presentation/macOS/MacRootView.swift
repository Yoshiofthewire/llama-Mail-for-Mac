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
    /// A server mailbox other than Inbox (Drafts, Junk, Sent, Trash, Archive/…).
    case folder(name: String)
    case contacts
}

struct MacRootView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(NavigationRouter.self) private var router
    @Environment(\.openWindow) private var openWindow

    private var inboxViewModel: InboxViewModel { SingletonGraph.shared.inboxViewModel }
    private var contactsViewModel: ContactsViewModel { SingletonGraph.shared.contactsViewModel }

    @State private var section: MacSection? = .inbox(keyword: nil)
    @State private var selectedEmail: Email?
    @State private var selectedContact: Contact?
    /// When off, the email preview pane is hidden and reading happens in
    /// pop-out windows (double-click). Contacts always keep their detail pane.
    @AppStorage("macShowPreviewPane") private var showPreviewPane = true

    var body: some View {
        @Bindable var router = router
        let theme = themeManager.palette

        Group {
            if showPreviewPane || section == .contacts {
                NavigationSplitView {
                    sidebar(theme: theme)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
                } content: {
                    contentColumn(theme: theme)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                } detail: {
                    detailPane(theme: theme)
                }
            } else {
                NavigationSplitView {
                    sidebar(theme: theme)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
                } detail: {
                    contentColumn(theme: theme)
                }
            }
        }
        .tint(theme.accent)
        .environment(\.theme, theme)
        .sheet(isPresented: $router.composeRequested) {
            ComposeView().environment(\.theme, theme)
        }
        .sheet(item: $router.pairingParams) { params in
            PushPairingView(initialParams: params).environment(\.theme, theme)
        }
        .sheet(item: $router.desktopPairingParams) { params in
            DesktopPairingView(initialParams: params).environment(\.theme, theme)
        }
        .sheet(item: $router.mfaRoute) { route in
            MfaApprovalView(challengeId: route.challengeId).environment(\.theme, theme)
        }
        .task {
            await inboxViewModel.load()
            inboxViewModel.startAutoRefresh()
            await inboxViewModel.loadSubfolders()
            await contactsViewModel.load()
        }
        .onChange(of: router.pendingMessageId) {
            openPendingMessageIfNeeded()
        }
        .onChange(of: section) {
            switch section {
            case .inbox(let keyword):
                Task { await inboxViewModel.selectFolder(StandardFolder.inbox, tab: keyword) }
            case .folder(let name):
                Task { await inboxViewModel.selectFolder(name) }
            case .contacts, nil:
                break
            }
        }
    }

    // MARK: - Sidebar

    /// Mailboxes shown between the keywords and Archive, in display order.
    private static let interiorFolders = [
        StandardFolder.drafts,
        StandardFolder.junk,
        StandardFolder.sent,
        StandardFolder.trash,
    ]

    private static func folderIcon(_ name: String) -> String {
        switch name {
        case StandardFolder.drafts: "doc.text"
        case StandardFolder.junk: "xmark.bin"
        case StandardFolder.sent: "paperplane"
        case StandardFolder.trash: "trash"
        default: "folder"
        }
    }

    private func sidebar(theme: ThemePalette) -> some View {
        List(selection: $section) {
            Section("Mail") {
                Label("Inbox", systemImage: "tray")
                    .moveDropTarget(StandardFolder.inbox, viewModel: inboxViewModel)
                    .tag(MacSection.inbox(keyword: nil))
                // Everything between Inbox and Archive is indented one level.
                ForEach(inboxViewModel.inboxSubfolders, id: \.name) { sub in
                    folderRow(path: sub.name, icon: "folder", indented: true)
                }
                ForEach(inboxViewModel.tabs, id: \.name) { tab in
                    Label(tab.name, systemImage: "tag")
                        .badge(tab.count)
                        .padding(.leading, 12)
                        .tag(MacSection.inbox(keyword: tab.name))
                }
                ForEach(Self.interiorFolders, id: \.self) { name in
                    folderRow(path: name, icon: Self.folderIcon(name), indented: true)
                }
                folderRow(path: StandardFolder.archive, icon: "archivebox", indented: false)
                ForEach(inboxViewModel.archiveSubfolders, id: \.name) { sub in
                    folderRow(path: sub.name, icon: "folder", indented: true)
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

    /// A selectable sidebar folder that also accepts dropped emails.
    private func folderRow(path: String, icon: String, indented: Bool) -> some View {
        Label(StandardFolder.displayName(path), systemImage: icon)
            .padding(.leading, indented ? 12 : 0)
            .moveDropTarget(path, viewModel: inboxViewModel)
            .tag(MacSection.folder(name: path))
    }

    // MARK: - Content column

    @ViewBuilder
    private func contentColumn(theme: ThemePalette) -> some View {
        switch section ?? .inbox(keyword: nil) {
        case .inbox, .folder:
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
                        .draggable(email.serverId)
                        .tag(email)
                        .listRowBackground(theme.bg)
                        .listRowSeparatorTint(theme.line)
                }
                // Single click selects (fills the preview pane when shown);
                // double click / primaryAction pops the email out.
                .contextMenu(forSelectionType: Email.self) { selection in
                    Button {
                        openInNewWindows(selection)
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                } primaryAction: { selection in
                    openInNewWindows(selection)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bg)
        .navigationTitle(currentInboxTitle)
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showPreviewPane) {
                    Label("Preview Pane", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the preview pane")
            }
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
        case .inbox, .folder:
            if let selectedEmail {
                EmailDetailView(email: selectedEmail, inboxViewModel: inboxViewModel)
                    .toolbar {
                        ToolbarItem {
                            Button {
                                openWindow(id: "email", value: selectedEmail.serverId)
                            } label: {
                                Label("Open in New Window", systemImage: "macwindow.badge.plus")
                            }
                        }
                    }
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
        switch section ?? .inbox(keyword: nil) {
        case .inbox(let keyword?):
            keyword
        case .folder(let name):
            StandardFolder.displayName(name)
        default:
            "Inbox"
        }
    }

    private func openInNewWindows(_ emails: Set<Email>) {
        for email in emails {
            openWindow(id: "email", value: email.serverId)
        }
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

private extension View {
    /// Accepts dragged email server ids and moves them to `folder`.
    func moveDropTarget(_ folder: String, viewModel: InboxViewModel) -> some View {
        dropDestination(for: String.self) { serverIds, _ in
            Task { await viewModel.move(serverIds: serverIds, to: folder) }
            return true
        }
    }
}

/// Content of a popped-out email window (LlamaApp "email" WindowGroup).
struct EmailWindowView: View {
    @Environment(\.theme) private var theme

    let serverId: String

    private var inboxViewModel: InboxViewModel { SingletonGraph.shared.inboxViewModel }

    var body: some View {
        if let email = inboxViewModel.email(withServerId: serverId) {
            EmailDetailView(email: email, inboxViewModel: inboxViewModel)
        } else {
            EmptyStateView(
                message: "This email is no longer available.",
                systemImage: "envelope"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        }
    }
}
#endif
