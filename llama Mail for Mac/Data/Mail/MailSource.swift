//
//  MailSource.swift
//  llama Mail
//
//  Abstraction over the mail backend. Relay is the only transport
//  (IMAP was dropped); the protocol remains so the transport stays swappable.
//

import Foundation

/// Message ids are Strings (`Email.serverId`) — relay ids.
protocol MailSource: Sendable {
    func listFolders() async throws -> [MailFolder]
    func fetchEmails(folder: String, from: Int, to: Int) async throws -> [Email]
    func search(folder: String, query: String) async throws -> [String]
    func setKeywords(folder: String, messageId: String, keywords: [String]) async throws
    func send(email: OutgoingEmail) async throws
}

/// Mail-layer failures that aren't plain network errors.
enum MailSourceError: Error, Equatable {
    /// No pairing stored — the user must pair the device first.
    case notPaired
    /// The relay has no endpoint for this operation (e.g. server-side search).
    case unsupported
    case invalidServerURL
}

/// User-facing result of a mail operation (spec §11 relay response mapping).
enum MailOutcome: Equatable, Sendable {
    case success
    /// Recipients/fields invalid before any network call.
    case invalid(String)
    /// Credentials rejected — re-pair the device.
    case unauthorized
    case notPaired
    case failure(String)

    static func from(_ error: Error) -> MailOutcome {
        switch error {
        case NetworkError.unauthorized:
            .unauthorized
        case MailSourceError.notPaired:
            .notPaired
        default:
            .failure("\(error)")
        }
    }
}
