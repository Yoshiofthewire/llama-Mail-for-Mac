//
//  MfaChallenge.swift
//  llama Mail
//
//  Domain model for an MFA push approval challenge (spec §5).
//  Payload contract: { type: "mfa_challenge", challengeId: "..." }.
//  Sensitive data: do NOT store challenge secret/token longer than needed.
//

import Foundation

struct MfaChallenge: Identifiable, Hashable, Sendable {
    static let payloadType = "mfa_challenge"

    var challengeId: String
    var receivedAt: Date

    var id: String { challengeId }
}
