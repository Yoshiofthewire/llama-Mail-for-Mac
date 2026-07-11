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
        .navigationTitle("Inbox")
        .navigationDestination(item: $presentedEmail) { email in
            EmailDetailView(email: email, inboxViewModel: viewModel)
        }
        .toolbar {
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
        }
        .onDisappear { viewModel.stopAutoRefresh() }
        .onChange(of: router.pendingMessageId) {
            openPendingMessageIfNeeded()
        }
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
