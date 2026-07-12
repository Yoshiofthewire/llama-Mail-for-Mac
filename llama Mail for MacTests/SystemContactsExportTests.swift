//
//  SystemContactsExportTests.swift
//  llama Mail for MacTests
//
//  Apple Contacts export: field mapping, the link-based diff (including
//  re-link after a tooOld wipe), and the exporter's guard rails and
//  failure handling through a mock contact store.
//

import Contacts
import Foundation
import Testing
@testable import llama_Mail_for_Mac

// MARK: - Helpers

private final class MockSystemContactStore: SystemContactStoring, @unchecked Sendable {
    struct StubError: Error {}

    var authorizationStatus: CNAuthorizationStatus = .authorized
    var accessGranted = true
    var failNextAdd = false
    var failingIdentifiers: Set<String> = []

    private(set) var cards: [String: CNContact] = [:]
    private(set) var addCount = 0
    private(set) var updateCount = 0
    private(set) var deleteCount = 0

    func requestAccess() async throws -> Bool { accessGranted }

    func fetch(identifier: String) throws -> CNContact? { cards[identifier] }

    func add(_ contact: CNMutableContact) throws {
        addCount += 1
        if failNextAdd {
            failNextAdd = false
            throw StubError()
        }
        cards[contact.identifier] = contact.copy() as? CNContact
    }

    func update(_ contact: CNMutableContact) throws {
        updateCount += 1
        if failingIdentifiers.contains(contact.identifier) { throw StubError() }
        cards[contact.identifier] = contact.copy() as? CNContact
    }

    func delete(identifier: String) throws {
        deleteCount += 1
        if failingIdentifiers.contains(identifier) { throw StubError() }
        cards[identifier] = nil
    }
}

private func makeContact(
    localId: UUID = UUID(),
    uid: String? = nil,
    name: String = "Ada Lovelace",
    email: String = "ada@example.com",
    phone: String = "",
    avatarUrl: String? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1_000)
) -> Contact {
    Contact(
        localId: localId,
        uid: uid,
        name: name,
        email: email,
        phone: phone,
        avatarUrl: avatarUrl,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        needsSync: false
    )
}

private func makeLink(
    localId: UUID = UUID(),
    uid: String? = nil,
    cnIdentifier: String = UUID().uuidString,
    exportedUpdatedAt: Date = Date(timeIntervalSince1970: 1_000)
) -> SystemContactLink {
    SystemContactLink(
        localId: localId,
        uid: uid,
        cnIdentifier: cnIdentifier,
        exportedUpdatedAt: exportedUpdatedAt
    )
}

private struct ExporterEnvironment {
    let exporter: SystemContactsExporter
    let mock: MockSystemContactStore
    let linkStore: SystemContactsLinkStore
    let settings: ContactsSettingsStore
    let dao: ContactDAO
}

private func makeEnvironment(
    enabled: Bool = true,
    status: CNAuthorizationStatus = .authorized
) throws -> ExporterEnvironment {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let mock = MockSystemContactStore()
    mock.authorizationStatus = status
    let linkStore = SystemContactsLinkStore(defaults: defaults)
    let settings = ContactsSettingsStore(defaults: defaults)
    settings.exportToSystemContactsEnabled = enabled
    let database = try AppDatabase(inMemory: true)
    let dao = ContactDAO(modelContainer: database.container)
    let exporter = SystemContactsExporter(
        store: mock,
        linkStore: linkStore,
        settings: settings,
        contactDAO: dao
    )
    return ExporterEnvironment(
        exporter: exporter,
        mock: mock,
        linkStore: linkStore,
        settings: settings,
        dao: dao
    )
}

// MARK: - Mapper

@Suite struct SystemContactMapperTests {
    @Test func splitsNameOnLastWhitespace() {
        let (given, family) = SystemContactMapper.nameComponents(
            from: "Ada M. Lovelace",
            fallbackEmail: ""
        )
        #expect(given == "Ada M.")
        #expect(family == "Lovelace")
    }

    @Test func singleTokenNameIsGivenNameOnly() {
        let (given, family) = SystemContactMapper.nameComponents(
            from: "Cher",
            fallbackEmail: ""
        )
        #expect(given == "Cher")
        #expect(family.isEmpty)
    }

    @Test func emptyNameFallsBackToEmailLocalPart() {
        let (given, family) = SystemContactMapper.nameComponents(
            from: "  ",
            fallbackEmail: "grace@example.com"
        )
        #expect(given == "grace")
        #expect(family.isEmpty)
    }

