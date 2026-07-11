//
//  ContactDetailView.swift
//  llama Mail
//
//  Contact page (spec §4). Existing contacts open read-only — a card layout
//  with the 52pt+ avatar header per STYLE_GUIDE §4 — and switch to the edit
//  form via the Edit button. New contacts start in the edit form.
//

import SwiftUI

struct ContactDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new contact.
    let contact: Contact?
    let viewModel: ContactsViewModel

    @State private var name: String
    @State private var email: String
    @State private var phone: String
    @State private var isEditing: Bool

    init(contact: Contact?, viewModel: ContactsViewModel) {
        self.contact = contact
        self.viewModel = viewModel
        _name = State(initialValue: contact?.name ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _isEditing = State(initialValue: contact == nil)
    }

    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                detailCards
            }
        }
        .background(theme.bg)
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
    }

    private var navigationTitle: String {
        if contact == nil { return "New Contact" }
        return isEditing ? "Edit Contact" : (name.isEmpty ? "Contact" : name)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if contact == nil {
                        dismiss()
                    } else {
                        revertEdits()
                        isEditing = false
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await save()
                        if contact == nil {
                            dismiss()
                        } else {
                            isEditing = false
                        }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Edit") { isEditing = true }
            }
        }
    }

    // MARK: - Read-only cards

    private var detailCards: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    AvatarView(name: name.isEmpty ? "?" : name, size: 72)
                    Text(name.isEmpty ? "Unnamed" : name)
                        .font(AppFont.ui(22, weight: .semibold))
                        .foregroundStyle(theme.inkStrong)
                        .multilineTextAlignment(.center)
                    StatusBadgeView(
                        label: contact?.uid == nil ? "Local only" : "Synced",
                        isActive: contact?.uid != nil
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: Shape.panel))

                VStack(spacing: 0) {
                    detailRow(icon: "envelope", label: "Email", value: email)
                    rowDivider
                    detailRow(icon: "phone", label: "Phone", value: phone)
                    if let uid = contact?.uid {
                        rowDivider
                        detailRow(icon: "arrow.triangle.2.circlepath", label: "Sync ID", value: uid)
                    }
                }
                .padding(.vertical, 6)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: Shape.panel))

                if let contact {
                    Button("Delete Contact") {
                        Task {
                            await viewModel.delete(contact)
                            dismiss()
                        }
                    }
                    .buttonStyle(DangerButtonStyle())
                }
            }
            .padding()
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(theme.line)
            .padding(.leading, 58)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(AppFont.ui(11, weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.65))
                Text(value.isEmpty ? "—" : value)
                    .font(AppFont.mono(14))
                    .foregroundStyle(value.isEmpty ? theme.ink.opacity(0.5) : theme.inkStrong)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Edit form

    private var editForm: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    AvatarView(name: name.isEmpty ? "?" : name, size: 52)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Details") {
                TextField("Name", text: $name)
                    .font(AppFont.ui(15))
                TextField("Email", text: $email)
                    .font(AppFont.mono(14))
                TextField("Phone", text: $phone)
                    .font(AppFont.mono(14))
            }
            .listRowBackground(theme.panel)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func revertEdits() {
        name = contact?.name ?? ""
        email = contact?.email ?? ""
        phone = contact?.phone ?? ""
    }

    private func save() async {
        var updated = contact ?? Contact(
            uid: nil, name: "", email: "", phone: "", avatarUrl: nil,
            createdAt: Date(), updatedAt: Date()
        )
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.email = email.trimmingCharacters(in: .whitespaces)
        updated.phone = phone.trimmingCharacters(in: .whitespaces)
        await viewModel.save(updated)
    }
}
