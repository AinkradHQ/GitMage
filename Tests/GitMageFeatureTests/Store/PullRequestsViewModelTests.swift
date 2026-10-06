import AinkradAppKit
import XCTest

@testable import GitMageFeature

@MainActor
final class PullRequestsViewModelTests: XCTestCase {
    private let repo = RepoRef(host: "github.com", owner: "o", name: "r")

    private func makeSummary(number: Int = 7) -> PullRequestSummary {
        PullRequestSummary(
            id: 1, number: number, title: "Fix", author: "alice", state: "open", isDraft: false, headBranch: "feat",
            baseBranch: "main")
    }

    private func makeDetail(number: Int = 7) -> PullRequestDetail {
        PullRequestDetail(
            number: number, title: "Fix", body: "body", state: "open", isDraft: false, author: "alice",
            createdAt: "2026-07-01T00:00:00Z", mergeable: true, mergeableState: "clean", additions: 1, deletions: 0,
            headBranch: "feat", baseBranch: "main")
    }

    func testLoadPopulatesPullRequestsFromProvider() async {
        let provider = StubForgeProvider()
        provider.summaries = [makeSummary()]
        let vm = PullRequestsViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))

        await vm.load()

        XCTAssertEqual(vm.pullRequests.count, 1)
        XCTAssertEqual(vm.pullRequests.first?.number, 7)
    }

    func testSelectPopulatesDetailFilesCommentsAndChecks() async {
        let provider = StubForgeProvider()
        provider.detail = makeDetail()
        provider.prFiles = [PRFile(filename: "a.swift", status: "modified", patch: nil)]
        provider.prComments = [ForgeComment(id: 1, author: "alice", body: "hi", createdAt: "now")]
        provider.checkRuns = [CheckRun(id: 1, name: "CI", status: "completed", conclusion: "success")]

        let vm = PullRequestsViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))
        await vm.select(7)

        XCTAssertEqual(vm.selectedPRNumber, 7)
        XCTAssertEqual(vm.detail?.number, 7)
        XCTAssertEqual(vm.files.count, 1)
        XCTAssertEqual(vm.comments.count, 1)
        XCTAssertEqual(vm.checks.count, 1)
        XCTAssertEqual(provider.checksRefArgs, ["feat"])
    }

    func testReviewApproveCallsProviderAndReloads() async {
        let provider = StubForgeProvider()
        provider.detail = makeDetail()
        let vm = PullRequestsViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))
        await vm.select(7)
        provider.pullRequestCallCount = 0

        await vm.review(.approve, body: "LGTM")

        XCTAssertEqual(provider.submitReviewCalls.count, 1)
        XCTAssertEqual(provider.submitReviewCalls.first?.event, .approve)
        XCTAssertEqual(provider.submitReviewCalls.first?.body, "LGTM")
        XCTAssertEqual(provider.pullRequestCallCount, 1)
    }

    func testUnauthorizedFromVerifySetsInvalidAuthState() async {
        let provider = StubForgeProvider()
        provider.verifyError = .unauthorized
        let secrets = MemorySecretStore()
        secrets.setSecret("bad-token", forKey: GitForgeAuth.key)
        let vm = PullRequestsViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: secrets))

        await vm.verify()

        if case .invalid = vm.authState {
            // expected
        } else {
            XCTFail("expected .invalid, got \(vm.authState)")
        }
    }

    func testMissingTokenSetsMissingTokenAuthState() async {
        let provider = StubForgeProvider()
        let vm = PullRequestsViewModel(repo: repo, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))

        await vm.verify()

        XCTAssertEqual(vm.authState, .missingToken)
    }

    func testNilRepoMakesLoadNoOp() async {
        let provider = StubForgeProvider()
        provider.summaries = [makeSummary()]
        let vm = PullRequestsViewModel(repo: nil, provider: provider, auth: GitForgeAuth(secrets: MemorySecretStore()))

        await vm.load()

        XCTAssertEqual(vm.pullRequests.count, 0)
        XCTAssertEqual(provider.listPullRequestsCallCount, 0)
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

// SAFETY: test double; each test builds its own and drives it from one task at a time.
private final class StubForgeProvider: GitForgeProvider, @unchecked Sendable {
    var summaries: [PullRequestSummary] = []
    var detail: PullRequestDetail?
    var prFiles: [PRFile] = []
    var prComments: [ForgeComment] = []
    var checkRuns: [CheckRun] = []
    var verifyError: ForgeError?
    var listPullRequestsError: ForgeError?

    var listPullRequestsCallCount = 0
    var pullRequestCallCount = 0
    var checksRefArgs: [String] = []
    var submitReviewCalls: [(event: ReviewEvent, body: String)] = []
    var mergeCalls: [MergeMethod] = []
    var addCommentCalls: [String] = []

    func verify() async throws -> ForgeUser {
        if let verifyError { throw verifyError }
        return ForgeUser(login: "alice")
    }

    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary] {
        listPullRequestsCallCount += 1
        if let listPullRequestsError { throw listPullRequestsError }
        return summaries
    }

    func searchPullRequests(_ repo: RepoRef, state: PRState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<PullRequestSummary>
    {
        if let listPullRequestsError { throw listPullRequestsError }
        return ForgePage(items: summaries, totalCount: summaries.count)
    }

    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail {
        pullRequestCallCount += 1
        guard let detail else { throw ForgeError.notFound }
        return detail
    }

    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile] {
        prFiles
    }

    func pullRequestCommits(_ repo: RepoRef, number: Int) async throws -> [PRCommit] { [] }

    func comments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] {
        prComments
    }

    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun] {
        checksRefArgs.append(ref)
        return checkRuns
    }

    func addComment(_ repo: RepoRef, number: Int, body: String) async throws {
        addCommentCalls.append(body)
    }

    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws {
        submitReviewCalls.append((event: event, body: body))
    }

    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws {
        mergeCalls.append(method)
    }

    func createPullRequest(_ repo: RepoRef, title: String, body: String, head: String, base: String, draft: Bool)
        async throws -> Int
    { 0 }
    func setPullRequestState(_ repo: RepoRef, number: Int, state: PRState) async throws {}

    func searchIssues(_ repo: RepoRef, state: IssueState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<IssueSummary>
    {
        ForgePage(items: [], totalCount: 0)
    }
    func issue(_ repo: RepoRef, number: Int) async throws -> IssueDetail { throw ForgeError.notFound }
    func issueComments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] { [] }
    func repoLabels(_ repo: RepoRef) async throws -> [IssueLabel] { [] }
    func assignableUsers(_ repo: RepoRef) async throws -> [ForgeUser] { [] }
    func createIssue(_ repo: RepoRef, title: String, body: String, labels: [String], assignees: [String]) async throws
        -> Int
    { 0 }
    func addIssueComment(_ repo: RepoRef, number: Int, body: String) async throws {}
    func setIssueState(_ repo: RepoRef, number: Int, state: IssueState) async throws {}
    func setLabels(_ repo: RepoRef, number: Int, labels: [String]) async throws {}
    func setAssignees(_ repo: RepoRef, number: Int, assignees: [String]) async throws {}
}
