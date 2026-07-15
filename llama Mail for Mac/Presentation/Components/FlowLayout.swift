//
//  FlowLayout.swift
//  llama Mail
//
//  Left-to-right layout that wraps onto new lines. HStack doesn't wrap and
//  LazyVGrid won't size itself to its content, so compose's recipient pills
//  need this.
//

import SwiftUI

/// Marks the subview that should stretch into whatever width is left on its
/// line, rather than be measured at its ideal size.
///
/// This exists for the text field trailing the pills: measured with an
/// unspecified proposal it reports an enormous ideal width, so a greedy
/// line-breaker always bumps it to a line of its own.
private struct FlowGreedyKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    func flowGreedy() -> some View {
        layoutValue(key: FlowGreedyKey.self, value: true)
    }
}

nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    /// A greedy subview breaks to the next line rather than be squeezed
    /// below this.
    var minGreedyWidth: CGFloat = 120

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = layout(subviews: subviews, maxWidth: maxWidth)
        let height = lines.reduce(0) { $0 + $1.height } +
            lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: maxWidth.isFinite ? maxWidth : lines.map(\.width).max() ?? 0,
                      height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for line in layout(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                let subview = subviews[item.index]
                let width = item.isGreedy
                    ? max(bounds.maxX - x, minGreedyWidth)
                    : item.size.width
                subview.place(
                    at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
                    proposal: ProposedViewSize(width: width, height: item.size.height)
                )
                x += width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    // MARK: - Line breaking

    private struct Item {
        var index: Int
        var size: CGSize
        var isGreedy: Bool
    }

    private struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines = [Line()]
        var x: CGFloat = 0
        for index in subviews.indices {
            let subview = subviews[index]
            let isGreedy = subview[FlowGreedyKey.self]
            // A greedy subview is measured against the space actually left,
            // never its (unbounded) ideal width. With no width proposed at
            // all there's no "space left" to offer, so it gets its minimum —
            // proposing infinity back would make it report an infinite ideal
            // and hand an infinite size to our caller.
            let greedyWidth = maxWidth.isFinite ? max(maxWidth - x, minGreedyWidth) : minGreedyWidth
            let size = isGreedy
                ? subview.sizeThatFits(ProposedViewSize(width: greedyWidth, height: nil))
                : subview.sizeThatFits(.unspecified)
            let needed = isGreedy ? minGreedyWidth : size.width
            let fits = x == 0 || x + needed <= maxWidth

            if !fits {
                lines.append(Line())
                x = 0
            }
            lines[lines.count - 1].items.append(
                Item(index: index, size: size, isGreedy: isGreedy)
            )
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
            x += size.width + spacing
            lines[lines.count - 1].width = x - spacing
        }
        return lines
    }
}
