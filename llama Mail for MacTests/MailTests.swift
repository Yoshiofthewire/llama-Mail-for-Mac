//
//  MailTests.swift
//  llama Mail for MacTests
//
//  Phase 3 tests: relay source mapping, comma-string send contract, keyword
//  tab computation, mode-aware repository, send use-case validation.
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

private let auth = RelayAuth(sub: "u1", hash: "h1")
private let server = "https://relay.example.com"

private func makeEmail(serverId: String, keywords: Set<String>) -> Email {
    Email(
        serverId: serverId,
        folder: "INBOX",
        senderName: "S",
        senderEmail: "s@example.com",
        subject: "Subject",
        body: "Body",
        keywords: keywords,
        receivedAt: Date(),
        read: false,
        starred: false
    )
}

private func makeOutgoing(
    to: [String] = ["a@x.com", "b@x.com"],
    cc: [String] = ["c@x.com"],
    bcc: [String] = []
) -> OutgoingEmail {
    OutgoingEmail(to: to, cc: cc, bcc: bcc, subject: "Hi", body: "Hello there")
}

// MARK: - Comma-string send contract

@Suite struct RelaySendRequestTests {
    @Test func recipientsAreCommaJoinedStrings() throws {
        let request = RelaySendRequest(from: makeOutgoing())
        #expect(request.to == "a@x.com, b@x.com")
        #expect(request.cc == "c@x.com")
        #expect(request.bcc == "")

        // Binding contract (spec §7): strings in the JSON, not arrays.
        let data = try JSONEncoder().encode(request)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["to"] as? String == "a@x.com, b@x.com")
        #expect(object["cc"] as? String == "c@x.com")
    }
}

// MARK: - RelayMailSource

@Suite struct RelayMailSourceTests {
    @Test func fetchEmailsMapsTabAndLabelToKeywords() async throws {
        let json = """
        {
          "emails": [
            {
              "id": "e-1",
              "senderName": "Ada",
              "senderEmail": "ada@example.com",
              "subject": "Report",
              "body": "The report",
              "tab": "Work",
              "label": "Important",
              "receivedAt": 1750000000,
              "read": true,
              "starred": false
            },
            { "id": "e-2", "subject": "Bare minimum" }
          ]
        }
        """
        let client = stubClient(json: json) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("\(server)/api/relay/folder?"))
            #expect(url.contains("sub=u1"))
            #expect(url.contains("hash=h1"))
            #expect(url.contains("folder=INBOX"))
            #expect(url.contains("from=0"))
            #expect(url.contains("to=50"))
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        let emails = try await source.fetchEmails(folder: "INBOX", from: 0, to: 50)

        #expect(emails.count == 2)
        let full = try #require(emails.first { $0.serverId == "e-1" })
        #expect(full.keywords == ["Work", "Important"])
        #expect(full.read)
        #expect(full.receivedAt == Date(timeIntervalSince1970: 1_750_000_000))

        let bare = try #require(emails.first { $0.serverId == "e-2" })
        #expect(bare.keywords.isEmpty)
        #expect(!bare.read)
    }

    @Test func listFoldersAndSearch() async throws {
        let foldersClient = stubClient(json: #"{"folders": ["INBOX", "Archive"]}"#) { request in
            #expect(request.url!.absoluteString.hasPrefix("\(server)/api/relay/folders?"))
        }
        let folders = try await RelayMailSource(httpClient: foldersClient, serverUrl: server, auth: auth)
            .listFolders()
        #expect(folders.map(\.name) == ["INBOX", "Archive"])

        let searchClient = stubClient(json: #"{"ids": ["e-1", "e-9"]}"#) { request in
            let url = request.url!.absoluteString
            #expect(url.hasPrefix("\(server)/api/relay/search?"))
            #expect(url.contains("query=report"))
        }
        let ids = try await RelayMailSource(httpClient: searchClient, serverUrl: server, auth: auth)
            .search(folder: "INBOX", query: "report")
        #expect(ids == ["e-1", "e-9"])
    }

    @Test func sendPostsCommaStringBody() async throws {
        let client = stubClient(json: #"{"ok": true}"#) { request in
            #expect(request.url!.absoluteString.hasPrefix("\(server)/api/relay/send?"))
            #expect(request.httpMethod == "POST")
            let body = request.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(body.contains(#""to":"a@x.com, b@x.com""#))
        }
        let source = RelayMailSource(httpClient: client, serverUrl: server, auth: auth)
        try await source.send(email: makeOutgoing())
    }
}

// MARK: - IMAP stub

@Suite struct ImapMailSourceTests {
    @Test func allOperationsAreUnsupportedInV1() async {
        let source = ImapMailSource()
        await #expect(throws: MailSourceError.imapUnsupportedInV1) {
            _ = try await source.listFolders()
        }
        await #expect(throws: MailSourceError.imapUnsupportedInV1) {
            _ = try await source.fetchEmails(folder: "INBOX", from: 0, to: 10)
        }
        await #expect(throws: MailSourceError.imapUnsupportedInV1) {
            try await source.send(email: makeOutgoing())
        }
    }
}

// MARK: - MailOutcome mapping

@Suite struct MailOutcomeTests {
    @Test func errorMapping() {
        #expect(MailOutcome.from(NetworkError.unauthorized) == .unauthorized)
        #expect(MailOutcome.from(MailSourceError.notPaired) == .notPaired)
        #expect(
            MailOutcome.from(MailSourceError.imapUnsupportedInV1)
            == .failure("Manual IMAP is not supported yet")
        )
        if case .failure = MailOutcome.from(NetworkError.serviceUnavailable) {} else {
            Issue.record("503 should map to failure")
        }
    }
}

