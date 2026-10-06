import Foundation

/// Drives the Worktrees surface: lists, adds, removes, locks, and opens git worktrees
/// for the active repository.
@MainActor
final class WorktreesViewModel: ObservableObject {
    enum AddMode: CaseIterable {
        case newBranch
        case existingBranch
        case detached
    }

    @Published var worktrees: [GitWorktree] = []
    @Published var selectedPath: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Commit graph of the selected worktree.
    @Published var graphRows: [GraphRow] = []
    @Published var isLoadingGraph = false
    @Published var selectedCommitSHA: String?
    @Published var selectedCommitDiff: GitDiffSnapshot?

    @Published var showAdd = false
    @Published var addMode: AddMode = .newBranch
    @Published var addBranchName: String = ""
    @Published var addRef: String = ""
    @Published var addExistingBranch: String?

    private let client: GitRepositoryClient
    private let repositoryPath: String
    private let currentRoot: String
    private let branches: [GitBranchSummary]
    private let onOpen: (String) -> Void

    init(
        client: GitRepositoryClient,
        repositoryPath: String,
        currentRoot: String,
        branches: [GitBranchSummary],
        onOpen: @escaping (String) -> Void
    ) {
        self.client = client
        self.repositoryPath = repositoryPath
        self.currentRoot = currentRoot
        self.branches = branches
        self.onOpen = onOpen
    }

    /// Branch names available for the "existing branch" add mode.
    var branchNames: [String] { branches.map(\.name) }

    func isCurrent(_ wt: GitWorktree) -> Bool {
        wt.path == currentRoot
    }

    func load() async {
        guard !repositoryPath.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        do {
            worktrees = try await client.loadWorktrees(in: repositoryPath)
        } catch {
            report(error)
        }
        isLoading = false
    }

    func select(_ path: String) {
        selectedPath = path
        selectedCommitSHA = nil
        selectedCommitDiff = nil
        graphRows = []
        Task { await loadGraph(for: path) }
    }

    private func loadGraph(for path: String) async {
        isLoadingGraph = true
        let commits = (try? await client.loadGraphCommits(limit: 200, in: path)) ?? []
        // A newer selection superseded this load — leave the spinner on for it
        // (don't flip it off here, which would flicker an empty state).
        guard selectedPath == path else { return }
        graphRows = GitGraphBuilder.build(commits)
        isLoadingGraph = false
    }

    /// Loads the diff for a commit tapped in the graph.
    func selectCommit(_ sha: String) {
        guard let path = selectedPath else { return }
        selectedCommitSHA = sha
        Task {
            let diff = try? await client.loadCommitDiff(sha: sha, in: path)
            guard selectedCommitSHA == sha else { return }
            selectedCommitDiff = diff
        }
    }

    func add(destination: String) async {
        guard !repositoryPath.isEmpty else { return }
        errorMessage = nil

        let base: WorktreeBase
        switch addMode {
        case .newBranch:
            base = .newBranch(addBranchName)
        case .existingBranch:
            base = .existingBranch(addExistingBranch ?? "")
        case .detached:
            base = .detached(ref: addRef)
        }

        do {
            try await client.addWorktree(path: destination, base: base, in: repositoryPath)
            showAdd = false
            addBranchName = ""
            addRef = ""
            addExistingBranch = nil
            await load()
        } catch {
            report(error)
        }
    }

    func remove(_ wt: GitWorktree, force: Bool) async {
        guard !repositoryPath.isEmpty else { return }
        errorMessage = nil
        do {
            try await client.removeWorktree(path: wt.path, force: force, in: repositoryPath)
            await load()
        } catch {
            report(error)
        }
    }

    func prune() async {
        guard !repositoryPath.isEmpty else { return }
        errorMessage = nil
        do {
            try await client.pruneWorktrees(in: repositoryPath)
            await load()
        } catch {
            report(error)
        }
    }

    func lock(_ wt: GitWorktree) async {
        guard !repositoryPath.isEmpty else { return }
        errorMessage = nil
        do {
            try await client.lockWorktree(path: wt.path, reason: nil, in: repositoryPath)
            await load()
        } catch {
            report(error)
        }
    }

    func unlock(_ wt: GitWorktree) async {
        guard !repositoryPath.isEmpty else { return }
        errorMessage = nil
        do {
            try await client.unlockWorktree(path: wt.path, in: repositoryPath)
            await load()
        } catch {
            report(error)
        }
    }

    func open(_ wt: GitWorktree) {
        onOpen(wt.path)
    }

    private func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
