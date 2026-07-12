//
//  ComposeView.swift
//  llama Mail
//
//  Compose UI (spec §7): aligned header fields, a rich-text body
//  (Bold/Italic/Underline toolbar + system formatting controls; formatted
//  drafts send as mode:"html"), and attachments via file picker or drag &
//  drop. macOS shows this in its own window ("compose" WindowGroup,
//  ⌘↩ sends); iOS presents it as a sheet. Errors show inline and keep the
//  draft in memory.
//

import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontResolutionContext) private var fontResolutionContext

    @State private var viewModel = ComposeViewModel(
        sendEmail: SingletonGraph.shared.sendEmailUseCase
    )
    @State private var selection = AttributedTextSelection()
    @State private var showFileImporter = false

    var body: some View {
#if os(macOS)
        content
            .frame(minWidth: 560, minHeight: 480)
#else
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
        }
#endif
    }

    private var content: some View {
        VStack(spacing: 0) {
            headerFields
                .padding(.horizontal)
                .padding(.vertical, 10)

            Divider().overlay(theme.line)

            TextEditor(text: $viewModel.body, selection: $selection)
                .font(AppFont.mono(14))
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .textInputFormattingControlVisibility(.visible, for: .all)
                .padding(8)
                .frame(minHeight: 160)

            if !viewModel.attachments.isEmpty {
                attachmentBar
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(AppFont.ui(13))
                    .foregroundStyle(SemanticColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .background(theme.bg)
        .navigationTitle("New Email")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    viewModel.addAttachment(from: url)
                }
            }
        }
        // Dragging files from Finder anywhere onto the compose surface
        // attaches them (addAttachment ignores non-file URLs).
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            for url in files {
                viewModel.addAttachment(from: url)
            }
            return true
        }
        .onChange(of: viewModel.didSend) {
            if viewModel.didSend { dismiss() }
        }
        .tint(theme.accent)
    }

    // MARK: - Header fields

    private var headerFields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            headerRow("To:") {
                TextField("recipient@example.com, another@example.com", text: $viewModel.to)
                    .font(AppFont.mono(13))
            }
            headerRow("Cc:") {
                TextField("", text: $viewModel.cc)
                    .font(AppFont.mono(13))
            }
            headerRow("Bcc:") {
                TextField("", text: $viewModel.bcc)
                    .font(AppFont.mono(13))
            }
            headerRow("Subject:") {
                TextField("", text: $viewModel.subject)
                    .font(AppFont.ui(14, weight: .medium))
            }
        }
        .textFieldStyle(.plain)
#if os(iOS)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
#endif
    }

    private func headerRow(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        GridRow {
            Text(label)
                .font(AppFont.ui(12, weight: .medium))
                .foregroundStyle(theme.ink.opacity(0.7))
                .gridColumnAlignment(.trailing)
            field()
                .foregroundStyle(theme.inkStrong)
        }
    }

    // MARK: - Attachments

    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(attachment.name)
                                .font(AppFont.ui(12, weight: .medium))
                                .foregroundStyle(theme.inkStrong)
                                .lineLimit(1)
                            Text(attachment.data.count.formatted(.byteCount(style: .file)))
                                .font(AppFont.ui(10))
                                .foregroundStyle(theme.ink.opacity(0.7))
                        }
                        Button {
                            viewModel.removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.ink.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Remove attachment")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.panel, in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItemGroup {
            ControlGroup {
                Toggle(isOn: boldBinding) {
                    Label("Bold", systemImage: "bold")
                }
                .keyboardShortcut("b")
                Toggle(isOn: italicBinding) {
                    Label("Italic", systemImage: "italic")
                }
                .keyboardShortcut("i")
                Toggle(isOn: underlineBinding) {
                    Label("Underline", systemImage: "underline")
                }
                .keyboardShortcut("u")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Attach File", systemImage: "paperclip")
            }
            .help("Attach a file (max 25 MB total)")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task { await viewModel.send(fontTraits: fontTraits) }
            } label: {
                if viewModel.isSending {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Send", systemImage: "paperplane.fill")
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.isSending)
            .help("Send (⌘↩)")
        }
    }

    // MARK: - Formatting

    /// Resolves a run's font to concrete traits so ComposeViewModel /
    /// RichTextHTML can tell bold/italic apart without a view environment.
    private var fontTraits: RichTextHTML.FontTraits {
        { [fontResolutionContext] font in
            let resolved = font.resolve(in: fontResolutionContext)
            return (resolved.isBold, resolved.isItalic)
        }
    }

    /// Bold/italic toggles follow the documented rich-TextEditor pattern:
    /// read the typing attributes, write through transformAttributes.
    private var boldBinding: Binding<Bool> {
        Binding {
            let font = selection.typingAttributes(in: viewModel.body).font ?? .default
            return font.resolve(in: fontResolutionContext).isBold
        } set: { isBold in
            viewModel.body.transformAttributes(in: &selection) {
                $0.font = ($0.font ?? .default).bold(isBold)
            }
        }
    }

    private var italicBinding: Binding<Bool> {
        Binding {
            let font = selection.typingAttributes(in: viewModel.body).font ?? .default
            return font.resolve(in: fontResolutionContext).isItalic
        } set: { isItalic in
            viewModel.body.transformAttributes(in: &selection) {
                $0.font = ($0.font ?? .default).italic(isItalic)
            }
        }
    }

    private var underlineBinding: Binding<Bool> {
        Binding {
            selection.typingAttributes(in: viewModel.body).underlineStyle != nil
        } set: { isOn in
            viewModel.body.transformAttributes(in: &selection) {
                $0.underlineStyle = isOn ? .single : nil
            }
        }
    }
}
