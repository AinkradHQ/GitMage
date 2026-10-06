import Foundation

extension GitRepositoryClient {
    func loadBranches(at path: String) async throws -> [GitBranchSummary] {
        let rootURL = try await repositoryRootURL(for: path)
        let output = try await runGit(
            [
                "for-each-ref",
                "--format=%(HEAD)\t%(refname:short)\t%(upstream:short)\t%(upstream:trackshort)",
                "refs/heads",
            ], in: rootURL, readOnly: true)
        return GitBranchParser.parse(output: output)
    }

    func checkoutBranch(_ branchName: String, in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["checkout", branchName], in: rootURL)
    }

    func createBranch(_ name: String, in path: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidBranchName }
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["checkout", "-b", trimmed], in: rootURL)
    }

    func fetch(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["fetch", "--all", "--prune"], in: rootURL)
    }

    /// Fast-forward-only pull. Surfaces git's error when the branch has diverged.
    func pull(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["pull", "--ff-only"], in: rootURL)
    }

    /// Pushes the current branch, setting `origin/<branch>` as upstream when none exists.
    func push(in path: String) async throws {
        let rootURL = try await repositoryRootURL(for: path)
        let branch = try await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard branch != "HEAD", !branch.isEmpty else { throw GitRepositoryError.detachedHead }

        // Only git's own "no upstream configured" means push with -u. Any
        // other failure (a broken upstream ref, a lock, a bad config) must
        // surface rather than silently re-point the branch.
        let hasUpstream: Bool
        do {
            _ = try await runGit(
                ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
                in: rootURL)
            hasUpstream = true
        } catch GitRepositoryError.commandFailed(let message) where message.contains("no upstream configured") {
            hasUpstream = false
        }

        if hasUpstream {
            _ = try await runGit(["push"], in: rootURL)
        } else {
            _ = try await runGit(["push", "-u", "origin", branch], in: rootURL)
        }
    }

    func deleteBranch(_ name: String, in path: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidBranchName }
        let rootURL = try await repositoryRootURL(for: path)
        _ = try await runGit(["branch", "-d", trimmed], in: rootURL)  // safe delete; refuses unmerged
    }
}
