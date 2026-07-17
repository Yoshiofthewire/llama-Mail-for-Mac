//
//  PushPairingViewModel.swift
//  llama Mail
//
//  Pairing flow state (spec §1). Links arrive via deep link or pasted text;
//  ponytail: camera QR scanning is v2 — deep links and paste cover pairing
//  until AVFoundation scanning is added.
//

import Foundation
import Observation

@Observable
@MainActor
final class PushPairingViewModel {
    enum State: Equatable {
        case idle
        case working
        case paired(deviceId: String?)
        case failed(String)
    }

    private let registrationService: DeviceRegistrationService
    private let pushSettingsStore: PushSettingsStore

    private(set) var state: State = .idle
    var pastedLink = ""

    init(
        registrationService: DeviceRegistrationService,
        pushSettingsStore: PushSettingsStore
    ) {
        self.registrationService = registrationService
        self.pushSettingsStore = pushSettingsStore
    }

    func pair(params: PairingParams) async {
        state = .working
        // Simulators never receive an APNs token; register with a placeholder
        // so pairing still completes (pull mode works without APNs).
        let token = pushSettingsStore.lastDeviceToken ?? "no-apns-token"
        let outcome = await registrationService.pair(params: params, deviceToken: token)
        switch outcome {
        case .success(let response):
            state = .paired(deviceId: response.deviceId)
        case .unauthorized:
            state = .failed("The server rejected the pairing — re-scan the QR code.")
        case .backendMisconfigured:
            state = .failed("The server is not configured for native pairing (503).")
        case .failure(let message):
            state = .failed(message)
        }
    }

    /// Pairs from a pasted llamalabels://native-pair link.
    func pairFromPastedLink() async {
        guard let url = URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)),
              let params = try? PairingLinkParser.parse(url) else {
            state = .failed("That doesn't look like a valid pairing link.")
            return
        }
        await pair(params: params)
    }

    /// Pairs from a scanned QR code containing a llamalabels://native-pair link.
    func pairFromScannedCode(_ payload: String) async {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let params = try? PairingLinkParser.parse(url) else {
            state = .failed("That QR code isn't a KyPost pairing code.")
            return
        }
        await pair(params: params)
    }

    /// Back to the scan/paste screen after a failure.
    func reset() {
        pastedLink = ""
        state = .idle
    }
}
