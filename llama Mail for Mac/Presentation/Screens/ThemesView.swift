//
//  ThemesView.swift
//  llama Mail
//
//  Theme picker (spec §6): the 13 shared themes with palette swatches.
//

import SwiftUI

struct ThemesView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let active = themeManager.palette
        List(AppTheme.themeNames, id: \.self) { name in
            let palette = AppTheme.palette(named: name)
            Button {
                themeManager.setTheme(named: name)
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        swatch(palette.bg)
                        swatch(palette.panel)
                        swatch(palette.accent)
                    }
                    Text(name)
                        .font(AppFont.ui(15, weight: .medium))
                        .foregroundStyle(active.inkStrong)
                    Spacer()
                    if themeManager.themeName == name {
                        Image(systemName: "checkmark")
                            .foregroundStyle(active.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(active.panel)
        }
        .scrollContentBackground(.hidden)
        .background(active.bg)
        .navigationTitle("Theme")
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.gray.opacity(0.4), lineWidth: 0.5)
            )
    }
}
