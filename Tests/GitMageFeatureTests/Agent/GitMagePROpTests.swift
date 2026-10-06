import AinkradAppKit
import Foundation
import Testing

@testable import GitMageFeature

// MARK: - doubles

/// A `GitForgeProvider` that answers from memory and records every call.
/// Nothing here touches the network — the handler is built with this instance
/// injected in place of `GitHubProvider`.
private final class StubForgeProvider: GitForgeProvider {
    var summaries: [PullRequestSummary] = []
    var detail: PullRequestDetail?
    var checkRuns: [CheckRun] = []
    var createdNumber = 42
    var thrownError: ForgeError?

    var listCalls: [PRState] = []
    var pullRequestCalls: [Int] = []
    var filesCalls: [Int] = []
    var commitsCalls: [Int] = []
    var commentsCalls: [Int] = []
    var checksCalls: [String] = []
    var addCommentCalls: [(number: Int, body: String)] = []
    var submitReviewCalls: [(number: Int, event: ReviewEvent, body: String)] = []
    var mergeCalls: [(number: Int, method: MergeMethod)] = []
    var createCalls: [(title: String, body: String, head: String, base: String, draft: Bool)] = []
    var setStateCalls: [(number: Int, state: PRState)] = []

    private func failIfNeeded() throws { if let thrownError { throw thrownError } }

    func verify() async throws -> ForgeUser { ForgeUser(login: "alice") }
    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary] {
        listCalls.append(state)
        try failIfNeeded()
        return summaries
    }
    func searchPullRequests(_ repo: RepoRef, state: PRState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<PullRequestSummary>
    {
        ForgePage(items: summaries, totalCount: summaries.count)
    }
    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail {
        pullRequestCalls.append(number)
        try failIfNeeded()
        guard let detail else { throw ForgeError.notFound }
        return detail
    }
    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile] {
        filesCalls.append(number)
        return []
    }
    func pullRequestCommits(_ repo: RepoRef, number: Int) async throws -> [PRCommit] {
        commitsCalls.append(number)
        return []
    }
    func comments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] {
        commentsCalls.append(number)
        return []
    }
    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun] {
        checksCalls.append(ref)
        return checkRuns
    }
    func addComment(_ repo: RepoRef, number: Int, body: String) async throws {
        addCommentCalls.append((number, body))
        try failIfNeeded()
    }
    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws {
        submitReviewCalls.append((number, event, body))
        try failIfNeeded()
    }
    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws {
        mergeCalls.append((number, method))
        try failIfNeeded()
    }
    func createPullRequest(_ repo: RepoRef, title: String, body: String, head: String, base: String, draft: Bool)
        async throws -> Int
    {
        createCalls.append((title, body, head, base, draft))
        try failIfNeeded()
        return createdNumber
    }
    func setPullRequestState(_ repo: RepoRef, number: Int, state: PRState) async throws {
        setStateCalls.append((number, state))
        try failIfNeeded()
    }

    func listIssues(_ repo: RepoRef, state: IssueState) async throws -> [IssueSummary] { [] }
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

