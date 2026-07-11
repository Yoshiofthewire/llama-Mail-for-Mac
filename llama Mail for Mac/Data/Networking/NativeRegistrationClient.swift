//
//  NativeRegistrationClient.swift
//  llama Mail
//
//  Registers this device's push token with the backend (spec §3).
//  The /register endpoint is provider agnostic: the raw APNs device token is
//  sent directly, no FCM bridging required.
//

import Foundation

struct RegistrationResponse: Decodable, Equatable, Sendable {
    enum DeliveryMode: String, Decodable, Sendable {
        case push
        case pull
    }

    var ok: Bool
    var synced: Bool?
    var deviceId: String?
    var deliveryMode: DeliveryMode?
    /// Optional; derived as {srv}/api/notifications/native/pull if absent (spec §3).
    var pullEndpoint: String?

    func resolvedPullEndpoint(srv: String) -> URL? {
        if let pullEndpoint, !pullEndpoint.isEmpty {
            return URL(string: pullEndpoint)
        }
        return URL(string: srv)?.appending(path: "api/notifications/native/pull")
    }
}

/// Registration result mapped to the spec §3 handling rules.
enum RegistrationOutcome: Equatable, Sendable {
    case success(RegistrationResponse)
    /// 401/403 — show error, prompt re-scan.
    case unauthorized
    /// 503 — persistent error, backend config issue, cannot retry.
    case backendMisconfigured
    case failure(String)
}

final class NativeRegistrationClient: Sendable {
    private struct RegisterRequest: Encodable {
        // ponytail: request body shape is not in the spec — {token, platform}
        // assumed; align with the backend contract before release.
        var token: String
        var platform: String
        var pairingToken: String
    }

    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Registers a push token. Called on first launch, token refresh, pairing
    /// success, and app foreground (spec §3).
    func register(deviceToken: String, params: PairingParams) async -> RegistrationOutcome {
        guard let endpoint = params.registrationEndpoint else {
            return .failure("Invalid registration URL")
        }
#if os(macOS)
        let platform = "macos"
#else
        let platform = "ios"
#endif
        do {
            let response = try await httpClient.post(
                RegistrationResponse.self,
                url: endpoint,
                query: params.auth.queryItems,
                jsonBody: RegisterRequest(
                    token: deviceToken,
                    platform: platform,
                    pairingToken: params.pt
                )
            )
            return .success(response)
        } catch NetworkError.unauthorized {
            return .unauthorized
        } catch NetworkError.serviceUnavailable {
            return .backendMisconfigured
        } catch {
            return .failure("\(error)")
        }
    }
}
