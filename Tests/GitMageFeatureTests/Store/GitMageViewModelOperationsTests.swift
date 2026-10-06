import Foundation
import Testing

@testable import GitMageFeature

/// Mutating operations and history paging in `GitMageViewModel`: commit, the
/// remote trio, stash and branch actions, and every failure's state. Real
/// repositories (including a local bare remote), no stub client.
@Suite("Git Mage — operations and paging")
@MainActor
struct GitMageViewModelOperationsTests {

    // MARK: - Commit

    @Test("Committing records the message, clears the draft and leaves a clean tree")
    func commitSucceeds() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.write("new.txt", "x")
        try repo.run("git", "add", "-A")
        let model = makeViewModel([repo.path])
        model.draftCommitMessage = "add new file"

        model.commitChanges()
        try await waitUntil("the commit") { isIdle(model) && model.draftCommitMessage.isEmpty }

        #expect(try repo.run("git", "log", "-1", "--format=%s").trimmed == "add new file")
        #expect(model.draftCommitMessage == "")
        #expect(model.repos.first?.draftCommitMessage == "", "the cleared draft is folded back into the library")
        #expect(model.snapshot?.changes.isEmpty == true)
        #expect(model.snapshot?.lastCommitSummary == "add new file")
        #expect(model.errorMessage == nil)
    }

    @Test("A commit with nothing staged fails, keeps the draft and releases the busy state")
    func commitNothingStaged() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])
        model.draftCommitMessage = "empty"

        model.commitChanges()
        try await waitUntil("the error") { model.errorMessage != nil }

        #expect(model.errorMessage == GitRepositoryError.nothingToCommit.errorDescription)
        #expect(model.draftCommitMessage == "empty")
        #expect(!model.isLoading)
        #expect(model.activeOperation == nil)
    }

    @Test("A blank commit message is refused with its own message")
    func commitBlankMessage() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.write("a.txt", "a")
        try repo.run("git", "add", "-A")
        let model = makeViewModel([repo.path])
        model.draftCommitMessage = "   "

        model.commitChanges()
        try await waitUntil("the error") { model.errorMessage != nil }

        #expect(model.errorMessage == GitRepositoryError.invalidCommitMessage.errorDescription)
    }

    @Test("A head-moving operation resets loaded history; staging keeps it")
    func historySurvivesOnlyHeadStableOperations() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])
        model.loadCommits()
        try await waitUntil("history") { model.commits.count == 1 && !model.isLoadingCommits }

        try repo.write("s.txt", "s")
        model.stageAllChanges()
        try await waitUntil("staging") { isIdle(model) && model.snapshot != nil }
        #expect(model.commits.count == 1, "staging cannot move HEAD, so history is kept")

        model.draftCommitMessage = "second"
        model.commitChanges()
        try await waitUntil("the commit") { isIdle(model) && model.snapshot?.lastCommitSummary == "second" }
        #expect(model.commits.isEmpty, "a commit moves HEAD, so history reloads from scratch")
        #expect(model.selectedCommitID == nil)
    }

    // MARK: - Branches

    @Test("Creating a branch checks it out, clears the name field and lists it")
    func createBranch() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])
        model.newBranchName = "feature/x"

        model.createBranch()
        try await waitUntil("the branch") { isIdle(model) && model.snapshot != nil }

        #expect(model.newBranchName == "")
        #expect(model.snapshot?.branchName == "feature/x")
        #expect(model.branches.contains { $0.name == "feature/x" && $0.isCurrent })
    }

    @Test("Checking out an unknown branch surfaces git's error and clears the busy state")
    func checkoutUnknownBranch() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])
        model.selectedBranchName = "no-such-branch"

        model.checkoutSelectedBranch()
        try await waitUntil("the error") { model.errorMessage != nil }

        #expect(model.errorMessage?.isEmpty == false)
        #expect(!model.isLoading)
        #expect(model.activeOperation == nil)
    }

    @Test("Deleting the checked-out branch fails and the branch stays")
    func deleteCurrentBranch() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])

        model.deleteBranch("main")
        try await waitUntil("the error") { model.errorMessage != nil }

        #expect(try repo.run("git", "branch", "--list", "main").contains("main"))
    }

    @Test("An action with no active repository does nothing and sets no state")
    func actionWithoutRepository() {
        let model = makeViewModel([])
        model.draftCommitMessage = "x"

        model.commitChanges()
        model.fetch()
        model.stashChanges()

        #expect(!model.isLoading)
        #expect(model.activeOperation == nil)
        #expect(model.errorMessage == nil)
    }

    // MARK: - Remote operations

    @Test("Fetch with no remote configured succeeds")
    func fetchWithoutRemote() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])

        model.fetch()
        #expect(model.activeOperation == "fetch", "the label is set synchronously, for the button spinner")
        #expect(model.isLoading)
        try await waitUntil("fetch") { isIdle(model) && model.snapshot != nil }

        #expect(model.errorMessage == nil)
    }

    @Test("Push, fetch and pull move commits between a clone and its bare remote")
    func remoteRoundTrip() async throws {
        let repo = try TempRepo()
        let remote = repo.path + "-remote.git"
        let peer = repo.path + "-peer"
        defer {
            repo.cleanUp()
            try? FileManager.default.removeItem(atPath: remote)
            try? FileManager.default.removeItem(atPath: peer)
        }
        try repo.run("git", "init", "--bare", "-b", "main", remote)
        try repo.run("git", "remote", "add", "origin", remote)
        let model = makeViewModel([repo.path])

        // First push has no upstream yet: it sets origin/main.
        model.push()
        try await waitUntil("the first push") { isIdle(model) && model.snapshot != nil }
        #expect(model.errorMessage == nil)
        #expect(model.snapshot?.upstream == "origin/main")
        #expect(model.snapshot?.aheadCount == 0)

        // A local commit shows as ahead, and the next push uses the upstream.
        try repo.write("local.txt", "l")
        try repo.run("git", "add", "-A")
        try repo.run("git", "commit", "-qm", "local")
        model.refresh()
        try await waitUntil("ahead") { isIdle(model) && model.snapshot?.aheadCount == 1 }
        model.push()
        try await waitUntil("the second push") { isIdle(model) && model.snapshot?.aheadCount == 0 }
        #expect(model.errorMessage == nil)

        // A peer pushes; fetch shows behind, pull fast-forwards.
        try repo.run("git", "clone", "-q", remote, peer)
        try repo.run("git", "-C", peer, "config", "user.email", "p@example.com")
        try repo.run("git", "-C", peer, "config", "user.name", "Peer")
        try "p".write(toFile: peer + "/peer.txt", atomically: true, encoding: .utf8)
        try repo.run("git", "-C", peer, "add", "-A")
        try repo.run("git", "-C", peer, "commit", "-qm", "from peer")
        try repo.run("git", "-C", peer, "push", "-q")

        model.fetch()
        try await waitUntil("behind") { isIdle(model) && model.snapshot?.behindCount == 1 }
        model.pull()
        try await waitUntil("the pull") { isIdle(model) && model.snapshot?.behindCount == 0 }
        #expect(model.errorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: repo.path + "/peer.txt"))
    }

    @Test("A pull with no upstream fails, reports it and releases the busy state")
    func pullWithoutUpstream() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])

        model.pull()
        try await waitUntil("the error") { model.errorMessage != nil }

        #expect(model.errorMessage?.isEmpty == false)
        #expect(!model.isLoading)
        #expect(model.activeOperation == nil)
    }

    // MARK: - History paging

    @Test("History loads 50 at a time, newest first, with a total and an auto-selected head")
    func historyPaging() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.run(
            "bash", "-c", "for i in $(seq 1 120); do git commit -q --allow-empty -m c$i; done")
        let model = makeViewModel([repo.path])

        model.loadCommits()
        try await waitUntil("page 1") { model.commits.count == 50 && !model.isLoadingCommits }
        #expect(model.hasMoreCommits)
        #expect(model.commits.first?.summary == "c120")
        #expect(model.selectedCommitID == model.commits.first?.id, "the newest commit is selected for the detail pane")
        try await waitUntil("the total") { model.totalCommits != nil }
        #expect(model.totalCommits == 121)

        model.loadMoreCommits()
        try await waitUntil("page 2") { model.commits.count == 100 && !model.isLoadingCommits }
        #expect(model.hasMoreCommits)

        model.loadMoreCommits()
        try await waitUntil("page 3") { model.commits.count == 121 && !model.isLoadingCommits }
        #expect(!model.hasMoreCommits, "a short page is the end of the log")
        #expect(model.commits.last?.summary == "initial")
        #expect(Set(model.commits.map(\.id)).count == 121, "pages do not overlap")

        model.loadMoreCommits()
        #expect(!model.isLoadingCommits, "past the end, scrolling starts no load")
        #expect(model.commits.count == 121)
    }

    @Test("Calling loadMoreCommits twice at once loads one page, not two")
    func loadMoreIsNotReentrant() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.run("bash", "-c", "for i in $(seq 1 60); do git commit -q --allow-empty -m c$i; done")
        let model = makeViewModel([repo.path])

        model.loadMoreCommits()
        model.loadMoreCommits()
        try await waitUntil("a page") { !model.isLoadingCommits && !model.commits.isEmpty }
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(model.commits.count == 50)
    }

    @Test("Opening History loads commits once; with no repository it loads nothing")
    func selectAreaHistory() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let empty = makeViewModel([])
        empty.selectArea(.history)
        #expect(empty.selectedArea == .history)
        #expect(!empty.isLoadingCommits)

        let model = makeViewModel([repo.path])
        model.selectArea(.history)
        #expect(model.isLoadingCommits)
        try await waitUntil("history") { model.commits.count == 1 && !model.isLoadingCommits }
    }

    @Test("A repository with no commits has an empty, finished history")
    func historyOfAnUnbornBranch() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        try repo.run("git", "checkout", "-q", "--orphan", "unborn")
        let model = makeViewModel([repo.path])

        model.loadCommits()
        try await waitUntil("the load") { !model.isLoadingCommits && !model.hasMoreCommits }

        #expect(model.commits.isEmpty)
        #expect(model.selectedCommitID == nil)
    }

    @Test("Selecting a commit titles its diff with the short sha and summary")
    func selectCommitTitle() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])
        model.loadCommits()
        try await waitUntil("history") { model.commitDiff != nil }

        let head = try #require(model.commits.first)
        #expect(model.commitDiff?.title == "\(head.shortSHA) · initial")
        #expect(model.commitDiff?.body.contains("README.md") == true)
    }

    @Test("Selecting a commit that does not exist shows git's error as the diff body")
    func selectUnknownCommit() async throws {
        let repo = try TempRepo()
        defer { repo.cleanUp() }
        let model = makeViewModel([repo.path])

        model.selectCommit(
            GitCommitSummary(id: "deadbeef", shortSHA: "deadbee", summary: "ghost", author: "A", relativeDate: ""))
        try await waitUntil("the diff") { model.commitDiff != nil }

        #expect(model.commitDiff?.title == "deadbee")
        #expect(model.commitDiff?.isEmpty == true)
        #expect(model.commitDiff?.body.isEmpty == false)
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
