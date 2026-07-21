//
//  KeywordSettingsView.swift
//  KyPost
//
//  Show/hide toggles per keyword (spec §2, §9). Keywords come from the
//  cached inbox; visibility persists in KeywordSettingsStore.
//

import SwiftUI

struct KeywordSettingsView: View {
    @Environment(\.theme) private var theme

    let viewModel: SettingsViewModel

    var body: some View {
        Group {
            if viewModel.keywordSettings.isEmpty {
                EmptyStateView(
                    message: "No keywords yet — they appear after your first inbox refresh.",
                    systemImage: "tag"
                )
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(viewModel.keywordSettings) { setting in
                    Toggle(
                        setting.name,
                        isOn: Binding(
                            get: { setting.visible },
                            set: { viewModel.setKeywordVisible($0, for: setting.name) }
                        )
                    )
                    .font(AppFont.ui(15))
                    .listRowBackground(theme.panel)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bg)
        .navigationTitle("Keyword Settings")
        .task { await viewModel.loadKeywordSettings() }
    }
}