    @Test func mapsLabeledFields() {
        let contact = makeContact(
            name: "Ada Lovelace",
            email: "ada@example.com",
            phone: "+1 555 0100",
            avatarUrl: "https://example.com/ada.png"
        )
        let cn = SystemContactMapper.makeContact(from: contact)
        #expect(cn.givenName == "Ada")
        #expect(cn.familyName == "Lovelace")
        #expect(cn.emailAddresses.first?.value as String? == "ada@example.com")
        #expect(cn.emailAddresses.first?.label == CNLabelHome)
        #expect(cn.phoneNumbers.first?.value.stringValue == "+1 555 0100")
        #expect(cn.urlAddresses.first?.value as String? == "https://example.com/ada.png")
    }

    @Test func emptyFieldsProduceEmptyArrays() {
        let contact = makeContact(email: "", phone: "", avatarUrl: nil)
        let cn = SystemContactMapper.makeContact(from: contact)
        #expect(cn.emailAddresses.isEmpty)
        #expect(cn.phoneNumbers.isEmpty)
        #expect(cn.urlAddresses.isEmpty)
    }

    @Test func applyPreservesUnmappedFields() {
        let cn = CNMutableContact()
        cn.organizationName = "Analytical Engines Ltd"
        SystemContactMapper.apply(makeContact(), to: cn)
        #expect(cn.organizationName == "Analytical Engines Ltd")
    }
}

// MARK: - Diff

@Suite struct SystemContactsDiffTests {
    @Test func unlinkedContactsBecomeCreates() {
        let contacts = [makeContact(name: "Ada"), makeContact(name: "Grace")]
        let plan = SystemContactsDiff.plan(contacts: contacts, links: [])
        #expect(plan.creates.count == 2)
        #expect(plan.updates.isEmpty)
        #expect(plan.deletes.isEmpty)
        #expect(plan.relinks.isEmpty)
    }

    @Test func editedLinkedContactBecomesUpdate() {
        let contact = makeContact(updatedAt: Date(timeIntervalSince1970: 2_000))
        let link = makeLink(
            localId: contact.localId,
            exportedUpdatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let plan = SystemContactsDiff.plan(contacts: [contact], links: [link])
        #expect(plan.updates.map(\.cnIdentifier) == [link.cnIdentifier])
        #expect(plan.creates.isEmpty)
    }

    @Test func unchangedLinkedContactIsSkipped() {
        let exportedAt = Date(timeIntervalSince1970: 1_000)
        let contact = makeContact(updatedAt: exportedAt)
        let link = makeLink(localId: contact.localId, exportedUpdatedAt: exportedAt)
        let plan = SystemContactsDiff.plan(contacts: [contact], links: [link])
        #expect(plan == SystemContactsExportPlan())
    }

    @Test func orphanedLinkBecomesDelete() {
        let link = makeLink()
        let plan = SystemContactsDiff.plan(contacts: [], links: [link])
        #expect(plan.deletes == [link])
    }

    @Test func relinksByUidAfterTooOldWipe() {
        // A tooOld re-pull keeps the server contact but assigns a new localId.
        let repulled = makeContact(uid: "srv-1")
        let staleLink = makeLink(localId: UUID(), uid: "srv-1")
        let plan = SystemContactsDiff.plan(contacts: [repulled], links: [staleLink])
        #expect(plan.relinks.count == 1)
        #expect(plan.relinks.first?.contact.localId == repulled.localId)
        #expect(plan.relinks.first?.link == staleLink)
        #expect(plan.deletes.isEmpty)
        #expect(plan.creates.isEmpty)
    }

    @Test func duplicateEmailsCreateIndependentCards() {
        let contacts = [
            makeContact(name: "Ada Work", email: "shared@example.com"),
            makeContact(name: "Ada Home", email: "shared@example.com"),
        ]
        let plan = SystemContactsDiff.plan(contacts: contacts, links: [])
        #expect(plan.creates.count == 2)
    }
}

// MARK: - Link store

@Suite struct SystemContactsLinkStoreTests {
    private func makeStore() -> SystemContactsLinkStore {
        SystemContactsLinkStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    @Test func roundTripsLinks() {
        let store = makeStore()
        let link = makeLink(uid: "srv-1")
        store.upsert(link)
        #expect(store.all() == [link])
        #expect(store.link(localId: link.localId) == link)
    }

    @Test func upsertReplacesByLocalId() {
        let store = makeStore()
        var link = makeLink()
        store.upsert(link)
        link.cnIdentifier = "replacement"
        store.upsert(link)
        #expect(store.all() == [link])
    }

    @Test func removesAndClears() {
        let store = makeStore()
        let first = makeLink()
        let second = makeLink()
        store.upsert(first)
        store.upsert(second)
        store.remove(localId: first.localId)
        #expect(store.all() == [second])
        store.clear()
        #expect(store.all().isEmpty)
    }
}

// MARK: - Exporter

@Suite struct SystemContactsExporterTests {
    @Test func disabledTogglePerformsNoStoreCalls() async throws {
        let env = try makeEnvironment(enabled: false)
        try await env.dao.upsert(contacts: [makeContact()])
        let summary = await env.exporter.reconcileAll()
        #expect(summary == SystemContactsExporter.Summary())
        #expect(env.mock.addCount == 0)
    }

