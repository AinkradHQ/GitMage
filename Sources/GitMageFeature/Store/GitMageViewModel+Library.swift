import AppKit
import Foundation

extension GitMageViewModel {
    // MARK: - Library management

    func addRepositoryFolder() {
        guard
            let url = pickFolder(
                title: "Add a Git Repository",
                prompt: "Add Repository",
                message: "Select a repository root folder."
            )
        else { return }
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
        guard
            let parent = pickFolder(
                title: "Choose a Destination Folder",
                prompt: "Clone Here",
                message: "Select the folder to clone the repository into."
            )
        else { return }

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
