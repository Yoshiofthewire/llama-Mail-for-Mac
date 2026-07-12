//
//  DesktopPairingTests.swift
//  llama Mail for MacTests
//
//  Desktop Pairing guide tests: deep-link parsing, endpoint derivation, code
//  format validation, and register outcome mapping via a stub transport.
//

import Foundation
import Testing
@testable import llama_Mail_for_Mac

// MARK: - Helpers

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

/// Sample code from the guide (32 chars, alphanumeric).
private let validCode = "A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6"
private let validDesktopLink = URL(
    string: "llamalabels://desktop-pair?code=\(validCode)&srv=https://relay.example.com"
)!

// MARK: - Register dedupe (one registration per code)

@MainActor
@Suite struct DesktopPairingServiceDedupeTests {
    private final class RequestCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func makeService(counter: RequestCounter) -> DesktopPairingService {
        let json = """
        {"ok": true, "sessionToken": "jwt-token", "expiresIn": 86400, \
        "userId": "u1", "userEmail": "user@example.com"}
        """
        let client = HTTPClient { request in
            counter.increment()
            try? await Task.sleep(for: .milliseconds(10))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(json.utf8), response)
        }
        return DesktopPairingService(
            client: DesktopRegistrationClient(httpClient: client),
            sessionStore: DesktopSessionStore(
                keychain: KeychainStorage(service: "com.urlxl.mail.tests.\(UUID().uuidString)")
            )
        )
    }

    private var params: DesktopPairingParams {
        DesktopPairingParams(code: validCode, srv: "https://relay.example.com")
    }

    /// The deep link is delivered to every open window and each auto-pairs;
    /// concurrent calls with one code must collapse into one registration.
    @Test func concurrentPairsWithSameCodeRegisterOnce() async {
        let counter = RequestCounter()
        let service = makeService(counter: counter)
        async let first = service.pair(params: params)
        async let second = service.pair(params: params)
        let outcomes = await [first, second]
        #expect(counter.count == 1)
        let expected = DesktopRegistrationOutcome.success(DesktopRegistrationResponse(
            ok: true, sessionToken: "jwt-token", expiresIn: 86400,
            userId: "u1", userEmail: "user@example.com"
        ))
        #expect(outcomes == [expected, expected])
    }

    @Test func repeatPairWithSameCodeReusesOutcome() async {
        let counter = RequestCounter()
        let service = makeService(counter: counter)
        let first = await service.pair(params: params)
        let second = await service.pair(params: params)
        #expect(counter.count == 1)
        #expect(first == second)
    }
}

// MARK: - Deep-link parsing

@Suite struct DesktopPairingLinkParserTests {
    @Test func parsesValidLink() throws {
        let params = try DesktopPairingLinkParser.parse(validDesktopLink)
        #expect(params.code == validCode)
        #expect(params.srv == "https://relay.example.com")
    }

    @Test(arguments: ["code", "srv"])
    func rejectsMissingRequiredParameter(missing: String) {
        let all = ["code": validCode, "srv": "https://s.example.com"]
        let query = all
            .filter { $0.key != missing }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let url = URL(string: "llamalabels://desktop-pair?\(query)")!
        #expect(throws: PairingLinkError.missingParameter(missing)) {
            try DesktopPairingLinkParser.parse(url)
        }
    }

    @Test func rejectsWrongSchemeOrHost() {
        let wrongScheme = URL(string: "https://desktop-pair?code=c&srv=s")!
        let wrongHost = URL(string: "llamalabels://native-pair?code=c&srv=s")!
        #expect(throws: PairingLinkError.notAPairingLink) {
            try DesktopPairingLinkParser.parse(wrongScheme)
        }
        #expect(throws: PairingLinkError.notAPairingLink) {
            try DesktopPairingLinkParser.parse(wrongHost)
        }
    }

    @Test func deepLinkHandlerRoutesDesktopPairingLinks() throws {
        let handler = DeepLinkHandler()
        let expected = NavigationAction.openDesktopPairingFlow(
            try DesktopPairingLinkParser.parse(validDesktopLink)
        )
        #expect(handler.handle(validDesktopLink) == expected)
    }

    @Test func registerEndpointDerivedFromSrv() {
        let params = DesktopPairingParams(code: validCode, srv: "https://relay.example.com")
        #expect(
            params.registerEndpoint?.absoluteString
            == "https://relay.example.com/api/notifications/desktop/register"
        )
    }
}

// MARK: - Code format validation (guide checklist)

@Suite struct DesktopPairingCodeValidationTests {
    @Test func acceptsGuideSampleCode() {
        #expect(DesktopPairingService.isValidCode(validCode))
    }

    @Test(arguments: [
        "",
        "SHORT",
        "A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6EXTRA",
        "A1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P!",
    ])
    func rejectsMalformedCodes(code: String) {
        #expect(!DesktopPairingService.isValidCode(code))
    }
}

// MARK: - Register outcome mapping

@Suite struct DesktopRegistrationClientTests {
    private let params = DesktopPairingParams(code: validCode, srv: "https://relay.example.com")

    @Test func successSendsCodeAndDecodesSession() async {
        let json = """
        {
          "ok": true,
          "sessionToken": "jwt-token",
          "expiresIn": 86400,
          "userId": "user123",
          "userEmail": "user@example.com"
        }
        """
        let client = stubClient(status: 200, json: json) { request in
            #expect(
                request.url!.absoluteString
                == "https://relay.example.com/api/notifications/desktop/register"
            )
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""pairingCode":"\#(validCode)""#))
            #expect(body.contains("appName"))
            #expect(body.contains("appVersion"))
            #expect(body.contains("platformInfo"))
        }
        let outcome = await DesktopRegistrationClient(httpClient: client).register(params: params)
        guard case .success(let response) = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }
        #expect(response.sessionToken == "jwt-token")
        #expect(response.expiresIn == 86400)
        #expect(response.userId == "user123")
        #expect(response.userEmail == "user@example.com")
    }

    @Test func invalidOrExpiredCodeIs401() async {
        let outcome = await DesktopRegistrationClient(httpClient: stubClient(status: 401))
            .register(params: params)
        #expect(outcome == .invalidOrExpiredCode)
    }

    @Test func consumedCodeIs409() async {
        let outcome = await DesktopRegistrationClient(httpClient: stubClient(status: 409))
            .register(params: params)
        #expect(outcome == .codeAlreadyConsumed)
    }

    @Test func rateLimitedIs429() async {
        let outcome = await DesktopRegistrationClient(httpClient: stubClient(status: 429))
            .register(params: params)
        #expect(outcome == .rateLimited)
    }

    @Test func rateLimitStatusMapping() {
        #expect(NetworkError.from(statusCode: 429) == .rateLimited)
    }
}
