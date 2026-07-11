//
//  ContactSyncClient.swift
//  llama Mail
//
//  Contact sync, matching the Android reference ContactSyncClient.kt /
//  ContactSyncModels.kt (Mobile_Contact_Sync.md) and verified against the
//  live backend 2026-07-10:
//    Pull: GET  {srv}/api/contacts/sync?sub&hash&since=N
//    Push: POST {srv}/api/contacts/sync?sub&hash  body {baseCursor, changes}
//  Both return {cursor, tooOld, changed: [...], deleted: [...]}.
//

import Foundation

/// A labeled value (email address or phone number) on a contact.
struct ContactFieldDTO: Codable, Equatable, Sendable {
    var label: String?
    var value: String
}

/// Matches Mobile_Contact_Sync.md's Contact JSON. Fields the iOS model does
/// not carry (org, addresses, …) are omitted; JSON decoding ignores them.
struct ContactDTO: Codable, Equatable, Sendable {
    /// Empty string marks a create on push (Android contract); server-assigned
    /// on responses.
    var uid: String?
    var rev: Int?
    var deleted: Bool?
    /// Full display name.
    var fn: String?
    var emails: [ContactFieldDTO]?
    var phones: [ContactFieldDTO]?

    var primaryEmail: String { emails?.first?.value ?? "" }
    var primaryPhone: String { phones?.first?.value ?? "" }
}

struct ContactSyncPushRequest: Encodable, Sendable {
    var baseCursor: Int
    var changes: [ContactDTO]
}

struct ContactSyncPullResponse: Decodable, Equatable, Sendable {
    var cursor: Int
    /// True when `since` predates the server's history window — discard the
    /// cursor and local cache, then re-pull from 0.
    var tooOld: Bool?
    var changed: [ContactDTO]?
    var deleted: [ContactDTO]?
}

final class ContactSyncClient: Sendable {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Pulls server changes after `since`; used when no local changes are queued.
    func pull(
        serverUrl: String,
        auth: RelayAuth,
        since: Int
    ) async throws -> ContactSyncPullResponse {
        try await httpClient.get(
            ContactSyncPullResponse.self,
            url: try endpoint(serverUrl),
            query: auth.queryItems + [
                URLQueryItem(name: "since", value: String(max(since, 0)))
            ]
        )
    }

    /// Pushes queued local changes; the response carries the same delta shape
    /// as a pull, including the server's copy of the pushed contacts.
    func push(
        serverUrl: String,
        auth: RelayAuth,
        baseCursor: Int,
        changes: [ContactDTO]
    ) async throws -> ContactSyncPullResponse {
        try await httpClient.post(
            ContactSyncPullResponse.self,
            url: try endpoint(serverUrl),
            query: auth.queryItems,
            jsonBody: ContactSyncPushRequest(baseCursor: baseCursor, changes: changes)
        )
    }

    private func endpoint(_ serverUrl: String) throws -> URL {
        guard let url = URL(string: serverUrl) else {
            throw NetworkError.invalidURL
        }
        return url.appending(path: "api/contacts/sync")
    }
}