    @Test func deniedAuthorizationPerformsNoStoreCalls() async throws {
        let env = try makeEnvironment(status: .denied)
        try await env.dao.upsert(contacts: [makeContact()])
        let summary = await env.exporter.reconcileAll()
        #expect(summary == SystemContactsExporter.Summary())
        #expect(env.mock.addCount == 0)
        #expect(await env.exporter.isDenied)
    }

    @Test func requestAccessPromptsOnlyWhenUndetermined() async throws {
        let env = try makeEnvironment(status: .notDetermined)
        #expect(await env.exporter.requestAccessIfNeeded())
        env.mock.accessGranted = false
        #expect(await env.exporter.requestAccessIfNeeded())

        let denied = try makeEnvironment(status: .denied)
        #expect(await !denied.exporter.requestAccessIfNeeded())
    }

    @Test func reconcileCreatesCardsAndLinks() async throws {
        let env = try makeEnvironment()
        try await env.dao.upsert(contacts: [makeContact(name: "Ada Lovelace")])
        let summary = await env.exporter.reconcileAll()
        #expect(summary.created == 1)
        let links = env.linkStore.all()
        #expect(links.count == 1)
        #expect(env.mock.cards[links[0].cnIdentifier]?.givenName == "Ada")
    }

    @Test func reconcileSkipsUnchangedOnSecondPass() async throws {
        let env = try makeEnvironment()
        try await env.dao.upsert(contacts: [makeContact()])
        await env.exporter.reconcileAll()
        let second = await env.exporter.reconcileAll()
        #expect(second == SystemContactsExporter.Summary())
        #expect(env.mock.addCount == 1)
        #expect(env.mock.updateCount == 0)
    }

    @Test func updateOnUserDeletedCardFallsBackToAdd() async throws {
        let env = try makeEnvironment()
        let contact = makeContact(updatedAt: Date(timeIntervalSince1970: 2_000))
        try await env.dao.upsert(contacts: [contact])
        // Link points at a card that no longer exists in the system store.
        env.linkStore.upsert(makeLink(
            localId: contact.localId,
            cnIdentifier: "gone",
            exportedUpdatedAt: Date(timeIntervalSince1970: 1_000)
        ))
        let summary = await env.exporter.reconcileAll()
        #expect(summary.created == 1)
        #expect(summary.failed == 0)
        let link = try #require(env.linkStore.link(localId: contact.localId))
        #expect(link.cnIdentifier != "gone")
        #expect(env.mock.cards[link.cnIdentifier] != nil)
    }

    @Test func partialFailureLeavesOtherCardsAppliedAndRetriable() async throws {
        let env = try makeEnvironment()
        try await env.dao.upsert(contacts: [
            makeContact(name: "Alpha One", email: "alpha@example.com"),
            makeContact(name: "Beta Two", email: "beta@example.com"),
        ])
        env.mock.failNextAdd = true
        let first = await env.exporter.reconcileAll()
        #expect(first.created == 1)
        #expect(first.failed == 1)
        #expect(env.linkStore.all().count == 1)

        // The failed contact has no link, so it retries as a create.
        let second = await env.exporter.reconcileAll()
        #expect(second.created == 1)
        #expect(env.linkStore.all().count == 2)
        #expect(env.mock.cards.count == 2)
    }

    @Test func incrementalUpsertAndDeleteMaintainLinks() async throws {
        let env = try makeEnvironment()
        let contact = makeContact()
        await env.exporter.exportUpsert(contact)
        #expect(env.mock.cards.count == 1)
        #expect(env.linkStore.all().count == 1)

        await env.exporter.exportDelete(localId: contact.localId)
        #expect(env.mock.cards.isEmpty)
        #expect(env.linkStore.all().isEmpty)
    }

    @Test func deleteOfUnlinkedContactTouchesNothing() async throws {
        let env = try makeEnvironment()
        await env.exporter.exportDelete(localId: UUID())
        #expect(env.mock.deleteCount == 0)
    }

    @Test func removeAllExportedDeletesCardsAndForgetsLinks() async throws {
        let env = try makeEnvironment()
        try await env.dao.upsert(contacts: [
            makeContact(name: "Alpha One", email: "alpha@example.com"),
            makeContact(name: "Beta Two", email: "beta@example.com"),
        ])
        await env.exporter.reconcileAll()
        #expect(env.mock.cards.count == 2)

        let removed = await env.exporter.removeAllExported()
        #expect(removed == 2)
        #expect(env.mock.cards.isEmpty)
        #expect(env.linkStore.all().isEmpty)
        #expect(await !env.exporter.hasExportedContacts())
    }
}
