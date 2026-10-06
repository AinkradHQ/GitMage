import AinkradAppKit
import AppKit
import Combine
import Foundation

@MainActor
final class GitMageViewModel: ObservableObject {
    // Library
    @Published var repos: [GitMageRepoConfig] = []
    @Published var activeRepoID: String?

    // Active-repo editors / transient state
    @Published var draftCommitMessage: String = ""
    @Published var newBranchName: String = ""
    @Published var snapshot: GitRepositorySnapshot?
    @Published var branches: [GitBranchSummary] = []
    @Published var stashes: [GitStashEntry] = []
    @Published var selectedStashDiff: GitDiffSnapshot?
    @Published var selectedBranchName: String = ""
    @Published var selectedChangeID: String?
    @Published var diffSnapshot: GitDiffSnapshot?
    @Published var isLoading = false
    /// Label of the git action currently running (e.g. "fetch", "pull",
    /// "push"), so a button can show its own inline spinner. Nil when idle.
    @Published var activeOperation: String?
    @Published var errorMessage: String?

    // Area / History state
    @Published var selectedArea: NavArea = .changes
    @Published var commits: [GitCommitSummary] = []
    /// True while a history page is loading; drives the scroll footer spinner.
    @Published var isLoadingCommits = false
    /// False once a page returns fewer than `commitPageSize` rows (end of log).
    @Published var hasMoreCommits = true
    /// Total commits reachable from HEAD, for the "loaded / total" header.
    @Published var totalCommits: Int?
    let commitPageSize = 50
    @Published var selectedCommitID: String?
    @Published var commitDiff: GitDiffSnapshot?

    // Prompts driven from the view
    @Published var pendingInitPath: String?
    @Published var showInitPrompt = false
    @Published var showClonePrompt = false
    @Published var cloneRemoteURL = ""

    /// How much `refresh()` loads.
    ///
    /// Basic mode needs the branch list and nothing else: `loadBranches` alone
    /// carries the current branch (`%(HEAD)`) and its ahead/behind
    /// (`%(upstream:trackshort)`), which is everything Fetch, Pull and the
    /// branch switcher display.
    ///
    /// It matters because git's cost here is dominated by process spawn, not by
    /// work: measured on this repo, each `git` invocation costs ~12ms of spawn
    /// against ~2-9ms of actual work, so the full refresh's five subprocesses
    /// (status, branches, stashes, rev-parse, and a diff of the first changed
    /// file) are ~73ms where basic's two are ~26ms. Trimming the VIEW alone
    /// would have saved none of it — the load is what costs.
    enum LoadScope { case basic, full }
    var loadScope: LoadScope = .full

    private let workspaceStore: GitMageWorkspaceStore
    let client = GitRepositoryClient()
    let log: PluginLogger
    private var didBootstrap = false
    /// In-flight read loads that write state after an await. Cancelled when the
    /// active repo changes, so a slow load never outlives the repo it was for.
    private var readTasks: [UUID: Task<Void, Never>] = [:]

