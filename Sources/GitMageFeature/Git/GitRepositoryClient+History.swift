import Foundation

extension GitRepositoryClient {
    /// Total number of commits reachable from HEAD (0 before the first commit).
    func commitCount(in path: String) async throws -> Int {
        let rootURL = try await repositoryRootURL(for: path)
        guard try await hasHead(in: rootURL) else { return 0 }
        let output = try await runGit(["rev-list", "--count", "HEAD"], in: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output) ?? 0
    }

    /// Commits with parent SHAs, for the commit-graph view.
    func loadGraphCommits(limit: Int, in path: String) async throws -> [GraphCommit] {
        let rootURL = try await repositoryRootURL(for: path)
        guard try await hasHead(in: rootURL) else { return [] }
        let sep = "\u{1f}"
        let output = try await runGit(
            [
                "log",
                "--topo-order",
                "--max-count=\(max(1, limit))",
                "--pretty=format:%H\(sep)%h\(sep)%s\(sep)%an\(sep)%ar\(sep)%P",
            ], in: rootURL)
        return GitGraphParser.parse(output)
    }

    func loadLog(skip: Int = 0, limit: Int, in path: String) async throws -> [GitCommitSummary] {
        let rootURL = try await repositoryRootURL(for: path)
        guard try await hasHead(in: rootURL) else { return [] }
        let output = try await runGit(
            [
                "log",
                "--skip=\(max(0, skip))",
                "--max-count=\(max(1, limit))",
                "--pretty=format:%H%x09%h%x09%s%x09%an%x09%ar",
            ], in: rootURL)
        return GitLogParser.parse(output: output)
    }

    func loadCommitDiff(sha: String, in path: String) async throws -> GitDiffSnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit(
            ["show", "--no-color", "--no-ext-diff", "--unified=3", "--format=medium", sha],
            in: rootURL
        )
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: sha,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }
}
