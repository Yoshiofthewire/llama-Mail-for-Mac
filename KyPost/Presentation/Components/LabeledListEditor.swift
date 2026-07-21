//
//  LabeledListEditor.swift
//  KyPost
//
//  Generic multi-value editor section for the contact edit form: one row per
//  item (caller supplies the row fields), a remove button per row, and an
//  add button. Rows bind by index into the caller's draft array — fine for a
//  form-local value-type draft.
//

import SwiftUI

struct EditableListSection<Item, RowContent: View>: View {
    @Environment(\.theme) private var theme

    let title: String
    let addTitle: String
    @Binding var items: [Item]
    let makeItem: () -> Item
    @ViewBuilder let row: (Binding<Item>) -> RowContent

    var body: some View {
        Section(title) {
            ForEach(Array(items.indices), id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    row($items[index])
                    Button {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                items.append(makeItem())
            } label: {
                Label(addTitle, systemImage: "plus.circle.fill")
                    .font(AppFont.ui(14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
        }
        .listRowBackground(theme.panel)
    }
}

/// Label + value pair row (emails, phones, websites, custom fields).
struct LabeledValueRow: View {
    @Binding var label: String?
    @Binding var value: String
    var labelPlaceholder = "Label"
    var valuePlaceholder = "Value"

    var body: some View {
        HStack(spacing: 8) {
            TextField(labelPlaceholder, text: Binding(
                get: { label ?? "" },
                set: { label = $0.isEmpty ? nil : $0 }
            ))
            .font(AppFont.ui(13))
            .frame(width: 90)
            TextField(valuePlaceholder, text: $value)
                .font(AppFont.mono(14))
        }
    }
}
