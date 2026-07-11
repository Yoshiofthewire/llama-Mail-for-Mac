//
//  SendEmailUseCase.swift
//  llama Mail
//
//  Validates and sends an outgoing email (spec §7). On failure the compose UI
//  shows a toast and keeps the draft in memory (no DB auto-save).
//

import Foundation

struct SendEmailUseCase {
    private let repository: MailRepository

    init(repository: MailRepository) {
        self.repository = repository
    }

    func callAsFunction(_ email: OutgoingEmail) async -> MailOutcome {
        let recipients = (email.to + email.cc + email.bcc)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !recipients.isEmpty else {
            return .invalid("Add at least one recipient")
        }
        guard recipients.allSatisfy(Self.looksLikeEmailAddress) else {
            return .invalid("Check the recipient addresses")
        }
        return await repository.send(email)
    }

    /// Minimal shape check (one @, non-empty local part, dot in domain) —
    /// real validation is the mail server's job.
    static func looksLikeEmailAddress(_ address: String) -> Bool {
        let parts = address.split(separator: "@")
        guard parts.count == 2 else { return false }
        return !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }
}
