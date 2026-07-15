//
//  HighlightedText.swift
//  llama Mail
//
//  Text with the matched span emboldened, for autocomplete and address book
//  rows (ContactAutocomplete.md §2).
//

import SwiftUI

/// Renders `text`, bolding `highlight`.
///
/// Built by concatenating Texts rather than by styling an AttributedString:
/// ContactSearch hands back a Range<String.Index> into the original string,
/// and converting that into AttributedString's own index space is an
/// error-prone step with nothing to show for it.
struct HighlightedText: View {
    let text: String
    let highlight: Range<String.Index>?
    var font: Font
    var highlightFont: Font

    var body: some View {
        if let highlight {
            Text(String(text[text.startIndex..<highlight.lowerBound])).font(font)
                + Text(String(text[highlight])).font(highlightFont)
                + Text(String(text[highlight.upperBound...])).font(font)
        } else {
            Text(text).font(font)
        }
    }
}
