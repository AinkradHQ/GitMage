import SwiftUI
import AinkradAppKit

/// A parsed diff plus everything the view needs to derive from it, computed
/// ONCE per diff instead of four times per render.
///
/// WHY this exists: `DiffView.body` previously called `Self.parse(diff.body)`
/// inline, then walked the result three more times (two `filter`s for the
/// header counts, one `map`/`max` for the column width). SwiftUI re-evaluates
/// `body` on every dependency change, so a 5,000-line diff paid four full
/// passes each time — before `ForEach` built 5,000 views.
struct DiffRows: Equatable {
    let rows: [DiffView.Row]
    let additions: Int
    let deletions: Int
    let codeWidth: CGFloat
    let hasTextualChanges: Bool

    init(body: String, fontSize: Double) {
        let rows = DiffView.parse(body)
        self.rows = rows

        // One pass for all four derived values, rather than three passes.
        var additions = 0
        var deletions = 0
        var maxLength = 0
        var hasTextual = false
        for row in rows {
            switch row.kind {
            case .add: additions += 1
            case .remove: deletions += 1
            default: break
            }
            if row.kind != .meta {
                hasTextual = true
                maxLength = max(maxLength, DiffView.displayText(row).count)
            }
        }
        self.additions = additions
        self.deletions = deletions
        self.hasTextualChanges = hasTextual
        self.codeWidth = max(CGFloat(maxLength) * CGFloat(fontSize) * 0.62 + 10, 80)
    }
}

struct DiffView: View {
    let diff: GitDiffSnapshot?
    let tokens: HostThemeTokens
    let fontSize: Double
    /// Embedded mode (e.g. inside an expanded file row): no own vertical scroll
    /// and no header — the diff flows in the parent's scroll.
    var embedded: Bool = false
    var showHeader: Bool = true

    private let numberWidth: CGFloat = 34
    private let signWidth: CGFloat = 16
    private var gutterWidth: CGFloat { numberWidth * 2 + 8 }

    enum LineKind { case hunk, add, remove, context, meta }
    struct Row: Identifiable, Equatable {
        let id: Int
        let kind: LineKind
        let oldNo: Int?
        let newNo: Int?
        let text: String
    }

