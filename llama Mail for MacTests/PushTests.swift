//
//  PushTests.swift
//  llama Mail for MacTests
//
//  Phase 5 tests: payload mapping, pull dedupe + cursor handoff, synthesized
//  seqs for push-mode arrivals, registration persistence, MFA use case.
//

import Foundation
import Testing
@testable import llama_Mail_for_Mac

// MARK: - Helpers

private func stubClient(
    status: Int = 200,
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

private let server = "https://relay.example.com"

private func scratchStores() -> (defaults: UserDefaults, keychain: KeychainStorage) {
    (
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
        KeychainStorage(service: "com.urlxl.mail.tests.\(UUID().uuidString)")
    )
}

private func makePairing() -> Pairing {
    Pairing(
        sub: "u1", hash: "h1", srv: server, registrationUrl: nil,
        pairingToken: "pt", lastDeviceId: nil, pairedAt: Date()
    )
}

// MARK: - Payload mapping

@Suite struct PushPayloadMapperTests {
    @Test func mapsMailPayloadWithContractKeys() throws {
        // Exact keys from spec §3, including capital-K Keywords.
        let userInfo: [AnyHashable: Any] = [
            "messageId": "m-1",
            "senderName": "Ada",
            "emailSubject": "Hello",
            "Keywords": ["Important", "Work"],
        ]
        guard case .mail(let mail)? = PushPayloadMapper.map(userInfo: userInfo) else {
            Issue.record("Expected mail payload")
            return
        }
        #expect(mail.messageId == "m-1")
        #expect(mail.senderName == "Ada")
        #expect(mail.emailSubject == "Hello")
        #expect(mail.keywords == ["Important", "Work"])
    }

    @Test func mapsMinimalMailPayload() {
        let payload = PushPayloadMapper.map(userInfo: ["messageId": "m-2"])
        #expect(payload == .mail(MailPushPayload(
            messageId: "m-2", senderName: "", emailSubject: "", keywords: []
        )))
    }

    @Test func mapsMfaChallenge() throws {
        let received = Date(timeIntervalSince1970: 1_750_000_000)
        let payload = PushPayloadMapper.map(
            userInfo: ["type": "mfa_challenge", "challengeId": "c-1"],
            receivedAt: received
        )
        #expect(payload == .mfaChallenge(MfaChallenge(challengeId: "c-1", receivedAt: received)))
    }

    @Test func rejectsUnrecognizedPayloads() {
        #expect(PushPayloadMapper.map(userInfo: [:]) == nil)
        #expect(PushPayloadMapper.map(userInfo: ["foo": "bar"]) == nil)
        // MFA without a challengeId is invalid, not a mail fallback.
        #expect(PushPayloadMapper.map(userInfo: ["type": "mfa_challenge"]) == nil)
        #expect(PushPayloadMapper.map(userInfo: ["messageId": ""]) == nil)
    }
}

// MARK: - PushRepository

@Suite struct PushRepositoryTests {
    private struct Environment {
        var repository: PushRepository
        var cursorStore: NotificationCursorStore
        var settings: PushSettingsStore
    }

    private func makeEnvironment(client: HTTPClient, paired: Bool = true) throws -> Environment {
        let (defaults, keychain) = scratchStores()
        let pairingStore = SecurePairingStore(keychain: keychain)
        if paired {
            try pairingStore.savePairing(makePairing())
        }
        let db = try AppDatabase(inMemory: true)
        let cursorStore = NotificationCursorStore(defaults: defaults)
        let settings = PushSettingsStore(defaults: defaults)
        let repository = PushRepository(
            dao: PushNotificationDAO(modelContainer: db.container),
            cursorStore: cursorStore,
            client: PushNotificationClient(httpClient: client),
            securePairingStore: pairingStore,
            pushSettingsStore: settings
        )
        return Environment(repository: repository, cursorStore: cursorStore, settings: settings)
    }

    @Test func pushArrivalsGetUniqueSynthesizedSeqs() async throws {
        let env = try makeEnvironment(client: stubClient())
        let payload = MailPushPayload(
            messageId: "m-1", senderName: "Ada", emailSubject: "Hi", keywords: []
        )
        let sameInstant = Date()
        let first = try await env.repository.recordPushArrival(payload, receivedAt: sameInstant)
        let second = try await env.repository.recordPushArrival(payload, receivedAt: sameInstant)

        #expect(first.seq != second.seq)
        #expect(try await env.repository.history().count == 2)
    }

