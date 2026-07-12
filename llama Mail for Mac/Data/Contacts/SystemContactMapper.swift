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
