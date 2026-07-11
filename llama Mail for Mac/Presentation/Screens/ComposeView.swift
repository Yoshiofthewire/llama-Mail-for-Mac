//
//  ComposeView.swift
//  llama Mail
//
//  Compose sheet (spec §7). Errors show inline and keep the draft in memory.
//  ponytail: no attachment support in v1, add file picker + multipart in v2.
//

import SwiftUI

struct ComposeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = ComposeViewModel(
        sendEmail: SingletonGraph.shared.sendEmailUseCase
    )

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("To (comma-separated)", text: $viewModel.to)
                        .font(AppFont.mono(14))
                    TextField("Cc", text: $viewModel.cc)
                        .font(AppFont.mono(14))
                    TextField("Bcc", text: $viewModel.bcc)
                        .font(AppFont.mono(14))
                    TextField("Subject", text: $viewModel.subject)
                        .font(AppFont.ui(15))
                }
                .listRowBackground(theme.panel)

                Section {
                    TextEditor(text: $viewModel.body)
                        .font(AppFont.mono(14))
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                }
                .listRowBackground(theme.panel)

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .font(AppFont.ui(13))
                            .foregroundStyle(SemanticColors.danger)
                    }
                    .listRowBackground(theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("New Email")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        if viewModel.isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send").fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isSending)
                }
            }
            .onChange(of: viewModel.didSend) {
                if viewModel.didSend { dismiss() }
            }
        }
        .tint(theme.accent)
    }
}