private func readOnlyHint(_ tool: [String: Any]) -> Bool {
    (tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool ?? false
}

// MARK: - tests

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GitMagePROpTests {
    private let repo = RepoRef(host: "github.com", owner: "o", name: "r")

    private func makeDetail(number: Int = 7) -> PullRequestDetail {
        PullRequestDetail(
            number: number, title: "Fix", body: "body", state: "open", isDraft: false,
            author: "alice", createdAt: "2026-07-01T00:00:00Z", mergeable: true,
            mergeableState: "clean", additions: 1, deletions: 0,
            headBranch: "feat", baseBranch: "main")
    }

    /// Builds the real server with BOTH forwarders, where the PR one is the real
    /// `PrOpActionHandler` wired to an in-memory provider and a fixed repo — so
    /// a call exercises tool → handler → provider without any git or network.
    private func makeServer(
        _ provider: StubForgeProvider,
        gitRecorder: RecordingForwarder = RecordingForwarder()
    )
        -> (MCPAppServer, [String])
    {
        let handler = PrOpActionHandler(
            resolveRepo: { _ in self.repo },
            makeProvider: { provider }
        )
        return GitMageMCPServer.make(
            appID: "gitmage",
            forward: { await gitRecorder.forward($0) },
            forwardPR: { await handler.run($0) }
        )
    }

    // MARK: publication

    @Test func publishesEveryPRToolAndNothingIsRejected() async {
        let (server, failures) = makeServer(StubForgeProvider())
        #expect(failures.isEmpty, "addTool rejected: \(failures)")

        let listed = Set(await listedTools(server).compactMap { $0["name"] as? String })
        let expected: Set<String> = [
            "pr_list", "pr_view", "pr_checks", "pr_create",
            "pr_comment", "pr_review", "pr_approve", "pr_merge", "pr_close",
        ]
        #expect(expected.isSubset(of: listed), "missing: \(expected.subtracting(listed))")
        // The git tools are still published alongside them.
        #expect(listed.contains("status"))
        #expect(listed == Set(GitMageMCPServer.tools.map(\.name)))
    }

    @Test func destructiveHintsMatchTheClassification() async {
        let (server, _) = makeServer(StubForgeProvider())
        let listed = await listedTools(server)
        // Merging and closing destroy or foreclose state that cannot be restored
        // through the API, and approving can auto-merge. Creating a PR,
        // commenting, and non-approving reviews are additive and remediable, so
        // they stay ungated.
        let expected: [String: Bool] = [
            "pr_list": false, "pr_view": false, "pr_checks": false, "pr_create": false,
            "pr_comment": false, "pr_review": false, "pr_approve": true,
            "pr_merge": true, "pr_close": true,
        ]
        for (name, flag) in expected {
            guard let entry = listed.first(where: { $0["name"] as? String == name }) else {
                Issue.record("tool \(name) was not listed")
                continue
            }
            #expect(destructiveHint(entry) == flag, "wrong destructiveHint for \(name)")
        }
        for name in ["pr_list", "pr_view", "pr_checks"] {
            guard let entry = listed.first(where: { $0["name"] as? String == name }) else { continue }
            #expect(readOnlyHint(entry), "\(name) should be readOnly")
        }
    }

    // MARK: routing

    @Test func aPRCallGoesDownThePRPathAndNeverTheGitPath() async {
        let provider = StubForgeProvider()
        let gitRecorder = RecordingForwarder()
        let (server, _) = makeServer(provider, gitRecorder: gitRecorder)

        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])

        #expect(outcome.isError == false)
        #expect(provider.listCalls == [.open], "pr_list did not reach the forge provider")
        #expect(gitRecorder.payloads.isEmpty, "a PR call reached the git handler")
    }

    @Test func aGitCallStillGoesDownTheGitPath() async {
        let provider = StubForgeProvider()
        let gitRecorder = RecordingForwarder()
        let (server, _) = makeServer(provider, gitRecorder: gitRecorder)

        _ = await call(server, "status", arguments: ["repoPath": "/r"])

        #expect(gitRecorder.lastObject?["operation"] as? String == "status")
        #expect(provider.listCalls.isEmpty)
    }

    @Test func missingRepoPathIsAnErrorNotAForwardedCall() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_list", arguments: [:])
        #expect(outcome.isError)
        #expect(provider.listCalls.isEmpty)
    }

    // MARK: argument forwarding, tool by tool

    @Test func prListForwardsTheStateFilter() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_list", arguments: ["repoPath": "/r", "args": ["state": "closed"]])
        #expect(provider.listCalls == [.closed])
    }

    @Test func prViewForwardsTheNumberToEveryDetailCall() async {
        let provider = StubForgeProvider()
        provider.detail = makeDetail()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_view", arguments: ["repoPath": "/r", "args": ["number": 7]])
        #expect(outcome.isError == false)
        #expect(provider.pullRequestCalls == [7])
        #expect(provider.filesCalls == [7])
        #expect(provider.commitsCalls == [7])
        #expect(provider.commentsCalls == [7])
    }

    @Test func prChecksResolvesTheHeadBranchThenAsksForCheckRuns() async {
        let provider = StubForgeProvider()
        provider.detail = makeDetail()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_checks", arguments: ["repoPath": "/r", "args": ["number": 7]])
        #expect(provider.pullRequestCalls == [7])
        #expect(provider.checksCalls == ["feat"], "pr_checks must query the PR's head branch")
    }

    @Test func prCreateForwardsTitleBodyHeadBaseAndDraft() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(
            server, "pr_create",
            arguments: [
                "repoPath": "/r",
                "args": ["title": "T", "body": "B", "head": "feat", "base": "main", "draft": true],
            ])
        #expect(outcome.isError == false)
        #expect(provider.createCalls.count == 1)
        #expect(provider.createCalls.first?.title == "T")
        #expect(provider.createCalls.first?.body == "B")
        #expect(provider.createCalls.first?.head == "feat")
        #expect(provider.createCalls.first?.base == "main")
        #expect(provider.createCalls.first?.draft == true)
    }

    @Test func prCreateRequiresTitleHeadAndBase() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_create", arguments: ["repoPath": "/r", "args": ["title": "T"]])
        #expect(outcome.isError)
        #expect(provider.createCalls.isEmpty)
    }

    @Test func prCommentForwardsNumberAndBody() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(
            server, "pr_comment",
            arguments: ["repoPath": "/r", "args": ["number": 7, "body": "nice"]])
        #expect(provider.addCommentCalls.count == 1)
        #expect(provider.addCommentCalls.first?.number == 7)
        #expect(provider.addCommentCalls.first?.body == "nice")
    }

    @Test func prReviewForwardsTheEventAndBody() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(
            server, "pr_review",
            arguments: [
                "repoPath": "/r",
                "args": ["number": 7, "event": "requestChanges", "body": "needs work"],
            ])
        #expect(provider.submitReviewCalls.count == 1)
        #expect(provider.submitReviewCalls.first?.number == 7)
        #expect(provider.submitReviewCalls.first?.event == .requestChanges)
        #expect(provider.submitReviewCalls.first?.body == "needs work")
    }

    // MARK: - evasion of pr_review's approval guard
    //
    // The property under test is NOT "the call returned an error" — an error
    // string would still read as a pass if the approval leaked past it. It is:
    // **an approving review never reaches GitHub through the ungated tool**. So
    // every case asserts on what the PROVIDER actually received.

    /// Whether an approval reached the forge. `submitReview` is the only call
    /// that can create one, so an empty list is proof nothing was approved.
    private func approved(_ provider: StubForgeProvider) -> Bool {
        provider.submitReviewCalls.contains { $0.event == .approve }
    }

    @Test(arguments: approveEvasions)
    func prReviewNeverApprovesHoweverTheEventIsSpelled(evasion: PREvasion) async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(
            server, "pr_review",
            arguments: ["repoPath": "/r", "args": ["number": 7, "event": evasion.value()]])
        #expect(
            approved(provider) == false,
            "pr_review reached an approval via \(evasion.label)")
    }

    @Test func prReviewIgnoresANestedOrDifferentlyCasedEventKey() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)

        // A nested `args.args.event` — neither the guard nor the sink reads it.
        _ = await call(
            server, "pr_review",
            arguments: ["repoPath": "/r", "args": ["number": 7, "args": ["event": "approve"]]])
        #expect(approved(provider) == false, "a nested args.event reached the sink")

        // An `"Event"` key: missed by the guard, and equally missed by the sink,
        // which reads `args["event"]` exactly.
        _ = await call(
            server, "pr_review",
            arguments: ["repoPath": "/r", "args": ["number": 7, "Event": "approve"]])
        #expect(approved(provider) == false, "a differently-cased Event key reached the sink")
    }

    @Test func prReviewStillAllowsTheNonApprovingEvents() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        for (raw, expected) in [("comment", ReviewEvent.comment), ("requestChanges", .requestChanges)] {
            let outcome = await call(
                server, "pr_review",
                arguments: ["repoPath": "/r", "args": ["number": 7, "event": raw]])
            #expect(outcome.isError == false, "pr_review refused \(raw)")
            #expect(provider.submitReviewCalls.last?.event == expected)
        }
    }

    @Test func prApproveIsPublishedDestructiveAndInjectsTheApproval() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)

        guard let entry = await listedTools(server).first(where: { $0["name"] as? String == "pr_approve" }) else {
            Issue.record("pr_approve was not published")
            return
        }
        #expect(destructiveHint(entry))

        // No `event` passed at all — the tool supplies it.
        let outcome = await call(
            server, "pr_approve",
            arguments: ["repoPath": "/r", "args": ["number": 7, "body": "LGTM"]])
        #expect(outcome.isError == false)
        #expect(provider.submitReviewCalls.count == 1)
        #expect(provider.submitReviewCalls.first?.event == .approve)
        #expect(provider.submitReviewCalls.first?.number == 7)
        #expect(provider.submitReviewCalls.first?.body == "LGTM")
    }

    /// Pins the coupling the `pr_review` guard depends on: it resolves through
    /// `PrOpActionHandler.reviewEvent`, the SAME function the handler uses, so
    /// adding a spelling there cannot open a hole here. This drives the real
    /// parser rather than a mirror of it.
    @Test func theGuardAndTheSinkShareOneApprovalParser() async {
        for spelling in ["approve", "Approve", "APPROVE", "approved", "APPROVED"] {
            #expect(
                PrOpActionHandler.reviewEvent(spelling) == .approve,
                "the sink no longer reads \"\(spelling)\" as an approval")
            #expect(
                GitMageMCPServer.ArgumentValue.approvingReviewEvent.matches(spelling),
                "the guard misses \"\(spelling)\" that the sink accepts as an approval")
        }
        // A non-approving event must NOT be caught, or pr_review is unusable.
        for spelling in ["comment", "requestChanges", "request_changes"] {
            #expect(
                GitMageMCPServer.ArgumentValue.approvingReviewEvent.matches(spelling) == false,
                "the guard over-rejects \"\(spelling)\"")
        }
    }

    @Test func prReviewRejectsAnUnknownEvent() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        let outcome = await call(
            server, "pr_review",
            arguments: ["repoPath": "/r", "args": ["number": 7, "event": "yolo"]])
        #expect(outcome.isError)
        #expect(provider.submitReviewCalls.isEmpty)
    }

    @Test func prMergeForwardsTheMergeMethodAndDefaultsToMerge() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(
            server, "pr_merge",
            arguments: ["repoPath": "/r", "args": ["number": 7, "method": "squash"]])
        #expect(provider.mergeCalls.first?.number == 7)
        #expect(provider.mergeCalls.first?.method == .squash)

        _ = await call(server, "pr_merge", arguments: ["repoPath": "/r", "args": ["number": 8]])
        #expect(provider.mergeCalls.last?.method == .merge)
    }

    @Test func prCloseSetsTheClosedState() async {
        let provider = StubForgeProvider()
        let (server, _) = makeServer(provider)
        _ = await call(server, "pr_close", arguments: ["repoPath": "/r", "args": ["number": 7]])
        #expect(provider.setStateCalls.count == 1)
        #expect(provider.setStateCalls.first?.number == 7)
        #expect(provider.setStateCalls.first?.state == .closed)
    }

    // MARK: preconditions — a PR tool must fail loudly, never silently no-op

    @Test func aMissingTokenIsAClearErrorAndNeverReachesTheProvider() async {
        let handler = PrOpActionHandler(resolveRepo: { _ in self.repo }, makeProvider: { nil })
        let (server, _) = GitMageMCPServer.make(
            appID: "gitmage",
            forward: { _ in AgentActionResult(text: "", isError: false) },
            forwardPR: { await handler.run($0) })
        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])
        #expect(outcome.isError)
        #expect(outcome.text.lowercased().contains("token"))
    }

    @Test func anUnrecognizedRemoteIsAClearError() async {
        let provider = StubForgeProvider()
        let handler = PrOpActionHandler(resolveRepo: { _ in nil }, makeProvider: { provider })
        let (server, _) = GitMageMCPServer.make(
            appID: "gitmage",
            forward: { _ in AgentActionResult(text: "", isError: false) },
            forwardPR: { await handler.run($0) })
        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])
        #expect(outcome.isError)
        #expect(provider.listCalls.isEmpty)
    }

    @Test func aForgeErrorSurfacesAsAToolError() async {
        let provider = StubForgeProvider()
        provider.thrownError = .unauthorized
        let (server, _) = makeServer(provider)
        let outcome = await call(server, "pr_list", arguments: ["repoPath": "/r"])
        #expect(outcome.isError)
        #expect(outcome.text.contains("token"))
    }
}
