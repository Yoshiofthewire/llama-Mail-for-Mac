//
//  NativeRegistrationClient.swift
//  llama Mail
//
//  Registers this device's push token with the backend (spec §3).
//  The /register endpoint is provider agnostic: the raw APNs device token is
//  sent directly, no FCM bridging required.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
        // Binding contract (backend nativeRegisterRequest in server.go):
        // subscriberId, pairingToken, and deviceToken are required (400 if
        // missing); platform, deviceName, and deviceId are optional.
        // deviceName is what the server's paired-device list displays —
        // without it the UI falls back to platform, and unknown platforms
        // normalize to "android". deviceId makes the server update the
        // existing device row instead of appending a duplicate; omitted on
        // first pairing (the server mints one).
        var subscriberId: String
        var pairingToken: String
        var deviceToken: String
        var deviceId: String?
        var platform: String
        var deviceName: String
    }

    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Registers a push token. Called on first launch, token refresh, pairing
    /// success, and app foreground (spec §3). Pass the stored deviceId when
    /// re-registering so the server updates that device instead of adding one.
    func register(
        deviceToken: String,
        params: PairingParams,
        deviceId: String? = nil
    ) async -> RegistrationOutcome {
        guard let endpoint = params.registrationEndpoint else {
            return .failure("Invalid registration URL")
        }
#if os(macOS)
        let platform = "macos"
        let deviceName = Host.current().localizedName ?? "Mac"
#else
        let platform = "ios"
        // Without the user-assigned-device-name entitlement this is the
        // generic model name ("iPhone"), which still beats the platform
        // fallback the server shows otherwise.
        let deviceName = await MainActor.run { UIDevice.current.name }
#endif
        do {
            let response = try await httpClient.post(
                RegistrationResponse.self,
                url: endpoint,
                query: params.auth.queryItems,
                jsonBody: RegisterRequest(
                    subscriberId: params.sub,
                    pairingToken: params.pt,
                    deviceToken: deviceToken,
                    deviceId: deviceId,
                    platform: platform,
                    deviceName: deviceName
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
