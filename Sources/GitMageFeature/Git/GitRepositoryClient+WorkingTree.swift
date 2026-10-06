import Foundation

extension GitRepositoryClient {
    func loadSnapshot(at path: String) async throws -> GitRepositorySnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        // Both read-only, so they share the concurrent lane and run together.
        // `GIT_OPTIONAL_LOCKS=0` stops `status` opportunistically rewriting the
        // index — that write is what could collide with a concurrent stage.
        async let status = runGit(
            ["status", "--short", "--branch"], in: rootURL,
            environment: Self.noOptionalLocks, readOnly: true)
        async let summary = try? runGit(["log", "-1", "--pretty=format:%s"], in: rootURL, readOnly: true)
        let statusOutput = try await status
        let lastCommitSummary = await summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitStatusParser.parse(
            statusOutput: statusOutput,
            repositoryRoot: rootURL.path,
            lastCommitSummary: lastCommitSummary?.isEmpty == true ? nil : lastCommitSummary
        )
    }

    func stageAllChanges(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["add", "-A"], in: rootURL)
    }

    /// Unstages every staged change. Before the first commit there is no HEAD to
    /// reset against, so the whole index is cleared instead.
    func unstageAllChanges(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        if try await hasHead(in: rootURL) {
            _ = try await runGit(["reset"], in: rootURL)
        } else {
            _ = try await runGit(["rm", "-r", "--cached", "."], in: rootURL)
        }
    }

    func stage(change: GitChange, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        if change.kind == .renamed, let sourcePath = change.sourcePath {
            _ = try await runGit(["add", sourcePath, change.filePath], in: rootURL)
        } else {
            _ = try await runGit(["add", change.filePath], in: rootURL)
        }
    }

    func unstage(change: GitChange, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        guard change.canUnstage else { return }
        if try await !hasHead(in: rootURL) {
            if change.kind == .renamed, let sourcePath = change.sourcePath {
                _ = try await runGit(["rm", "--cached", "--", sourcePath, change.filePath], in: rootURL)
            } else {
                _ = try await runGit(["rm", "--cached", "--", change.filePath], in: rootURL)
            }
            return
        }

        if change.kind == .renamed, let sourcePath = change.sourcePath {
            _ = try await runGit(["restore", "--staged", "--", sourcePath, change.filePath], in: rootURL)
        } else {
            _ = try await runGit(["restore", "--staged", "--", change.filePath], in: rootURL)
        }
    }

    func discard(change: GitChange, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        switch change.kind {
        case .untracked:
            _ = try await runGit(["clean", "-f", "--", change.filePath], in: rootURL)
        case .renamed:
            if let sourcePath = change.sourcePath {
                _ = try await runGit(
                    ["restore", "--source=HEAD", "--worktree", "--staged", "--", sourcePath, change.filePath],
                    in: rootURL)
            } else {
                _ = try await runGit(
                    ["restore", "--source=HEAD", "--worktree", "--staged", "--", change.filePath], in: rootURL)
            }
        default:
            _ = try await runGit(
                ["restore", "--source=HEAD", "--worktree", "--staged", "--", change.filePath], in: rootURL)
        }
    }

    func commit(message: String, in path: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidCommitMessage }

        let rootURL = try await repositoryRootURL(for: path)
        let staged = try await runGit(["diff", "--cached", "--name-only"], in: rootURL)
        guard !staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitRepositoryError.nothingToCommit
        }
        _ = try await runGit(["commit", "-m", trimmed], in: rootURL)
    }

    func loadDiff(for change: GitChange, in path: String) async throws -> GitDiffSnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        let title =
            change.kind == .renamed ? "\(change.sourcePath ?? change.path) → \(change.filePath)" : change.filePath

        let arguments: [String]
        switch change.kind {
        case .untracked:
            arguments = ["diff", "--no-index", "--", "/dev/null", change.filePath]
        case .renamed:
            let pathspecs = change.sourcePath.map { [$0, change.filePath] } ?? [change.filePath]
            arguments =
                change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--"] + pathspecs
                : ["diff", "--no-ext-diff", "--unified=3", "--"] + pathspecs
        case .deleted:
            arguments =
                change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--", change.filePath]
                : ["diff", "--no-ext-diff", "--unified=3", "--", change.filePath]
        default:
            arguments =
                change.isIndexStaged
                ? ["diff", "--cached", "--no-ext-diff", "--unified=3", "--", change.filePath]
                : ["diff", "--no-ext-diff", "--unified=3", "--", change.filePath]
        }

        let output = try await runGit(
            arguments,
            in: rootURL,
            acceptedExitCodes: change.kind == .untracked ? [0, 1] : [0]
        )

        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: title,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }
}
