//
//  PgpQrClient.swift
//  llama Mail
//
//  In-person PGP public-key exchange over QR (Client_PGP_Update.md), verified
//  against the backend source 2026-07-15
//  (llama-labels backend/internal/api/pgp_qr_handlers.go, server.go:238-239):
//    Mint: GET {srv}/api/pgp/qr/token   — session-authenticated (withAuth)
//    Pick: GET {url from token}?t=…     — NO middleware; the ?t= token is the
//                                         only gate, so it works unauthenticated
//
//  Error mapping deliberately stays in the ViewModels rather than here:
//  NetworkError collapses 401/403 into .unauthorized and leaves 400/404 as
//  .server(statusCode:), which is lossy in general but unambiguous per
//  endpoint — /token can return 401 but never 403, and /key can return 403 but
//  never 401 (it has no auth to fail). See PgpQrViewModel.
//

import Foundation

/// Response of GET /api/pgp/qr/token: a short-lived (2 minute) pickup URL to
/// render as a QR code.
struct PgpQrTokenResponse: Decodable, Equatable, Sendable {
    var token: String
    /// RFC3339, as formatted by the backend's `expiresAt.Format(time.RFC3339)`.
    var expiresAt: String
    /// Absolute pickup URL — the string that goes into the QR code.
    var url: String

    /// Parsed `expiresAt`, or nil if the server sent something unparseable.
    /// Go's RFC3339 omits fractional seconds, but tolerate them either way.
    var expiresAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: expiresAt)
    }
}

/// Response of GET /api/pgp/qr/key?t=… — the scanned person's public key.
struct PgpQrKeyResponse: Decodable, Equatable, Sendable {
    /// Backend sends the account's username here.
    var name: String
    var fingerprint: String
    /// Armored ASCII public key, stored verbatim on `Contact.pgpKey`.
    var publicKey: String
}

final class PgpQrClient: Sendable {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// GET {srv}/api/pgp/qr/token — mints a 2-minute pickup token for this
    /// account's own key.
    ///
    /// Takes `DesktopSession.authorizationHeaders` (Bearer) per the documented
    /// contract. ⚠️ Today's backend has no Bearer handling at all — `currentUser`
    /// reads only the `llama_session` cookie — so this always 401s until the
    /// backend ships it. MyPgpQrViewModel renders that as `.sessionExpired`.
    ///
    /// Errors: 401 credentials rejected, 400 no PGP identity on the account,
    /// 503 pairing secret unset server-side.
    func fetchToken(
        serverUrl: String,
        headers: [String: String]
    ) async throws -> PgpQrTokenResponse {
        guard let base = URL(string: serverUrl) else {
            throw NetworkError.invalidURL
        }
        return try await httpClient.get(
            PgpQrTokenResponse.self,
            url: base.appending(path: "api/pgp/qr/token"),
            headers: headers
        )
    }

    /// GET of a scanned pickup URL, verbatim — the `?t=` token is already in it
    /// and is the endpoint's only credential, so no auth is attached.
    ///
    /// Errors: 403 token expired or invalid, 404 that account has no PGP
    /// identity, 400 missing `t`, 503 pairing secret unset server-side.
    func fetchKey(from url: URL) async throws -> PgpQrKeyResponse {
        try await httpClient.get(PgpQrKeyResponse.self, url: url)
    }

    /// Validates a scanned QR payload as a key-pickup URL before any network
    /// call, so a QR code from anything else fails fast and locally.
    ///
    /// Requires https (the token is a bearer credential in the query string),
    /// the `/api/pgp/qr/key` path, and a non-empty `t`. The host is deliberately
    /// not pinned to the paired server: the whole point is scanning someone
    /// else's code, and they may be on a different llama-labels instance.
    static func keyURL(fromScannedPayload payload: String) -> URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.path.hasSuffix("/api/pgp/qr/key"),
            let token = components.queryItems?.first(where: { $0.name == "t" })?.value,
            !token.isEmpty,
            let url = components.url
        else { return nil }
        return url
    }
}
