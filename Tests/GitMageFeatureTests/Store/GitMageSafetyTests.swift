import AinkradAppKit
import Foundation
import Testing

@testable import GitMageFeature

/// Stale-result guards and conflict reporting in `GitMageViewModel`, against
/// real temporary repositories (a stub client would agree with whatever the
/// code does).
@Suite("Git Mage — stale results and conflict reporting")
@MainActor
struct GitMageSafetyTests {

    @Test("A commit count that lands after a repo switch is dropped")
    func staleCommitTotal() async throws {
        let (a, b) = try twoRepos()
        defer {
            a.cleanUp()
            b.cleanUp()
        }
        let model = makeModel(a, b)

        model.loadCommits()
        model.activeRepoID = b.path
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(model.totalCommits == nil, "repo A's count must not land under repo B")
    }

    @Test("A commit diff that lands after a repo switch is dropped")
    func staleCommitDiff() async throws {
        let (a, b) = try twoRepos()
        defer {
            a.cleanUp()
            b.cleanUp()
        }
        let model = makeModel(a, b)
        let sha = try a.run("git", "rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)

        model.selectCommit(
            GitCommitSummary(
                id: sha, shortSHA: String(sha.prefix(7)), summary: "initial", author: "T", relativeDate: ""))
        model.activeRepoID = b.path
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(model.commitDiff == nil, "repo A's commit diff must not show under repo B")
    }

    @Test("A stash diff that lands after a repo switch is dropped")
    func staleStashDiff() async throws {
        let (a, b) = try twoRepos()
        defer {
            a.cleanUp()
            b.cleanUp()
        }
        try a.write("README.md", "changed")
        try a.run("git", "stash", "push")
        let model = makeModel(a, b)

        model.selectStash(GitStashEntry(id: "stash@{0}", message: "wip"))
        model.activeRepoID = b.path
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(model.selectedStashDiff == nil, "repo A's stash diff must not show under repo B")
    }

    @Test("A working-tree diff that lands after a repo switch is dropped")
    func staleWorkingDiff() async throws {
        let (a, b) = try twoRepos()
        defer {
            a.cleanUp()
            b.cleanUp()
        }
        try a.write("README.md", "changed")
        let model = makeModel(a, b)
        let change = GitChange(
            id: "README.md", path: "README.md", filePath: "README.md", sourcePath: nil,
            statusCode: " M", kind: .modified)

        model.loadDiff(for: change)
        model.activeRepoID = b.path
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(model.diffSnapshot == nil, "repo A's diff must not show under repo B")
    }

    @Test("Conflicts are reported from the refreshed state, not the stale snapshot")
    func conflictsReadAfterRefresh() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.run("git", "checkout", "-q", "-b", "other")
        try repo.write("README.md", "other")
        try repo.run("git", "commit", "-qam", "other")
        try repo.run("git", "checkout", "-q", "main")
        try repo.write("README.md", "main")
        try repo.run("git", "commit", "-qam", "main")
        try repo.run("git", "merge", "other")  // conflicts; exit status ignored

        let emitter = ConflictEmitter()
        let model = GitMageViewModel(host: FakeHostServices(context: RecordingContextRegistry(), signals: emitter))
        model.repos = [
            GitMageRepoConfig(id: repo.path, path: repo.path, name: "t", draftCommitMessage: "", lastBranch: "")
        ]
        model.activeRepoID = repo.path
        // No refresh has run, so `snapshot` is nil: only a refresh inside
        // `run()` can make the conflict visible to the reporter.
        model.fetch()
        let deadline = Date().addingTimeInterval(10)
        while emitter.kinds.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }

        #expect(emitter.kinds.contains("git.conflict"))
    }

    private func twoRepos() throws -> (TempRepo, TempRepo) { (try TempRepo(), try TempRepo()) }

    private func makeModel(_ a: TempRepo, _ b: TempRepo) -> GitMageViewModel {
        let model = GitMageViewModel(host: FakeHostServices(context: RecordingContextRegistry()))
        model.repos = [a, b].map {
            GitMageRepoConfig(id: $0.path, path: $0.path, name: "t", draftCommitMessage: "", lastBranch: "")
        }
        model.activeRepoID = a.path
        return model
    }
}

private final class ConflictEmitter: PluginSignalEmitter {
    var kinds: [String] = []
    func emit(
        kind: String, severity: SignalSeverity, title: String, body: String?,
        importance: SignalImportance, deepLink: SignalDeepLink?,
        actions: [SignalAction], dedupeKey: String?
    ) { kinds.append(kind) }
    func own(limit: Int) -> [SignalEvent] { [] }
    func handleAction(_ actionID: String, _ handler: @escaping @MainActor () async -> Void) -> AgentActionToken {
        AgentActionToken()
    }
    func removeActionHandler(_ token: AgentActionToken) {}
}
