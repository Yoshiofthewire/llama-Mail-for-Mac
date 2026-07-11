//
//  MfaResponseClient.swift
//  llama Mail
//
//  Sends MFA approve/deny responses (spec §5).
//  POST {srv}/api/mfa/push/respond?sub=&hash=  body: {challengeId, approved}
//

import Foundation

/// Result mapped to the spec §5 handling rules.
enum MfaResponseOutcome: Equatable, Sendable {
    /// 200 — close the notification.
    case success
    /// 403/409 — backend rejection; show a toast explaining why.
    case rejected
    /// Network error — offer retry.
    case failure(String)
}

final class MfaResponseClient: Sendable {
    private struct RespondRequest: Encodable {
        var challengeId: String
        var approved: Bool
    }

    private struct RespondResponse: Decodable {
        var ok: Bool?
    }

    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func respond(
        serverUrl: String,
        auth: RelayAuth,
        challengeId: String,
        approved: Bool
    ) async -> MfaResponseOutcome {
        guard let endpoint = URL(string: serverUrl)?.appending(path: "api/mfa/push/respond") else {
            return .failure("Invalid server URL")
        }
        do {
            _ = try await httpClient.post(
                RespondResponse.self,
                url: endpoint,
                query: auth.queryItems,
                jsonBody: RespondRequest(challengeId: challengeId, approved: approved)
            )
            return .success
        } catch NetworkError.unauthorized, NetworkError.conflict {
            return .rejected
        } catch {
            return .failure("\(error)")
        }
    }
}
