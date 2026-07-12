//
//  HTTPClient.swift
//  llama Mail
//
//  URLSession wrapper (spec Phase 2, OkHttp equivalent). Centralizes the
//  sub/hash query-param auth and HTTP status → error mapping so every client
//  shares one failure model (Ponytail principle #4).
//

import Foundation

/// Shared failure model for all backend calls.
enum NetworkError: Error, Equatable {
    case invalidURL
    /// 401/403 — pairing credentials rejected; prompt re-scan (spec §3).
    case unauthorized
    /// 409 — backend rejected the request state (e.g. expired MFA challenge).
    case conflict
    /// 429 — rate limited (e.g. too many desktop pairing attempts); wait, then retry.
    case rateLimited
    /// 503 — backend config issue; persistent error, cannot retry (spec §3).
    case serviceUnavailable
    case server(statusCode: Int)
    case transport(description: String)
    case decoding(description: String)

    /// Maps a non-2xx HTTP status to its error. 2xx returns nil.
    static func from(statusCode: Int) -> NetworkError? {
        switch statusCode {
        case 200..<300: nil
        case 401, 403: .unauthorized
        case 409: .conflict
        case 429: .rateLimited
        case 503: .serviceUnavailable
        default: .server(statusCode: statusCode)
        }
    }
}

/// Relay auth credentials, sent as query params on every request (spec §2).
struct RelayAuth: Equatable, Sendable {
    var sub: String
    var hash: String

    init(sub: String, hash: String) {
        self.sub = sub
        self.hash = hash
    }

    init(pairing: Pairing) {
        self.init(sub: pairing.sub, hash: pairing.hash)
    }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "sub", value: sub), URLQueryItem(name: "hash", value: hash)]
    }
}

final class HTTPClient: Sendable {
    /// Injectable transport so clients are unit-testable without a network.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        transport = { try await session.data(for: $0) }
    }

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    // MARK: - Requests

    func get<Response: Decodable>(
        _ type: Response.Type,
        url: URL,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Response {
        var request = URLRequest(url: try url.appending(queryOrThrow: query))
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return try await decode(execute(request))
    }

    /// GET returning the raw response body (attachment downloads).
    func getData(
        url: URL,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: try url.appending(queryOrThrow: query))
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return try await execute(request)
    }

    func post<Response: Decodable>(
        _ type: Response.Type,
        url: URL,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        jsonBody: some Encodable
    ) async throws -> Response {
        var request = URLRequest(url: try url.appending(queryOrThrow: query))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            request.httpBody = try encoder.encode(jsonBody)
        } catch {
            throw NetworkError.decoding(description: "Encoding request body: \(error)")
        }
        return try await decode(execute(request))
    }

    // MARK: - Private

    private func execute(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transport(description: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.transport(description: "Non-HTTP response")
        }
        if let error = NetworkError.from(statusCode: http.statusCode) {
            throw error
        }
        return data
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NetworkError.decoding(description: "\(error)")
        }
    }
}

extension URL {
    /// Appends query items, preserving any existing ones.
    func appending(queryOrThrow items: [URLQueryItem]) throws -> URL {
        guard !items.isEmpty else { return self }
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        components.queryItems = (components.queryItems ?? []) + items
        guard let url = components.url else { throw NetworkError.invalidURL }
        return url
    }
}
