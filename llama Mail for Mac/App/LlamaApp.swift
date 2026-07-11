//
//  LlamaApp.swift
//  llama Mail
//
//  App entry point: platform delegate, dependency graph, theme, router,
//  deep links, and notification-tap routing. iOS gets the tab layout;
//  macOS gets the split-view window + Preferences + menu commands.
//

import SwiftUI
import SwiftData

@main
struct LlamaApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif

    @State private var themeManager = ThemeManager()
    @State private var router = NavigationRouter(
        deepLinkHandler: SingletonGraph.shared.deepLinkHandler
    )

    private var graph: SingletonGraph { .shared }

    var body: some Scene {
#if os(macOS)
        mainWindow
            .commands {
                LlamaCommands(router: router)
            }

        // Pop-out reader: one window per email, keyed by relay server id.
        WindowGroup("Email", id: "email", for: String.self) { $serverId in
            EmailWindowView(serverId: serverId ?? "")
                .environment(themeManager)
                .environment(router)
                .environment(\.theme, themeManager.palette)
                .preferredColorScheme(themeManager.palette.preferredColorScheme)
                .background(themeManager.palette.bg.ignoresSafeArea())
        }
        .defaultSize(width: 680, height: 620)

        Settings {
            MacPreferencesView()
                .environment(themeManager)
                .environment(router)
        }
#else
        mainWindow
#endif
    }

    private var mainWindow: some Scene {
        WindowGroup {
            rootView
                .environment(themeManager)
                .environment(router)
                .environment(\.theme, themeManager.palette)
                .preferredColorScheme(themeManager.palette.preferredColorScheme)
                .background(themeManager.palette.bg.ignoresSafeArea())
                .onOpenURL { url in
                    router.handleURL(url)
                }
                .onAppear {
                    // Notification taps (mail body / MFA fallback) route here.
                    graph.pushNotificationDispatcher.onNavigate = { [weak router] action in
                        router?.handle(action)
                    }
                }
        }
        .modelContainer(graph.database.container)
    }

    @ViewBuilder
    private var rootView: some View {
#if os(macOS)
        MacRootView()
#else
        MainTabView()
#endif
    }
}