    @Test func pullDeduplicatesBySeqAndAdvancesCursorAfterHandoff() async throws {
        let json = """
        {
          "notifications": [
            { "seq": 3, "messageId": "m-3", "senderName": "A", "emailSubject": "s3" },
            { "seq": 5, "messageId": "m-5", "senderName": "B", "emailSubject": "s5" }
          ],
          "cursor": 5
        }
        """
        let client = stubClient(json: json) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("\(server)/api/notifications/native/pull?"))
            #expect(url.contains("sub=u1"))
            #expect(url.contains("after=3"))
        }
        let env = try makeEnvironment(client: client)
        env.cursorStore.advance(to: 3)

        let delivered = try await env.repository.pullOnce()
        // seq 3 <= cursor: deduped; only seq 5 is new.
        #expect(delivered.map(\.seq) == [5])
        #expect(env.cursorStore.lastCursor == 5)
        #expect(try await env.repository.history().map(\.seq) == [5])
    }

    @Test func storedPullEndpointOverridesDerivedOne() async throws {
        let client = stubClient(json: #"{"notifications": [], "cursor": 0}"#) { request in
            #expect(request.url!.absoluteString.hasPrefix("https://pull.example.com/custom?"))
        }
        let env = try makeEnvironment(client: client)
        env.settings.pullEndpoint = "https://pull.example.com/custom"
        _ = try await env.repository.pullOnce()
    }

    @Test func pullWithoutPairingThrows() async throws {
        let env = try makeEnvironment(client: stubClient(), paired: false)
        await #expect(throws: MailSourceError.notPaired) {
            try await env.repository.pullOnce()
        }
    }
}

// MARK: - DeviceRegistrationService

@Suite struct DeviceRegistrationServiceTests {
    private struct Environment {
        var service: DeviceRegistrationService
        var pairingStore: SecurePairingStore
        var settings: PushSettingsStore
    }

    private func makeEnvironment(client: HTTPClient, paired: Bool = false) throws -> Environment {
        let (defaults, keychain) = scratchStores()
        let pairingStore = SecurePairingStore(keychain: keychain)
        if paired {
            try pairingStore.savePairing(makePairing())
        }
        let settings = PushSettingsStore(defaults: defaults)
        let service = DeviceRegistrationService(
            client: NativeRegistrationClient(httpClient: client),
            securePairingStore: pairingStore,
            pushSettingsStore: settings
        )
        return Environment(service: service, pairingStore: pairingStore, settings: settings)
    }

    private let params = PairingParams(sub: "u1", hash: "h1", srv: server, pt: "pt-1")

    @Test func successfulPairingPersistsEverything() async throws {
        let json = #"{"ok": true, "deviceId": "dev-7", "deliveryMode": "pull"}"#
        let env = try makeEnvironment(client: stubClient(json: json))

        let outcome = await env.service.pair(params: params, deviceToken: "apns-token")
        guard case .success = outcome else {
            Issue.record("Expected success, got \(outcome)")
            return
        }

        let pairing = try #require(try env.pairingStore.loadPairing())
        #expect(pairing.sub == "u1")
        #expect(pairing.lastDeviceId == "dev-7")
        #expect(env.settings.deliveryMode == .pull)
        // pullEndpoint absent in response → derived from srv (spec §3).
        #expect(env.settings.pullEndpoint == "\(server)/api/notifications/native/pull")
    }

    @Test func failedPairingSavesNothing() async throws {
        let env = try makeEnvironment(client: stubClient(status: 403))
        let outcome = await env.service.pair(params: params, deviceToken: "t")
        #expect(outcome == .unauthorized)
        #expect(try env.pairingStore.loadPairing() == nil)
        #expect(env.settings.deliveryMode == nil)
    }

    @Test func reregisterUsesStoredPairing() async throws {
        let client = stubClient(json: #"{"ok": true, "deviceId": "dev-8"}"#) { request in
            #expect(
                request.url!.absoluteString
                    .hasPrefix("\(server)/api/notifications/native/register?")
            )
        }
        let env = try makeEnvironment(client: client, paired: true)
        let outcome = await env.service.reregisterIfPaired(deviceToken: "t2")
        #expect(outcome != nil)
        #expect(try env.pairingStore.loadPairing()?.lastDeviceId == "dev-8")
    }

    @Test func reregisterWithoutPairingIsNoOp() async throws {
        let env = try makeEnvironment(client: stubClient(), paired: false)
        let outcome = await env.service.reregisterIfPaired(deviceToken: "t")
        #expect(outcome == nil)
    }
}

// MARK: - ApproveMfaChallengeUseCase

@Suite struct ApproveMfaChallengeUseCaseTests {
    private func makeUseCase(client: HTTPClient, paired: Bool) throws -> ApproveMfaChallengeUseCase {
        let (_, keychain) = scratchStores()
        let pairingStore = SecurePairingStore(keychain: keychain)
        if paired {
            try pairingStore.savePairing(makePairing())
        }
        return ApproveMfaChallengeUseCase(
            client: MfaResponseClient(httpClient: client),
            securePairingStore: pairingStore
        )
    }

    @Test func approvesThroughPairedServer() async throws {
        let client = stubClient(json: #"{"ok": true}"#) { request in
            #expect(request.url!.absoluteString.hasPrefix("\(server)/api/mfa/push/respond?"))
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""challengeId":"c-1""#))
            #expect(body.contains(#""approved":true"#))
        }
        let useCase = try makeUseCase(client: client, paired: true)
        let outcome = await useCase(challengeId: "c-1", approved: true)
        #expect(outcome == .success)
    }

    @Test func failsWhenUnpaired() async throws {
        let useCase = try makeUseCase(client: stubClient(), paired: false)
        let outcome = await useCase(challengeId: "c-1", approved: false)
        #expect(outcome == .failure("Device is not paired"))
    }
}
