//
//  Config.swift
//  llama Mail
//
//  App-wide constants. Values marked "binding contract" must match the
//  Android reference implementation exactly (spec §DOX).
//

import Foundation

enum Config {
    // Binding contract: deep-link scheme is exactly llamalabels://native-pair.
    static let deepLinkScheme = "llamalabels"
    static let pairingHost = "native-pair"

    static let defaultImapPort = 993
    static let defaultSmtpPort = 587
    static let defaultImapFolder = "INBOX"

    /// Foreground refresh cadence for keyword tabs and pull-mode polling (spec §2, §3).
    static let foregroundRefreshInterval: TimeInterval = 90

    // Binding contract: theme names match web theme.ts / Android AppTheme.kt.
    static let defaultThemeName = "Dark Matter"
}
