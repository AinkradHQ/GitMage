import Foundation
import Testing

@testable import GitMageFeature

/// Library management in `GitMageViewModel` — select, remove, open — and the
/// error state of a refresh, against real temporary repositories.
@Suite("Git Mage — library management")
@MainActor
struct GitMageViewModelLibraryTests {

    @Test("Selecting another repository clears the old state and loads the new one")
    func selectRepository() async throws {
        let a = try TempRepo()
        let b = try TempRepo()
        defer { a.cleanUp(); b.cleanUp() }
        try b.run("git", "checkout", "-q", "-b", "other")
        let model = makeViewModel([a.path, b.path])
        model.refresh()
        try await waitUntil("A to load") { model.snapshot != nil && isIdle(model) }
        #expect(model.snapshot?.branchName == "main")

        model.selectRepository(b.path)

        #expect(model.activeRepoID == b.path)
        #expect(model.snapshot == nil, "A's snapshot must not show under B")
        #expect(model.branches.isEmpty)
        try await waitUntil("B to load") { model.snapshot != nil && isIdle(model) }
        #expect(model.snapshot?.branchName == "other")
        #expect(model.snapshot?.rootPath.hasSuffix(URL(fileURLWithPath: b.path).lastPathComponent) == true)
    }

    @Test("Selecting the active repository is a no-op")
    func selectActiveRepository() async throws {
        let a = try TempRepo()
        defer { a.cleanUp() }
        let model = makeViewModel([a.path])
        model.refresh()
        try await waitUntil("A to load") { model.snapshot != nil && isIdle(model) }

        model.selectRepository(a.path)

        #expect(model.snapshot != nil, "re-selecting must not reset or reload")
        #expect(!model.isLoading)
    }

    @Test("Each repository keeps its own commit draft across a switch")
    func draftsFollowTheRepository() async throws {
        let a = try TempRepo()
        let b = try TempRepo()
        defer { a.cleanUp(); b.cleanUp() }
        let model = makeViewModel([a.path, b.path])
        model.draftCommitMessage = "draft for A"

        model.selectRepository(b.path)
        #expect(model.repos.first { $0.id == a.path }?.draftCommitMessage == "draft for A")
        #expect(model.draftCommitMessage == "")

        model.draftCommitMessage = "draft for B"
        model.selectRepository(a.path)
        #expect(model.draftCommitMessage == "draft for A")
        try await waitUntil("A to load") { isIdle(model) }
    }

    @Test("Removing a repository that is not active leaves the active one alone")
    func removeInactive() async throws {
        let a = try TempRepo()
        let b = try TempRepo()
        defer { a.cleanUp(); b.cleanUp() }
        let model = makeViewModel([a.path, b.path])
        model.refresh()
        try await waitUntil("A to load") { model.snapshot != nil && isIdle(model) }

        model.removeRepository(b.path)

        #expect(model.repos.map(\.id) == [a.path])
        #expect(model.activeRepoID == a.path)
        #expect(model.snapshot != nil, "the active repository's state is untouched")
    }

    @Test("Removing the active repository falls back to the first one left and reloads")
    func removeActive() async throws {
        let a = try TempRepo()
        let b = try TempRepo()
        defer { a.cleanUp(); b.cleanUp() }
        try b.run("git", "checkout", "-q", "-b", "other")
        let model = makeViewModel([a.path, b.path])
        model.refresh()
        try await waitUntil("A to load") { model.snapshot != nil && isIdle(model) }

        model.removeRepository(a.path)

        #expect(model.repos.map(\.id) == [b.path])
        #expect(model.activeRepoID == b.path)
        #expect(model.snapshot == nil, "A's snapshot is cleared at once")
        try await waitUntil("B to load") { model.snapshot != nil && isIdle(model) }
        #expect(model.snapshot?.branchName == "other")
    }

    @Test("Removing the last repository leaves no active repository and starts no load")
    func removeLast() async throws {
        let a = try TempRepo()
        defer { a.cleanUp() }
        let model = makeViewModel([a.path])
        model.refresh()
        try await waitUntil("A to load") { model.snapshot != nil && isIdle(model) }

        model.removeRepository(a.path)

        #expect(model.repos.isEmpty)
        #expect(model.activeRepoID == nil)
        #expect(!model.hasActiveRepo)
        #expect(model.snapshot == nil)
        #expect(!model.isLoading)
    }

    @Test("Opening a path adds it, names it by its folder, makes it active and loads it")
    func openRepositoryPath() async throws {
        let a = try TempRepo()
        let b = try TempRepo()
        defer { a.cleanUp(); b.cleanUp() }
        let model = makeViewModel([a.path])

        model.openRepositoryPath(b.path)

        #expect(model.repos.count == 2)
        let added = model.repos.first { $0.path == b.path }
        #expect(added?.name == URL(fileURLWithPath: b.path).lastPathComponent)
        #expect(model.activeRepoID == added?.id)
        try await waitUntil("B to load") { model.snapshot != nil && isIdle(model) }
    }

    @Test("Opening a path that is already in the library re-selects it without a duplicate")
    func openExistingPath() async throws {
        let a = try TempRepo()
        let b = try TempRepo()
        defer { a.cleanUp(); b.cleanUp() }
        let model = makeViewModel([a.path, b.path])

        model.openRepositoryPath(b.path)

        #expect(model.repos.count == 2)
        #expect(model.activeRepoID == b.path)
        try await waitUntil("B to load") { model.snapshot != nil && isIdle(model) }
    }

    @Test("Refreshing with no active repository reports the missing path and starts nothing")
    func refreshWithoutRepository() {
        let model = makeViewModel([])

        let task = model.refresh()

        #expect(task == nil)
        #expect(model.errorMessage == GitRepositoryError.missingPath.localizedDescription)
        #expect(!model.isLoading)
    }

    @Test("Refreshing a folder that is not a repository clears the state and sets the error")
    func refreshNotARepository() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitmage-notrepo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = makeViewModel([folder.path])

        model.refresh()
        try await waitUntil("the error") { model.errorMessage != nil }

        #expect(model.snapshot == nil)
        #expect(model.branches.isEmpty)
        #expect(!model.isLoading)
        #expect(model.activeOperation == nil)
    }

    @Test("A clone with a blank URL is refused before any folder picker opens")
    func cloneBlankURL() {
        let model = makeViewModel([])
        model.cloneRemoteURL = "   "

        model.performClone()

        #expect(model.errorMessage == GitRepositoryError.invalidRemoteURL.errorDescription)
        #expect(!model.isLoading)
    }
}
