//
//  MfaApprovalView.swift
//  KyPost
//
//  In-app MFA approval fallback (spec §5) — reached by tapping the MFA
//  notification body. Same use case as the notification's Approve/Deny.
//

import SwiftUI

struct MfaApprovalView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: MfaApprovalViewModel

    init(challengeId: String) {
        _viewModel = State(initialValue: MfaApprovalViewModel(
            challengeId: challengeId,
            approveMfaChallenge: SingletonGraph.shared.approveMfaChallengeUseCase
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.accent)

                Text("Sign-in request")
                    .font(AppFont.ui(20, weight: .semibold))
                    .foregroundStyle(theme.inkStrong)

                Text("A sign-in is waiting for approval from this device.")
                    .font(AppFont.ui(14))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)

                Text(viewModel.challengeId)
                    .font(AppFont.mono(12))
                    .foregroundStyle(theme.ink.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.panel, in: Capsule())

                switch viewModel.state {
                case .pending:
                    actionButtons
                case .sending:
                    ProgressView()
                case .done(let message):
                    Text(message)
                        .font(AppFont.ui(15, weight: .medium))
                        .foregroundStyle(SemanticColors.successText)
                    Button("Close") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                case .failed(let message):
                    Text(message)
                        .font(AppFont.ui(13))
                        .foregroundStyle(SemanticColors.danger)
                        .multilineTextAlignment(.center)
                    actionButtons
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .navigationTitle("Two-Factor Approval")
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
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button("Approve") {
                Task { await viewModel.respond(approved: true) }
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Deny") {
                Task { await viewModel.respond(approved: false) }
            }
            .buttonStyle(DangerButtonStyle())
        }
        .padding(.top, 8)
    }
}
