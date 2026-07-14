//
//  NetworkingTests.swift
//  llama Mail for MacTests
//
//  Phase 2 tests: deep-link parsing, endpoint resolution, status mapping,
//  response decoding, and client outcome mapping via a stub transport.
//

import Foundation
import Testing
@testable import llama_Mail_for_Mac

// MARK: - Helpers

/// HTTPClient whose transport returns a canned response; `onRequest` lets
/// tests assert on the outgoing request.
private func stubClient(
    status: Int,
    json: String = "{}",
    onRequest: (@Sendable (URLRequest) -> Void)? = nil
) -> HTTPClient {
    HTTPClient { request in
        onRequest?(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }
}

private let validPairingLink = URL(
    string: "llamalabels://native-pair?sub=user1&hash=abc123&srv=https://relay.example.com&pt=token9"
)!

// MARK: - Pairing link parsing

@Suite struct PairingLinkParserTests {
    @Test func parsesValidLink() throws {
        let params = try PairingLinkParser.parse(validPairingLink)
        #expect(params.sub == "user1")
        #expect(params.hash == "abc123")
        #expect(params.srv == "https://relay.example.com")
        #expect(params.pt == "token9")
        #expect(params.reg == nil)
    }

    @Test func parsesOptionalRegParameter() throws {
        let url = URL(string: validPairingLink.absoluteString + "&reg=https://reg.example.com/custom")!
        let params = try PairingLinkParser.parse(url)
        #expect(params.reg == "https://reg.example.com/custom")
    }

    @Test(arguments: ["sub", "hash", "srv", "pt"])
    func rejectsMissingRequiredParameter(missing: String) {
        let all = ["sub": "u", "hash": "h", "srv": "https://s.example.com", "pt": "p"]
        let query = all
            .filter { $0.key != missing }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let url = URL(string: "llamalabels://native-pair?\(query)")!
        #expect(throws: PairingLinkError.missingParameter(missing)) {
            try PairingLinkParser.parse(url)
        }
    }

    @Test func rejectsEmptyRequiredParameter() {
        let url = URL(string: "llamalabels://native-pair?sub=&hash=h&srv=https://s.example.com&pt=p")!
        #expect(throws: PairingLinkError.missingParameter("sub")) {
            try PairingLinkParser.parse(url)
        }
    }

    @Test func rejectsWrongSchemeOrHost() {
        let wrongScheme = URL(string: "https://native-pair?sub=u&hash=h&srv=s&pt=p")!
        let wrongHost = URL(string: "llamalabels://other-host?sub=u&hash=h&srv=s&pt=p")!
        #expect(throws: PairingLinkError.notAPairingLink) {
            try PairingLinkParser.parse(wrongScheme)
        }
        #expect(throws: PairingLinkError.notAPairingLink) {
            try PairingLinkParser.parse(wrongHost)
        }
    }

    @Test func deepLinkHandlerRoutesPairingLinks() throws {
        let handler = DeepLinkHandler()
        let action = handler.handle(validPairingLink)
        let expected = NavigationAction.openPairingFlow(try PairingLinkParser.parse(validPairingLink))
        #expect(action == expected)
        #expect(handler.handle(URL(string: "https://example.com")!) == nil)
    }
}

// MARK: - Endpoint resolution

@Suite struct EndpointResolutionTests {
    @Test func registrationEndpointDerivedFromSrv() {
        let params = PairingParams(sub: "u", hash: "h", srv: "https://relay.example.com", pt: "p")
        #expect(
            params.registrationEndpoint?.absoluteString
            == "https://relay.example.com/api/notifications/native/register"
        )
    }

    @Test func regParameterOverridesDerivedEndpoint() {
        let params = PairingParams(
            sub: "u", hash: "h", srv: "https://relay.example.com", pt: "p",
            reg: "https://custom.example.com/register"
        )
        #expect(params.registrationEndpoint?.absoluteString == "https://custom.example.com/register")
    }

    @Test func pullEndpointDerivedWhenAbsent() {
        let response = RegistrationResponse(ok: true, deliveryMode: .pull, pullEndpoint: nil)
        #expect(
            response.resolvedPullEndpoint(srv: "https://relay.example.com")?.absoluteString
            == "https://relay.example.com/api/notifications/native/pull"
        )
    }

    @Test func explicitPullEndpointWins() {
        let response = RegistrationResponse(
            ok: true,
            pullEndpoint: "https://pull.example.com/notifications"
        )
        #expect(
            response.resolvedPullEndpoint(srv: "https://relay.example.com")?.absoluteString
            == "https://pull.example.com/notifications"
        )
    }
}

