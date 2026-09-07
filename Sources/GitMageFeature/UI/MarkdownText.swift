import SwiftUI
import AinkradAppKit

/// A lightweight GitHub-flavored markdown renderer for PR/issue descriptions
/// and comments. Handles headings, fenced code blocks, ordered/unordered
/// lists, blockquotes, horizontal rules, and paragraphs; inline emphasis
/// (bold/italic/`code`/links/strikethrough) is rendered via `AttributedString`.
struct MarkdownText: View {
    let markdown: String
    let tokens: HostThemeTokens
    var baseSize: CGFloat = 12

    private enum Block {
        case paragraph(String)
        case heading(level: Int, text: String)
        case code(String)
        case quote([String])
        case list(ordered: Bool, items: [String])
        case rule
    }

    var body: some View {
        // Computed once per render rather than inline inside ForEach, and
        // wrapped in LazyVStack so a long issue/PR body doesn't build one
        // live view per block up front.
        let blocks = Self.parse(markdown)
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(tokens.foreground.opacity(0.85))
        .tint(tokens.accentPrimary)
    }

    @ViewBuilder private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inline(text, size: baseSize)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .heading(let level, let text):
            inline(text, size: headingSize(level), weight: .semibold)
                .foregroundStyle(tokens.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(AinkradFont.mono(baseSize - 0.5))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.55)))
            .overlay(ChamferShape(cut: AinkradRadius.sm).strokeBorder(tokens.foreground.opacity(0.07)))

        case .quote(let lines):
            HStack(spacing: 8) {
                ChamferShape(cut: AinkradRadius.sm).fill(tokens.accentPrimary.opacity(0.5)).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        inline(line, size: baseSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(tokens.foreground.opacity(0.6))
            }
            .fixedSize(horizontal: false, vertical: true)

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            .font(AinkradFont.mono(baseSize))
                            .foregroundStyle(tokens.accentSecondary)
                        inline(item, size: baseSize)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .textSelection(.enabled)

        case .rule:
            LinearGradient(colors: [.clear, tokens.accentPrimary.opacity(0.3), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1).padding(.vertical, 3)
        }
    }

    private func inline(_ string: String, size: CGFloat, weight: Font.Weight = .regular) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: string, options: options) {
            return Text(attributed).font(AinkradFont.display(size, weight: weight))
        }
        return Text(string).font(AinkradFont.display(size, weight: weight))
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseSize + 6
        case 2: return baseSize + 4
        case 3: return baseSize + 2
        default: return baseSize + 1
        }
    }

    // MARK: - Block parsing

    private static func parse(_ md: String) -> [Block] {
        var blocks: [Block] = []
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            if trimmed.hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }   // closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if let heading = headingLevel(trimmed) {
                blocks.append(.heading(level: heading.0, text: heading.1)); i += 1; continue
            }

            if isRule(trimmed) { blocks.append(.rule); i += 1; continue }

            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var q = lines[i].trimmingCharacters(in: .whitespaces)
                    q.removeFirst()
                    if q.hasPrefix(" ") { q.removeFirst() }
                    quote.append(q); i += 1
                }
                blocks.append(.quote(quote)); continue
            }

            if listMarker(trimmed) != nil {
                var items: [String] = []
                var ordered = false
                while i < lines.count {
                    let lt = lines[i].trimmingCharacters(in: .whitespaces)
                    if let marker = listMarker(lt) {
                        ordered = marker.ordered
                        items.append(marker.text); i += 1
                    } else if lt.isEmpty {
                        break
                    } else if !items.isEmpty {
                        items[items.count - 1] += " " + lt; i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(ordered: ordered, items: items)); continue
            }

            var paragraph: [String] = []
            while i < lines.count {
                let lt = lines[i].trimmingCharacters(in: .whitespaces)
                if lt.isEmpty || lt.hasPrefix("```") || headingLevel(lt) != nil
                    || isRule(lt) || lt.hasPrefix(">") || listMarker(lt) != nil {
                    break
                }
                paragraph.append(lines[i]); i += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        }
        return blocks
    }

    private static func headingLevel(_ line: String) -> (Int, String)? {
        var count = 0
        for c in line { if c == "#" { count += 1 } else { break } }
        let chars = Array(line)
        guard count >= 1, count <= 6, chars.count > count, chars[count] == " " else { return nil }
        return (count, String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        line == "---" || line == "***" || line == "___"
    }

    private static func listMarker(_ line: String) -> (ordered: Bool, text: String)? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return (false, String(line.dropFirst(2)))
        }
        let chars = Array(line)
        var idx = 0
        while idx < chars.count && chars[idx].isNumber { idx += 1 }
        if idx > 0, idx + 1 < chars.count, chars[idx] == ".", chars[idx + 1] == " " {
            return (true, String(chars[(idx + 2)...]))
        }
        return nil
    }
}
