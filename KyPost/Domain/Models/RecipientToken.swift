//
//  RecipientToken.swift
//  KyPost
//
//  One committed recipient in a compose field (ContactAutocomplete.md §2).
//

import Foundation

/// A recipient pill. Not Codable on purpose: ComposeDraft is the persisted
/// shape (a WindowGroup scene value), and these carry UUID identities that
/// have no meaning across launches. Tokens are live editing state only.
nonisolated struct RecipientToken: Identifiable, Hashable, Sendable {
    let id: UUID
    /// The bare address, in the case it was typed or stored in. Never
    /// lowercased for display — see `comparisonKey` for matching.
    var address: String
    /// Set when contact-backed, or parsed out of a "Name <addr>" header.
    var displayName: String?
    /// nil for addresses typed by hand rather than picked from the book.
    var contactId: UUID?

    init(id: UUID = UUID(), address: String, displayName: String? = nil, contactId: UUID? = nil) {
        self.id = id
        self.address = address
        self.displayName = displayName
        self.contactId = contactId
    }

    /// Identity for duplicate detection. Local parts are case-sensitive per
    /// RFC 5321, but no mail system in practice treats them that way, and a
    /// user who types A@x.com and a@x.com means one person both times.
    var comparisonKey: String { address.lowercased() }

    var label: String {
        guard let displayName, !displayName.isEmpty else { return address }
        return displayName
    }

    var isContactBacked: Bool { contactId != nil }
}
