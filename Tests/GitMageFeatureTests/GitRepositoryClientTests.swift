import XCTest

@testable import GitMageFeature

final class GitRepositoryClientTests: XCTestCase {
    func testStagesAndCommitsRepositoryChanges() async throws {
        let repoURL = try makeTemporaryRepository()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()

        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "Add README", in: repoURL.path)

        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertEqual(snapshot.lastCommitSummary, "Add README")
        XCTAssertTrue(snapshot.changes.isEmpty)
    }

    /// An open's loads — snapshot, branches, stashes — cost one `rev-parse`
    /// for the whole set, not one (or two) per load. Was 10 before the root
    /// was resolved once; each extra spawn is ~12ms of pure overhead.
    func testOpenLoadsResolveTheRootOnce() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()

        _ = try await client.loadSnapshot(at: repoURL.path)
        async let branches = client.loadBranches(at: repoURL.path)
        async let stashes = client.loadStashes(in: repoURL.path)
        _ = try await (branches, stashes)

        // rev-parse + status + log + for-each-ref + stash list
        let spawns = await client.spawnCount
        XCTAssertEqual(spawns, 5)
    }

    func testRejectsEmptyCommitMessage() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()

        do {
            try await client.commit(message: "   ", in: repoURL.path)
            XCTFail("Expected empty commit message to fail")
        } catch let error as GitRepositoryError {
            XCTAssertEqual(error, .invalidCommitMessage)
        }
    }

    func testUnstagesSelectedChange() async throws {
        let repoURL = try makeTemporaryRepository()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()
        try await client.stageAllChanges(in: repoURL.path)

        let stagedSnapshot = try await client.loadSnapshot(at: repoURL.path)
        guard let change = stagedSnapshot.changes.first else {
            return XCTFail("Expected a staged change")
        }

        try await client.unstage(change: change, in: repoURL.path)

        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertEqual(snapshot.changes.first?.kind, .untracked)
    }

    func testDiscardsUntrackedChange() async throws {
        let repoURL = try makeTemporaryRepository()
        let fileURL = repoURL.appendingPathComponent("temp.txt")
        try "scratch\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()
        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        guard let change = snapshot.changes.first(where: { $0.kind == .untracked }) else {
            return XCTFail("Expected an untracked change")
        }

        try await client.discard(change: change, in: repoURL.path)

        let after = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertTrue(after.changes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDiscardsTrackedModification() async throws {
        let repoURL = try makeTemporaryRepository()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "Add README", in: repoURL.path)

        try "changed\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        guard let change = snapshot.changes.first(where: { $0.kind == .modified }) else {
            return XCTFail("Expected a modified change")
        }

        try await client.discard(change: change, in: repoURL.path)

        let after = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertTrue(after.changes.isEmpty)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, "hello\n")
    }

    func testLoadsDiffForRenamedFile() async throws {
        let repoURL = try makeTemporaryRepository()
        let fileURL = repoURL.appendingPathComponent("README.md")
        let renamedURL = repoURL.appendingPathComponent("GUIDE.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "Add README", in: repoURL.path)

        try runGit(["mv", "README.md", "GUIDE.md"], in: repoURL)

        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        guard let change = snapshot.changes.first(where: { $0.kind == .renamed }) else {
            return XCTFail("Expected a renamed change")
        }

        XCTAssertTrue(change.isIndexStaged)
        XCTAssertEqual(snapshot.statusSummary, "1 changed · 1 staged")

        let diff = try await client.loadDiff(for: change, in: repoURL.path)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertTrue(diff.body.contains("README.md"))
        XCTAssertTrue(diff.body.contains("GUIDE.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
    }

    func testLoadsDiffForUnstagedDeletion() async throws {
        let repoURL = try makeTemporaryRepository()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let client = GitRepositoryClient()
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "Add README", in: repoURL.path)

        try FileManager.default.removeItem(at: fileURL)

        let snapshot = try await client.loadSnapshot(at: repoURL.path)
        guard let change = snapshot.changes.first(where: { $0.kind == .deleted }) else {
            return XCTFail("Expected a deleted change")
        }

        XCTAssertFalse(change.isIndexStaged)

        let diff = try await client.loadDiff(for: change, in: repoURL.path)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertTrue(diff.body.contains("deleted file mode"))
    }

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

    func testStashPushListAndPop() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try seedInitialCommit(in: repoURL, client: client, commitAll: true)

        try "changed\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await client.stashPush(in: repoURL.path)

        let stashes = try await client.loadStashes(in: repoURL.path)
        XCTAssertEqual(stashes.count, 1)
        XCTAssertEqual(stashes.first?.id, "stash@{0}")

        let clean = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertTrue(clean.changes.isEmpty)

        try await client.stashPop(in: repoURL.path)
        let restored = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertFalse(restored.changes.isEmpty)
        let afterPop = try await client.loadStashes(in: repoURL.path)
        XCTAssertTrue(afterPop.isEmpty)
    }

    func testStashDiffReturnsChange() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try seedInitialCommit(in: repoURL, client: client, commitAll: true)

        try "changed\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await client.stashPush(in: repoURL.path)

        let stashes = try await client.loadStashes(in: repoURL.path)
        let entry = try XCTUnwrap(stashes.first)

        let diff = try await client.stashDiff(entry.id, in: repoURL.path)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertTrue(diff.body.contains("README.md"))
    }

    func testStashApplyAndDrop() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try seedInitialCommit(in: repoURL, client: client, commitAll: true)

        try "changed\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await client.stashPush(in: repoURL.path)

        let stashes = try await client.loadStashes(in: repoURL.path)
        let entry = try XCTUnwrap(stashes.first)

        try await client.stashApply(entry, in: repoURL.path)
        let afterApply = try await client.loadSnapshot(at: repoURL.path)
        XCTAssertFalse(afterApply.changes.isEmpty)
        // apply keeps the stash
        let keptStashes = try await client.loadStashes(in: repoURL.path)
        XCTAssertEqual(keptStashes.count, 1)

        try await client.stashDrop(entry, in: repoURL.path)
        let afterDrop = try await client.loadStashes(in: repoURL.path)
        XCTAssertTrue(afterDrop.isEmpty)
    }

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

    func testRepositoryNameFromRemote() {
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "https://github.com/owner/repo.git"), "repo")
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "https://github.com/owner/repo"), "repo")
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "git@github.com:owner/repo.git"), "repo")
        XCTAssertEqual(GitRepositoryClient.repositoryName(fromRemote: "/tmp/local/repo/"), "repo")
    }

    func testLoadsCommitLog() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "First commit", in: repoURL.path)

        let log = try await client.loadLog(limit: 20, in: repoURL.path)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.summary, "First commit")
        XCTAssertEqual(log.first?.author, "Git Mage")
        XCTAssertFalse(log.first?.shortSHA.isEmpty ?? true)
        XCTAssertFalse(log.first?.relativeDate.isEmpty ?? true)
    }

    func testLoadsCommitDiff() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "hello\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "First commit", in: repoURL.path)

        let log = try await client.loadLog(limit: 1, in: repoURL.path)
        let sha = try XCTUnwrap(log.first?.id)
        let diff = try await client.loadCommitDiff(sha: sha, in: repoURL.path)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertTrue(diff.body.contains("README.md"))
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

    private func seedInitialCommit(in repoURL: URL, client: GitRepositoryClient, commitAll: Bool = false) throws {
        if !commitAll {
            let seed = repoURL.appendingPathComponent(".seed")
            try "seed\n".write(to: seed, atomically: true, encoding: .utf8)
        }
        try runGit(["add", "-A"], in: repoURL)
        try runGit(["commit", "-m", "Initial commit"], in: repoURL)
    }

    private func makeBareRemoteWithCommit() throws -> (bare: URL, work: URL) {
        let work = try makeTemporaryRepository()
        let seed = work.appendingPathComponent("README.md")
        try "hello\n".write(to: seed, atomically: true, encoding: .utf8)
        try runGit(["add", "-A"], in: work)
        try runGit(["commit", "-m", "Initial commit"], in: work)

        let bare = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(UUID().uuidString).git", isDirectory: true)
        try runGit(["init", "--bare", bare.path], in: work)
        try runGit(["push", bare.path, "HEAD"], in: work)
        return (bare, work)
    }

    private func makeTemporaryRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "gitmage@example.com"], in: root)
        try runGit(["config", "user.name", "Git Mage"], in: root)
        return root
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitRepositoryClientTests", code: Int(process.terminationStatus))
        }
    }
}
