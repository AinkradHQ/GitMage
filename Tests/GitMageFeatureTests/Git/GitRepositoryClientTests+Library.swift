import XCTest

@testable import GitMageFeature

extension GitRepositoryClientTests {
    func testInitializesRepository() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let client = GitRepositoryClient()

        var wasRepo = await client.isRepository(at: root.path)
        XCTAssertFalse(wasRepo)

        try await client.initRepository(at: root.path)
        wasRepo = await client.isRepository(at: root.path)
        XCTAssertTrue(wasRepo)
    }

    func testClonesRepositoryFromLocalBareRemote() async throws {
        let (bareURL, _) = try makeBareRemoteWithCommit()
        let client = GitRepositoryClient()

        let destinationParent = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let clonedPath = try await client.clone(remoteURL: bareURL.path, into: destinationParent.path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: clonedPath))
        let wasRepo = await client.isRepository(at: clonedPath)
        XCTAssertTrue(wasRepo)
    }

    func testRepositoryNameFromRemote() {
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "https://github.com/owner/repo.git"), "repo")
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "https://github.com/owner/repo"), "repo")
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "git@github.com:owner/repo.git"), "repo")
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "/tmp/local/repo/"), "repo")
    }
}
