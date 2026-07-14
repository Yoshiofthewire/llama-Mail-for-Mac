//
//  ComposeViewModel.swift
//  llama Mail
//
//  Compose state (spec §7). On failure the draft stays in memory — no DB
//  auto-save. The body is rich text: formatted drafts send as mode:"html"
//  (RichTextHTML), unformatted ones stay mode:"plain".
//

import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A file staged for sending; kept in memory with its loaded bytes.
struct ComposeAttachment: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var mimeType: String
    var data: Data
}

@Observable
@MainActor
final class ComposeViewModel {
    private let sendEmail: SendEmailUseCase

    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = AttributedString()
    var attachments: [ComposeAttachment] = []

    private(set) var isSending = false
    private(set) var errorMessage: String?
    private(set) var didSend = false

    init(sendEmail: SendEmailUseCase, draft: ComposeDraft? = nil) {
        self.sendEmail = sendEmail
        if let draft {
            to = draft.to
            cc = draft.cc
            subject = draft.subject
            body = AttributedString(draft.body)
        }
    }

    var attachmentTotalBytes: Int {
        attachments.reduce(0) { $0 + $1.data.count }
    }

    /// Loads a picked/dropped file into the draft, enforcing the same 25 MB
    /// total budget the backend applies. fileImporter URLs are
    /// security-scoped; access is claimed around the read.
    func addAttachment(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            guard attachmentTotalBytes + data.count <= SendEmailUseCase.maxAttachmentBytes else {
                errorMessage = "Attachments too large (max 25 MB total)"
                return
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?
                .preferredMIMEType ?? "application/octet-stream"
            attachments.append(ComposeAttachment(
                name: url.lastPathComponent,
                mimeType: mimeType,
                data: data
            ))
            errorMessage = nil
        } catch {
            errorMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func removeAttachment(_ attachment: ComposeAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    /// Sends the draft. `fontTraits` resolves bold/italic on body runs (from
    /// the view's font resolution context) so formatted text goes out as HTML.
    func send(fontTraits: @escaping RichTextHTML.FontTraits) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        let isHTML = RichTextHTML.hasFormatting(body, fontTraits: fontTraits)
        let outcome = await sendEmail(OutgoingEmail(
            to: recipients(from: to),
            cc: recipients(from: cc),
            bcc: recipients(from: bcc),
            subject: subject,
            body: isHTML
                ? RichTextHTML.htmlDocument(from: body, fontTraits: fontTraits)
                : String(body.characters),
            mode: isHTML ? "html" : "plain",
            attachments: attachments.map {
                OutgoingAttachment(name: $0.name, mimeType: $0.mimeType, data: $0.data)
            }
        ))
        switch outcome {
        case .success:
            didSend = true
            errorMessage = nil
        case .invalid(let message):
            errorMessage = message
        case .unauthorized:
            errorMessage = "Not authorized — re-pair the device or check credentials."
        case .notPaired:
            errorMessage = "Pair this device before sending."
        case .failure(let message):
            errorMessage = message
        }
    }

    private func recipients(from field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Reply / Reply All / Forward drafts

/// Prefilled compose state built from an existing email. Codable + Hashable
/// so macOS can pass it as a "compose" WindowGroup value; Identifiable so
/// iOS can present it with sheet(item:).
struct ComposeDraft: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var to = ""
    var cc = ""
    var subject = ""
    var body = ""

    static func reply(to email: Email) -> ComposeDraft {
        ComposeDraft(
            to: email.senderEmail.isEmpty ? email.senderName : email.senderEmail,
            subject: prefixed("Re:", email.subject),
            body: quotedBody(of: email)
        )
    }

    /// Reply to the sender, Cc'ing everyone else on the original To/Cc —
    /// minus the sender (already in To) and our own address (`ownAddress`,
    /// the pairing's sub).
    static func replyAll(to email: Email, ownAddress: String?) -> ComposeDraft {
        var draft = reply(to: email)
        var excluded = [email.senderEmail.lowercased()]
        if let ownAddress { excluded.append(ownAddress.lowercased()) }
        var seen = Set<String>()
        let others = (addresses(in: email.sentTo) + addresses(in: email.cc)).filter {
            !excluded.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted
        }
        draft.cc = others.joined(separator: ", ")
        return draft
    }

    static func forward(_ email: Email) -> ComposeDraft {
        let sender = email.senderName == email.senderEmail || email.senderName.isEmpty
            ? email.senderEmail
            : "\(email.senderName) <\(email.senderEmail)>"
        var header = """
        ---------- Forwarded message ----------
        From: \(sender)
        Date: \(email.receivedAt.formatted(date: .abbreviated, time: .shortened))
        Subject: \(email.subject)
        """
        if !email.sentTo.isEmpty {
            header += "\nTo: \(email.sentTo)"
        }
        return ComposeDraft(
            subject: prefixed("Fwd:", email.subject),
            body: "\n\n\(header)\n\n\(plainText(email.body))"
        )
    }

    // MARK: - Helpers

    /// "Re:"/"Fwd:" prefix, skipped when the subject already carries it.
    private static func prefixed(_ prefix: String, _ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
            return trimmed
        }
        return trimmed.isEmpty ? prefix : "\(prefix) \(trimmed)"
    }

    /// "On {date}, {sender} wrote:" attribution plus the original body,
    /// each line "> "-quoted, after two blank lines for the reply text.
    private static func quotedBody(of email: Email) -> String {
        let sender = email.senderName.isEmpty ? email.senderEmail : email.senderName
        let date = email.receivedAt.formatted(date: .abbreviated, time: .shortened)
        let quoted = plainText(email.body)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return "\n\nOn \(date), \(sender) wrote:\n\(quoted)"
    }

    /// Bare addresses from a comma-joined header string whose entries may be
    /// "Name <addr>" or bare addresses.
    private static func addresses(in header: String) -> [String] {
        header.split(separator: ",").compactMap { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            if let open = trimmed.lastIndex(of: "<"),
               let close = trimmed.lastIndex(of: ">"),
               open < close {
                return String(trimmed[trimmed.index(after: open)..<close])
                    .trimmingCharacters(in: .whitespaces)
            }
            return trimmed.contains("@") ? trimmed : nil
        }
    }

    /// Reduces an HTML body to quotable plain text (the compose editor is
    /// text, not a web view): tags stripped, block ends → newlines, common
    /// entities decoded. Plain bodies pass through untouched.
    static func plainText(_ body: String) -> String {
        guard body.range(of: "<[a-zA-Z!/]", options: .regularExpression) != nil else {
            return body
        }
        var text = body
        for pattern in ["(?is)<(style|script|head)\\b.*?</\\1>", "(?s)<!--.*?-->"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(
            of: "(?i)<br\\b[^>]*>|</(p|div|tr|li|h[1-6]|blockquote|table)>",
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        // Collapse the newline runs left behind by nested block markup.
        text = text.replacingOccurrences(
            of: "\\n[ \\t]*(\\n[ \\t]*)+",
            with: "\n\n",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
