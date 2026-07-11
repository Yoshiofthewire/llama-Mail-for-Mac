//
//  Email.swift
//  llama Mail
//
//  Domain model for a received email (spec §8 emails table).
//

import Foundation

struct Email: Identifiable, Hashable, Sendable {
    /// IMAP UID or Relay ID.
    var serverId: String
    var folder: String
    var senderName: String
    var senderEmail: String
    var subject: String
    var body: String
    /// IMAP user flags (KEYWORD tokens) or relay tab/label values; drives inbox tabs.
    var keywords: Set<String>
    var receivedAt: Date
    var read: Bool
    var starred: Bool

    var id: String { serverId }
}

/// A folder on the mail server (spec §2 MailGateway.listFolders).
struct MailFolder: Hashable, Sendable {
    var name: String
}

/// An email being composed (spec §7 SendEmailUseCase).
struct OutgoingEmail: Sendable {
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var subject: String
    var body: String
    // ponytail: no attachment support in v1, add file picker + multipart/form-data in v2
    var attachments: [AttachmentRef] = []
    /// Relay mode only: server-side categorization.
    var tab: String?
}

struct AttachmentRef: Hashable, Sendable {
    var fileName: String
    var url: URL
}
