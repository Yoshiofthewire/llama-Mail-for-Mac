//
//  DesktopSessionStore.swift
//  llama Mail
//
//  Keychain-backed store for the desktop pairing session (Desktop Pairing
//  guide checklist: token lives only in the credential store, never in logs).
//

import Foundation

/// Session established by exchanging a desktop pairing code for a token.
struct DesktopSession: Equatable, Sendable {
    var sessionToken: String
    var expiresAt: Date
    var userId: String?
    var userEmail: String?
    /// Server base URL the session was established against.
    var srv: String
    var pairedAt: Date

    var isExpired: Bool {
        expiresAt <= Date()
    }

    /// Guide Step 4: authenticated requests send Authorization: Bearer <token>.
    var authorizationHeaders: [String: String] {
        ["Authorization": "Bearer \(sessionToken)"]
    }
}

final class DesktopSessionStore: Sendable {
    private enum Key {
        static let sessionToken = "desktopSessionToken"
        static let expiresAtTimestamp = "desktopSessionExpiresAt"
        static let userId = "desktopSessionUserId"
        static let userEmail = "desktopSessionUserEmail"
        static let srv = "desktopSessionSrv"
        static let pairedAtTimestamp = "desktopSessionPairedAt"
        static let all = [
            sessionToken, expiresAtTimestamp, userId, userEmail, srv, pairedAtTimestamp,
        ]
    }

    private let keychain: KeychainStorage

    init(keychain: KeychainStorage) {
        self.keychain = keychain
    }

    func saveSession(_ session: DesktopSession) throws {
        try keychain.set(session.sessionToken, forKey: Key.sessionToken)
        try keychain.set(
            String(session.expiresAt.timeIntervalSince1970),
            forKey: Key.expiresAtTimestamp
        )
        try keychain.set(session.srv, forKey: Key.srv)
        try keychain.set(
            String(session.pairedAt.timeIntervalSince1970),
            forKey: Key.pairedAtTimestamp
        )
        if let userId = session.userId {
            try keychain.set(userId, forKey: Key.userId)
        } else {
            try keychain.remove(Key.userId)
        }
        if let userEmail = session.userEmail {
            try keychain.set(userEmail, forKey: Key.userEmail)
        } else {
            try keychain.remove(Key.userEmail)
        }
    }

    /// Returns nil unless token, expiry, and srv are all present.
    func loadSession() throws -> DesktopSession? {
        guard
            let token = try keychain.string(forKey: Key.sessionToken), !token.isEmpty,
            let srv = try keychain.string(forKey: Key.srv), !srv.isEmpty,
            let expiresAt = try keychain.string(forKey: Key.expiresAtTimestamp)
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
        else { return nil }

        let pairedAt = try keychain.string(forKey: Key.pairedAtTimestamp)
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:)) ?? .distantPast

        return DesktopSession(
            sessionToken: token,
            expiresAt: expiresAt,
            userId: try keychain.string(forKey: Key.userId),
            userEmail: try keychain.string(forKey: Key.userEmail),
            srv: srv,
            pairedAt: pairedAt
        )
    }

    /// Stored session, or nil if missing or expired. Expired sessions are
    /// cleared so stale tokens never linger in the Keychain (guide checklist:
    /// handle token expiration gracefully).
    func activeSession() -> DesktopSession? {
        guard let session = try? loadSession() else { return nil }
        if session.isExpired {
            try? clear()
            return nil
        }
        return session
    }

    func clear() throws {
        for key in Key.all {
            try keychain.remove(key)
        }
    }
}
