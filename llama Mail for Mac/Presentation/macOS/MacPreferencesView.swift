//
//  MacPreferencesView.swift
//  llama Mail
//
//  Native macOS Settings window (Cmd+,): toolbar-style tabs with grouped
//  forms, standard controls, and the theme accent as tint — per the style
//  guide's "stay native wins" rule.
//

#if os(macOS)
import SwiftUI

struct MacPreferencesView: View {
    @Environment(ThemeManager.self) private var themeManager

    @State private var viewModel = SettingsViewModel(
        securePairingStore: SingletonGraph.shared.securePairingStore,
        pushSettingsStore: SingletonGraph.shared.pushSettingsStore,
        desktopSessionStore: SingletonGraph.shared.desktopSessionStore,
        mailRepository: SingletonGraph.shared.mailRepository,
        keywordRepository: SingletonGraph.shared.keywordRepository
    )

    var body: some View {
        TabView {
            ConnectionPane(viewModel: viewModel)
                .tabItem { Label("Connection", systemImage: "link") }

            AppearancePane()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            KeywordsPane(viewModel: viewModel)
                .tabItem { Label("Keywords", systemImage: "tag") }

            NotificationsPane(viewModel: viewModel)
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
        }
        .frame(width: 560, height: 460)
        .tint(themeManager.palette.accent)
        .environment(\.theme, themeManager.palette)
        .preferredColorScheme(themeManager.palette.preferredColorScheme)
    }
}

// MARK: - Connection

private struct ConnectionPane: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showPairingSheet = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    StatusBadgeView(
                        label: viewModel.isPaired ? "Paired" : "Not paired",
                        isActive: viewModel.isPaired
                    )
                }
                if viewModel.isPaired {
                    LabeledContent("Server", value: viewModel.pairedServerHost ?? "—")
                    if let deviceId = viewModel.pairedDeviceId {
                        LabeledContent("Device ID") {
                            Text(deviceId)
                                .font(AppFont.mono(11))
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Text("Pair this Mac with your Llama Mail account to load mail.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Relay")
            }

            Section {
                HStack {
                    if viewModel.isPaired {
                        Button("Test Connection") {
                            Task { await viewModel.testConnection() }
                        }
                        Button("Re-pair…") { showPairingSheet = true }
                        Spacer()
                        Button("Remove Pairing", role: .destructive) {
                            viewModel.unpair()
                        }
                    } else {
                        Button("Pair This Mac…") { showPairingSheet = true }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
            }

            if let session = viewModel.desktopSession {
                Section {
                    if let email = session.userEmail {
                        LabeledContent("Account", value: email)
                    }
                    LabeledContent(
                        "Signed in",
                        value: session.pairedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledContent(
                        "Expires",
                        value: session.expiresAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    HStack {
                        Spacer()
                        Button("Forget This Computer", role: .destructive) {
                            viewModel.forgetDesktopPairing()
                        }
                    }
                } header: {
                    Text("Desktop Session")
                }
            }

            Section {
                LabeledContent(
                    "Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )
            } header: {
                Text("About")
            }

            if let message = viewModel.statusMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showPairingSheet) {
            DesktopPairingView(initialParams: nil)
        }
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Form {
            Section {
                ForEach(AppTheme.themeNames, id: \.self) { name in
                    let palette = AppTheme.palette(named: name)
                    Button {
                        themeManager.setTheme(named: name)
                    } label: {
                        HStack(spacing: 10) {
                            HStack(spacing: 3) {
                                swatch(palette.bg)
                                swatch(palette.panel)
                                swatch(palette.accent)
                            }
                            Text(name)
                            Spacer()
                            if themeManager.themeName == name {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(themeManager.palette.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Themes are shared with the web and Android apps.")
            }
        }
        .formStyle(.grouped)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
    }
}

// MARK: - Keywords

private struct KeywordsPane: View {
    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            if viewModel.keywordSettings.isEmpty {
                Section {
                    Text("No keywords yet — they appear after your first inbox refresh.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(viewModel.keywordSettings) { setting in
                        Toggle(
                            setting.name,
                            isOn: Binding(
                                get: { setting.visible },
                                set: { viewModel.setKeywordVisible($0, for: setting.name) }
                            )
                        )
                    }
                } header: {
                    Text("Inbox Tabs")
                } footer: {
                    Text("Hidden keywords stay on emails but don't get a sidebar tab.")
                }
            }
        }
        .formStyle(.grouped)
        .task { await viewModel.loadKeywordSettings() }
    }
}

// MARK: - Notifications

private struct NotificationsPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Show system notifications", isOn: $viewModel.systemNotificationsEnabled)
                LabeledContent("Delivery Mode", value: viewModel.deliveryMode)
            } footer: {
                Text("In Pull mode this Mac checks for notifications every 90 seconds while running.")
            }
        }
        .formStyle(.grouped)
    }
}
#endif
