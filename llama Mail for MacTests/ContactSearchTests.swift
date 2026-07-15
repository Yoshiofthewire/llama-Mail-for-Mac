//
//  ContactSearchTests.swift
//  llama Mail for MacTests
//
//  Address-book matching and address validation (ContactAutocomplete.md
//  §1, §4). Pure — no database, no view model.
//

import Foundation
import Testing
@testable import llama_Mail_for_Mac

// MARK: - Helpers


private func index(_ contacts: Contact...) -> ContactSearchIndex {
    ContactSearchIndex(contacts: contacts)
}

// MARK: - Ranking

@Suite("Contact search ranking")
struct ContactSearchRankingTests {
    /// One query hitting every tier at once pins the whole order in one go.
    @Test func ranksPrefixesOverSubstringsAndNamesOverAddresses() {
        let subject = index(
            makeContact("Alan Turing", "alan@x.com"),          // namePrefix
            makeContact("Grace Alcott", "grace@x.com"),        // nameWordPrefix
            makeContact("Zoe Quinn", "alfred@x.com"),          // addressPrefix
            makeContact("Natalia Rey", "natalia@x.com"),       // nameSubstring ("tal"→no; see below)
            makeContact("Bob Smith", "b.alpha@x.com")          // addressSubstring
        )
        let ranks = ContactSearch.matches("al", in: subject, options: .autocomplete)
            .map(\.rank)

        #expect(ranks == [.namePrefix, .nameWordPrefix, .addressPrefix, .nameSubstring, .addressSubstring])
    }

    @Test func tiesAtEqualRankResolveByName() {
        let subject = index(
            makeContact("Adam Zeta", "z@x.com"),
            makeContact("Adam Vale", "v@x.com")
        )
        // Both are namePrefix at offset 0, so only the name can decide.
        let names = ContactSearch.matches("adam", in: subject, options: .directory)
            .map(\.entry.displayName)

        #expect(names == ["Adam Vale", "Adam Zeta"])
    }

    @Test func earlierMatchesOutrankLaterOnesAtEqualRank() {
        let subject = index(
            makeContact("Zoe", "xxxal@x.com"),
            makeContact("Abe", "xal@x.com")
        )
        // Both addressSubstring; Abe's hit is at offset 1 vs Zoe's at 3.
        let names = ContactSearch.matches("al", in: subject, options: .directory)
            .map(\.entry.displayName)

        #expect(names == ["Abe", "Zoe"])
    }

    @Test func capsRowsPerContact() {
        let subject = index(
            makeContact("Ada Lovelace", "ada1@x.com", "ada2@x.com", "ada3@x.com", "ada4@x.com")
        )
        let matches = ContactSearch.matches("ada", in: subject, options: .autocomplete)

        #expect(matches.count == 2)
    }

    @Test func capsTotalResults() {
        let contacts = (1...9).map { makeContact("Ann \($0)", "ann\($0)@x.com") }
        let matches = ContactSearch.matches(
            "ann",
            in: ContactSearchIndex(contacts: contacts),
            options: .autocomplete
        )

        #expect(matches.count == 5)
    }

    @Test func matchesIgnoringCaseAndDiacritics() {
        let subject = index(makeContact("José Álvarez", "jose@x.com"))

        #expect(!ContactSearch.matches("jose", in: subject, options: .autocomplete).isEmpty)
        #expect(!ContactSearch.matches("ÁLV", in: subject, options: .autocomplete).isEmpty)
    }

    /// The regression test for mapping a folded range onto the original.
    /// Folding isn't length-preserving, so a range computed against the folded
    /// string points at the wrong characters here — or out of bounds.
    @Test func highlightRangesSliceTheOriginalString() throws {
        let subject = index(makeContact("Straße Fischer", "s@x.com"))
        let match = try #require(
            ContactSearch.matches("stra", in: subject, options: .autocomplete).first
        )
        let highlight = try #require(match.nameHighlight)

