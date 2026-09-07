import Foundation
import Combine
import AppKit
import AinkradAppKit

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
    @Published var isLoadingDiff = false
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
    private let commitPageSize = 50
    @Published var selectedCommitID: String?
    @Published var commitDiff: GitDiffSnapshot?

    // Prompts driven from the view
    @Published var pendingInitPath: String?
    @Published var showInitPrompt = false
    @Published var showClonePrompt = false
    @Published var cloneRemoteURL = ""

    private let workspaceStore: GitMageWorkspaceStore
    private let client = GitRepositoryClient()
    private let log: PluginLogger
    private var didBootstrap = false

    /// Files Git Mage's notifications. Generation 9 onward; every host that
    /// can load this bundle supplies one.
    private let reporter: GitMageSignalReporter

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

    private func loadActiveRepoIntoEditors() {
        let repo = activeRepo
        draftCommitMessage = repo?.draftCommitMessage ?? ""
        selectedBranchName = repo?.lastBranch ?? ""
        selectedChangeID = repo?.lastSelectedFileID
    }

    private func resetTransientState() {
        snapshot = nil
        branches = []
        stashes = []
        diffSnapshot = nil
        selectedStashDiff = nil
        errorMessage = nil
    }

    /// Folds the live editor state back into the active repo config.
    private func syncActiveRepoState() {
        guard let activeRepoID,
              let index = repos.firstIndex(where: { $0.id == activeRepoID }) else { return }
        repos[index].draftCommitMessage = draftCommitMessage
        repos[index].lastBranch = selectedBranchName
        repos[index].lastSelectedFileID = selectedChangeID
    }

    private func persistLibrary() {
        syncActiveRepoState()
        workspaceStore.saveLibrary(GitMageLibraryState(repos: repos, activeRepoID: activeRepoID))
    }

    func saveDraft() {
        persistLibrary()
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard hasActiveRepo else { return }
        refresh()
    }

    // MARK: - Library management

    func addRepositoryFolder() {
        guard let url = pickFolder(
            title: "Add a Git Repository",
            prompt: "Add Repository",
            message: "Select a repository root folder."
        ) else { return }
        let path = url.path

        Task { @MainActor in
            if await client.isRepository(at: path) {
                registerRepository(path: path)
            } else {
                pendingInitPath = path
                showInitPrompt = true
            }
        }
    }

    func confirmInitPendingRepository() {
        guard let path = pendingInitPath else { return }
        pendingInitPath = nil
        Task { @MainActor in
            do {
                try await client.initRepository(at: path)
                log.info("Initialized new repository at \(path)")
                registerRepository(path: path)
            } catch {
                report(error, context: "initialize repository at \(path)")
            }
        }
    }

    func cancelInitPendingRepository() {
        pendingInitPath = nil
    }

    func startClone() {
        cloneRemoteURL = ""
        showClonePrompt = true
    }

    func performClone() {
        let remote = cloneRemoteURL
        guard !remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = GitRepositoryError.invalidRemoteURL.errorDescription
            return
        }
        guard let parent = pickFolder(
            title: "Choose a Destination Folder",
            prompt: "Clone Here",
            message: "Select the folder to clone the repository into."
        ) else { return }

        isLoading = true
        errorMessage = nil
        showClonePrompt = false

        Task { @MainActor in
            do {
                let destination = try await client.clone(remoteURL: remote, into: parent.path)
                cloneRemoteURL = ""
                log.info("Cloned \(remote) into \(destination)")
                registerRepository(path: destination)
            } catch {
                isLoading = false
                report(error, context: "clone \(remote)")
            }
        }
    }

    /// Adds (or re-selects) a repo, makes it active, and loads it.
    private func registerRepository(path: String) {
        syncActiveRepoState()

        if let existing = repos.first(where: { $0.path == path }) {
            activeRepoID = existing.id
        } else {
            let repo = GitMageRepoConfig(
                id: UUID().uuidString,
                path: path,
                name: (path as NSString).lastPathComponent
            )
            repos.append(repo)
            activeRepoID = repo.id
        }

        resetTransientState()
        loadActiveRepoIntoEditors()
        persistLibrary()
        refresh()
    }

    /// Registers (or re-selects) the repo at `path` — public hook for surfaces like Worktrees
    /// that need to open a directory as its own library entry.
    func openRepositoryPath(_ path: String) {
        registerRepository(path: path)
    }

    func selectRepository(_ id: String) {
        guard id != activeRepoID else { return }
        syncActiveRepoState()
        persistLibrary()

        activeRepoID = id
        resetTransientState()
        loadActiveRepoIntoEditors()
        refresh()
    }

    func removeActiveRepository() {
        guard let activeRepoID else { return }
        removeRepository(activeRepoID)
    }

    func removeRepository(_ id: String) {
        repos.removeAll { $0.id == id }
        if activeRepoID == id {
            activeRepoID = repos.first?.id
            resetTransientState()
            loadActiveRepoIntoEditors()
        }
        persistLibrary()
        if hasActiveRepo { refresh() }
    }

    // MARK: - Snapshot / refresh

    func refresh() {
        let path = repositoryPath
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = GitRepositoryError.missingPath.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let newSnapshot = try await client.loadSnapshot(at: path)
                let newBranches = (try? await client.loadBranches(at: path)) ?? []
                let newStashes = (try? await client.loadStashes(in: path)) ?? []
                snapshot = newSnapshot
                branches = newBranches
                stashes = newStashes
                selectedStashDiff = nil
                commits = []
                selectedCommitID = nil
                commitDiff = nil
                if selectedArea == .history { loadCommits() }
                if selectedBranchName.isEmpty || !newBranches.contains(where: { $0.name == selectedBranchName }) {
                    selectedBranchName = newSnapshot.branchName
                }
                persistLibrary()
                log.info("Loaded repository snapshot for \(path)")
                isLoading = false
                activeOperation = nil
                if let selectedChangeID,
                   let existingChange = newSnapshot.changes.first(where: { $0.id == selectedChangeID }) {
                    selectChange(existingChange)
                } else if let firstChange = newSnapshot.changes.first {
                    selectedChangeID = firstChange.id
                    selectChange(firstChange)
                } else {
                    selectedChangeID = nil
                    diffSnapshot = nil
                }
            } catch {
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

    // MARK: - Branches

    func checkoutSelectedBranch() {
        let branch = selectedBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return }
        run(context: "checkout branch \(branch)") { [self] in
            try await client.checkoutBranch(branch, in: repositoryPath)
        }
    }

    func createBranch() {
        let name = newBranchName
        run(context: "create branch \(name)") { [self] in
            try await client.createBranch(name, in: repositoryPath)
            newBranchName = ""
        }
    }

    func deleteBranch(_ name: String) {
        run(context: "delete branch \(name)") { [self] in try await client.deleteBranch(name, in: repositoryPath) }
    }

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
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { totalCommits = nil; return }
        Task { @MainActor in
            totalCommits = try? await client.commitCount(in: path)
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
                diff = GitDiffSnapshot(title: "\(commit.shortSHA) · \(commit.summary)", body: diff.body, isEmpty: diff.isEmpty)
                commitDiff = diff
            } catch {
                commitDiff = GitDiffSnapshot(title: commit.shortSHA, body: error.localizedDescription, isEmpty: true)
            }
        }
    }

    // MARK: - Remote operations

    func fetch() {
        run(context: "fetch") { [self] in try await client.fetch(in: repositoryPath) }
    }

    func pull() {
        run(context: "pull") { [self] in try await client.pull(in: repositoryPath) }
    }

    func push() {
        run(context: "push") { [self] in try await client.push(in: repositoryPath) }
    }

    // MARK: - Stash

    func stashChanges() {
        run(context: "stash changes") { [self] in try await client.stashPush(in: repositoryPath) }
    }

    func popLatestStash() {
        run(context: "pop stash") { [self] in try await client.stashPop(in: repositoryPath) }
    }

    func applyStash(_ entry: GitStashEntry) {
        run(context: "apply \(entry.id)") { [self] in try await client.stashApply(entry, in: repositoryPath) }
    }

    func dropStash(_ entry: GitStashEntry) {
        run(context: "drop \(entry.id)") { [self] in try await client.stashDrop(entry, in: repositoryPath) }
    }

    func selectStash(_ entry: GitStashEntry) {
        let path = repositoryPath
        Task { @MainActor in
            do {
                selectedStashDiff = try await client.stashDiff(entry.id, in: path)
            } catch {
                selectedStashDiff = GitDiffSnapshot(title: entry.id, body: error.localizedDescription, isEmpty: true)
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
        isLoadingDiff = true
        Task { @MainActor in
            do {
                let diff = try await client.loadDiff(for: change, in: path)
                diffSnapshot = diff
                isLoadingDiff = false
            } catch {
                diffSnapshot = GitDiffSnapshot(
                    title: change.path,
                    body: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    isEmpty: true
                )
                isLoadingDiff = false
                log.error("Failed to load diff for \(change.filePath): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Staging

    func stageAllChanges() {
        run(context: "stage all changes") { [self] in try await client.stageAllChanges(in: repositoryPath) }
    }

    func unstageAllChanges() {
        run(context: "unstage all changes") { [self] in try await client.unstageAllChanges(in: repositoryPath) }
    }

    func stageSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "stage \(change.filePath)") { [self] in try await client.stage(change: change, in: repositoryPath) }
    }

    func unstageSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "unstage \(change.filePath)") { [self] in try await client.unstage(change: change, in: repositoryPath) }
    }

    func discardSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "discard \(change.filePath)") { [self] in try await client.discard(change: change, in: repositoryPath) }
    }

    func commitChanges() {
        let message = draftCommitMessage
        run(context: "commit") { [self] in
            try await client.commit(message: message, in: repositoryPath)
            draftCommitMessage = ""
            persistLibrary()
        }
    }

    var selectedChange: GitChange? {
        guard let selectedChangeID else { return snapshot?.changes.first }
        return snapshot?.changes.first { $0.id == selectedChangeID }
    }

    // MARK: - Helpers

    /// Runs a mutating git action, then refreshes on success or reports on failure.
    private func run(context: String, _ action: @escaping () async throws -> Void) {
        guard hasActiveRepo else { return }
        isLoading = true
        activeOperation = context
        errorMessage = nil
        // Captured before the work starts, and the repo path with it: the
        // active repo can change while a long fetch runs, and reporting the
        // outcome against whatever is selected when it lands would attribute
        // one repository's failure to another.
        let startedAt = Date()
        let repository = repositoryPath
        Task { @MainActor in
            do {
                try await action()
                log.info("Completed \(context) in \(repository)")
                refresh()
                let elapsed = Date().timeIntervalSince(startedAt)
                // Success only past the threshold: a 200ms status refresh is
                // not news, a four-minute clone is the thing the user walked
                // away from.
                if elapsed >= GitMageSignalReporter.successThreshold {
                    reporter.operationFinished(operation: context, repository: repository,
                                               duration: elapsed)
                }
                // Conflicts are checked AFTER the refresh, on the state the
                // refresh produced. A conflict is not a thrown error — the
                // command did what it was asked — so this is the only place it
                // can be observed.
                reportConflictsIfAny(operation: context, repository: repository)
            } catch {
                isLoading = false
                activeOperation = nil
                report(error, context: context)
                reporter.operationFailed(operation: context, repository: repository,
                                         reason: Self.describe(error))
            }
        }
    }

    /// Files a conflict row when the working tree has conflicted entries.
    ///
    /// Reads `snapshot`, which `refresh()` has just repopulated. Silent when
    /// there are none, so this is safe to call after every operation rather
    /// than only after the ones that can conflict — a list of "operations that
    /// can conflict" is exactly the kind of thing that goes stale.
    private func reportConflictsIfAny(operation: String, repository: String) {
        guard let snapshot else { return }
        let conflicted = snapshot.changes
            .filter { $0.kind == .conflicted }
            .map(\.path)
        reporter.conflictsDetected(operation: operation, repository: repository,
                                   files: conflicted)
    }

    /// The same text `report(_:context:)` shows in the UI, so the feed row and
    /// the banner cannot disagree about what went wrong.
    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func report(_ error: Error, context: String) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        log.error("Failed to \(context): \(error.localizedDescription)")
    }

    private func pickFolder(title: String, prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.canResolveUbiquitousConflicts = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
