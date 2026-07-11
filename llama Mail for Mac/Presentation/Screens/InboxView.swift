//
//  InboxView.swift
//  llama Mail
//
//  Email list with keyword tabs (spec §2), pull-to-refresh, 90s auto-refresh
//  while visible, and notification-tap deep-open support.
//

import SwiftUI

struct InboxView: View {
    @Environment(\.theme) private var theme
    @Environment(NavigationRouter.self) private var router

    @Bindable var viewModel: InboxViewModel
    @State private var showCompose = false
    @State private var presentedEmail: Email?

    var body: some View {
        VStack(spacing: 0) {
            KeywordTabView(tabs: viewModel.tabs, selected: $viewModel.selectedTab)

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(AppFont.ui(13))
                    .foregroundStyle(SemanticColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }

            if viewModel.filteredEmails.isEmpty {
                ScrollView {
                    EmptyStateView(
                        message: viewModel.selectedTab == nil
                            ? "No emails yet — pull to refresh."
                            : "Nothing tagged \(viewModel.selectedTab ?? "")",
                        systemImage: "tray"
                    )
                }
                .refreshable { await viewModel.refresh() }
            } else {
                List(viewModel.filteredEmails) { email in
                    Button {
                        presentedEmail = email
                    } label: {
                        EmailListRow(email: email)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.bg)
                    .listRowSeparatorTint(theme.line)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.refresh() }
            }
        }
        .background(theme.bg)
        .navigationTitle(viewModel.folderDisplayName)
        .toolbarTitleMenu {
            folderPicker
        }
        .navigationDestination(item: $presentedEmail) { email in
            EmailDetailView(email: email, inboxViewModel: viewModel)
        }
        .toolbar {
            // Explicit folder button — the title menu's chevron is easy to miss.
            ToolbarItem(placement: .navigation) {
                Menu {
                    folderPicker
                } label: {
                    Label("Folder", systemImage: "folder")
                }
            }
            ToolbarItem {
                Button {
                    showCompose = true
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeView().environment(\.theme, theme)
        }
        .task {
            await viewModel.load()
            viewModel.startAutoRefresh()
            openPendingMessageIfNeeded()
            await viewModel.loadSubfolders()
        }
        .onDisappear { viewModel.stopAutoRefresh() }
        .onChange(of: router.pendingMessageId) {
            openPendingMessageIfNeeded()
        }
    }

    /// Server folder choices, shared by the title menu and the toolbar button.
    private var folderPicker: some View {
        Picker("Folder", selection: folderSelection) {
            Label("Inbox", systemImage: "tray").tag(StandardFolder.inbox)
            ForEach(viewModel.inboxSubfolders, id: \.name) { sub in
                Label(StandardFolder.displayName(sub.name), systemImage: "folder")
                    .tag(sub.name)
            }
            Label("Junk", systemImage: "xmark.bin").tag(StandardFolder.junk)
            Label("Trash", systemImage: "trash").tag(StandardFolder.trash)
        }
    }

    /// Folder choice for the menus; switching reloads the list.
    private var folderSelection: Binding<String> {
        Binding(
            get: { viewModel.folder },
            set: { name in Task { await viewModel.selectFolder(name) } }
        )
    }

    /// Opens the email a notification tap pointed at (spec §3).
    private func openPendingMessageIfNeeded() {
        guard let messageId = router.pendingMessageId else { return }
        if let email = viewModel.email(withServerId: messageId) {
            presentedEmail = email
            router.pendingMessageId = nil
        }
    }
}
