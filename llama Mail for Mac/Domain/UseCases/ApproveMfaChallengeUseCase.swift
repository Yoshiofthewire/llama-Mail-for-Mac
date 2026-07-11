//
//  ApproveMfaChallengeUseCase.swift
//  llama Mail
//
//  Responds to an MFA push challenge (spec §5). Used by both the notification
//  action buttons and the in-app MfaApprovalView fallback.
//

import Foundation

struct ApproveMfaChallengeUseCase {
    private let client: MfaResponseClient
    private let securePairingStore: SecurePairingStore

    init(client: MfaResponseClient, securePairingStore: SecurePairingStore) {
        self.client = client
        self.securePairingStore = securePairingStore
    }

    func callAsFunction(challengeId: String, approved: Bool) async -> MfaResponseOutcome {
        guard let pairing = try? securePairingStore.loadPairing() else {
            return .failure("Device is not paired")
        }
        return await client.respond(
            serverUrl: pairing.srv,
            auth: RelayAuth(pairing: pairing),
            challengeId: challengeId,
            approved: approved
        )
    }
}
