import Foundation

extension GitMageViewModel {
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
        run(context: "stash changes", movesHead: false) { [self] in try await client.stashPush(in: repositoryPath) }
    }

    func popLatestStash() {
        run(context: "pop stash", movesHead: false) { [self] in try await client.stashPop(in: repositoryPath) }
    }

    func applyStash(_ entry: GitStashEntry) {
        run(context: "apply \(entry.id)", movesHead: false) { [self] in
            try await client.stashApply(entry, in: repositoryPath)
        }
    }

    func dropStash(_ entry: GitStashEntry) {
        run(context: "drop \(entry.id)", movesHead: false) { [self] in
            try await client.stashDrop(entry, in: repositoryPath)
        }
    }

    func selectStash(_ entry: GitStashEntry) {
        let path = repositoryPath
        trackRead { [self] in
            do {
                let diff = try await client.stashDiff(entry.id, in: path)
                guard repositoryPath == path else { return }  // switched repos mid-load
                selectedStashDiff = diff
            } catch {
                guard repositoryPath == path else { return }
                selectedStashDiff = GitDiffSnapshot(title: entry.id, body: error.displayMessage, isEmpty: true)
            }
        }
    }

    // MARK: - Staging

    func stageAllChanges() {
        run(context: "stage all changes", movesHead: false) { [self] in
            try await client.stageAllChanges(in: repositoryPath)
        }
    }

    func unstageAllChanges() {
        run(context: "unstage all changes", movesHead: false) { [self] in
            try await client.unstageAllChanges(in: repositoryPath)
        }
    }

    func stageSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "stage \(change.filePath)", movesHead: false) { [self] in
            try await client.stage(change: change, in: repositoryPath)
        }
    }

    func unstageSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "unstage \(change.filePath)", movesHead: false) { [self] in
            try await client.unstage(change: change, in: repositoryPath)
        }
    }

    func discardSelectedChange() {
        guard let change = selectedChange else { return }
        run(context: "discard \(change.filePath)", movesHead: false) { [self] in
            try await client.discard(change: change, in: repositoryPath)
        }
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
    /// `movesHead: false` for actions that cannot change history, so the
    /// follow-up refresh keeps the loaded commits instead of reloading them.
    private func run(
        context: String, movesHead: Bool = true,
        _ action: @escaping () async throws -> Void
    ) {
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
                Log.store.info("Completed \(context) in \(repository)")
                await refresh(includeHistory: movesHead)?.value
                let elapsed = Date().timeIntervalSince(startedAt)
                // Success only past the threshold: a 200ms status refresh is
                // not news, a four-minute clone is the thing the user walked
                // away from.
                if elapsed >= GitMageSignalReporter.successThreshold {
                    reporter.operationFinished(
                        operation: context, repository: repository,
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
                reporter.operationFailed(
                    operation: context, repository: repository,
                    reason: error.displayMessage)
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
        reporter.conflictsDetected(
            operation: operation, repository: repository,
            files: conflicted)
    }
}
