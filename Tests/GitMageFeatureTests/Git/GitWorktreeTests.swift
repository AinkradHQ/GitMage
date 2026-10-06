import XCTest

@testable import GitMageFeature

final class GitWorktreeParserTests: XCTestCase {
    func testParsesMainAndLinkedWorktrees() {
        let out = """
            worktree /repo
            HEAD 1111111111111111111111111111111111111111
            branch refs/heads/main

            worktree /repo-feature
            HEAD 2222222222222222222222222222222222222222
            branch refs/heads/feature

            worktree /repo-detached
            HEAD 3333333333333333333333333333333333333333
            detached

            worktree /repo-locked
            HEAD 4444444444444444444444444444444444444444
            branch refs/heads/wip
            locked needs review

            """
        let wts = GitWorktreeParser.parse(porcelain: out)
        XCTAssertEqual(wts.count, 4)
        XCTAssertEqual(wts[0].branch, "main")
        XCTAssertEqual(wts[2].branch, nil)
        XCTAssertTrue(wts[3].isLocked)
    }

    func testParsesBareAndPrunable() {
        let out = """
            worktree /bare
            bare

            worktree /gone
            HEAD 5555555555555555555555555555555555555555
            branch refs/heads/gone
            prunable gitdir file points to non-existent location

            """
        let wts = GitWorktreeParser.parse(porcelain: out)
        XCTAssertEqual(wts.count, 2)
        XCTAssertTrue(wts[1].isPrunable)
    }
}

final class GitWorktreeClientTests: XCTestCase {
    func testAddListLockRemove() async throws {
        let repoURL = try makeTemporaryRepository()
        let client = GitRepositoryClient()
        // seed a commit so a branch exists
        let f = repoURL.appendingPathComponent("README.md")
        try "hi\n".write(to: f, atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: repoURL.path)
        try await client.commit(message: "init", in: repoURL.path)

        let wtPath = repoURL.path + "-wt"
        try await client.addWorktree(path: wtPath, base: .newBranch("wt-branch"), in: repoURL.path)

        var wts = try await client.loadWorktrees(in: repoURL.path)
        XCTAssertEqual(wts.count, 2)
        XCTAssertTrue(wts.contains { $0.branch == "wt-branch" })

        try await client.lockWorktree(path: wtPath, reason: "hold", in: repoURL.path)
        wts = try await client.loadWorktrees(in: repoURL.path)
        let lockedEntry = wts.first { $0.branch == "wt-branch" }
        XCTAssertTrue(lockedEntry?.isLocked ?? false)

        try await client.unlockWorktree(path: wtPath, in: repoURL.path)
        try await client.removeWorktree(path: wtPath, force: true, in: repoURL.path)
        wts = try await client.loadWorktrees(in: repoURL.path)
        XCTAssertFalse(wts.contains { $0.branch == "wt-branch" })
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
            throw NSError(domain: "GitWorktreeTests", code: Int(process.terminationStatus))
        }
    }
}
