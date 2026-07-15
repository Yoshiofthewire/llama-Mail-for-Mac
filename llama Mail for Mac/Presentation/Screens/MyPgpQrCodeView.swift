//
//  MyPgpQrCodeView.swift
//  llama Mail
//
//  "My QR Code" (Client_PGP_Update.md): shows a short-lived pickup URL as a QR
//  code for someone standing next to you to scan.
//
//  ⚠️ Blocked end-to-end on the backend: minting needs Bearer auth, which the
//  server does not implement, and the endpoint that would mint this app's
//  session token (POST /api/notifications/desktop/register) is unbuilt. Until
//  both land this screen renders .needsPairing or .sessionExpired. The scan
//  half (ScanPgpKeyView) works against today's server.
//

import SwiftUI

struct MyPgpQrCodeView: View {
    @Environment(\.theme) private var theme

    @State private var viewModel = MyPgpQrViewModel(
        client: SingletonGraph.shared.pgpQrClient,
        sessionStore: SingletonGraph.shared.desktopSessionStore
    )

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .loading:
                ProgressView("Preparing your code…")
                    .frame(maxHeight: .infinity)
            case .showing(let urlString, _):
                qrContent(urlString: urlString)
            case .needsPairing:
                message(
                    "Pair this computer with the web app to show your key code.",
                    icon: "lock.shield"
                )
            case .noPgpIdentity:
                message(
                    "Set up a PGP key in the web app first, then come back.",
                    icon: "key"
                )
            case .sessionExpired:
                retryable(
                    "This computer's session has expired — pair it again to show your code.",
                    icon: "lock.slash"
                )
            case .unavailable:
                // 503 is a server config gap; retrying cannot fix it, so no CTA.
                message(
                    "Key exchange isn't set up on this server.",
                    icon: "exclamationmark.triangle"
                )
            case .failed(let text):
                retryable(text, icon: "exclamationmark.triangle")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .navigationTitle("My QR Code")
        .task { await viewModel.refresh() }
        .task { await viewModel.observeExpiry() }
    }

    private func qrContent(urlString: String) -> some View {
        VStack(spacing: 14) {
            if let cgImage = QRCodeGenerator.cgImage(for: urlString) {
                // Always on white regardless of theme — a dark-tinted QR code
                // is a QR code that doesn't scan.
                Image(decorative: cgImage, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: Shape.field))
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.ink.opacity(0.5))
                Text("Couldn't render the QR code.")
                    .font(AppFont.ui(14))
                    .foregroundStyle(theme.ink)
            }

            Text("Have them scan this in llama Mail to add your public key.")
                .font(AppFont.ui(14))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)

            if let seconds = viewModel.secondsRemaining {
                Text(seconds > 0 ? "Expires in \(seconds)s" : "Expired — refreshing…")
                    .font(AppFont.mono(12))
                    .foregroundStyle(theme.ink.opacity(0.7))
                    .monospacedDigit()
            }

            Button("Refresh") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxHeight: .infinity)
    }

    private func message(_ text: String, icon: String) -> some View {
        EmptyStateView(message: text, systemImage: icon)
            .frame(maxHeight: .infinity)
    }

    private func retryable(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            EmptyStateView(message: text, systemImage: icon)
            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxHeight: .infinity)
    }
}