    /// Starts a read load owned by this model (see `readTasks`).
    @discardableResult
    func trackRead(_ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor in
            await body()
            readTasks[id] = nil
        }
        readTasks[id] = task
        return task
    }

    private func cancelReads() {
        for task in readTasks.values { task.cancel() }
        readTasks = [:]
        isLoadingCommits = false
    }

    /// Files Git Mage's notifications. Generation 9 onward; every host that
    /// can load this bundle supplies one.
    let reporter: GitMageSignalReporter

    init(host: HostServices) {
        self.workspaceStore = GitMageWorkspaceStore(documents: host.documents)
        self.log = host.log
        self.reporter = GitMageSignalReporter(signals: host.signals)
        let library = workspaceStore.loadLibrary()
        self.repos = library.repos
        self.activeRepoID = library.activeRepoID ?? library.repos.first?.id
        loadActiveRepoIntoEditors()
    }

    // MARK: - Active repo

    var activeRepo: GitMageRepoConfig? {
        guard let activeRepoID else { return nil }
        return repos.first { $0.id == activeRepoID }
    }

    var repositoryPath: String { activeRepo?.path ?? "" }
    var hasActiveRepo: Bool { !repositoryPath.isEmpty }

    func currentRemote() async -> RepoRef? {
        guard hasActiveRepo else { return nil }
        return try? await client.remoteInfo(in: repositoryPath)
    }

    func loadActiveRepoIntoEditors() {
        let repo = activeRepo
        draftCommitMessage = repo?.draftCommitMessage ?? ""
        selectedBranchName = repo?.lastBranch ?? ""
        selectedChangeID = repo?.lastSelectedFileID
    }

    func resetTransientState() {
        snapshot = nil
        branches = []
        stashes = []
        diffSnapshot = nil
        selectedStashDiff = nil
        errorMessage = nil
        cancelReads()
    }

    /// Folds the live editor state back into the active repo config.
    func syncActiveRepoState() {
        guard let activeRepoID,
            let index = repos.firstIndex(where: { $0.id == activeRepoID })
        else { return }
        repos[index].draftCommitMessage = draftCommitMessage
        repos[index].lastBranch = selectedBranchName
        repos[index].lastSelectedFileID = selectedChangeID
    }

    func persistLibrary() {
        syncActiveRepoState()
        workspaceStore.saveLibrary(GitMageLibraryState(repos: repos, activeRepoID: activeRepoID))
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard hasActiveRepo else { return }
        refresh()
    }

    // MARK: - Snapshot / refresh

    /// The basic-mode load: branches, and nothing else.
    ///
    /// Deliberately does NOT clear `snapshot`, `commits` or `stashes`. Switching
    /// a pane basic -> advanced keeps this model, and wiping what advanced
    /// already loaded would make the switch look like a reload every time.
    private func refreshBranchesOnly(at path: String) -> Task<Void, Never> {
        isLoading = true
        errorMessage = nil
        return trackRead { [self] in
            let loaded = (try? await client.loadBranches(at: path)) ?? []
            guard repositoryPath == path else { return }  // switched repos mid-load
            branches = loaded
            if let current = loaded.first(where: { $0.isCurrent }) {
                selectedBranchName = current.name
            }
            isLoading = false
            activeOperation = nil
        }
    }

    /// `includeHistory: false` is the lighter reload after an action that
    /// cannot move HEAD (stage, unstage, discard, stash): history is kept.
    /// Returns the load so `run()` can await it before reading the state it produces.
    @discardableResult
    func refresh(includeHistory: Bool = true) -> Task<Void, Never>? {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = GitRepositoryError.missingPath.localizedDescription
            return nil
        }

        if loadScope == .basic {
            return refreshBranchesOnly(at: path)
        }

        isLoading = true
        errorMessage = nil

        return trackRead { [self] in
            do {
                // Concurrent: the three loads are independent read-only commands.
                async let loadedSnapshot = client.loadSnapshot(at: path)
                async let loadedBranches = try? client.loadBranches(at: path)
                async let loadedStashes = try? client.loadStashes(in: path)
                let newSnapshot = try await loadedSnapshot
                let newBranches = await loadedBranches ?? []
                let newStashes = await loadedStashes ?? []
                // The user switched repos while this ran: painting these results
                // would show one repository's state under another's name.
                guard repositoryPath == path else { return }
                snapshot = newSnapshot
                branches = newBranches
                stashes = newStashes
                selectedStashDiff = nil
                if includeHistory {
                    commits = []
                    selectedCommitID = nil
                    commitDiff = nil
                    if selectedArea == .history { loadCommits() }
                }
                if selectedBranchName.isEmpty || !newBranches.contains(where: { $0.name == selectedBranchName }) {
                    selectedBranchName = newSnapshot.branchName
                }
                persistLibrary()
                log.info("Loaded repository snapshot for \(path)")
                isLoading = false
                activeOperation = nil
                // Only the change the user already picked is re-diffed. No eager
                // first-file diff: it cost a spawn on every open for a diff the
                // user may never look at.
                if let selectedChangeID,
                    let existingChange = newSnapshot.changes.first(where: { $0.id == selectedChangeID })
                {
                    selectChange(existingChange)
                } else {
                    selectedChangeID = nil
                    diffSnapshot = nil
                }
            } catch {
                guard repositoryPath == path else { return }
                await client.forgetRoot(for: path)
                snapshot = nil
                branches = []
                stashes = []
                diffSnapshot = nil
                selectedStashDiff = nil
                isLoading = false
                activeOperation = nil
                report(error, context: "load repository snapshot")
            }
        }
    }

    // MARK: - Diff

    func selectChange(_ change: GitChange) {
        selectedChangeID = change.id
        loadDiff(for: change)
    }

    func loadDiff(for change: GitChange) {
        let path = repositoryPath
        trackRead { [self] in
            do {
                let diff = try await client.loadDiff(for: change, in: path)
                guard repositoryPath == path else { return }  // switched repos mid-load
                diffSnapshot = diff
            } catch {
                guard repositoryPath == path else { return }
                diffSnapshot = GitDiffSnapshot(
                    title: change.path,
                    body: error.displayMessage,
                    isEmpty: true
                )
                log.error("Failed to load diff for \(change.filePath): \(error.localizedDescription)")
            }
        }
    }

    /// Clears the banner the shell shows for `errorMessage`.
    func dismissError() { errorMessage = nil }

    func report(_ error: Error, context: String) {
        errorMessage = error.displayMessage
        log.error("Failed to \(context): \(error.localizedDescription)")
    }
}
