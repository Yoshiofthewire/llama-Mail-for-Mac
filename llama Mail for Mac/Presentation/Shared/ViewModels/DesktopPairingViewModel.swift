//
//  DesktopPairingViewModel.swift
//  llama Mail
//
//  Desktop pairing flow state (Desktop Pairing guide). Codes arrive via the
//  llamalabels://desktop-pair deep link, or as a pasted link when the browser
//  could not launch the app.
//

import Foundation
import Observation

@Observable
@MainActor
final class DesktopPairingViewModel {
    enum State: Equatable {
        case idle
        case working
        case paired(userEmail: String?)
        case failed(String)
    }

    private let pairingService: DesktopPairingService

    private(set) var state: State = .idle
    var pastedLink = ""

    init(pairingService: DesktopPairingService) {
        self.pairingService = pairingService
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

    /// Pairs from a pasted llamalabels://desktop-pair link.
    func pairFromPastedLink() async {
        guard let url = URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)),
              let params = try? DesktopPairingLinkParser.parse(url) else {
            state = .failed("That doesn't look like a valid desktop pairing link.")
            return
        }
        await pair(params: params)
    }

    func reset() {
        pastedLink = ""
        state = .idle
    }
}
