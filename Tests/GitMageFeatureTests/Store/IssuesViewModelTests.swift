import AinkradAppKit
import XCTest

@testable import GitMageFeature

@MainActor
final class IssuesViewModelTests: XCTestCase {
    private let repo = RepoRef(host: "github.com", owner: "o", name: "r")

    private func makeSummary(number: Int = 7) -> IssueSummary {
        IssueSummary(
            id: 1, number: number, title: "Bug", author: "alice", state: "open", labelNames: ["bug"], commentCount: 2)
    }

    private func makeDetail(number: Int = 7, state: String = "open") -> IssueDetail {
        IssueDetail(
            number: number, title: "Bug", body: "body", state: state, author: "alice",
            createdAt: "2026-07-01T00:00:00Z", labels: [IssueLabel(name: "bug", color: "red")], assignees: ["bob"])
    }

    func testLoadPopulatesIssuesLabelsAndUsers() async {
        let provider = StubIssueForgeProvider()
        provider.summaries = [makeSummary()]
        provider.labels = [IssueLabel(name: "bug", color: "red")]
        provider.users = [ForgeUser(login: "bob")]
        let vm = IssuesViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))

        await vm.load()

        XCTAssertEqual(vm.issues.count, 1)
        XCTAssertEqual(vm.issues.first?.number, 7)
        XCTAssertEqual(vm.repoLabels.count, 1)
        XCTAssertEqual(vm.assignableUsers.count, 1)
    }

    func testSelectPopulatesDetailAndComments() async {
        let provider = StubIssueForgeProvider()
        provider.detail = makeDetail()
        provider.comments = [ForgeComment(id: 1, author: "alice", body: "hi", createdAt: "now")]
        let vm = IssuesViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))

        await vm.select(7)

        XCTAssertEqual(vm.selectedNumber, 7)
        XCTAssertEqual(vm.detail?.number, 7)
        XCTAssertEqual(vm.comments.count, 1)
    }

    func testCreateCallsProviderThenReloads() async {
        let provider = StubIssueForgeProvider()
        provider.summaries = [makeSummary()]
        let vm = IssuesViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))
        vm.newTitle = "New issue"
        vm.newBody = "Details"
        vm.newLabels = ["bug"]
        vm.newAssignees = ["bob"]
        vm.showNew = true

        await vm.create()

        XCTAssertEqual(provider.createIssueCalls.count, 1)
        XCTAssertEqual(provider.createIssueCalls.first?.title, "New issue")
        XCTAssertEqual(provider.searchIssuesCallCount, 1)
        XCTAssertFalse(vm.showNew)
        XCTAssertEqual(vm.newTitle, "")
    }

    func testToggleStateOnOpenIssueClosesAndRefreshes() async {
        let provider = StubIssueForgeProvider()
        provider.detail = makeDetail(state: "open")
        let vm = IssuesViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))
        await vm.select(7)
        provider.issueCallCount = 0

        await vm.toggleState()

        XCTAssertEqual(provider.setIssueStateCalls.count, 1)
        XCTAssertEqual(provider.setIssueStateCalls.first?.state, .closed)
        XCTAssertEqual(provider.issueCallCount, 1)
    }

    func testNilRepoMakesLoadNoOp() async {
        let provider = StubIssueForgeProvider()
        provider.summaries = [makeSummary()]
        let vm = IssuesViewModel(repo: nil, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))

        await vm.load()

        XCTAssertEqual(vm.issues.count, 0)
        XCTAssertEqual(provider.searchIssuesCallCount, 0)
    }
}

// MARK: - Test doubles

private final class MemorySecretStore: PluginSecretStore {
    private var storage: [String: String] = [:]
    func secret(forKey key: String) -> String? { storage[key] }
    func setSecret(_ value: String?, forKey key: String) {
        storage[key] = value
    }
}

private final class StubIssueForgeProvider: GitForgeProvider {
    var summaries: [IssueSummary] = []
    var detail: IssueDetail?
    var comments: [ForgeComment] = []
    var labels: [IssueLabel] = []
    var users: [ForgeUser] = []
    var verifyError: ForgeError?
    var listIssuesError: ForgeError?

    var searchIssuesCallCount = 0
    var issueCallCount = 0
    var createIssueCalls: [(title: String, body: String, labels: [String], assignees: [String])] = []
    var addIssueCommentCalls: [String] = []
    var setIssueStateCalls: [(number: Int, state: IssueState)] = []
    var setLabelsCalls: [[String]] = []
    var setAssigneesCalls: [[String]] = []

    func verify() async throws -> ForgeUser {
        if let verifyError { throw verifyError }
        return ForgeUser(login: "alice")
    }

    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary] { [] }
    func searchPullRequests(_ repo: RepoRef, state: PRState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<PullRequestSummary>
    {
        ForgePage(items: [], totalCount: 0)
    }
    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail { throw ForgeError.notFound }
    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile] { [] }
    func pullRequestCommits(_ repo: RepoRef, number: Int) async throws -> [PRCommit] { [] }
    func comments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] { [] }
    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun] { [] }
    func addComment(_ repo: RepoRef, number: Int, body: String) async throws {}
    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws {}
    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws {}
    func createPullRequest(_ repo: RepoRef, title: String, body: String, head: String, base: String, draft: Bool)
        async throws -> Int
    { 0 }
    func setPullRequestState(_ repo: RepoRef, number: Int, state: PRState) async throws {}

    func searchIssues(_ repo: RepoRef, state: IssueState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<IssueSummary>
    {
        searchIssuesCallCount += 1
        if let listIssuesError { throw listIssuesError }
        return ForgePage(items: summaries, totalCount: summaries.count)
    }

    func issue(_ repo: RepoRef, number: Int) async throws -> IssueDetail {
        issueCallCount += 1
        guard let detail else { throw ForgeError.notFound }
        return detail
    }

    func issueComments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] {
        comments
    }

    func repoLabels(_ repo: RepoRef) async throws -> [IssueLabel] {
        labels
    }

    func assignableUsers(_ repo: RepoRef) async throws -> [ForgeUser] {
        users
    }

    func createIssue(_ repo: RepoRef, title: String, body: String, labels: [String], assignees: [String]) async throws
        -> Int
    {
        createIssueCalls.append((title: title, body: body, labels: labels, assignees: assignees))
        return 42
    }

    func addIssueComment(_ repo: RepoRef, number: Int, body: String) async throws {
        addIssueCommentCalls.append(body)
    }

    func setIssueState(_ repo: RepoRef, number: Int, state: IssueState) async throws {
        setIssueStateCalls.append((number: number, state: state))
    }

    func setLabels(_ repo: RepoRef, number: Int, labels: [String]) async throws {
        setLabelsCalls.append(labels)
    }

    func setAssignees(_ repo: RepoRef, number: Int, assignees: [String]) async throws {
        setAssigneesCalls.append(assignees)
    }
}
