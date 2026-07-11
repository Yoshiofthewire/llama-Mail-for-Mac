//
//  MainTabView.swift
//  llama Mail
//
//  Root navigation (spec §10): Inbox / Contacts / Settings tabs, with the
//  pairing and MFA flows presented as sheets driven by NavigationRouter.
//

import SwiftUI

struct MainTabView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(NavigationRouter.self) private var router

    @State private var inboxViewModel = InboxViewModel(
        mailRepository: SingletonGraph.shared.mailRepository,
        keywordRepository: SingletonGraph.shared.keywordRepository
    )
    @State private var contactsViewModel = ContactsViewModel(
        repository: SingletonGraph.shared.contactSyncRepository
    )

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                InboxView(viewModel: inboxViewModel)
            }
            .tabItem { Label("Inbox", systemImage: "tray.fill") }
            .tag(AppTab.inbox)

            NavigationStack {
                ContactsListView(viewModel: contactsViewModel)
            }
            .tabItem { Label("Contacts", systemImage: "person.2.fill") }
            .tag(AppTab.contacts)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .tint(themeManager.palette.accent)
        .environment(\.theme, themeManager.palette)
        .sheet(item: $router.pairingParams) { params in
            PushPairingView(initialParams: params)
                .environment(\.theme, themeManager.palette)
        }
        .sheet(item: $router.mfaRoute) { route in
            MfaApprovalView(challengeId: route.challengeId)
                .environment(\.theme, themeManager.palette)
        }
    }
}
