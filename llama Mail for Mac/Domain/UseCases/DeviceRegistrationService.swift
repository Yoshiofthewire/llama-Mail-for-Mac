//
//  DeviceRegistrationService.swift
//  llama Mail
//
//  Push token registration flow (spec §3): initial pairing from a QR/deep
//  link, and re-registration on token refresh / app foreground using the
//  stored pairing. On success the pairing and delivery settings are persisted.
//

import Foundation

extension PairingParams {
    /// Rebuilds link params from a stored pairing, for re-registration.
    init(pairing: Pairing) {
        self.init(
            sub: pairing.sub,
            hash: pairing.hash,
            srv: pairing.srv,
            pt: pairing.pairingToken,
            reg: pairing.registrationUrl
        )
    }
}

final class DeviceRegistrationService {
    private let client: NativeRegistrationClient
    private let securePairingStore: SecurePairingStore
    private let pushSettingsStore: PushSettingsStore

    init(
        client: NativeRegistrationClient,
        securePairingStore: SecurePairingStore,
        pushSettingsStore: PushSettingsStore
    ) {
        self.client = client
        self.securePairingStore = securePairingStore
        self.pushSettingsStore = pushSettingsStore
    }

    /// Initial pairing (QR scan / deep link). Persists the pairing and
    /// delivery settings only if registration succeeds (spec §1 flow).
    func pair(params: PairingParams, deviceToken: String) async -> RegistrationOutcome {
        let outcome = await client.register(deviceToken: deviceToken, params: params)
        if case .success(let response) = outcome {
            do {
                try securePairingStore.savePairing(Pairing(
                    sub: params.sub,
                    hash: params.hash,
                    srv: params.srv,
                    registrationUrl: params.reg,
                    pairingToken: params.pt,
                    lastDeviceId: response.deviceId,
                    pairedAt: Date()
                ))
            } catch {
                return .failure("Registered but could not save pairing: \(error)")
            }
            pushSettingsStore.deliveryMode = response.deliveryMode ?? .push
            pushSettingsStore.pullEndpoint = response
                .resolvedPullEndpoint(srv: params.srv)?.absoluteString
        }
        return outcome
    }

    /// Re-registration for safety (token refresh, app foreground, spec §3).
    /// Returns nil when the device was never paired — nothing to refresh.
    @discardableResult
    func reregisterIfPaired(deviceToken: String) async -> RegistrationOutcome? {
        guard let pairing = try? securePairingStore.loadPairing() else { return nil }
        return await pair(params: PairingParams(pairing: pairing), deviceToken: deviceToken)
    }
}