// MARK: - Status mapping

@Suite struct NetworkErrorMappingTests {
    @Test func statusCodeMapping() {
        #expect(NetworkError.from(statusCode: 200) == nil)
        #expect(NetworkError.from(statusCode: 204) == nil)
        #expect(NetworkError.from(statusCode: 401) == .unauthorized)
        #expect(NetworkError.from(statusCode: 403) == .unauthorized)
        #expect(NetworkError.from(statusCode: 409) == .conflict)
        #expect(NetworkError.from(statusCode: 503) == .serviceUnavailable)
        #expect(NetworkError.from(statusCode: 500) == .server(statusCode: 500))
    }
}

// MARK: - Response decoding

@Suite struct ResponseDecodingTests {
    @Test func registrationResponseDecodesSpecSample() async throws {
        // Sample from spec §3.
        let json = """
        {
          "ok": true,
          "synced": true,
          "deviceId": "dev-42",
          "deliveryMode": "push",
          "pullEndpoint": "https://relay.example.com/api/notifications/native/pull"
        }
        """
        let client = stubClient(status: 200, json: json)
        let response = try await client.get(
            RegistrationResponse.self,
            url: URL(string: "https://relay.example.com/register")!
        )
        #expect(response.ok)
        #expect(response.synced == true)
        #expect(response.deviceId == "dev-42")
        #expect(response.deliveryMode == .push)
    }

    @Test func pullResponseDecodesCapitalKKeywords() async throws {
        let json = """
        {
          "notifications": [
            {
              "seq": 7,
              "messageId": "m-7",
              "senderName": "Ada",
              "emailSubject": "Hello",
              "Keywords": ["Important", "Work"]
            }
          ],
          "cursor": 8
        }
        """
        let client = stubClient(status: 200, json: json)
        let response = try await PushNotificationClient(httpClient: client).pull(
            endpoint: URL(string: "https://relay.example.com/api/notifications/native/pull")!,
            auth: RelayAuth(sub: "u", hash: "h"),
            after: 6
        )
        #expect(response.cursor == 8)
        let dto = try #require(response.notifications.first)
        #expect(dto.keywords == ["Important", "Work"])

        let domain = dto.toDomain()
        #expect(domain.seq == 7)
        #expect(domain.messageId == "m-7")
        #expect(domain.keywords == ["Important", "Work"])
        #expect(!domain.read)
    }
}

// MARK: - Client outcome mapping

@Suite struct NativeRegistrationClientTests {
    private let params = PairingParams(sub: "u1", hash: "h1", srv: "https://relay.example.com", pt: "p1")

    @Test func successCarriesResponseAndAuthQuery() async {
        let client = stubClient(status: 200, json: #"{"ok": true, "deviceId": "d1"}"#) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("https://relay.example.com/api/notifications/native/register"))
            #expect(url.contains("sub=u1"))
            #expect(url.contains("hash=h1"))
            #expect(request.httpMethod == "POST")
            // Body fields are a binding contract with the live backend:
            // subscriberId, pairingToken, and deviceToken are required.
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""subscriberId":"u1""#))
            #expect(body.contains(#""pairingToken":"p1""#))
            #expect(body.contains(#""deviceToken":"apns-token""#))
            // deviceName is what the server's paired-device list displays;
            // without it the UI falls back to the platform string.
            #expect(body.contains(#""deviceName":""#))
        }
        let outcome = await NativeRegistrationClient(httpClient: client)
            .register(deviceToken: "apns-token", params: params)
        guard case .success(let response) = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
        #expect(response.deviceId == "d1")
    }

