//
//  RichTextHTML.swift
//  KyPost
//
//  Converts compose rich text (AttributedString from the styled TextEditor)
//  into the minimal HTML the relay's mode:"html" send path expects
//  (Mobile_Mail_Relay.md). Bold/italic live in the SwiftUI font attribute,
//  which is only introspectable through Font.resolve(in:) — callers inject
//  that as a closure so this logic stays unit-testable without a view.
//

import Foundation
import SwiftUI

enum RichTextHTML {
    /// Bold/italic lookup for a run's font. Views build one from
    /// `@Environment(\.fontResolutionContext)`; tests inject a fake.
    typealias FontTraits = (Font) -> (bold: Bool, italic: Bool)

    /// True when any run carries formatting the converter would emit —
    /// unformatted drafts should be sent as mode:"plain" instead.
    static func hasFormatting(_ text: AttributedString, fontTraits: FontTraits) -> Bool {
        text.runs.contains { run in
            if run.underlineStyle != nil || run.strikethroughStyle != nil || run.link != nil {
                return true
            }
            guard let font = run.font else { return false }
            let traits = fontTraits(font)
            return traits.bold || traits.italic
        }
    }

    /// A full HTML document for the message body. The `<html>/<body>` wrapper
    /// matters: readers (including our EmailDetailView) sniff for structural
    /// tags to decide between WebKit and plain-text rendering.
    static func htmlDocument(from text: AttributedString, fontTraits: FontTraits) -> String {
        var fragments = ""
        for run in text.runs {
            var fragment = escape(String(text.characters[run.range]))
                .replacingOccurrences(of: "\n", with: "<br>\n")

            var bold = false
            var italic = false
            if let font = run.font {
                (bold, italic) = fontTraits(font)
            }
            if run.strikethroughStyle != nil {
                fragment = "<s>\(fragment)</s>"
            }
            if run.underlineStyle != nil {
                fragment = "<u>\(fragment)</u>"
            }
            if italic {
                fragment = "<em>\(fragment)</em>"
            }
            if bold {
                fragment = "<strong>\(fragment)</strong>"
            }
            if let link = run.link {
                fragment = "<a href=\"\(escape(link.absoluteString))\">\(fragment)</a>"
            }
            fragments += fragment
        }
        return "<html><body>\(fragments)</body></html>"
    }

    /// Escapes text content and attribute values.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
