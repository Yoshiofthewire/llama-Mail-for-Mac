//
//  ContactSearch.swift
//  KyPost
//
//  Address-book matching for compose's autocomplete and the address book
//  modal (ContactAutocomplete.md §1). Pure: it takes a prebuilt index and
//  returns ranked matches, so both surfaces rank identically and the whole
//  thing is testable without a database or a view.
//
//  Search runs in memory over the contacts ContactsViewModel already holds
//  rather than as a SwiftData query. Contact.emails is an encoded Codable
//  blob that #Predicate cannot see inside (ContactEntity.swift), so matching
//  on an address in the store would need a denormalized column, a migration,
//  and upkeep on every write path — for a table this size.
//

import Foundation

/// One searchable (contact, address) pair. A contact with three addresses
/// produces three entries: the token a row commits *is* an address, so a row
/// has to name one unambiguously.
nonisolated struct ContactSearchEntry: Identifiable, Hashable, Sendable {
    let contact: Contact
    let address: String
    /// "work"/"home" etc., shown as a hint so two rows for one person are
    /// tellable apart.
    let addressLabel: String?
    let displayName: String
    /// Case- and diacritic-folded, built once at index time. Filtering with
    /// localizedCaseInsensitiveContains would route every field of every
    /// contact through ICU collation on each keystroke.
    let foldedName: String
    let foldedAddress: String

    var id: String { "\(contact.localId)|\(address.lowercased())" }
}

