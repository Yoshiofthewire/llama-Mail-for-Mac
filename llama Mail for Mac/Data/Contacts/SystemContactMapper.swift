//
//  SystemContactMapper.swift
//  llama Mail
//
//  Pure Contact -> CNMutableContact field mapping. `apply` only touches the
//  mapped fields so anything the user added to a card in Contacts.app
//  (birthday, address, …) survives re-exports. Never writes `note`: that
//  requires the restricted com.apple.developer.contacts.notes entitlement.
//

import Contacts
import Foundation

enum SystemContactMapper {
    static let avatarUrlLabel = "Avatar"

    static let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactEmailAddressesKey,
        CNContactPhoneNumbersKey,
        CNContactUrlAddressesKey,
    ] as [CNKeyDescriptor]

    /// Splits on the last whitespace: "Ada M. Lovelace" -> ("Ada M.", "Lovelace").
    /// Empty names fall back to the email local-part so cards aren't blank.
    static func nameComponents(
        from name: String,
        fallbackEmail: String
    ) -> (given: String, family: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let localPart = fallbackEmail.split(separator: "@").first.map(String.init)
            return (localPart ?? "", "")
        }
        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        guard parts.count > 1 else { return (trimmed, "") }
        return (parts.dropLast().joined(separator: " "), String(parts.last!))
    }

    static func makeContact(from contact: Contact) -> CNMutableContact {
        let cn = CNMutableContact()
        apply(contact, to: cn)
        return cn
    }

    /// De-dupe identity across the app and Contacts.app: primary email when
    /// present (case-insensitive), else name + phone digits. Nil when there
    /// isn't enough signal to match safely.
    static func matchKey(name: String, email: String, phone: String) -> String? {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !email.isEmpty { return "email:\(email)" }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digits = phone.filter(\.isNumber)
        guard !name.isEmpty, !digits.isEmpty else { return nil }
        return "name+phone:\(name)|\(digits)"
    }

    static func matchKey(for contact: Contact) -> String? {
        matchKey(name: contact.name, email: contact.email, phone: contact.phone)
    }

    /// Every identity a card can match under: one key per email address,
    /// else the name+phone fallback.
    static func matchKeys(for cn: CNContact) -> [String] {
        let name = [cn.givenName, cn.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let emailKeys = cn.emailAddresses.compactMap {
            matchKey(name: name, email: $0.value as String, phone: "")
        }
        if !emailKeys.isEmpty { return emailKeys }
        let phone = cn.phoneNumbers.first?.value.stringValue ?? ""
        return matchKey(name: name, email: "", phone: phone).map { [$0] } ?? []
    }

    /// Reverse mapping for sync-back: a card added in Contacts.app becomes a
    /// local app contact queued for the next relay push.
    static func contact(from cn: CNContact) -> Contact {
        let now = Date()
        return Contact(
            name: [cn.givenName, cn.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            email: cn.emailAddresses.first.map { $0.value as String } ?? "",
            phone: cn.phoneNumbers.first?.value.stringValue ?? "",
            avatarUrl: nil,
            createdAt: now,
            updatedAt: now,
            needsSync: true
        )
    }

    static func apply(_ contact: Contact, to cn: CNMutableContact) {
        let (given, family) = nameComponents(from: contact.name, fallbackEmail: contact.email)
        cn.givenName = given
        cn.familyName = family
        cn.emailAddresses = contact.email.isEmpty
            ? []
            : [CNLabeledValue(label: CNLabelHome, value: contact.email as NSString)]
        cn.phoneNumbers = contact.phone.isEmpty
            ? []
            : [CNLabeledValue(
                label: CNLabelPhoneNumberMain,
                value: CNPhoneNumber(stringValue: contact.phone)
            )]
        cn.urlAddresses = contact.avatarUrl.map {
            [CNLabeledValue(label: Self.avatarUrlLabel, value: $0 as NSString)]
        } ?? []
    }
}
