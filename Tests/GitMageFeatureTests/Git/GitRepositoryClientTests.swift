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

    func seedInitialCommit(in repoURL: URL, client: GitRepositoryClient, commitAll: Bool = false) throws {
        if !commitAll {
            let seed = repoURL.appendingPathComponent(".seed")
            try "seed\n".write(to: seed, atomically: true, encoding: .utf8)
        }
        try runGit(["add", "-A"], in: repoURL)
        try runGit(["commit", "-m", "Initial commit"], in: repoURL)
    }

    func makeBareRemoteWithCommit() throws -> (bare: URL, work: URL) {
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

    func makeTemporaryRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "gitmage@example.com"], in: root)
        try runGit(["config", "user.name", "Git Mage"], in: root)
        return root
    }

    func runGit(_ arguments: [String], in directory: URL) throws {
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
