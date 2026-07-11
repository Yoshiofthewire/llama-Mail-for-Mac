//
//  PushRepository.swift
//  llama Mail
//
//  Notification history + pull-mode polling (spec §3). De-duplication is by
//  strictly-increasing seq; the cursor advances to max(last, response.cursor)
//  only after notifications are handed off.
//

import Foundation

final class PushRepository {
    private let dao: PushNotificationDAO
    private let cursorStore: NotificationCursorStore
    private let client: PushNotificationClient
    private let securePairingStore: SecurePairingStore
    private let pushSettingsStore: PushSettingsStore

    init(
        dao: PushNotificationDAO,
        cursorStore: NotificationCursorStore,
        client: PushNotificationClient,
        securePairingStore: SecurePairingStore,
        pushSettingsStore: PushSettingsStore
    ) {
        self.dao = dao
        self.cursorStore = cursorStore
        self.client = client
        self.securePairingStore = securePairingStore
        self.pushSettingsStore = pushSettingsStore
    }

    // MARK: - History

    func history(limit: Int = 50) async throws -> [PushNotification] {
        try await dao.listHistory(limit: limit)
    }

    func markRead(seq: Int) async throws {
        try await dao.markRead(seq: seq)
    }

    /// Records a push-mode arrival. Push payloads carry no server seq, so one
    /// is synthesized from the arrival time (ms epoch), bumped on collision.
    @discardableResult
    func recordPushArrival(
        _ payload: MailPushPayload,
        receivedAt: Date = Date()
    ) async throws -> PushNotification {
        var seq = Int(receivedAt.timeIntervalSince1970 * 1000)
        var notification = payload.toNotification(seq: seq, receivedAt: receivedAt)
        while try await !dao.insert(notification: notification) {
            seq += 1
            notification.seq = seq
        }
        return notification
    }

    // MARK: - Pull mode

    /// One poll of the pull endpoint. Returns the newly delivered
    /// notifications (already persisted to history).
    @discardableResult
    func pullOnce() async throws -> [PushNotification] {
        guard let pairing = try securePairingStore.loadPairing() else {
            throw MailSourceError.notPaired
        }
        guard let endpoint = resolvePullEndpoint(srv: pairing.srv) else {
            throw NetworkError.invalidURL
        }

        let lastCursor = cursorStore.lastCursor
        let response = try await client.pull(
            endpoint: endpoint,
            auth: RelayAuth(pairing: pairing),
            after: lastCursor
        )

        var delivered: [PushNotification] = []
        for dto in response.notifications where dto.seq > lastCursor {
            let notification = dto.toDomain()
            if try await dao.insert(notification: notification) {
                delivered.append(notification)
            }
        }

        // Hand-off complete; only now advance the cursor (spec §3).
        cursorStore.advance(to: response.cursor)
        return delivered
    }

    // MARK: - Private

    private func resolvePullEndpoint(srv: String) -> URL? {
        if let stored = pushSettingsStore.pullEndpoint, let url = URL(string: stored) {
            return url
        }
        return URL(string: srv)?.appending(path: "api/notifications/native/pull")
    }
}
