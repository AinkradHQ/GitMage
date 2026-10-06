import XCTest

@testable import GitMageFeature

extension GitRepositoryClientTests {
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
}
