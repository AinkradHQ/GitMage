import AinkradAppKit
import Foundation

/// Reference box for `GitMageWorkspaceStore`'s v2 save guard. The store is a
/// struct held in a `let` whose `loadLibrary` does not mutate, so the flag
/// lives here instead of in the struct.
private final class SaveGate {
    var canSave = true
}

struct GitMageWorkspaceStore {
    private let documents: PluginDocumentStore
    private let legacyKey = "workspace.state.v1"
    private let libraryKey = "library.state.v2"
    /// Whether the v2 document may be written. A box, because this store is a
    /// struct held in a `let` and `loadLibrary` does not mutate.
    private let saveGate = SaveGate()

    init(documents: PluginDocumentStore) {
        self.documents = documents
    }

    // MARK: - Library (v2)

    /// Loads the repo library, migrating a legacy single-repo install on first run.
    /// A corrupt v2 is set aside (or blocks v2 saves when it cannot be) and
    /// then falls through to the legacy migration exactly as before.
    func loadLibrary() -> GitMageLibraryState {
        let loaded = loadDocument(
            GitMageLibraryState.self, key: libraryKey, from: documents, app: "gitmage")
        saveGate.canSave = loaded.canSave
        if let library = loaded.value {
            return library
        }

        let migrated = migrateLegacyIfPresent()
        if let migrated {
            saveLibrary(migrated)
            return migrated
        }
        return GitMageLibraryState()
    }

    func saveLibrary(_ state: GitMageLibraryState) {
        guard saveGate.canSave else {
            AinkradLog.logger(app: "gitmage", area: "persistence")
                .error("saving is off: the loaded document did not decode and could not be set aside")
            return
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        documents.setData(data, forKey: libraryKey)
    }

    private func migrateLegacyIfPresent() -> GitMageLibraryState? {
        let legacy = load()
        let path = legacy.repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let repo = GitMageRepoConfig(
            id: UUID().uuidString,
            path: legacy.repositoryPath,
            name: (legacy.repositoryPath as NSString).lastPathComponent,
            draftCommitMessage: legacy.draftCommitMessage
        )
        return GitMageLibraryState(repos: [repo], activeRepoID: repo.id)
    }

    // MARK: - Legacy (v1) — retained for migration and existing tests

    func load() -> GitMageWorkspaceState {
        guard let data = documents.data(forKey: legacyKey) else { return GitMageWorkspaceState() }
        return (try? JSONDecoder().decode(GitMageWorkspaceState.self, from: data)) ?? GitMageWorkspaceState()
    }

    func save(_ state: GitMageWorkspaceState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        documents.setData(data, forKey: legacyKey)
    }
}
