//
//  SecurePairingStore.swift
//  llama Mail
//
//  Keychain-backed store for relay pairing credentials (spec §1).
//  Keys are a binding contract: sub, deviceSecret, srv, registrationUrl,
//  pairingToken, lastDeviceId, pairedAtTimestamp.
//

import Foundation

/// Credentials produced by a successful native-pair registration.
struct Pairing: Equatable, Sendable {
    var sub: String
    /// Per-device pairing secret, minted once at registration and returned
    /// only in that response — never carried in the pairing deep link/QR.
    /// May be empty for a pairing created before this field existed
    /// (pre-migration); that's not an error, see DeregisterDeviceUseCase.
    var deviceSecret: String
    /// Relay server URL; sourced from pairing, never edited by the user.
    var srv: String
    var registrationUrl: String?
    var pairingToken: String
    var lastDeviceId: String?
    var pairedAt: Date
}

final class SecurePairingStore: Sendable {
    private enum Key {
        static let sub = "sub"
        static let deviceSecret = "deviceSecret"
        static let srv = "srv"
        static let registrationUrl = "registrationUrl"
        static let pairingToken = "pairingToken"
        static let lastDeviceId = "lastDeviceId"
        static let pairedAtTimestamp = "pairedAtTimestamp"
        static let all = [sub, deviceSecret, srv, registrationUrl, pairingToken, lastDeviceId, pairedAtTimestamp]
    }

    private let keychain: KeychainStorage

    init(keychain: KeychainStorage) {
        self.keychain = keychain
    }

    func savePairing(_ pairing: Pairing) throws {
        try keychain.set(pairing.sub, forKey: Key.sub)
        try keychain.set(pairing.deviceSecret, forKey: Key.deviceSecret)
        try keychain.set(pairing.srv, forKey: Key.srv)
        try keychain.set(pairing.pairingToken, forKey: Key.pairingToken)
        try keychain.set(
            String(pairing.pairedAt.timeIntervalSince1970),
            forKey: Key.pairedAtTimestamp
        )
        if let registrationUrl = pairing.registrationUrl {
            try keychain.set(registrationUrl, forKey: Key.registrationUrl)
        } else {
            try keychain.remove(Key.registrationUrl)
        }
        if let lastDeviceId = pairing.lastDeviceId {
            try keychain.set(lastDeviceId, forKey: Key.lastDeviceId)
        } else {
            try keychain.remove(Key.lastDeviceId)
        }
    }

    /// Returns nil unless all required fields (sub, srv, pairingToken) are
    /// present. deviceSecret is deliberately NOT required: a pairing saved
    /// before that field existed must still load as "paired" (with an empty
    /// secret) rather than silently reading as unpaired.
    func loadPairing() throws -> Pairing? {
        guard
            let sub = try keychain.string(forKey: Key.sub), !sub.isEmpty,
            let srv = try keychain.string(forKey: Key.srv), !srv.isEmpty,
            let pairingToken = try keychain.string(forKey: Key.pairingToken), !pairingToken.isEmpty
        else { return nil }

        let pairedAt = try keychain.string(forKey: Key.pairedAtTimestamp)
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:)) ?? .distantPast

        return Pairing(
            sub: sub,
            deviceSecret: try keychain.string(forKey: Key.deviceSecret) ?? "",
            srv: srv,
            registrationUrl: try keychain.string(forKey: Key.registrationUrl),
            pairingToken: pairingToken,
            lastDeviceId: try keychain.string(forKey: Key.lastDeviceId),
            pairedAt: pairedAt
        )
    }

    var isPaired: Bool {
        (try? loadPairing()) != nil
    }

    func clear() throws {
        for key in Key.all {
            try keychain.remove(key)
        }
    }
}
