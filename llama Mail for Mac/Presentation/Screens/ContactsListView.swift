//
//  ContactsListView.swift
//  llama Mail
//
//  Contact list with avatars and sync status (spec §4).
//

import SwiftUI

struct ContactsListView: View {
    @Environment(\.theme) private var theme

    @Bindable var viewModel: ContactsViewModel
    @State private var showNewContact = false

    var body: some View {
        Group {
            if viewModel.contacts.isEmpty {
                ScrollView {
                    EmptyStateView(
                        message: "No contacts yet — add one or sync from the server.",
                        systemImage: "person.crop.circle.badge.plus"
                    )
                }
            } else {
                List(viewModel.contacts) { contact in
                    NavigationLink(value: contact) {
                        HStack(spacing: 12) {
                            AvatarView(name: contact.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(AppFont.ui(15, weight: .medium))
                                    .foregroundStyle(theme.inkStrong)
                                Text(contact.primaryEmail)
                                    .font(AppFont.mono(12))
                                    .foregroundStyle(theme.ink.opacity(0.8))
                            }
                            Spacer()
                            StatusBadgeView(
                                label: contact.uid == nil ? "Local" : "Synced",
                                isActive: contact.uid != nil
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(theme.bg)
                    .listRowSeparatorTint(theme.line)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bg)
        .navigationTitle("Contacts")
        .navigationDestination(for: Contact.self) { contact in
            ContactDetailView(contact: contact, viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showNewContact = true
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    Task { await viewModel.sync() }
                } label: {
                    if viewModel.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            ToolbarItem {
                Button {
                    Task { await viewModel.dedupe() }
                } label: {
                    Label("Find Duplicates", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(viewModel.isSyncing)
            }
        }
        .sheet(isPresented: $showNewContact) {
            NavigationStack {
                ContactDetailView(contact: nil, viewModel: viewModel)
            }
            .environment(\.theme, theme)
        }
        .task { await viewModel.load() }
        .overlay(alignment: .bottom) {
            if let message = viewModel.statusMessage {
                Text(message)
                    .font(AppFont.ui(13))
                    .foregroundStyle(theme.inkStrong)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.panel, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
                    .padding(.bottom, 10)
            }
        }
    }
}
