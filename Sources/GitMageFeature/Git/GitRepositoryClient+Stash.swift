import Foundation

extension GitRepositoryClient {
    func stashPush(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "push", "--include-untracked"], in: rootURL)
    }

    func stashPop(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "pop"], in: rootURL)
    }

    func stashApply(_ entry: GitStashEntry, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "apply", entry.id], in: rootURL)
    }

    func stashDrop(_ entry: GitStashEntry, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["stash", "drop", entry.id], in: rootURL)
    }

    func loadStashes(in path: String) async throws -> [GitStashEntry] {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit(["stash", "list", "--format=%gd%x09%gs"], in: rootURL, readOnly: true)
        return GitStashParser.parse(output: output)
    }

    func stashDiff(_ id: String, in path: String) async throws -> GitDiffSnapshot {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit(
            ["stash", "show", "-p", "--no-color", "--no-ext-diff", "--unified=3", id],
            in: rootURL
        )
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitDiffSnapshot(
            title: id,
            body: body.isEmpty ? "No diff available." : body,
            isEmpty: body.isEmpty
        )
    }
}
