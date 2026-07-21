//
//  DeepLinkHandler.swift
//  llama Mail
//
//  Deep-link parsing and routing (spec §1, §10). Binding contract: the pairing
//  scheme is exactly kypost://native-pair with required params
//  sub, srv, pt and optional reg. There is no credential in the link itself —
//  the per-device pairing secret is issued only via the registration
//  response, never carried in the deep link/QR.
//

import Foundation

/// Parameters carried by a pairing deep link / QR code.
struct PairingParams: Equatable, Sendable {
    var sub: String
    /// Relay server URL; becomes Pairing.srv, never edited by the user.
    var srv: String
    /// Pairing token.
    var pt: String
    /// Optional registration URL override.
    var reg: String?

    /// Registration endpoint: `reg` override wins, otherwise derived from srv
    /// (mirrors the pull-endpoint derivation rule in spec §3).
    var registrationEndpoint: URL? {
        if let reg, !reg.isEmpty {
            return URL(string: reg)
        }
        return URL(string: srv)?.appending(path: "api/notifications/native/register")
    }
}

enum PairingLinkError: Error, Equatable {
    case notAPairingLink
    case missingParameter(String)
    /// `srv`/`reg` must be `https` — the pairing exchange sends the device's
    /// real push token and (on success) mints the per-device secret, so a
    /// plaintext destination could have both intercepted in transit.
    case insecureServerURL
}

enum PairingLinkParser {
    /// Parses and validates a pairing link. All required params must be
    /// present and non-empty (spec §1), and `srv`/`reg` must be `https` URLs
    /// (mirrors the same check already applied to the PGP QR-key flow in
    /// PgpQrClient.keyURL(fromScannedPayload:)).
    static func parse(_ url: URL) throws -> PairingParams {
        guard
            url.scheme?.lowercased() == Config.deepLinkScheme,
            url.host()?.lowercased() == Config.pairingHost
        else {
            throw PairingLinkError.notAPairingLink
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = (components?.queryItems ?? []).reduce(into: [String: String]()) {
            $0[$1.name] = $1.value
        }

        func required(_ name: String) throws -> String {
            guard let value = query[name], !value.isEmpty else {
                throw PairingLinkError.missingParameter(name)
            }
            return value
        }

        let srv = try required("srv")
        guard URL(string: srv)?.scheme?.lowercased() == "https" else {
            throw PairingLinkError.insecureServerURL
        }
        let reg = query["reg"].flatMap { $0.isEmpty ? nil : $0 }
        if let reg, URL(string: reg)?.scheme?.lowercased() != "https" {
            throw PairingLinkError.insecureServerURL
        }

        return PairingParams(
            sub: try required("sub"),
            srv: srv,
            pt: try required("pt"),
            reg: reg
        )
    }
}

/// Parameters carried by a desktop pairing deep link (Desktop Pairing guide).
struct DesktopPairingParams: Equatable, Sendable {
    /// One-time pairing code: 32 characters, 5-minute TTL, single use.
    var code: String
    /// Server base URL from the `srv` param.
    var srv: String

    /// Registration endpoint, derived from srv per the guide's Step 3.
    var registerEndpoint: URL? {
        URL(string: srv)?.appending(path: "api/notifications/desktop/register")
    }
}

enum DesktopPairingLinkParser {
    /// Parses kypost://desktop-pair?code=…&srv=… links. Both params are
    /// required and non-empty, and `srv` must be an `https` URL (see
    /// PairingLinkError.insecureServerURL).
    static func parse(_ url: URL) throws -> DesktopPairingParams {
        guard
            url.scheme?.lowercased() == Config.deepLinkScheme,
            url.host()?.lowercased() == Config.desktopPairingHost
        else {
            throw PairingLinkError.notAPairingLink
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = (components?.queryItems ?? []).reduce(into: [String: String]()) {
            $0[$1.name] = $1.value
        }

        guard let code = query["code"], !code.isEmpty else {
            throw PairingLinkError.missingParameter("code")
        }
        guard let srv = query["srv"], !srv.isEmpty else {
            throw PairingLinkError.missingParameter("srv")
        }
        guard URL(string: srv)?.scheme?.lowercased() == "https" else {
            throw PairingLinkError.insecureServerURL
        }
        return DesktopPairingParams(code: code, srv: srv)
    }
}

/// Where a deep link or notification tap should take the user (spec §10).
enum NavigationAction: Equatable, Sendable {
    case openPairingFlow(PairingParams)
    case openDesktopPairingFlow(DesktopPairingParams)
    case openEmail(messageId: String)
    case openMfaApproval(challengeId: String)
}

struct DeepLinkHandler: Sendable {
    /// Nonisolated so `DeepLinkHandler()` can appear as a default argument
    /// (evaluated in a nonisolated context) without an isolation hop.
    nonisolated init() {}

    /// Maps an incoming URL to a navigation action; nil for unrecognized URLs.
    func handle(_ url: URL) -> NavigationAction? {
        if let params = try? PairingLinkParser.parse(url) {
            return .openPairingFlow(params)
        }
        if let params = try? DesktopPairingLinkParser.parse(url) {
            return .openDesktopPairingFlow(params)
        }
        return nil
    }
}