nonisolated struct ContactSearchIndex: Sendable {
    let entries: [ContactSearchEntry]

    /// Contacts with no address are dropped — they can't become a token.
    init(contacts: [Contact] = []) {
        entries = contacts.flatMap { contact -> [ContactSearchEntry] in
            let name = contact.name.isEmpty ? contact.derivedDisplayName : contact.name
            return contact.emails.compactMap { email in
                let address = email.value.trimmingCharacters(in: .whitespaces)
                guard !address.isEmpty else { return nil }
                return ContactSearchEntry(
                    contact: contact,
                    address: address,
                    addressLabel: email.label,
                    displayName: name,
                    foldedName: Self.folded(name),
                    foldedAddress: Self.folded(address)
                )
            }
        }
    }

    static func folded(_ string: String) -> String {
        string.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

/// Why a row matched, best first. Prefix beats substring because people type
/// the start of what they mean; name beats address at equal prefix-ness
/// because the name is the row's primary label, so a name hit is what reads
/// as "closest". nameWordPrefix sits above addressPrefix so typing a surname
/// surfaces the person ahead of an unrelated address starting the same way.
nonisolated enum MatchRank: Int, Comparable, Sendable {
    case namePrefix = 0
    case nameWordPrefix
    case addressPrefix
    case nameSubstring
    case addressSubstring

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct ContactMatch: Identifiable, Hashable, Sendable {
    let entry: ContactSearchEntry
    let rank: MatchRank
    /// Ranges into the *original* strings, ready to slice for bolding.
    let nameHighlight: Range<String.Index>?
    let addressHighlight: Range<String.Index>?

    var id: String { entry.id }
}

nonisolated enum ContactSearch {
    struct Options: Sendable {
        /// nil = unlimited.
        var limit: Int?
        /// Caps rows per contact so one many-addressed contact can't fill the
        /// dropdown and hide everyone else. nil = unlimited.
        var maxPerContact: Int?
        var emptyQueryMatchesAll: Bool

        /// The compose dropdown: five rows, at most two per contact, and
        /// nothing at all until something is typed.
        static let autocomplete = Options(limit: 5, maxPerContact: 2, emptyQueryMatchesAll: false)

        /// The address book modal: the whole book, one row per contact.
        static let directory = Options(limit: nil, maxPerContact: 1, emptyQueryMatchesAll: true)
    }

    static func matches(
        _ query: String,
        in index: ContactSearchIndex,
        options: Options
    ) -> [ContactMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            guard options.emptyQueryMatchesAll else { return [] }
            let all = index.entries.map {
                (match: ContactMatch(entry: $0, rank: .namePrefix, nameHighlight: nil, addressHighlight: nil),
                 offset: 0)
            }
            return capped(ordered(all), options: options)
        }

        let folded = ContactSearchIndex.folded(trimmed)
        let scored = index.entries.compactMap { entry -> (match: ContactMatch, offset: Int)? in
            guard let (rank, offset) = rank(entry, matching: folded) else { return nil }
            return (
                ContactMatch(
                    entry: entry,
                    rank: rank,
                    nameHighlight: highlight(of: trimmed, in: entry.displayName),
                    addressHighlight: highlight(of: trimmed, in: entry.address)
                ),
                offset
            )
        }
        return capped(ordered(scored), options: options)
    }

    // MARK: - Ranking

    /// Ranks against the folded strings and reports where the hit started, so
    /// ties resolve by "how early does this match" rather than index order.
    private static func rank(_ entry: ContactSearchEntry, matching query: String) -> (MatchRank, Int)? {
        if entry.foldedName.hasPrefix(query) { return (.namePrefix, 0) }
        if let offset = wordPrefixOffset(of: query, in: entry.foldedName) {
            return (.nameWordPrefix, offset)
        }
        if entry.foldedAddress.hasPrefix(query) { return (.addressPrefix, 0) }
        if let offset = substringOffset(of: query, in: entry.foldedName) {
            return (.nameSubstring, offset)
        }
        if let offset = substringOffset(of: query, in: entry.foldedAddress) {
            return (.addressSubstring, offset)
        }
        return nil
    }

    /// Offset of the first word after the first that starts with `query`. The
    /// first word is skipped: that's a namePrefix, already ranked higher.
    private static func wordPrefixOffset(of query: String, in name: String) -> Int? {
        var offset = 0
        for word in name.split(separator: " ", omittingEmptySubsequences: false) {
            if offset > 0, word.hasPrefix(query) { return offset }
            offset += word.count + 1
        }
        return nil
    }

    private static func substringOffset(of query: String, in string: String) -> Int? {
        guard let found = string.range(of: query) else { return nil }
        return string.distance(from: string.startIndex, to: found.lowerBound)
    }

    // MARK: - Highlighting

    /// Locates `query` in the *original* string, never the folded one.
    /// Folding isn't length-preserving ("ß" folds to "ss", "ﬁ" to "fi"), so a
    /// range found in the folded string silently misaligns against the
    /// original — bolding the wrong characters, or trapping on an
    /// out-of-bounds String.Index. Matching the original with the same
    /// insensitivity options gives ranges in the right index space; when the
    /// folding is lossy enough that this finds nothing, no highlight is a
    /// better answer than a wrong one.
    private static func highlight(of query: String, in original: String) -> Range<String.Index>? {
        original.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: .current
        )
    }

    // MARK: - Ordering and caps

    /// Total order. The trailing keys exist so results are stable and
    /// assertable, not "whatever the filter happened to return".
    private static func ordered(_ scored: [(match: ContactMatch, offset: Int)]) -> [ContactMatch] {
        scored.sorted { lhs, rhs in
            if lhs.match.rank != rhs.match.rank { return lhs.match.rank < rhs.match.rank }
            if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
            let names = lhs.match.entry.displayName
                .localizedStandardCompare(rhs.match.entry.displayName)
            if names != .orderedSame { return names == .orderedAscending }
            return lhs.match.entry.address < rhs.match.entry.address
        }
        .map(\.match)
    }

    private static func capped(_ matches: [ContactMatch], options: Options) -> [ContactMatch] {
        guard options.limit != nil || options.maxPerContact != nil else { return matches }
        var perContact: [UUID: Int] = [:]
        var kept: [ContactMatch] = []
        for match in matches {
            if let maxPerContact = options.maxPerContact {
                let seen = perContact[match.entry.contact.localId, default: 0]
                guard seen < maxPerContact else { continue }
                perContact[match.entry.contact.localId] = seen + 1
            }
            kept.append(match)
            if let limit = options.limit, kept.count >= limit { break }
        }
        return kept
    }
}
