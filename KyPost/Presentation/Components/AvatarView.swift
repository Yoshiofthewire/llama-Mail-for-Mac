//
//  AvatarView.swift
//  KyPost
//
//  Circular gradient avatar with initials (STYLE_GUIDE §4, web
//  .contacts-avatar): two-stop accent gradient, 1pt border, 34pt list /
//  52pt detail sizes.
//

import SwiftUI

struct AvatarView: View {
    @Environment(\.theme) private var theme

    let name: String
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [theme.accent, theme.accentSoft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(Circle().strokeBorder(theme.line, lineWidth: 1))
            .overlay {
                Text(initials)
                    .font(AppFont.ui(size * 0.38, weight: .semibold))
                    .foregroundStyle(theme.readableOnAccent)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
