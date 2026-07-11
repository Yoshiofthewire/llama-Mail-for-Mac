//
//  DesktopPairingService.swift
//  llama Mail
//
//  Desktop pairing flow (Desktop Pairing guide): validate the one-time code,
//  exchange it for a session token, and persist the session in the Keychain.
//

import Foundation

final class DesktopPairingService {
    private let client: DesktopRegistrationClient
    private let sessionStore: DesktopSessionStore

    init(client: DesktopRegistrationClient, sessionStore: DesktopSessionStore) {
        self.client = client
        self.sessionStore = sessionStore
    }

    /// Guide checklist: validate the code format before sending. The guide
    /// says "32 hex chars" but its own sample codes are alphanumeric, so only
    /// length + alphanumeric are enforced.
    static func isValidCode(_ code: String) -> Bool {
        code.count == Config.desktopPairingCodeLength
            && code.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Exchanges the code for a session token and persists it on success.
    /// Codes are single-use, so a failed exchange is never retried here —
    /// the user gets a fresh code from the web app instead.
    func pair(params: DesktopPairingParams) async -> DesktopRegistrationOutcome {
        guard Self.isValidCode(params.code) else {
            return .failure(
                "Malformed pairing code — expected \(Config.desktopPairingCodeLength) characters."
            )
        }
        let outcome = await client.register(params: params)
        if case .success(let response) = outcome {
            do {
                try sessionStore.saveSession(DesktopSession(
                    sessionToken: response.sessionToken,
                    expiresAt: Date(timeIntervalSinceNow: TimeInterval(response.expiresIn)),
                    userId: response.userId,
                    userEmail: response.userEmail,
                    srv: params.srv,
                    pairedAt: Date()
                ))
            } catch {
                return .failure("Paired, but the session could not be saved: \(error)")
            }
        }
        return outcome
    }

    /// "Forget This Computer" (guide checklist): clears the stored session.
    func unpair() throws {
        try sessionStore.clear()
    }
}
