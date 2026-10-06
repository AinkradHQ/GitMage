import XCTest

@testable import GitMageFeature

final class GitTagParserTests: XCTestCase {
    func testParsesAnnotatedAndLightweight() {
        let out = "v1.0\tFirst release\nv1.1\t\n"
        let tags = GitTagParser.parse(out)
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags[0].name, "v1.0")
        XCTAssertEqual(tags[0].message, "First release")
        XCTAssertEqual(tags[1].name, "v1.1")
        XCTAssertNil(tags[1].message)
    }
}

final class AdvancedOpsClientTests: XCTestCase {
    func testTagCreateListDelete() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()
        try await client.createTag(name: "v1", message: "rel", in: repo.path)
        var tags = try await client.loadTags(in: repo.path)
        XCTAssertTrue(tags.contains { $0.name == "v1" && $0.message == "rel" })
        try await client.deleteTag(name: "v1", in: repo.path)
        tags = try await client.loadTags(in: repo.path)
        XCTAssertFalse(tags.contains { $0.name == "v1" })
    }

    func testResetHardMovesHeadAndDiscards() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()
        let firstLog = try await client.loadLog(limit: 1, in: repo.path)
        let firstSHA = try XCTUnwrap(firstLog.first?.id)
        // second commit
        try writeCommit(repo, file: "b.txt", contents: "b", msg: "second", client: client)
        // dirty change
        try "dirty".write(to: repo.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try await client.reset(to: firstSHA, mode: .hard, autostash: false, in: repo.path)
        let log = try await client.loadLog(limit: 10, in: repo.path)
        XCTAssertEqual(log.count, 1)
        let snap = try await client.loadSnapshot(at: repo.path)
        XCTAssertTrue(snap.changes.isEmpty)  // hard reset discarded the dirty change
    }

    func testResetHardAutostashPreservesChange() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()
        try "dirty\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let headLog = try await client.loadLog(limit: 1, in: repo.path)
        let head = try XCTUnwrap(headLog.first?.id)
        try await client.reset(to: head, mode: .hard, autostash: true, in: repo.path)
        let stashes = try await client.loadStashes(in: repo.path)
        XCTAssertEqual(stashes.count, 1)  // change preserved as a stash
    }

    func testCherryPickConflictSetsStateThenAbortClears() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()
        // resolve default branch name (main or master) dynamically
        let branches = try await client.loadBranches(at: repo.path)
        let base = try XCTUnwrap(branches.first?.name)

        // main: edit line
        try "main-change\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: repo.path)
        try await client.commit(message: "main edit", in: repo.path)

        // branch from first commit, conflicting edit, commit
        let fullLog = try await client.loadLog(limit: 10, in: repo.path)
        let first = try XCTUnwrap(fullLog.last?.id)
        try runGit(["checkout", "-b", "feat", first], in: repo)
        try "feat-change\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "feat edit"], in: repo)
        let featLog = try await client.loadLog(limit: 1, in: repo.path)
        let featSHA = try XCTUnwrap(featLog.first?.id)
        try runGit(["checkout", base], in: repo)

        // cherry-pick the conflicting commit -> conflict
        _ = try? await client.cherryPick(sha: featSHA, in: repo.path)
        let state = try await client.operationState(in: repo.path)
        XCTAssertEqual(state, .cherryPicking)
        try await client.abortOperation(in: repo.path)
        let cleared = try await client.operationState(in: repo.path)
        XCTAssertEqual(cleared, .none)
    }

    // MARK: - Helpers

    private func makeRepo() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "gitmage@example.com"], in: root)
        try runGit(["config", "user.name", "Git Mage"], in: root)
        let readme = root.appendingPathComponent("README.md")
        try "hello\n".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "-A"], in: root)
        try runGit(["commit", "-m", "Initial commit"], in: root)
        return root
    }

    private func writeCommit(_ repo: URL, file: String, contents: String, msg: String, client: GitRepositoryClient)
        throws
    {
        try contents.write(to: repo.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try runGit(["add", "-A"], in: repo)
        try runGit(["commit", "-m", msg], in: repo)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AdvancedOpsTests", code: Int(process.terminationStatus))
        }
    }
}
