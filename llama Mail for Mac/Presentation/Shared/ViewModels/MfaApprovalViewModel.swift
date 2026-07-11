//
//  MfaApprovalViewModel.swift
//  llama Mail
//
//  In-app MFA approval fallback (spec §5) — same use case as the
//  notification action buttons.
//

import Foundation
import Observation

@Observable
@MainActor
final class MfaApprovalViewModel {
    enum State: Equatable {
        case pending
        case sending
        case done(String)
        case failed(String)
    }

    let challengeId: String
    private let approveMfaChallenge: ApproveMfaChallengeUseCase

    private(set) var state: State = .pending

    init(challengeId: String, approveMfaChallenge: ApproveMfaChallengeUseCase) {
        self.challengeId = challengeId
        self.approveMfaChallenge = approveMfaChallenge
    }

    func respond(approved: Bool) async {
        state = .sending
        let outcome = await approveMfaChallenge(challengeId: challengeId, approved: approved)
        switch outcome {
        case .success:
            state = .done(approved ? "Sign-in approved" : "Sign-in denied")
        case .rejected:
            state = .failed("The server rejected this response — the challenge may have expired.")
        case .failure(let message):
            state = .failed("\(message) — try again.")
        }
    }
}