    var body: some View {
        if let diff {
            // Computed once per (diff, fontSize) rather than four times per render.
            let parsed = DiffRows(body: diff.body, fontSize: fontSize)
            VStack(alignment: .leading, spacing: 0) {
                if showHeader {
                    header(title: diff.title, parsed: parsed)
                    GlowRule(tokens: tokens)
                }
                content(parsed)
            }
            .frame(maxWidth: .infinity, maxHeight: embedded ? nil : .infinity, alignment: .topLeading)
        } else if !embedded {
            EmptyStateView(icon: "doc.text.magnifyingglass", title: "No file selected",
                           message: "Select a file, commit, or stash to inspect its diff.", tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(title: String, parsed: DiffRows) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(tokens.accentSecondary)
            Text(title)
                .font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.75))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if parsed.additions > 0 {
                Text("+\(parsed.additions)").font(AinkradFont.mono(10, weight: .semibold)).foregroundStyle(GMColor.diffAdd(tokens))
            }
            if parsed.deletions > 0 {
                Text("−\(parsed.deletions)").font(AinkradFont.mono(10, weight: .semibold)).foregroundStyle(GMColor.diffRemove(tokens))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    @ViewBuilder private func content(_ parsed: DiffRows) -> some View {
        if parsed.hasTextualChanges {
            // LazyVStack: a 5,000-line diff builds only the rows on screen.
            // `alignment` and `spacing` match the VStack this replaced so the
            // layout is unchanged. The explicit `.frame(width:)` keeps the
            // horizontal scroll extent correct — unrealised lazy rows have no
            // width otherwise, and this view sits inside a horizontally
            // scrolling ScrollView.
            let stack = LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(parsed.rows) { row($0, codeWidth: parsed.codeWidth) }
            }
            .frame(width: parsed.codeWidth + gutterWidth + signWidth, alignment: .leading)
            .padding(.vertical, 4)
            .textSelection(.enabled)

            if embedded {
                ScrollView(.horizontal, showsIndicators: false) { stack }
            } else {
                ScrollView([.vertical, .horizontal]) { stack }
            }
        } else if !embedded {
            EmptyStateView(icon: "doc.text", title: "No textual changes",
                           message: "This change has no line-level diff to show.", tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("No textual changes.")
                .font(AinkradFont.mono(10)).foregroundStyle(tokens.foreground.opacity(0.4)).padding(8)
        }
    }

    @ViewBuilder private func row(_ r: Row, codeWidth: CGFloat) -> some View {
        switch r.kind {
        case .meta:
            EmptyView()
        case .hunk:
            HStack(spacing: 0) {
                Color.clear.frame(width: gutterWidth + signWidth)
                Text(r.text)
                    .font(AinkradFont.mono(fontSize - 1, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.9))
                    .lineLimit(1)
                    .frame(width: codeWidth, alignment: .leading)
                    .padding(.leading, 4)
            }
            .background(tokens.accentSecondary.opacity(0.08))
        default:
            HStack(spacing: 0) {
                gutterCell(r.oldNo, r.newNo)
                Text(sign(r.kind))
                    .font(AinkradFont.mono(fontSize))
                    .foregroundStyle(signColor(r.kind))
                    .frame(width: signWidth, alignment: .center)
                Text(SyntaxHighlighter.highlight(Self.displayText(r), tokens: tokens))
                    .font(AinkradFont.mono(fontSize))
                    .lineLimit(1)
                    .frame(width: codeWidth, alignment: .leading)
                    .padding(.trailing, 8)
            }
            .background(lineBackground(r.kind))
        }
    }

    private func gutterCell(_ old: Int?, _ new: Int?) -> some View {
        HStack(spacing: 0) {
            Text(old.map(String.init) ?? "")
                .frame(width: numberWidth, alignment: .trailing)
            Text(new.map(String.init) ?? "")
                .frame(width: numberWidth, alignment: .trailing)
        }
        .font(AinkradFont.mono(max(9, fontSize - 2)))
        .foregroundStyle(tokens.foreground.opacity(0.3))
        .padding(.trailing, 8)
        .background(tokens.foreground.opacity(0.03))
    }

    /// Tab-expanded text for a row (tabs → 4 spaces) so columns align.
    static func displayText(_ r: Row) -> String {
        r.text.replacingOccurrences(of: "\t", with: "    ")
    }

    private func signColor(_ kind: LineKind) -> Color {
        switch kind {
        case .add: return GMColor.diffAdd(tokens)
        case .remove: return GMColor.diffRemove(tokens)
        default: return tokens.foreground.opacity(0.3)
        }
    }

    private func lineBackground(_ kind: LineKind) -> Color {
        switch kind {
        case .add: return GMColor.diffAdd(tokens).opacity(0.12)
        case .remove: return GMColor.diffRemove(tokens).opacity(0.12)
        default: return .clear
        }
    }

    private func sign(_ kind: LineKind) -> String {
        switch kind {
        case .add: return "+"
        case .remove: return "−"
        default: return " "
        }
    }

    // MARK: - Parsing

    static func parse(_ body: String) -> [Row] {
        if body.isEmpty { return [] }
        var rows: [Row] = []
        var oldLine = 0
        var newLine = 0
        var id = 0
        // Track whether we're inside a hunk. File headers (---/+++/index/…) only
        // appear BETWEEN `diff --git` and the first `@@`; once in a hunk, a line
        // starting with `-`/`+` is content — even "--- foo" (SQL/Markdown) or
        // "+++x". Prefix alone can't disambiguate, so gate headers on !inHunk.
        var inHunk = false
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            if line.hasPrefix("diff --git") {
                inHunk = false
                rows.append(Row(id: id, kind: .meta, oldNo: nil, newNo: nil, text: line))
            } else if line.hasPrefix("@@") {
                let (o, n) = parseHunkHeader(line)
                oldLine = o
                newLine = n
                inHunk = true
                rows.append(Row(id: id, kind: .hunk, oldNo: nil, newNo: nil, text: line))
            } else if !inHunk {
                // Everything before a file's first hunk is header/meta.
                rows.append(Row(id: id, kind: .meta, oldNo: nil, newNo: nil, text: line))
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — not a content line.
                rows.append(Row(id: id, kind: .meta, oldNo: nil, newNo: nil, text: line))
            } else if line.hasPrefix("+") {
                rows.append(Row(id: id, kind: .add, oldNo: nil, newNo: newLine, text: String(line.dropFirst())))
                newLine += 1
            } else if line.hasPrefix("-") {
                rows.append(Row(id: id, kind: .remove, oldNo: oldLine, newNo: nil, text: String(line.dropFirst())))
                oldLine += 1
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                rows.append(Row(id: id, kind: .context, oldNo: oldLine, newNo: newLine, text: text))
                oldLine += 1
                newLine += 1
            }
            id += 1
        }
        return rows
    }

    private static func parseHunkHeader(_ line: String) -> (Int, Int) {
        var oldStart = 0
        var newStart = 0
        for token in line.split(separator: " ") {
            if token.hasPrefix("-") {
                oldStart = Int(token.dropFirst().split(separator: ",").first ?? "") ?? 0
            } else if token.hasPrefix("+") {
                newStart = Int(token.dropFirst().split(separator: ",").first ?? "") ?? 0
            }
        }
        return (oldStart, newStart)
    }
}
