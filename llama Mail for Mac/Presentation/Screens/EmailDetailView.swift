//
//  EmailDetailView.swift
//  llama Mail
//
//  Read view. HTML bodies render in a themed WebView (matching Android
//  EmailDetailActivity's wrapper); plain-text bodies use the mono font per
//  STYLE_GUIDE §2 (web .email-reader-body-block). Reply/forward are v2 stubs.
//

import QuickLook
import SwiftUI
import WebKit

struct EmailDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(\.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let email: Email
    let inboxViewModel: InboxViewModel

    /// Fetched lazily on open — the inbox listing has no attachment info.
    @State private var attachments: [EmailAttachment] = []
    @State private var downloadingIndex: Int?
    @State private var quickLookURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()
                .background(theme.panel, in: RoundedRectangle(cornerRadius: Shape.panel))
                .padding([.horizontal, .top])

            if !attachments.isEmpty {
                attachmentBar
            }

            if bodyLooksLikeHTML {
                EmailBodyWebView(html: themedHTML(email.body))
                    .padding()
            } else {
                ScrollView {
                    Text(email.body)
                        .font(AppFont.mono(14))
                        .foregroundStyle(theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .background(theme.bg)
        .navigationTitle(email.senderName.isEmpty ? "Email" : email.senderName)
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    Task {
                        await inboxViewModel.delete(serverIds: [email.serverId])
                        dismiss()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Move to Trash")
            }
        }
        .quickLookPreview($quickLookURL)
        .task {
            await inboxViewModel.markRead(email)
            attachments = await inboxViewModel.attachments(for: email)
        }
    }

    /// Attachment chips; tapping downloads to a temp file and Quick Looks it.
    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    Button {
                        openAttachment(attachment)
                    } label: {
                        HStack(spacing: 6) {
                            if downloadingIndex == attachment.index {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 11))
                            }
                            Text(attachment.name)
                                .font(AppFont.ui(12, weight: .medium))
                                .foregroundStyle(theme.inkStrong)
                                .lineLimit(1)
                            Text(attachment.size.formatted(.byteCount(style: .file)))
                                .font(AppFont.ui(10))
                                .foregroundStyle(theme.ink.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.panel, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadingIndex != nil)
                    .help("Download and preview")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func openAttachment(_ attachment: EmailAttachment) {
        downloadingIndex = attachment.index
        Task {
            if let url = await inboxViewModel.downloadAttachment(attachment, of: email) {
                quickLookURL = url
            }
            downloadingIndex = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(email.subject.isEmpty ? "(No subject)" : email.subject)
                .font(AppFont.ui(20, weight: .semibold))
                .foregroundStyle(theme.inkStrong)

            HStack(spacing: 10) {
                AvatarView(name: email.senderName.isEmpty ? email.senderEmail : email.senderName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.senderName.isEmpty ? email.senderEmail : email.senderName)
                        .font(AppFont.ui(15, weight: .medium))
                        .foregroundStyle(theme.inkStrong)
                    Text(email.senderEmail)
                        .font(AppFont.mono(12))
                        .foregroundStyle(theme.ink.opacity(0.8))
                }
                Spacer()
                Text(email.receivedAt, format: .dateTime.day().month().hour().minute())
                    .font(AppFont.ui(12))
                    .foregroundStyle(theme.ink.opacity(0.7))
            }

            if !email.keywords.isEmpty {
                HStack(spacing: 6) {
                    ForEach(email.keywords.sorted(), id: \.self) { keyword in
                        Text(keyword)
                            .font(AppFont.ui(11, weight: .medium))
                            .foregroundStyle(theme.readableOnAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(theme.accent))
                    }
                }
            }
        }
    }

    /// The relay serves HTML bodies inline on /api/inbox; plain-text messages
    /// come through without markup, so sniff for tags before using WebKit.
    private var bodyLooksLikeHTML: Bool {
        email.body.range(
            of: "<(html|head|body|div|p|br|table|tr|td|a|img|span|ul|ol|li|h[1-6])[\\s>/]",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Wraps the message HTML in the same themed scaffold Android uses
    /// (EmailDetailActivity), so colors track the active palette.
    private func themedHTML(_ body: String) -> String {
        """
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <style>
                body {
                    font-family: ui-monospace, Menlo, monospace;
                    font-size: 14px;
                    line-height: 1.5;
                    color: \(cssHex(theme.inkStrong));
                    background-color: \(cssHex(theme.bg));
                    margin: 0;
                    padding: 12px;
                    word-break: break-word;
                }
                a { color: \(cssHex(theme.accent)); }
                img { max-width: 100%; height: auto; }
                pre { white-space: pre-wrap; }
            </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private func cssHex(_ color: Color) -> String {
        let resolved = color.resolve(in: environment)
        func channel(_ value: Float) -> Int {
            Int((max(0, min(1, value)) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X",
            channel(resolved.red), channel(resolved.green), channel(resolved.blue)
        )
    }
}

/// Renders one email's HTML; link taps open in the default browser instead
/// of navigating the message view.
private struct EmailBodyWebView: View {
    let html: String

    @Environment(\.openURL) private var openURL
    @State private var page: WebPage?

    var body: some View {
        Group {
            if let page {
                WebView(page)
                    .webViewBackForwardNavigationGestures(.disabled)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: html) {
            let page = self.page ?? WebPage(navigationDecider: LinksOpenExternally(openURL: openURL))
            self.page = page
            page.load(html: html)
        }
    }

    private struct LinksOpenExternally: WebPage.NavigationDeciding {
        let openURL: OpenURLAction

        func decidePolicy(
            for action: WebPage.NavigationAction,
            preferences: inout WebPage.NavigationPreferences
        ) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated else { return .allow }
            if let url = action.request.url {
                openURL(url)
            }
            return .cancel
        }
    }
}
