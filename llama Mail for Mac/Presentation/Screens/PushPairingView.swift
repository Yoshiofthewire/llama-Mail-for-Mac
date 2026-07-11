//
//  PushPairingView.swift
//  llama Mail
//
//  Pairing flow (spec §1). Auto-pairs when opened from a deep link. On iOS
//  the default entry point is camera QR scanning, with a paste-the-link
//  fallback; macOS pairs via deep link or paste.
//

import SwiftUI

struct PushPairingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Non-nil when opened from a llamalabels://native-pair deep link.
    let initialParams: PairingParams?

    @State private var viewModel = PushPairingViewModel(
        registrationService: SingletonGraph.shared.deviceRegistrationService,
        pushSettingsStore: SingletonGraph.shared.pushSettingsStore
    )
#if os(iOS)
    /// nil until the camera permission request resolves.
    @State private var cameraAccessGranted: Bool?
#endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch viewModel.state {
                case .idle:
                    idleContent
                case .working:
                    ProgressView("Pairing…")
                        .frame(maxHeight: .infinity)
                case .paired(let deviceId):
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(SemanticColors.successBorder)
                        Text("Device paired")
                            .font(AppFont.ui(19, weight: .semibold))
                            .foregroundStyle(theme.inkStrong)
                        if let deviceId {
                            Text(deviceId)
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
            .navigationTitle("Pair Device")
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
#if os(iOS)
            scannerContent
#else
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(theme.accent)
            Text("Open a pairing link from the web app, or paste it below.")
                .font(AppFont.ui(14))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
#endif

            TextField("llamalabels://native-pair?…", text: $viewModel.pastedLink)
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

#if os(iOS)
    /// Default iOS entry point: scan the pairing QR code from the web app.
    @ViewBuilder
    private var scannerContent: some View {
        if QRScannerView.isSupported && cameraAccessGranted != false {
            Group {
                if cameraAccessGranted == true {
                    QRScannerView { payload in
                        Task { await viewModel.pairFromScannedCode(payload) }
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: Shape.field))
            .overlay(
                RoundedRectangle(cornerRadius: Shape.field)
                    .strokeBorder(theme.line, lineWidth: 1)
            )
            .task {
                if cameraAccessGranted == nil {
                    cameraAccessGranted = await QRScannerView.requestCameraAccess()
                }
            }
            Text("Point the camera at the pairing QR code from the web app, or paste the link below.")
                .font(AppFont.ui(14))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
        } else {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(theme.accent)
            Text("Camera unavailable — paste the pairing link below instead.")
                .font(AppFont.ui(14))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
        }
    }
#endif
}
