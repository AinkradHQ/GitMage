import AinkradAppKit
import Foundation
import XCTest

@testable import GitMageFeature

@MainActor
final class GitOpActionHandlerTests: XCTestCase {
    private func json(_ d: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: d), as: UTF8.self)
    }

    // Mirrors the private helper duplicated across GitRepositoryClientTests /
    // GitWorktreeTests / WorktreesViewModelTests — each test file keeps its own
    // copy since it's `private`, not a shared XCTestCase base.
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
            throw NSError(domain: "GitOpActionHandlerTests", code: Int(process.terminationStatus))
        }
    }

    func testStatusReturnsBranchInfo() async throws {
        let repo = try makeTemporaryRepository()
        try "hi\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let handler = GitOpActionHandler(client: GitRepositoryClient())
        let result = await handler.run(json(["operation": "status", "repoPath": repo.path]))
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains("README.md") || result.text.contains("branch"))
    }

    func testCommitCreatesACommit() async throws {
        let repo = try makeTemporaryRepository()
        try "hi\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let handler = GitOpActionHandler(client: GitRepositoryClient())
        _ = await handler.run(json(["operation": "stageAll", "repoPath": repo.path]))
        let result = await handler.run(
            json([
                "operation": "commit", "repoPath": repo.path,
                "args": ["message": "Add README"],
            ]))
        XCTAssertFalse(result.isError)
    }

    func testUnsupportedOperationIsError() async throws {
        // `discard` takes a structured GitChange value, so it stays unsupported.
        let repo = try makeTemporaryRepository()
        let handler = GitOpActionHandler(client: GitRepositoryClient())
        let result = await handler.run(json(["operation": "discard", "repoPath": repo.path]))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.lowercased().contains("unsupported"))
    }

    func testResetHardIsHandled() async throws {
        let repo = try makeTemporaryRepository()
        try "a\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let handler = GitOpActionHandler(client: GitRepositoryClient())
        _ = await handler.run(json(["operation": "stageAll", "repoPath": repo.path]))
        _ = await handler.run(
            json([
                "operation": "commit", "repoPath": repo.path,
                "args": ["message": "c1"],
            ]))
        let result = await handler.run(
            json([
                "operation": "reset", "repoPath": repo.path,
                "args": ["ref": "HEAD", "mode": "hard"],
            ]))
        XCTAssertFalse(result.isError)
    }

    func testMalformedInputIsError() async throws {
        let handler = GitOpActionHandler(client: GitRepositoryClient())
        let result = await handler.run("not json")
        XCTAssertTrue(result.isError)
    }
}
