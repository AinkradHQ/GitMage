import XCTest
import AinkradAppKit
@testable import GitMageFeature

final class GitMageWorkspaceStoreTests: XCTestCase {
    func testRoundTripsWorkspaceState() {
        let documents = MemoryDocumentStore()
        let store = GitMageWorkspaceStore(documents: documents)
        let state = GitMageWorkspaceState(repositoryPath: "/tmp/repo", draftCommitMessage: "WIP")

        store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testRoundTripsLibraryState() {
        let documents = MemoryDocumentStore()
        let store = GitMageWorkspaceStore(documents: documents)
        let repo = GitMageRepoConfig(id: "abc", path: "/tmp/repo", name: "repo", draftCommitMessage: "WIP", lastBranch: "main")
        let library = GitMageLibraryState(repos: [repo], activeRepoID: "abc")

        store.saveLibrary(library)

        XCTAssertEqual(store.loadLibrary(), library)
    }

    func testMigratesLegacyWorkspaceIntoLibrary() {
        let documents = MemoryDocumentStore()
        let store = GitMageWorkspaceStore(documents: documents)
        store.save(GitMageWorkspaceState(repositoryPath: "/tmp/legacy-repo", draftCommitMessage: "carry over"))

        let library = store.loadLibrary()

        XCTAssertEqual(library.repos.count, 1)
        let repo = try? XCTUnwrap(library.repos.first)
        XCTAssertEqual(repo?.path, "/tmp/legacy-repo")
        XCTAssertEqual(repo?.name, "legacy-repo")
        XCTAssertEqual(repo?.draftCommitMessage, "carry over")
        XCTAssertEqual(library.activeRepoID, repo?.id)

        // Migration is persisted, so a second load returns the same library.
        XCTAssertEqual(store.loadLibrary(), library)
    }

    func testReturnsEmptyLibraryWithoutLegacyState() {
        let store = GitMageWorkspaceStore(documents: MemoryDocumentStore())
        XCTAssertEqual(store.loadLibrary(), GitMageLibraryState())
    }

    func testCorruptLibraryIsSetAsideNotOverwritten() {
        let seed = Data("{not json".utf8)
        let documents = MemoryDocumentStore()
        documents.setData(seed, forKey: "library.state.v2")
        let store = GitMageWorkspaceStore(documents: documents)
        store.save(GitMageWorkspaceState(repositoryPath: "/tmp/legacy-repo", draftCommitMessage: "carry over"))

        let library = store.loadLibrary()

        // The corrupt v2 falls through to the legacy migration, as today.
        XCTAssertEqual(library.repos.count, 1)
        XCTAssertEqual(library.repos.first?.path, "/tmp/legacy-repo")
        let backups = documents.keys.filter { $0.hasPrefix("library.state.v2.corrupt-") }
        XCTAssertEqual(backups.count, 1, "corrupt bytes were not set aside")
        XCTAssertEqual(documents.data(forKey: backups.first ?? ""), seed, "backup does not hold the seed bytes")
    }

    func testUnverifiableSetAsideKeepsOriginal() {
        let seed = Data("{not json".utf8)
        let documents = RejectingCorruptDocs()
        documents.setData(seed, forKey: "library.state.v2")
        let store = GitMageWorkspaceStore(documents: documents)
        store.save(GitMageWorkspaceState(repositoryPath: "/tmp/legacy-repo", draftCommitMessage: "carry over"))

        _ = store.loadLibrary()
        store.saveLibrary(GitMageLibraryState())

        XCTAssertEqual(
            documents.data(forKey: "library.state.v2"), seed,
            "the only copy of the user's data was overwritten")
    }
}

