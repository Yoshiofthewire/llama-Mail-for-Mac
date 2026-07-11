//
//  ComposeViewModel.swift
//  llama Mail
//
//  Compose state (spec §7). On failure the draft stays in memory — no DB
//  auto-save.
//

import Foundation
import Observation

@Observable
@MainActor
final class ComposeViewModel {
    private let sendEmail: SendEmailUseCase

    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""

    private(set) var isSending = false
    private(set) var errorMessage: String?
    private(set) var didSend = false

    init(sendEmail: SendEmailUseCase) {
        self.sendEmail = sendEmail
    }

    func send() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        let outcome = await sendEmail(OutgoingEmail(
            to: recipients(from: to),
            cc: recipients(from: cc),
            bcc: recipients(from: bcc),
            subject: subject,
            body: body
        ))
        switch outcome {
        case .success:
            didSend = true
            errorMessage = nil
        case .invalid(let message):
            errorMessage = message
        case .unauthorized:
            errorMessage = "Not authorized — re-pair the device or check credentials."
        case .notPaired:
            errorMessage = "Pair this device before sending."
        case .failure(let message):
            errorMessage = message
        }
    }

    private func recipients(from field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