    @Test func unauthorizedPromptsRescan() async {
        let outcome = await NativeRegistrationClient(httpClient: stubClient(status: 403))
            .register(deviceToken: "t", params: params)
        #expect(outcome == .unauthorized)
    }

    @Test func serviceUnavailableIsPersistentError() async {
        let outcome = await NativeRegistrationClient(httpClient: stubClient(status: 503))
            .register(deviceToken: "t", params: params)
        #expect(outcome == .backendMisconfigured)
    }
}

@Suite struct MfaResponseClientTests {
    private let auth = RelayAuth(sub: "u", hash: "h")

    @Test func successOn200() async {
        let client = stubClient(status: 200, json: #"{"ok": true}"#) { request in
            #expect(
                request.url!.absoluteString
                    .hasPrefix("https://relay.example.com/api/mfa/push/respond")
            )
            // Contract: auth and device identity travel in the body, and the
            // boolean field is "approve" (not "approved").
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""challengeId":"c1""#))
            #expect(body.contains(#""subscriberId":"u""#))
            #expect(body.contains(#""subscriberHash":"h""#))
            #expect(body.contains(#""deviceId":"dev-1""#))
            #expect(body.contains(#""approve":true"#))
        }
        let outcome = await MfaResponseClient(httpClient: client).respond(
            serverUrl: "https://relay.example.com",
            auth: auth,
            deviceId: "dev-1",
            challengeId: "c1",
            approved: true
        )
        #expect(outcome == .success)
    }

    @Test(arguments: [403, 409])
    func backendRejectionIsRejected(status: Int) async {
        let outcome = await MfaResponseClient(httpClient: stubClient(status: status)).respond(
            serverUrl: "https://relay.example.com",
            auth: auth,
            deviceId: "dev-1",
            challengeId: "c1",
            approved: false
        )
        #expect(outcome == .rejected)
    }

    @Test func transportErrorIsFailure() async {
        let client = HTTPClient { _ in
            throw URLError(.notConnectedToInternet)
        }
        let outcome = await MfaResponseClient(httpClient: client).respond(
            serverUrl: "https://relay.example.com",
            auth: auth,
            deviceId: "dev-1",
            challengeId: "c1",
            approved: true
        )
        guard case .failure = outcome else {
            Issue.record("Expected failure, got \(outcome)")
            return
        }
    }
}

@Suite struct ContactSyncClientTests {
    @Test func pullSendsSinceAndDecodesResponse() async throws {
        let client = stubClient(
            status: 200,
            json: #"{"cursor": 456, "changed": [{"uid": "srv-1", "rev": 2, "fn": "Ada"}], "deleted": []}"#
        ) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("https://relay.example.com/api/contacts/sync"))
            #expect(url.contains("since=123"))
            #expect(request.httpMethod == "GET")
        }
        let response = try await ContactSyncClient(httpClient: client).pull(
            serverUrl: "https://relay.example.com",
            auth: RelayAuth(sub: "u", hash: "h"),
            since: 123
        )
        #expect(response.cursor == 456)
        #expect(response.changed?.first?.uid == "srv-1")
        #expect(response.changed?.first?.fn == "Ada")
    }

    @Test func pushSendsBaseCursorAndChanges() async throws {
        let client = stubClient(status: 200, json: #"{"cursor": 7}"#) { request in
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""baseCursor":123"#))
            #expect(body.contains(#""fn":"Ada""#))
            #expect(body.contains(#""value":"ada@example.com""#))
        }
        let response = try await ContactSyncClient(httpClient: client).push(
            serverUrl: "https://relay.example.com",
            auth: RelayAuth(sub: "u", hash: "h"),
            baseCursor: 123,
            changes: [ContactDTO(
                uid: "",
                rev: 0,
                deleted: nil,
                fn: "Ada",
                emails: [ContactFieldDTO(label: nil, value: "ada@example.com")],
                phones: []
            )]
        )
        #expect(response.cursor == 7)
    }
}
