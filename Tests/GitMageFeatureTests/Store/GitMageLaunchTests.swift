import AinkradAppKit
import Foundation
import Testing

@testable import GitMageFeature

/// Forge's "Open in Git Mage": a repository, and maybe one of its commits.
@Suite("Git Mage — launches from other apps")
@MainActor
struct GitMageLaunchTests {
    @Test("A commit opens its repository's History with that commit selected")
    func showsACommit() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let sha = try repo.run("git", "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let model = makeViewModel([])
        model.handleLaunch(#"{"kind":"showInGitMage","path":"\#(repo.path)","sha":"\#(sha)","title":"initial"}"#)
        #expect(model.repos.map(\.path) == [repo.path])
        #expect(model.selectedArea == .history)
        #expect(model.selectedCommitID == sha)
        try await waitUntil("the commit's diff") { model.commitDiff != nil }
        #expect(model.commitDiff?.title.hasPrefix(String(sha.prefix(7))) == true)
    }

    @Test("A repository alone opens its Changes; other payloads are not Git Mage's")
    func showsARepositoryAndIgnoresTheRest() throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([])
        model.handleLaunch(AinkradLaunchIntent(kind: "openDirectory", path: repo.path).json)
        model.handleLaunch("not json")
        #expect(model.repos.isEmpty)
        model.handleLaunch(#"{"kind":"showInGitMage","path":"\#(repo.path)"}"#)
        #expect(model.activeRepoID != nil)
        #expect(model.selectedArea == .changes)
    }
}
