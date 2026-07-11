//
//  SettingsView.swift
//  llama Mail
//
//  iOS settings: relay pairing status, theme, keywords, notifications, about.
//  macOS uses MacPreferencesView (native Settings window) instead.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme

    @State private var viewModel = SettingsViewModel(
        securePairingStore: SingletonGraph.shared.securePairingStore,
        pushSettingsStore: SingletonGraph.shared.pushSettingsStore,
        desktopSessionStore: SingletonGraph.shared.desktopSessionStore,
        mailRepository: SingletonGraph.shared.mailRepository,
        keywordRepository: SingletonGraph.shared.keywordRepository
    )
    @State private var showPairingSheet = false

    var body: some View {
        Form {
            Section("Connection") {
                if viewModel.isPaired {
                    LabeledContent("Connected via", value: viewModel.pairedServerHost ?? "—")
                    if let deviceId = viewModel.pairedDeviceId {
                        LabeledContent("Device ID") {
                            Text(deviceId).font(AppFont.mono(12))
                        }
                    }
                    HStack {
                        StatusBadgeView(label: "Paired", isActive: true)
                        Spacer()
                    }
                    Button("Test Connection") {
                        Task { await viewModel.testConnection() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Re-pair Device") { showPairingSheet = true }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Remove Pairing") { viewModel.unpair() }
                        .buttonStyle(DangerButtonStyle())
                } else {
                    HStack {
                        StatusBadgeView(label: "Not paired", isActive: false)
                        Spacer()
                    }
                    Text("Pair this device with your Llama Mail account to load mail.")
                        .font(AppFont.ui(13))
                        .foregroundStyle(theme.ink.opacity(0.8))
                    Button("Pair Device") { showPairingSheet = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .listRowBackground(theme.panel)

            Section("Appearance") {
                NavigationLink {
                    ThemesView()
                } label: {
                    LabeledContent("Theme") {
                        ThemeNameLabel()
                    }
                }
            }
            .listRowBackground(theme.panel)

            Section("Keywords") {
                NavigationLink("Keyword Settings") {
                    KeywordSettingsView(viewModel: viewModel)
                }
            }
            .listRowBackground(theme.panel)

            Section("Notifications") {
                Toggle("Enable system notifications", isOn: $viewModel.systemNotificationsEnabled)
                LabeledContent("Delivery Mode", value: viewModel.deliveryMode)
            }
            .listRowBackground(theme.panel)

            Section("About") {
                LabeledContent(
                    "Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )
            }
            .listRowBackground(theme.panel)

            if let message = viewModel.statusMessage {
                Section {
                    Text(message)
                        .font(AppFont.ui(13))
                        .foregroundStyle(theme.ink)
                }
                .listRowBackground(theme.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Settings")
        .sheet(isPresented: $showPairingSheet) {
            PushPairingView(initialParams: nil)
                .environment(\.theme, theme)
        }
    }
}

/// Small helper so the settings row shows the live theme name.
private struct ThemeNameLabel: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Text(themeManager.themeName)
    }
}
