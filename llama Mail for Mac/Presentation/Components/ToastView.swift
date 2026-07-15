//
//  ToastView.swift
//  llama Mail
//
//  Bottom-anchored transient message, shared by the contact list's sync
//  status and compose's duplicate-recipient notice.
//

import SwiftUI

struct ToastView: View {
    @Environment(\.theme) private var theme

    let message: String

    var body: some View {
        Text(message)
            .font(AppFont.ui(13))
            .foregroundStyle(theme.inkStrong)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.line, lineWidth: 1))
            .padding(.bottom, 10)
    }
}

extension View {
    /// Shows `message` over the bottom of this view, or nothing when nil.
    ///
    /// A pure renderer: dismissal is the caller's business. The contact
    /// screens pass a sync status that's meant to persist until it changes,
    /// while compose expires its own toast on a timer — so a timer in here
    /// would be wrong for half the callers.
    func toast(message: String?) -> some View {
        overlay(alignment: .bottom) {
            if let message {
                ToastView(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}
