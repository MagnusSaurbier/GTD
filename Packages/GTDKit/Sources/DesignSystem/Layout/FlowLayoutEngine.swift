import Foundation

// STYLEGUIDE §3.1 — chips "wrap lines, `chipGap` both ways. Never a horizontal scroller on the
// card." This is the pure row-wrapping algorithm behind the SwiftUI `Layout` conformance in
// `Components/Chip.swift`; it is Foundation-only so it is unit-tested on Linux without a
// compiled `Layout` protocol witness.

/// Wraps a sequence of item sizes into rows that fit within `maxWidth`, placing `spacing`
/// between items on both axes. One greedy left-to-right pass, matching `FlowLayout`.
public enum FlowLayoutEngine {

    /// One item's row index and top-left position within the overall bounds.
    public struct Placement: Sendable, Equatable {
        public let index: Int
        public let row: Int
        public let position: CGPoint
    }

    public struct Result: Sendable, Equatable {
        public let placements: [Placement]
        /// The bounding size: as wide as the widest row (capped at `maxWidth` when finite),
        /// as tall as every row's height plus the vertical gaps between them.
        public let size: CGSize
    }

    /// - Parameters:
    ///   - sizes: each subview's own size, in the order they should be placed.
    ///   - maxWidth: the width to wrap within. `.infinity` never wraps (one row).
    ///   - spacing: gap between items, used both between columns and between rows.
    public static func layout(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> Result {
        guard !sizes.isEmpty else { return Result(placements: [], size: .zero) }

        struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
        var rows: [Row] = []
        var current = Row()

        for index in sizes.indices {
            let size = sizes[index]
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, maxWidth.isFinite, needed > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }

        var placements: [Placement] = []
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            var x: CGFloat = 0
            for index in row.indices {
                let size = sizes[index]
                // Vertically center within the row, matching `FlowLayout.placeSubviews`.
                let itemY = y + (row.height - size.height) / 2
                placements.append(Placement(index: index, row: rowIndex, position: CGPoint(x: x, y: itemY)))
                x += size.width + spacing
            }
            y += row.height + spacing
        }

        let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let contentWidth = rows.map(\.width).max() ?? 0
        let width = maxWidth.isFinite ? min(contentWidth, maxWidth) : contentWidth
        return Result(placements: placements, size: CGSize(width: width, height: totalHeight))
    }
}
