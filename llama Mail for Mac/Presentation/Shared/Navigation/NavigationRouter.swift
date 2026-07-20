//
//  NavigationRouter.swift
//  llama Mail
//
//  App-level routing state (spec §10). Receives NavigationActions from deep
//  links and notification taps and drives tab selection + presented sheets.
//

import SwiftUI
import Observation

enum AppTab: Hashable {
    case inbox
    case contacts
    case settings
}

/// Identifiable wrapper so an MFA challenge can drive a sheet.
struct MfaRoute: Identifiable, Equatable {
    let challengeId: String
    var id: String { challengeId }
}

extension PairingParams: Identifiable {
    var id: String { "\(sub)|\(srv)" }
}

extension DesktopPairingParams: Identifiable {
    var id: String { code }
}

@Observable
@MainActor
final class NavigationRouter {
    var selectedTab: AppTab = .inbox
    /// Presented pairing flow (from QR / deep link).
    var pairingParams: PairingParams?
    /// Presented desktop pairing flow (kypost://desktop-pair deep link).
    var desktopPairingParams: DesktopPairingParams?
    /// Presented in-app MFA approval fallback.
    var mfaRoute: MfaRoute?
    /// Message the inbox should open once loaded (from a notification tap).
    var pendingMessageId: String?

    private let deepLinkHandler: DeepLinkHandler

    init(deepLinkHandler: DeepLinkHandler = DeepLinkHandler()) {
        self.deepLinkHandler = deepLinkHandler
    }

    func handle(_ action: NavigationAction) {
        switch action {
        case .openPairingFlow(let params):
            pairingParams = params
        case .openDesktopPairingFlow(let params):
            desktopPairingParams = params
        case .openEmail(let messageId):
            selectedTab = .inbox
            pendingMessageId = messageId
        case .openMfaApproval(let challengeId):
            mfaRoute = MfaRoute(challengeId: challengeId)
        }
    }

    /// Entry point for onOpenURL.
    func handleURL(_ url: URL) {
        guard let action = deepLinkHandler.handle(url) else { return }
        handle(action)
    }
}
