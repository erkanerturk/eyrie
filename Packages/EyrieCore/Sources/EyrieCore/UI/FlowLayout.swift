import SwiftUI

/// Left-aligned layout that wraps onto new lines instead of clipping or
/// squeezing. The panel is a fixed 340 pt wide, so a row of status badges can
/// overflow — this keeps every badge legible on its own line rather than
/// truncating them all.
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 5, lineSpacing: CGFloat = 4) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    /// Subviews are measured once per layout pass and the resulting rows are
    /// reused: `sizeThatFits` and `placeSubviews` are called back to back with
    /// the same width, and re-measuring in each (plus again while placing) cost
    /// four `sizeThatFits` calls per badge.
    public struct Cache {
        var sizes: [CGSize] = []
        var rows: [Row] = []
        var rowsWidth: CGFloat = .nan
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.rows = []
        cache.rowsWidth = .nan
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(in: &cache, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } +
            lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let rows = rows(in: &cache, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = cache.sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    public struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(in cache: inout Cache, maxWidth: CGFloat) -> [Row] {
        if cache.rowsWidth == maxWidth { return cache.rows }
        let rows = layout(sizes: cache.sizes, maxWidth: maxWidth)
        cache.rows = rows
        cache.rowsWidth = maxWidth
        return rows
    }

    private func layout(sizes: [CGSize], maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in sizes.indices {
            let size = sizes[index]
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
