//
//  DesktopPairingViewModel.swift
//  llama Mail
//
//  Desktop pairing flow state (Desktop Pairing guide). Codes arrive via the
//  kypost://desktop-pair deep link, or as a pasted link when the browser
//  could not launch the app.
//

import Foundation
import Observation

/// A parsed desktop pairing link/code awaiting the user's explicit
/// confirmation before any network call fires. `existingHost` is set when
/// accepting would replace an already-paired session.
struct PendingDesktopPairingConfirmation: Equatable, Sendable {
    let params: DesktopPairingParams
    let existingHost: String?
}

@Observable
@MainActor
final class DesktopPairingViewModel {
    enum State: Equatable {
        case idle
        /// Destination host shown; the network call fires only once the
        /// user taps through (see `pair(params:)`).
        case confirming(PendingDesktopPairingConfirmation)
        case working
        case paired(userEmail: String?)
        case failed(String)
    }

    private let pairingService: DesktopPairingService
    private let sessionStore: DesktopSessionStore

    private(set) var state: State = .idle
    var pastedLink = ""

    init(pairingService: DesktopPairingService, sessionStore: DesktopSessionStore) {
        self.pairingService = pairingService
        self.sessionStore = sessionStore
    }

    /// Shows the destination host and waits for explicit confirmation —
    /// called instead of pairing immediately for every entry point (deep
    /// link or pasted link), since a crafted link could otherwise silently
    /// repoint the pairing at an attacker server with no warning at all.
    func present(params: DesktopPairingParams) {
        state = .confirming(
            PendingDesktopPairingConfirmation(params: params, existingHost: currentPairedHost)
        )
    }

    private var currentPairedHost: String? {
        guard let session = try? sessionStore.loadSession() else { return nil }
        return URL(string: session.srv)?.host
    }

    func pair(params: DesktopPairingParams) async {
        state = .working
        switch await pairingService.pair(params: params) {
        case .success(let response):
            state = .paired(userEmail: response.userEmail)
        case .invalidOrExpiredCode:
            state = .failed(
                "The pairing code is invalid or expired — codes last 5 minutes. Get a new one from the web app."
            )
        case .codeAlreadyConsumed:
            state = .failed(
                "That pairing code was already used — each code works once. Get a new one from the web app."
            )
        case .rateLimited:
            state = .failed("Too many pairing attempts. Wait an hour, then try again.")
        case .failure(let message):
            state = .failed(message)
        }
    }

    /// Parses a pasted kypost://desktop-pair link and asks for confirmation.
    func pairFromPastedLink() async {
        guard let url = URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)),
              let params = try? DesktopPairingLinkParser.parse(url) else {
            state = .failed("That doesn't look like a valid desktop pairing link.")
            return
        }
        present(params: params)
    }

    func reset() {
        pastedLink = ""
        state = .idle
    }
}
