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

    init(sendEmail: SendEmailUseCase) {
        self.sendEmail = sendEmail
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
