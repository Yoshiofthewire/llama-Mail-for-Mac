//
//  PushSettingsStore.swift
//  llama Mail
//
//  UserDefaults-backed push delivery configuration (spec §3). Nothing here is
//  sensitive: the delivery mode and pull endpoint come from the registration
//  response; the APNs token is device-scoped and rotates.
//

import Foundation

final class PushSettingsStore {
    private enum Key {
        static let deliveryMode = "push.deliveryMode"
        static let pullEndpoint = "push.pullEndpoint"
        static let systemNotificationsEnabled = "push.systemNotificationsEnabled"
        static let lastDeviceToken = "push.lastDeviceToken"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var deliveryMode: RegistrationResponse.DeliveryMode? {
        get {
            defaults.string(forKey: Key.deliveryMode)
                .flatMap(RegistrationResponse.DeliveryMode.init(rawValue:))
        }
        set {
            defaults.set(newValue?.rawValue, forKey: Key.deliveryMode)
        }
    }

    /// Resolved pull endpoint from the registration response (spec §3).
    var pullEndpoint: String? {
        get { defaults.string(forKey: Key.pullEndpoint) }
        set { defaults.set(newValue, forKey: Key.pullEndpoint) }
    }

    /// User toggle from Settings; payloads are still parsed and saved to
    /// in-app history when off (spec §3 Notification Permission).
    var systemNotificationsEnabled: Bool {
        get { defaults.object(forKey: Key.systemNotificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.systemNotificationsEnabled) }
    }

    /// Latest APNs token, kept for re-registration on foreground/pairing.
    var lastDeviceToken: String? {
        get { defaults.string(forKey: Key.lastDeviceToken) }
        set { defaults.set(newValue, forKey: Key.lastDeviceToken) }
    }
}
