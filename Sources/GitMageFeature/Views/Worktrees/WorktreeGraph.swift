import AinkradAppKit
import SwiftUI

/// Lane colors for the commit graph — theme accents first, then a few fixed
/// hues for deeper branch nesting (data viz, like label colors).
enum GraphPalette {
    static func color(_ index: Int, _ tokens: HostThemeTokens) -> Color {
        let base: [Color] = [
            tokens.accentPrimary, tokens.accentSecondary, tokens.accentTertiary,
            Color(red: 0.38, green: 0.80, blue: 0.52),  // design-lint: allow raw-color token-gap graphLane
            Color(red: 0.92, green: 0.62, blue: 0.32),  // design-lint: allow raw-color token-gap graphLane
            Color(red: 0.60, green: 0.52, blue: 0.92),  // design-lint: allow raw-color token-gap graphLane
        ]
        return base[((index % base.count) + base.count) % base.count]
    }
}

/// Shared geometry for the graph gutter, so the canvas that draws the lanes and
/// the frame that reserves room for them can never disagree.
enum GraphLayout {
    static let laneSpacing: CGFloat = 14
    static let gutterPadding: CGFloat = 8

    /// Grows with the lane count — every lane's node and edges stay inside it.
    static func gutterWidth(laneCount: Int) -> CGFloat {
        CGFloat(max(laneCount, 1)) * laneSpacing + gutterPadding
    }

    /// Center x of a lane inside the gutter.
    static func laneX(_ lane: Int) -> CGFloat { CGFloat(lane) * laneSpacing + laneSpacing / 2 }
}

/// Draws one row's slice of the commit graph: pass-through/merge lanes and the
/// node, using the row's `before`/`after` lane occupancy.
struct GraphGutter: View {
    @Environment(\.ainkradSkin) private var skin
    let row: GraphRow
    let isSelected: Bool
    let tokens: HostThemeTokens

    var body: some View {
        Canvas { ctx, size in
            let h = size.height
            let center = h / 2
            let sha = row.commit.sha
            func x(_ c: Int) -> CGFloat { GraphLayout.laneX(c) }

            // A connector that leaves/enters each end vertically (an S-curve when
            // the columns differ), so lanes read as smooth branches, not steep
            // full-row diagonals.
            func connector(_ from: CGPoint, _ to: CGPoint) -> Path {
                var p = Path()
                p.move(to: from)
                if abs(from.x - to.x) < 0.5 {
                    p.addLine(to: to)
                } else {
                    let midY = (from.y + to.y) / 2
                    p.addCurve(
                        to: to,
                        control1: CGPoint(x: from.x, y: midY),
                        control2: CGPoint(x: to.x, y: midY))
                }
                return p
            }

            // Lanes entering from the top: merge into the node, or pass through.
            for (c, entry) in row.before.enumerated() {
                guard let entry else { continue }
                if entry == sha {
                    ctx.stroke(
                        connector(CGPoint(x: x(c), y: 0), CGPoint(x: x(row.col), y: center)),
                        with: .color(GraphPalette.color(c, tokens)), lineWidth: 2)
                } else {
                    let bcol = row.after.firstIndex(of: entry) ?? c
                    ctx.stroke(
                        connector(CGPoint(x: x(c), y: 0), CGPoint(x: x(bcol), y: h)),
                        with: .color(GraphPalette.color(bcol, tokens)), lineWidth: 2)
                }
            }

            // Node → each parent (first parent stays in this lane; merges fan out).
            for parent in row.commit.parents {
                let bcol = row.after.firstIndex(of: parent) ?? row.col
                ctx.stroke(
                    connector(CGPoint(x: x(row.col), y: center), CGPoint(x: x(bcol), y: h)),
                    with: .color(GraphPalette.color(bcol, tokens)), lineWidth: 2)
            }

            // The commit node.
            let nodeColor = isSelected ? tokens.accentPrimary : GraphPalette.color(row.col, tokens)
            let r: CGFloat = isSelected ? 5 : 4
            let dot = CGRect(x: x(row.col) - r, y: center - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: dot), with: .color(nodeColor))
            if isSelected {
                ctx.stroke(
                    Path(ellipseIn: dot.insetBy(dx: -2.5, dy: -2.5)),
                    with: .color(tokens.accentPrimary.opacity(skin.opacity.o50)), lineWidth: 1.5)
            }
        }
    }
}

/// An interactive graph row: gutter + commit info; tap to select (loads its diff).
struct GraphCommitRow: View {
    @Environment(\.ainkradSkin) private var skin
    let row: GraphRow
    let laneCount: Int
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    @State private var hovering = false

    private let rowHeight: CGFloat = 34
    private var gutterWidth: CGFloat { GraphLayout.gutterWidth(laneCount: laneCount) }

    var body: some View {
        HStack(spacing: skin.spacing.sm) {
            GraphGutter(row: row, isSelected: isSelected, tokens: tokens)
                .frame(width: gutterWidth, height: rowHeight)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(row.commit.summary)
                    .font(AinkradFont.display(skin.type.sizes.t12))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : skin.opacity.o90))
                    .lineLimit(1)
                GMCommitMeta(
                    sha: row.commit.shortSHA, author: row.commit.author, date: row.commit.relativeDate,
                    tokens: tokens)
            }
            Spacer(minLength: 4)
        }
        .padding(.trailing, skin.size.s10)
        .frame(height: rowHeight)
        .ainkradRowBackground(isSelected: isSelected, isHovered: hovering)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}
