//
//  DeregisterDeviceUseCase.swift
//  llama Mail
//
//  Removes this device from the account's paired-devices list on the server
//  (spec §1 successor). Best-effort: SettingsViewModel.unpair() clears local
//  pairing state unconditionally regardless of this outcome.
//

import Foundation

struct DeregisterDeviceUseCase {
    private let client: DeregisterClient
    private let securePairingStore: SecurePairingStore

    init(client: DeregisterClient, securePairingStore: SecurePairingStore) {
        self.client = client
        self.securePairingStore = securePairingStore
    }

    /// Skips the network call entirely for a pre-migration pairing with no
    /// stored deviceSecret, or a pairing that never completed registration —
    /// there's nothing valid to authenticate the request with.
    func callAsFunction() async -> DeregisterOutcome {
        guard let pairing = try? securePairingStore.loadPairing(),
              let deviceId = pairing.lastDeviceId, !deviceId.isEmpty,
              !pairing.deviceSecret.isEmpty
        else {
            return .failure("Device is not registered")
        }
        return await client.deregister(serverUrl: pairing.srv, auth: RelayAuth(pairing: pairing))
    }
}