        #expect(String(match.entry.displayName[highlight]) == "Stra")
    }

    @Test func emptyQueryReturnsNothingForAutocompleteAndEverythingForDirectory() {
        let subject = index(
            makeContact("Bea", "bea@x.com"),
            makeContact("Abe", "abe@x.com")
        )

        #expect(ContactSearch.matches("", in: subject, options: .autocomplete).isEmpty)
        #expect(ContactSearch.matches("  ", in: subject, options: .autocomplete).isEmpty)

        let all = ContactSearch.matches("", in: subject, options: .directory)
        #expect(all.map(\.entry.displayName) == ["Abe", "Bea"])
    }

    @Test func directoryShowsOneRowPerContact() {
        let subject = index(makeContact("Ada", "a1@x.com", "a2@x.com"))

        #expect(ContactSearch.matches("", in: subject, options: .directory).count == 1)
    }

    @Test func contactsWithoutAnAddressAreNotIndexed() {
        let subject = index(
            makeContact("No Address"),
            makeContact("Has Address", "has@x.com")
        )

        #expect(subject.entries.count == 1)
        #expect(ContactSearch.matches("", in: subject, options: .directory).count == 1)
    }
}

// MARK: - Validation

@Suite("Email address validation")
struct EmailAddressValidationTests {
    @Test(arguments: [
        "a@b.com",
        "a.b+c@sub.example.co.uk",
        "first.last@example.museum",
        "user!#$%&'*+-/=?^_`{|}~@example.com",
    ])
    func accepts(_ address: String) {
        #expect(EmailAddress.isValid(address))
    }

    @Test(arguments: [
        "",
        "a@b",                  // no dot in the domain
        "a@@b.com",
        "a b@c.com",
        "@b.com",
        "a@",
        "a@-b.com",
        "a@b-.com",
        "plainaddress",
        "a@b..com",
    ])
    func rejects(_ address: String) {
        #expect(!EmailAddress.isValid(address))
    }

    @Test func rejectsOversizedAddresses() {
        #expect(!EmailAddress.isValid(String(repeating: "a", count: 250) + "@example.com"))
        #expect(!EmailAddress.isValid(String(repeating: "a", count: 65) + "@example.com"))
        #expect(EmailAddress.isValid(String(repeating: "a", count: 64) + "@example.com"))
    }
}

// MARK: - Parsing

@Suite("Email header parsing")
struct EmailAddressParsingTests {
    @Test func parsesNamedAndBareEntries() {
        let parsed = EmailAddress.parse("Alice <a@x.com>, b@y.com")

        #expect(parsed.count == 2)
        #expect(parsed[0].name == "Alice")
        #expect(parsed[0].address == "a@x.com")
        #expect(parsed[1].name == nil)
        #expect(parsed[1].address == "b@y.com")
    }

    @Test func stripsQuotesFromDisplayNames() {
        let parsed = EmailAddress.parse("\"Chen, Alice\" <a@x.com>")

        // The quoted comma splits the entry; what matters is the address
        // survives, which is all replyAll consumes.
        #expect(parsed.map(\.address) == ["a@x.com"])
    }

    @Test func splitsOnSemicolons() {
        #expect(EmailAddress.parse("a@x.com; b@y.com").map(\.address) == ["a@x.com", "b@y.com"])
    }

    @Test func dropsEntriesWithoutAnAddress() {
        #expect(EmailAddress.parse("").isEmpty)
        #expect(EmailAddress.parse("not an address").isEmpty)
        #expect(EmailAddress.parse("a@x.com,").map(\.address) == ["a@x.com"])
    }

    /// Non-validating on purpose — ComposeDraft.replyAll relies on it.
    @Test func doesNotValidate() {
        #expect(EmailAddress.parse("nonsense@localhost").map(\.address) == ["nonsense@localhost"])
    }
}
