import XCTest

@testable import GitMageFeature

extension GitRepositoryClientTests {
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
}
