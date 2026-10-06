import XCTest

@testable import GitMageFeature

@MainActor
final class AdvancedViewModelTests: XCTestCase {
    func testLoadPopulatesCommitsTagsAndState() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()
        let vm = AdvancedViewModel(client: client, repositoryPath: repo.path, branches: [], onChanged: {})
        await vm.load()
        XCTAssertFalse(vm.commits.isEmpty)
        XCTAssertTrue(vm.tags.isEmpty)
        XCTAssertEqual(vm.operationState, .none)
        XCTAssertNil(vm.errorMessage)
    }

    func testCreateAndDeleteTag() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()
        var changed = 0
        let vm = AdvancedViewModel(client: client, repositoryPath: repo.path, branches: [], onChanged: { changed += 1 })
        vm.newTagName = "v1"
        vm.newTagMessage = "rel"
        await vm.createTag()
        XCTAssertTrue(vm.tags.contains { $0.name == "v1" })
        XCTAssertEqual(vm.newTagName, "")
        XCTAssertGreaterThan(changed, 0)

        await vm.deleteTag("v1")
        XCTAssertFalse(vm.tags.contains { $0.name == "v1" })
    }

    func testRequestResetSetsPendingConfirmThenConfirmPerformsReset() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()
        let firstLog = try await client.loadLog(limit: 1, in: repo.path)
        let firstSHA = try XCTUnwrap(firstLog.first?.id)
        try writeCommit(repo, file: "b.txt", contents: "b", msg: "second")

        let vm = AdvancedViewModel(client: client, repositoryPath: repo.path, branches: [], onChanged: {})
        await vm.load()
        XCTAssertEqual(vm.commits.count, 2)

        vm.selectedCommit = firstSHA
        vm.resetMode = .hard
        vm.autostash = false
        vm.requestReset()

        XCTAssertNotNil(vm.pendingConfirm)
        // reset has NOT happened yet
        var log = try await client.loadLog(limit: 10, in: repo.path)
        XCTAssertEqual(log.count, 2)

        // Confirm exactly as the view does: capture, consume, then perform.
        let action = try XCTUnwrap(vm.pendingConfirm)
        vm.cancelPending()
        await action.perform()
        XCTAssertNil(vm.pendingConfirm)
        log = try await client.loadLog(limit: 10, in: repo.path)
        XCTAssertEqual(log.count, 1)
    }

    func testCherryPickConflictSetsOperationStateNotError() async throws {
        let repo = try makeRepo()
        let client = GitRepositoryClient()

        let branches = try await client.loadBranches(at: repo.path)
        let base = try XCTUnwrap(branches.first?.name)

        try "main-change\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try await client.stageAllChanges(in: repo.path)
        try await client.commit(message: "main edit", in: repo.path)

        let fullLog = try await client.loadLog(limit: 10, in: repo.path)
        let first = try XCTUnwrap(fullLog.last?.id)
        try runGit(["checkout", "-b", "feat", first], in: repo)
        try "feat-change\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "feat edit"], in: repo)
        let featLog = try await client.loadLog(limit: 1, in: repo.path)
        let featSHA = try XCTUnwrap(featLog.first?.id)
        try runGit(["checkout", base], in: repo)

        var changed = 0
        let vm = AdvancedViewModel(client: client, repositoryPath: repo.path, branches: [], onChanged: { changed += 1 })
        vm.selectedCommit = featSHA
        await vm.cherryPick()

        XCTAssertEqual(vm.operationState, .cherryPicking)
        XCTAssertNil(vm.errorMessage)
        XCTAssertGreaterThan(changed, 0)

        await vm.abortOperation()
        XCTAssertEqual(vm.operationState, .none)
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

    private func writeCommit(_ repo: URL, file: String, contents: String, msg: String) throws {
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
            throw NSError(domain: "AdvancedViewModelTests", code: Int(process.terminationStatus))
        }
    }
}
