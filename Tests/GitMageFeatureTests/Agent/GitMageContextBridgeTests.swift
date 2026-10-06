import AinkradAppKit
import XCTest

@testable import GitMageFeature

/// A test double for the active-repo surface the bridge reads. Lets the bridge
/// be tested without a live GitMageViewModel.
@MainActor
final class FakeGitContextSource: GitContextSource {
    var repoSnapshot: GitRepositorySnapshot?
    var repoName: String?
    init(repoSnapshot: GitRepositorySnapshot? = nil, repoName: String? = nil) {
        self.repoSnapshot = repoSnapshot
        self.repoName = repoName
    }
    func agentRepositorySnapshot() -> GitRepositorySnapshot? { repoSnapshot }
    func agentRepositoryName() -> String? { repoName }
}

private func snap(
    root: String = "/Users/x/proj", branch: String = "main",
    upstream: String? = nil, ahead: Int = 0, behind: Int = 0,
    lastCommit: String? = "init", changes: [GitChange] = []
) -> GitRepositorySnapshot {
    GitRepositorySnapshot(
        rootPath: root, branchName: branch, upstream: upstream,
        aheadCount: ahead, behindCount: behind,
        lastCommitSummary: lastCommit, changes: changes)
}

@MainActor
final class GitMageContextBridgeTests: XCTestCase {
    func testNilWhenNoSource() {
        let bridge = GitMageContextBridge()
        XCTAssertNil(bridge.snapshot())
    }

    func testNilWhenSourceHasNoRepo() {
        let bridge = GitMageContextBridge()
        let source = FakeGitContextSource(repoSnapshot: nil, repoName: nil)
        bridge.setActiveSource(source)
        XCTAssertNil(bridge.snapshot())
    }

    func testCleanRepoSnapshot() {
        let bridge = GitMageContextBridge()
        let source = FakeGitContextSource(repoSnapshot: snap(), repoName: "proj")
        bridge.setActiveSource(source)
        let s = bridge.snapshot()
        XCTAssertEqual(s?.kind, "git")
        XCTAssertEqual(s?.title, "Git — proj")
        XCTAssertEqual(s?.text, "/Users/x/proj · main · Clean\nHEAD: init")
    }

    func testAheadBehindRendered() {
        let bridge = GitMageContextBridge()
        let source = FakeGitContextSource(repoSnapshot: snap(ahead: 2, behind: 1), repoName: "proj")
        bridge.setActiveSource(source)
        XCTAssertEqual(bridge.snapshot()?.text, "/Users/x/proj · main(+2/-1) · Clean\nHEAD: init")
    }

    func testAheadOnlyRendered() {
        let bridge = GitMageContextBridge()
        let source = FakeGitContextSource(repoSnapshot: snap(ahead: 3), repoName: "proj")
        bridge.setActiveSource(source)
        XCTAssertEqual(bridge.snapshot()?.text, "/Users/x/proj · main(+3) · Clean\nHEAD: init")
    }

    func testBehindOnlyRendered() {
        let bridge = GitMageContextBridge()
        let source = FakeGitContextSource(repoSnapshot: snap(behind: 2), repoName: "proj")
        bridge.setActiveSource(source)
        XCTAssertEqual(bridge.snapshot()?.text, "/Users/x/proj · main(-2) · Clean\nHEAD: init")
    }

    func testNameFallsBackToLastPathComponent() {
        let bridge = GitMageContextBridge()
        let source = FakeGitContextSource(repoSnapshot: snap(root: "/a/b/coolrepo"), repoName: nil)
        bridge.setActiveSource(source)
        XCTAssertEqual(bridge.snapshot()?.title, "Git — coolrepo")
    }

    func testClearYieldsNil() {
        let bridge = GitMageContextBridge()
        let source = FakeGitContextSource(repoSnapshot: snap(), repoName: "proj")
        bridge.setActiveSource(source)
        bridge.clearActiveSource(source)
        XCTAssertNil(bridge.snapshot())
    }

    func testClearDifferentSourceIsNoOp() {
        let bridge = GitMageContextBridge()
        let active = FakeGitContextSource(repoSnapshot: snap(), repoName: "keep")
        let other = FakeGitContextSource(repoSnapshot: snap(), repoName: "other")
        bridge.setActiveSource(active)
        bridge.clearActiveSource(other)
        XCTAssertEqual(bridge.snapshot()?.title, "Git — keep")
    }
}
