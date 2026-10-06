import Foundation

extension GitMageViewModel {
    // MARK: - Areas / History

    func selectArea(_ area: NavArea) {
        selectedArea = area
        if area == .history && commits.isEmpty && hasActiveRepo { loadCommits() }
    }

    /// Loads (or reloads from scratch) the first page of history.
    func loadCommits() {
        commits = []
        hasMoreCommits = true
        loadCommitTotal()
        loadMoreCommits()
    }

    private func loadCommitTotal() {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            totalCommits = nil
            return
        }
        Task { @MainActor in
            let total = try? await client.commitCount(in: path)
            guard repositoryPath == path else { return }  // switched repos mid-load
            totalCommits = total
        }
    }

    /// Appends the next page of commits. Safe to call repeatedly from scroll —
    /// re-entrancy and end-of-history are guarded.
    func loadMoreCommits() {
        guard hasActiveRepo, hasMoreCommits, !isLoadingCommits else { return }
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let skip = commits.count
        isLoadingCommits = true
        Task { @MainActor in
            let page = (try? await client.loadLog(skip: skip, limit: commitPageSize, in: path)) ?? []
            // Guard against a concurrent refresh having reset the list.
            if commits.count == skip {
                commits.append(contentsOf: page)
            }
            hasMoreCommits = page.count == commitPageSize
            isLoadingCommits = false
            if selectedCommitID == nil, let first = commits.first {
                selectCommit(first)
            }
        }
    }

    func selectCommit(_ commit: GitCommitSummary) {
        selectedCommitID = commit.id
        let path = repositoryPath
        Task { @MainActor in
            do {
                var diff = try await client.loadCommitDiff(sha: commit.id, in: path)
                guard repositoryPath == path else { return }  // switched repos mid-load
                diff = GitDiffSnapshot(
                    title: "\(commit.shortSHA) · \(commit.summary)", body: diff.body, isEmpty: diff.isEmpty)
                commitDiff = diff
            } catch {
                guard repositoryPath == path else { return }
                commitDiff = GitDiffSnapshot(title: commit.shortSHA, body: error.localizedDescription, isEmpty: true)
            }
        }
    }
}
