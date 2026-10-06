import Foundation

enum RemoteInfoParser {
    /// Parses an https or scp-style git remote URL into host/owner/name.
    static func parse(remoteURL: String) -> RepoRef? {
        var s = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if s.hasSuffix("/") { s = String(s.dropLast()) }

        // scp-style: git@host:owner/repo
        if let at = s.range(of: "@"), let colon = s.range(of: ":", range: at.upperBound..<s.endIndex) {
            let host = String(s[at.upperBound..<colon.lowerBound])
            let path = String(s[colon.upperBound...])
            return Self.ref(host: host, path: path)
        }
        // url-style: scheme://host/owner/repo
        if let schemeRange = s.range(of: "://") {
            let rest = String(s[schemeRange.upperBound...])
            guard let firstSlash = rest.firstIndex(of: "/") else { return nil }
            let host = String(rest[..<firstSlash])
            let path = String(rest[rest.index(after: firstSlash)...])
            return Self.ref(host: host, path: path)
        }
        return nil
    }

    private static func ref(host: String, path: String) -> RepoRef? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return RepoRef(host: host, owner: parts[0], name: parts[1])
    }
}

enum GitStatusParser {
    static func parse(statusOutput: String, repositoryRoot: String, lastCommitSummary: String?) -> GitRepositorySnapshot
    {
        let lines = statusOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = lines.first ?? ""
        let branchInfo = parseHeader(header)
        let changes = lines.dropFirst().compactMap(parseChangeLine)
        return GitRepositorySnapshot(
            rootPath: repositoryRoot,
            branchName: branchInfo.branchName,
            upstream: branchInfo.upstream,
            aheadCount: branchInfo.aheadCount,
            behindCount: branchInfo.behindCount,
            lastCommitSummary: lastCommitSummary,
            changes: changes
        )
    }

    private static func parseHeader(_ header: String) -> (
        branchName: String, upstream: String?, aheadCount: Int, behindCount: Int
    ) {
        guard header.hasPrefix("## ") else {
            return ("detached HEAD", nil, 0, 0)
        }

        let content = String(header.dropFirst(3))
        let branchAndState = content.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let branchPart = String(branchAndState.first ?? "")
        let statePart = branchAndState.count > 1 ? String(branchAndState[1]) : ""

        var branchName = branchPart
        var upstream: String?
        if let ellipsis = branchPart.range(of: "...") {
            branchName = String(branchPart[..<ellipsis.lowerBound])
            upstream = String(branchPart[ellipsis.upperBound...])
        }

        var aheadCount = 0
        var behindCount = 0
        if statePart.contains("ahead") {
            aheadCount = parseCount(statePart, token: "ahead")
        }
        if statePart.contains("behind") {
            behindCount = parseCount(statePart, token: "behind")
        }

        if content.contains("No commits yet on ") {
            branchName = content.replacingOccurrences(of: "No commits yet on ", with: "")
            upstream = nil
        }

        return (branchName, upstream, aheadCount, behindCount)
    }

