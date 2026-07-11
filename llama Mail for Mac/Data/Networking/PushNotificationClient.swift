//
//  PushNotificationClient.swift
//  llama Mail
//
//  Pull-mode notification polling (spec §3). Binding contract: payload keys
//  are messageId, senderName, emailSubject, Keywords (capital K); items carry
//  a strictly-increasing seq used for de-duplication.
//

import Foundation

struct PullResponse: Decodable, Equatable, Sendable {
    var notifications: [PullNotificationDTO]
    /// Updated cursor position; persist via NotificationCursorStore.advance
    /// only after notifications are handed off.
    var cursor: Int
}

struct PullNotificationDTO: Decodable, Equatable, Sendable {
    var seq: Int
    var messageId: String
    var senderName: String?
    var emailSubject: String?
    var keywords: [String]?

    private enum CodingKeys: String, CodingKey {
        case seq
        case messageId
        case senderName
        case emailSubject
        // Binding contract with Android: capital K.
        case keywords = "Keywords"
    }
}

// MARK: - Mapping (PayloadMapper equivalent)

extension PullNotificationDTO {
    func toDomain(receivedAt: Date = Date()) -> PushNotification {
        PushNotification(
            seq: seq,
            messageId: messageId,
            senderName: senderName ?? "",
            emailSubject: emailSubject ?? "",
            keywords: keywords ?? [],
            receivedAt: receivedAt,
            read: false
        )
    }
}

final class PushNotificationClient: Sendable {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// GET {pullEndpoint}?sub=&hash=&after={cursor}
    func pull(endpoint: URL, auth: RelayAuth, after cursor: Int) async throws -> PullResponse {
        try await httpClient.get(
            PullResponse.self,
            url: endpoint,
            query: auth.queryItems + [URLQueryItem(name: "after", value: String(cursor))]
        )
    }
}
