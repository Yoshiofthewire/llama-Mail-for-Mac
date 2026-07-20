//
//  DesktopPairingView.swift
//  llama Mail
//
//  Desktop pairing flow (Desktop Pairing guide). Auto-pairs when opened from
//  a kypost://desktop-pair deep link; offers a paste-the-link fallback
//  for when the browser could not launch the app.
//

import SwiftUI

struct DesktopPairingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Non-nil when opened from a kypost://desktop-pair deep link.
    let initialParams: DesktopPairingParams?

    @State private var viewModel = DesktopPairingViewModel(
        pairingService: SingletonGraph.shared.desktopPairingService
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch viewModel.state {
                case .idle:
                    idleContent
                case .working:
                    ProgressView("Pairing…")
                        .frame(maxHeight: .infinity)
                case .paired(let userEmail):
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(SemanticColors.successBorder)
                        Text("Computer paired")
                            .font(AppFont.ui(19, weight: .semibold))
                            .foregroundStyle(theme.inkStrong)
                        if let userEmail {
                            Text("Paired as \(userEmail)")
                                .font(AppFont.mono(12))
                                .foregroundStyle(theme.ink.opacity(0.8))
                        }
                        Button("Done") { dismiss() }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 8)
                    }
                    .frame(maxHeight: .infinity)
                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(SemanticColors.warning)
                        Text(message)
                            .font(AppFont.ui(14))
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { viewModel.reset() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .navigationTitle("Pair Desktop App")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(theme.accent)
        .task {
            if let initialParams {
                await viewModel.pair(params: initialParams)
            }
        }
    }

    private var idleContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "laptopcomputer.and.arrow.down")
                .font(.system(size: 44))
                .foregroundStyle(theme.accent)
            Text("Click “Pair Desktop App” on the web app's Pairing page, or paste the pairing link below.")
                .font(AppFont.ui(14))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)

            TextField("kypost://desktop-pair?…", text: $viewModel.pastedLink)
                .font(AppFont.mono(13))
                .textFieldStyle(.plain)
                .padding(12)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: Shape.field))
                .overlay(
                    RoundedRectangle(cornerRadius: Shape.field)
                        .strokeBorder(theme.line, lineWidth: 1)
                )

            Button("Pair") {
                Task { await viewModel.pairFromPastedLink() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.pastedLink.isEmpty)
        }
        .frame(maxHeight: .infinity)
    }
}