    private static func parseCount(_ state: String, token: String) -> Int {
        let needle = "\(token) "
        guard let range = state.range(of: needle) else { return 0 }
        let suffix = state[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    /// Decodes the C-style quoting `git status --short` applies to any path
    /// containing non-ASCII bytes, a quote, a backslash or a control character:
    /// the whole path is wrapped in `"` and the offending bytes are written as
    /// backslash escapes (`\303\251` for `é`, `\"`, `\t`, …).
    ///
    /// The parser previously took the remainder of the line **verbatim**, so
    /// for `"src/caf\303\251.txt"` it produced a `filePath` that included the
    /// surrounding quotes and the literal escape text. That path does not
    /// exist, so every subsequent `git add`/`git checkout --` on it failed —
    /// staging and discarding were simply broken for any file whose name wasn't
    /// plain ASCII.
    ///
    /// Octal escapes are decoded at the **byte** level and only then interpreted
    /// as UTF-8: `é` is two bytes (`\303\251`), and decoding each escape to its
    /// own Character would produce mojibake instead of the original name.
    static func unquotePath(_ raw: String) -> String {
        guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else { return raw }
        let body = Array(raw.dropFirst().dropLast().utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(body.count)
        var i = 0
        while i < body.count {
            guard body[i] == UInt8(ascii: "\\"), i + 1 < body.count else {
                bytes.append(body[i])
                i += 1
                continue
            }
            let next = body[i + 1]
            switch next {
            case UInt8(ascii: "n"):
                bytes.append(0x0A)
                i += 2
            case UInt8(ascii: "t"):
                bytes.append(0x09)
                i += 2
            case UInt8(ascii: "r"):
                bytes.append(0x0D)
                i += 2
            case UInt8(ascii: "\""):
                bytes.append(0x22)
                i += 2
            case UInt8(ascii: "\\"):
                bytes.append(0x5C)
                i += 2
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                // Exactly three octal digits, per git's quoting.
                let digits = body[(i + 1)..<min(i + 4, body.count)]
                guard digits.count == 3,
                    let value = UInt16(String(decoding: digits, as: UTF8.self), radix: 8),
                    value <= 0xFF
                else {
                    bytes.append(body[i])
                    i += 1
                    continue
                }
                bytes.append(UInt8(value))
                i += 4
            default:
                bytes.append(body[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Finds the ` -> ` that separates a rename's two paths, ignoring any that
    /// appears **inside** a quoted path — a file literally named `a -> b` is
    /// legal, and splitting on it would silently produce two wrong paths.
    private static func renameSeparatorRange(in remainder: String) -> Range<String.Index>? {
        var inQuotes = false
        var escaped = false
        var index = remainder.startIndex
        while index < remainder.endIndex {
            let ch = remainder[index]
            if escaped {
                escaped = false
                index = remainder.index(after: index)
                continue
            }
            if ch == "\\" && inQuotes {
                escaped = true
                index = remainder.index(after: index)
                continue
            }
            if ch == "\"" {
                inQuotes.toggle()
                index = remainder.index(after: index)
                continue
            }
            if !inQuotes, remainder[index...].hasPrefix(" -> ") {
                return index..<remainder.index(index, offsetBy: 4)
            }
            index = remainder.index(after: index)
        }
        return nil
    }

    private static func parseChangeLine(_ line: String) -> GitChange? {
        guard line.count >= 3 else { return nil }
        let statusCode = String(line.prefix(2))
        let remainder = String(line.dropFirst(3))
        if statusCode == "!!" {
            let path = unquotePath(remainder)
            return GitChange(
                id: "\(statusCode):\(path)",
                path: path,
                filePath: path,
                sourcePath: nil,
                statusCode: statusCode,
                kind: .ignored
            )
        }

        let displayPath: String
        let filePath: String
        let sourcePath: String?
        let kind: GitChangeKind

        if let renameRange = renameSeparatorRange(in: remainder) {
            let oldPath = unquotePath(String(remainder[..<renameRange.lowerBound]))
            let newPath = unquotePath(String(remainder[renameRange.upperBound...]))
            displayPath = "\(oldPath) → \(newPath)"
            filePath = newPath
            sourcePath = oldPath
            kind = .renamed
        } else {
            let path = unquotePath(remainder)
            displayPath = path
            filePath = path
            sourcePath = nil
            kind = kindForStatus(statusCode)
        }

        return GitChange(
            id: "\(statusCode):\(displayPath)",
            path: displayPath,
            filePath: filePath,
            sourcePath: sourcePath,
            statusCode: statusCode,
            kind: kind
        )
    }

    private static func kindForStatus(_ statusCode: String) -> GitChangeKind {
        let characters = Array(statusCode)
        let index0 = characters.first ?? " "
        let index1 = characters.dropFirst().first ?? " "

        if statusCode == "??" { return .untracked }
        if index0 == "U" || index1 == "U" { return .conflicted }
        if index0 == "D" || index1 == "D" { return .deleted }
        if index0 != " " && index1 == " " { return .staged }
        if index0 == " " && index1 != " " { return .modified }
        return index0 != " " ? .staged : .modified
    }
}

enum GitBranchParser {
    static func parse(output: String) -> [GitBranchSummary] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap(parseLine)
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent && !rhs.isCurrent }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func parseLine(_ line: String) -> GitBranchSummary? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }
        let isCurrent = parts[0] == "*"
        let name = parts[1]
        let upstream = parts[2].isEmpty ? nil : parts[2]
        let tracking = parts[3].isEmpty ? nil : parts[3]
        return GitBranchSummary(name: name, upstream: upstream, isCurrent: isCurrent, tracking: tracking)
    }
}

enum GitLogParser {
    static func parse(output: String) -> [GitCommitSummary] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 5 else { return nil }
                return GitCommitSummary(
                    id: parts[0],
                    shortSHA: parts[1],
                    summary: parts[2],
                    author: parts[3],
                    relativeDate: parts[4]
                )
            }
    }
}

enum GitStashParser {
    static func parse(output: String) -> [GitStashEntry] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard let ref = parts.first, !ref.isEmpty else { return nil }
                let message = parts.count > 1 ? parts[1] : ref
                return GitStashEntry(id: ref, message: message)
            }
    }
}

enum GitWorktreeParser {
    static func parse(porcelain: String) -> [GitWorktree] {
        var result: [GitWorktree] = []
        let blocks = porcelain.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let wtLine = lines.first(where: { $0.hasPrefix("worktree ") }) else { continue }
            let path = String(wtLine.dropFirst("worktree ".count))
            var branch: String?
            var isLocked = false
            var isPrunable = false
            for line in lines {
                if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                } else if line == "locked" || line.hasPrefix("locked ") {
                    isLocked = true
                } else if line == "prunable" || line.hasPrefix("prunable ") {
                    isPrunable = true
                }
            }
            result.append(
                GitWorktree(
                    path: path, branch: branch, isLocked: isLocked, isPrunable: isPrunable))
        }
        return result
    }
}

enum GitTagParser {
    static func parse(_ output: String) -> [GitTag] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            let msg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            return GitTag(name: name, message: msg.isEmpty ? nil : msg)
        }
    }
}
