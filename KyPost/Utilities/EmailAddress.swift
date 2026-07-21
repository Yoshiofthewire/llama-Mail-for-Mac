//
//  EmailAddress.swift
//  KyPost
//
//  Address validation and header parsing for compose's recipient fields
//  (ContactAutocomplete.md §4).
//

import Foundation

nonisolated enum EmailAddress {
    /// RFC 5321 size caps, which the grammar below can't express.
    private static let maxLength = 254
    private static let maxLocalPartLength = 64

    /// True when `address` is a bare address we're willing to send to.
    ///
    /// This is the HTML5 email-input grammar, not RFC 5322. RFC 5322 is a
    /// deliberate non-goal: its real grammar accepts quoted local parts,
    /// comments, and IP-address literals that no one wants in a To field, and
    /// expressing it takes the notorious ~6.4KB regex. HTML5's production is
    /// itself specified as a willful violation of RFC 5322 for exactly this
    /// reason, and it's what mail clients actually enforce.
    ///
    /// One tightening over HTML5: the domain must contain a dot, so
    /// `alice@localhost` is rejected. Mail leaves via a relay here, so a
    /// TLD-less domain is a typo every time.
    static func isValid(_ address: String) -> Bool {
        guard address.count <= maxLength, let at = address.lastIndex(of: "@") else {
            return false
        }
        guard address.distance(from: address.startIndex, to: at) <= maxLocalPartLength else {
            return false
        }
        return address.wholeMatch(
            of: /[A-Za-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+/
        ) != nil
    }

    /// Splits a header or typed field into its entries, each "Name <addr>" or
    /// a bare address. Separators are "," (RFC) and ";" (what people type).
    ///
    /// Deliberately non-validating: ComposeDraft.replyAll feeds real headers
    /// through this and only wants the addresses out, while compose validates
    /// typed text separately with `isValid`. Entries without an "@" are
    /// dropped, which is what makes a trailing separator harmless.
    static func parse(_ text: String) -> [(name: String?, address: String)] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" }).compactMap { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard let open = trimmed.lastIndex(of: "<"),
                  let close = trimmed.lastIndex(of: ">"),
                  open < close
            else {
                return trimmed.contains("@") ? (nil, trimmed) : nil
            }
            let address = String(trimmed[trimmed.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
            guard !address.isEmpty else { return nil }
            let name = String(trimmed[trimmed.startIndex..<open])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? nil : name, address)
        }
    }
}