// MARK: - Keyword tabs

@Suite struct KeywordRepositoryTests {
    private let emails = [
        makeEmail(serverId: "1", keywords: ["Work", "Important"]),
        makeEmail(serverId: "2", keywords: ["work happens later alphabetically", "Work"]),
        makeEmail(serverId: "3", keywords: []),
    ]

    @Test func computeTabsIsUniqueSortedWithCounts() {
        let tabs = KeywordRepository.computeTabs(from: emails)
        #expect(tabs.map(\.name) == ["Important", "Work", "work happens later alphabetically"])
        #expect(tabs.first { $0.name == "Work" }?.count == 2)
        #expect(tabs.first { $0.name == "Important" }?.count == 1)
    }

    @Test func visibleTabsRespectsVisibilityStore() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let repository = KeywordRepository(settingsStore: KeywordSettingsStore(defaults: defaults))

        #expect(repository.visibleTabs(from: emails).count == 3)
        repository.setVisible(false, for: "Work")
        #expect(repository.visibleTabs(from: emails).map(\.name)
                == ["Important", "work happens later alphabetically"])

        // Settings list still includes hidden keywords, flagged invisible.
        let settings = repository.allSettings(from: emails)
        #expect(settings.first { $0.name == "Work" }?.visible == false)
    }
}

// MARK: - MailRepository

@Suite struct MailRepositoryTests {
    private func makeRepository(
        client: HTTPClient,
        mode: MailConnectionMode,
        paired: Bool
    ) throws -> MailRepository {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let keychain = KeychainStorage(service: "com.urlxl.mail.tests.\(UUID().uuidString)")
        let settingsStore = MailSettingsStore(defaults: defaults, keychain: keychain)
        settingsStore.connectionMode = mode

        let pairingStore = SecurePairingStore(keychain: keychain)
        if paired {
            try pairingStore.savePairing(Pairing(
                sub: "u1",
                hash: "h1",
                srv: server,
                registrationUrl: nil,
                pairingToken: "pt",
                lastDeviceId: nil,
                pairedAt: Date()
            ))
        }
        let db = try AppDatabase(inMemory: true)
        return MailRepository(
            mailSettingsStore: settingsStore,
            securePairingStore: pairingStore,
            emailDAO: EmailDAO(modelContainer: db.container),
            httpClient: client
        )
    }

    @Test func relayModeWithoutPairingIsNotPaired() throws {
        let repository = try makeRepository(client: stubClient(), mode: .relay, paired: false)
        #expect(throws: MailSourceError.notPaired) {
            _ = try repository.makeSource()
        }
    }

    @Test func refreshFolderCachesSnapshot() async throws {
        let json = #"{"emails": [{"id": "e-1", "subject": "Cached", "tab": "Work"}]}"#
        let repository = try makeRepository(client: stubClient(json: json), mode: .relay, paired: true)

        let fetched = try await repository.refreshFolder("INBOX")
        #expect(fetched.count == 1)

        let cached = try await repository.cachedFolder("INBOX")
        #expect(cached.map(\.serverId) == ["e-1"])
        #expect(cached.first?.subject == "Cached")
    }

    @Test func manualImapSendFailsInV1() async throws {
        let repository = try makeRepository(client: stubClient(), mode: .manualImap, paired: false)
        let outcome = await repository.send(makeOutgoing())
        #expect(outcome == .failure("Manual IMAP is not supported yet"))
    }
}

// MARK: - SendEmailUseCase

@Suite struct SendEmailUseCaseTests {
    private func makeUseCase(client: HTTPClient) throws -> SendEmailUseCase {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let keychain = KeychainStorage(service: "com.urlxl.mail.tests.\(UUID().uuidString)")
        let settingsStore = MailSettingsStore(defaults: defaults, keychain: keychain)
        settingsStore.connectionMode = .relay
        let pairingStore = SecurePairingStore(keychain: keychain)
        try pairingStore.savePairing(Pairing(
            sub: "u1", hash: "h1", srv: server, registrationUrl: nil,
            pairingToken: "pt", lastDeviceId: nil, pairedAt: Date()
        ))
        let db = try AppDatabase(inMemory: true)
        return SendEmailUseCase(repository: MailRepository(
            mailSettingsStore: settingsStore,
            securePairingStore: pairingStore,
            emailDAO: EmailDAO(modelContainer: db.container),
            httpClient: client
        ))
    }

    @Test func rejectsEmptyRecipients() async throws {
        let send = try makeUseCase(client: stubClient())
        let outcome = await send(makeOutgoing(to: [], cc: [], bcc: []))
        #expect(outcome == .invalid("Add at least one recipient"))
    }

    @Test func rejectsMalformedAddresses() async throws {
        let send = try makeUseCase(client: stubClient())
        let outcome = await send(makeOutgoing(to: ["not-an-address"], cc: [], bcc: []))
        #expect(outcome == .invalid("Check the recipient addresses"))
    }

    @Test func sendsValidEmail() async throws {
        let send = try makeUseCase(client: stubClient(json: #"{"ok": true}"#))
        let outcome = await send(makeOutgoing())
        #expect(outcome == .success)
    }

    @Test func addressShapeCheck() {
        #expect(SendEmailUseCase.looksLikeEmailAddress("a@b.co"))
        #expect(!SendEmailUseCase.looksLikeEmailAddress("a@b"))
        #expect(!SendEmailUseCase.looksLikeEmailAddress("@b.co"))
        #expect(!SendEmailUseCase.looksLikeEmailAddress("a@b."))
        #expect(!SendEmailUseCase.looksLikeEmailAddress("a@@b.co"))
    }
}
