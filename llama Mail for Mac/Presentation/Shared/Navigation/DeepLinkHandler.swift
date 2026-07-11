//
//  DeepLinkHandler.swift
//  llama Mail
//
//  Deep-link parsing and routing (spec §1, §10). Binding contract: the pairing
//  scheme is exactly llamalabels://native-pair with required params
//  sub, hash, srv, pt and optional reg.
//

import Foundation

/// Parameters carried by a pairing deep link / QR code.
struct PairingParams: Equatable, Sendable {
    var sub: String
    var hash: String
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

    var auth: RelayAuth {
        RelayAuth(sub: sub, hash: hash)
    }
}

enum PairingLinkError: Error, Equatable {
    case notAPairingLink
    case missingParameter(String)
}

enum PairingLinkParser {
    /// Parses and validates a pairing link. All required params must be
    /// present and non-empty (spec §1).
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

        return PairingParams(
            sub: try required("sub"),
            hash: try required("hash"),
            srv: try required("srv"),
            pt: try required("pt"),
            reg: query["reg"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

/// Where a deep link or notification tap should take the user (spec §10).
enum NavigationAction: Equatable, Sendable {
    case openPairingFlow(PairingParams)
    case openEmail(messageId: String)
    case openMfaApproval(challengeId: String)
}

struct DeepLinkHandler: Sendable {
    /// Maps an incoming URL to a navigation action; nil for unrecognized URLs.
    func handle(_ url: URL) -> NavigationAction? {
        guard let params = try? PairingLinkParser.parse(url) else { return nil }
        return .openPairingFlow(params)
    }
}
