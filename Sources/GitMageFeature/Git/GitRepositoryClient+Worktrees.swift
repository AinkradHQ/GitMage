import Foundation

extension GitRepositoryClient {
    func loadWorktrees(in path: String) async throws -> [GitWorktree] {
        let rootURL = try await repositoryRootURL(for: path)
        let out = try await runGit(["worktree", "list", "--porcelain"], in: rootURL)
        return GitWorktreeParser.parse(porcelain: out)
    }

    func addWorktree(path: String, base: WorktreeBase, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.pathDoesNotExist(path) }
        var args = ["worktree", "add"]
        switch base {
        case .newBranch(let name): args += ["-b", name, trimmed]
        case .existingBranch(let name): args += [trimmed, name]
        case .detached(let ref): args += ["--detach", trimmed, ref]
        }
        _ = try await runGit(args, in: rootURL)
    }

    func removeWorktree(path: String, force: Bool, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        _ = try await runGit(args, in: rootURL)
    }

    func pruneWorktrees(in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        _ = try await runGit(["worktree", "prune"], in: rootURL)
    }

    func lockWorktree(path: String, reason: String?, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        var args = ["worktree", "lock"]
        if let reason, !reason.isEmpty { args += ["--reason", reason] }
        args.append(path)
        _ = try await runGit(args, in: rootURL)
    }

    func unlockWorktree(path: String, in repoPath: String) async throws {
        let rootURL = try await repositoryRootURL(for: repoPath)
        _ = try await runGit(["worktree", "unlock", path], in: rootURL)
    }
}
