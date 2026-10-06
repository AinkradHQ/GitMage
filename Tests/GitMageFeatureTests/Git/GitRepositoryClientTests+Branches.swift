import XCTest

@testable import GitMageFeature

extension GitRepositoryClientTests {
    func testCreatesAndChecksOutBranch() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        try seedInitialCommit(in: repoURL, client: client)

        try await client.createBranch("feature/x", in: repoURL.path)

        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertEqual(snapshot.branchName, "feature/x")
    }

    func testRejectsEmptyBranchName() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        do {
            try await client.createBranch("  ", in: repoURL.path)
            XCTFail("Expected empty branch name to fail")
        } catch let error as GitRepositoryError {
            XCTAssertEqual(error, .invalidBranchName)
        }
    }

    func testPushSetsUpstreamForNewBranch() async throws {
        let (bareURL, _) = try makeBareRemoteWithCommit()
        let client = GitRepositoryClient()

        let destinationParent = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let clonedPath = try await client.clone(remoteURL: bareURL.path, into: destinationParent.path)
        let clonedURL = URL(fileURLWithPath: clonedPath)
        try runGit(["config", "user.email", "gitmage@example.com"], in: clonedURL)
        try runGit(["config", "user.name", "Git Mage"], in: clonedURL)

        try await client.createBranch("feature/push", in: clonedPath)
        let fileURL = clonedURL.appendingPathComponent("feature.txt")
        try "feature\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: clonedPath)
        try await client.commit(message: "Add feature", in: clonedPath)

        try await client.push(in: clonedPath)

        // The branch now exists on the bare remote.
        try runGit(["rev-parse", "--verify", "refs/heads/feature/push"], in: bareURL)
    }

    /// An upstream that is configured but unreadable is NOT "no upstream":
    /// pushing with `-u origin` anyway would silently re-point the branch.
    func testPushDoesNotMistakeABrokenUpstreamForNone() async throws {
        let (bareURL, _) = try makeBareRemoteWithCommit()
        let client = GitRepositoryClient()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let clonedPath = try await client.clone(remoteURL: bareURL.path, into: parent.path)
        let clonedURL = URL(fileURLWithPath: clonedPath)
        try runGit(["config", "user.email", "gitmage@example.com"], in: clonedURL)
        try runGit(["config", "user.name", "Git Mage"], in: clonedURL)
        try await client.createBranch("feature/broken", in: clonedPath)
        // Configured upstream whose remote-tracking ref does not exist.
        try runGit(["config", "branch.feature/broken.remote", "origin"], in: clonedURL)
        try runGit(["config", "branch.feature/broken.merge", "refs/heads/feature/broken"], in: clonedURL)

        do {
            try await client.push(in: clonedPath)
            XCTFail("expected the broken upstream to surface")
        } catch let GitRepositoryError.commandFailed(message) {
            XCTAssertFalse(message.contains("no upstream configured"), message)
        }
        let pushed = (try? runGit(["rev-parse", "--verify", "refs/heads/feature/broken"], in: bareURL)) != nil
        XCTAssertFalse(pushed, "the branch must not have been pushed with -u")
    }

    func testDeletesMergedBranch() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "First commit", in: repoURL.path)

        try await client.createBranch("scratch", in: repoURL.path)  // creates + checks out scratch
        // Return to the repo's default branch (main or master) before deleting scratch.
        let branches = try await client.loadBranches(at: repoURL.path)
        let base = try XCTUnwrap(branches.first(where: { $0.name != "scratch" })?.name)
        try await client.checkoutBranch(base, in: repoURL.path)
        try await client.deleteBranch("scratch", in: repoURL.path)

        let after = try await client.loadBranches(at: repoURL.path)
        XCTAssertNil(after.first(where: { $0.name == "scratch" }))
    }
}
