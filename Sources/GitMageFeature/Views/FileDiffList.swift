import SwiftUI
import AinkradAppKit

/// One file's slice of a unified diff.
struct DiffFile: Identifiable {
    let id: String
    let filename: String
    let status: String        // added / removed / renamed / modified
    let patch: String?
}

/// Splits a multi-file unified diff (e.g. `git show` / `git stash show -p`)
/// into per-file slices, ignoring any commit-message preamble.
enum DiffFileSplitter {
    static func split(_ body: String) -> [DiffFile] {
        let lines = body.components(separatedBy: "\n")
        var files: [DiffFile] = []
        var current: [String] = []
        var started = false

        func flush() {
            guard !current.isEmpty else { return }
            let (name, status) = parseHeader(current)
            files.append(DiffFile(id: "\(files.count)-\(name)", filename: name,
                                  status: status, patch: current.joined(separator: "\n")))
            current = []
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
                started = true
                current = [line]
            } else if started {
                current.append(line)
            }
        }
        flush()

        if files.isEmpty, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [DiffFile(id: "0", filename: "", status: "modified", patch: body)]
        }
        return files
    }

    private static func parseHeader(_ lines: [String]) -> (name: String, status: String) {
        var name = ""
        var status = "modified"
        if let header = lines.first, header.hasPrefix("diff --git ") {
            // "diff --git a/path b/path" → prefer the b/ side.
            if var b = header.components(separatedBy: " ").last {
                if b.hasPrefix("b/") { b.removeFirst(2) }
                name = b
            }
        }
        for line in lines {
            if line.hasPrefix("new file") { status = "added" }
            else if line.hasPrefix("deleted file") { status = "removed" }
            else if line.hasPrefix("rename ") { status = "renamed" }
            else if line.hasPrefix("+++ ") {
                var p = String(line.dropFirst(4))
                if p.hasPrefix("b/") { p.removeFirst(2) }
                if p != "/dev/null", !p.isEmpty { name = p }
            }
        }
        return (name, status)
    }
}

/// A scrolling list of collapsible file rows — click a file to reveal its diff
/// inline. Shared by the PR Files tab and the History/Stash detail panes.
struct FileDiffList: View {
    let files: [DiffFile]
    let tokens: HostThemeTokens
    let fontSize: Double
    var fallbackTitle: String = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if files.isEmpty {
                    EmptyStateView(icon: "doc.text", title: "No changes",
                                   message: "This diff has no files to show.", tokens: tokens)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(files) { file in
                        FileDisclosureRow(
                            filename: file.filename.isEmpty ? fallbackTitle : file.filename,
                            status: file.status,
                            patch: file.patch,
                            // Auto-expand when there's only one file.
                            isExpanded: expanded.contains(file.id) || files.count == 1,
                            tokens: tokens,
                            fontSize: fontSize,
                            onToggle: {
                                if expanded.contains(file.id) { expanded.remove(file.id) }
                                else { expanded.insert(file.id) }
                            }
                        )
                    }
                }
            }
            .padding(12)
        }
    }
}

/// A collapsible file row: status badge + filename + chevron; expands to the
/// embedded diff.
struct FileDisclosureRow: View {
    let filename: String
    let status: String
    let patch: String?
    let isExpanded: Bool
    let tokens: HostThemeTokens
    let fontSize: Double
    let onToggle: () -> Void
    @State private var hovering = false

    private var badgeLetter: String {
        switch status.lowercased() {
        case "added": return "A"
        case "removed": return "D"
        case "renamed": return "R"
        default: return "M"
        }
    }
    private var badgeColor: Color {
        switch status.lowercased() {
        case "added": return GMColor.diffAdd(tokens)
        case "removed": return GMColor.diffRemove(tokens)
        case "renamed": return tokens.accentSecondary
        default: return tokens.accentTertiary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                    .frame(width: 12)
                Text(badgeLetter)
                    .font(AinkradFont.mono(10, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .frame(width: 18, height: 18)
                    .background(ChamferShape(cut: AinkradRadius.sm).fill(badgeColor.opacity(0.16)))
                Text(filename.isEmpty ? "(diff)" : filename)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(hovering ? tokens.surfaceElevated.opacity(0.5) : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { hovering = $0 }

            if isExpanded {
                GlowRule(tokens: tokens)
                DiffView(
                    diff: GitDiffSnapshot(title: filename, body: patch ?? "", isEmpty: patch == nil),
                    tokens: tokens, fontSize: fontSize, embedded: true, showHeader: false
                )
            }
        }
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.25)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.foreground.opacity(0.07)))
        .clipShape(ChamferShape(cut: AinkradRadius.md))
    }
}
