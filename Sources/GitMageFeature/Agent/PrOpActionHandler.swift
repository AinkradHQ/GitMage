import AinkradAppKit
import Foundation

/// Maps a `{operation, repoPath, args}` PR request to the SAME `GitForgeProvider`
/// the Pull Requests UI drives — the sibling of `GitOpActionHandler`, which does
/// the same for local git.
///
/// No GitHub client lives here and none is spawned: the two seams into the world
/// (which repo `repoPath` names, and which provider to talk to) are injected, so
/// the tests exercise the whole tool → handler → provider chain with an
/// in-memory provider and never open a socket or run `git`.
///
/// A `MainActor` class rather than a struct so it is `Sendable` and can be
/// captured by `GitMageMCPServer.make`'s `@Sendable` forwarder.
@MainActor
final class PrOpActionHandler {
    /// Resolves a repository path to its forge coordinates. Nil when the repo
    /// has no `origin`, or one this app cannot parse.
    private let resolveRepo: (String) async -> RepoRef?
    /// The forge client. Nil when no GitHub token is configured.
    private let makeProvider: () -> GitForgeProvider?

    /// The provider, built once on first use.
    private var cachedProvider: GitForgeProvider?

    private func prepareProvider() -> Bool {
        if cachedProvider == nil { cachedProvider = makeProvider() }
        return cachedProvider != nil
    }

    init(
        resolveRepo: @escaping (String) async -> RepoRef?,
        makeProvider: @escaping () -> GitForgeProvider?
    ) {
        self.resolveRepo = resolveRepo
        self.makeProvider = makeProvider
    }

    /// The production wiring: `origin` via the shared git client, GitHub via the
    /// token in the host's secret store.
    convenience init(client: GitRepositoryClient, secrets: PluginSecretStore) {
        self.init(
            resolveRepo: { try? await client.remoteInfo(in: $0) },
            makeProvider: { GitForgeAuth(secrets: secrets).token().map { GitHubProvider(token: $0) } }
        )
    }

    func run(_ json: String) async -> AgentActionResult {
        guard let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let operation = obj["operation"] as? String,
            let repoPath = obj["repoPath"] as? String
        else {
            return bad("pr_op: malformed input")
        }
        let args = obj["args"] as? [String: Any] ?? [:]

        guard prepareProvider() else {
            return bad("No GitHub token is configured. Add one in Git Mage's settings before running PR operations.")
        }
        guard let repo = await resolveRepo(repoPath) else {
            return bad("\(repoPath) has no recognized GitHub \"origin\" remote.")
        }

        do {
            return try await perform(operation, repo: repo, args: args)
        } catch let error as ForgeError {
            return bad(error.errorDescription ?? "GitHub request failed.")
        } catch {
            return bad(error.displayMessage)
        }
    }

    // MARK: - dispatch

    private func perform(
        _ operation: String, repo: RepoRef,
        args: [String: Any]
    ) async throws -> AgentActionResult {
        guard let provider = cachedProvider else { return bad("pr_op: no forge provider") }
        switch operation {
        case "listPRs":
            let state = PRState(rawValue: (args["state"] as? String) ?? "open") ?? .open
            let items = try await provider.listPullRequests(repo, state: state)
            guard !items.isEmpty else { return ok("No \(state.rawValue) pull requests.") }
            return ok(
                items.map {
                    "#\($0.number) \($0.title) — \($0.author) [\($0.state)\($0.isDraft ? ", draft" : "")] \($0.headBranch) → \($0.baseBranch)"
                }.joined(separator: "\n"))

        case "viewPR":
            guard let number = number(args) else { return bad("viewPR requires args.number") }
            let detail = try await provider.pullRequest(repo, number: number)
            let files = try await provider.files(repo, number: number)
            let commits = try await provider.pullRequestCommits(repo, number: number)
            let comments = try await provider.comments(repo, number: number)
            return ok(describe(detail, files: files, commits: commits, comments: comments))

        case "ciStatus":
            guard let number = number(args) else { return bad("ciStatus requires args.number") }
            let detail = try await provider.pullRequest(repo, number: number)
            let runs = try await provider.checks(repo, ref: detail.headBranch)
            guard !runs.isEmpty else { return ok("No check runs for \(detail.headBranch).") }
            return ok(
                runs.map { "\($0.name): \($0.status)\($0.conclusion.map { c in " (\(c))" } ?? "")" }
                    .joined(separator: "\n"))

        case "createPR":
            guard let title = nonEmpty(args["title"]) else { return bad("createPR requires args.title") }
            guard let head = nonEmpty(args["head"]) else { return bad("createPR requires args.head") }
            guard let base = nonEmpty(args["base"]) else { return bad("createPR requires args.base") }
            let number = try await provider.createPullRequest(
                repo, title: title, body: (args["body"] as? String) ?? "",
                head: head, base: base, draft: (args["draft"] as? Bool) ?? false)
            return ok("opened PR #\(number): \(title) (\(head) → \(base))")

        case "commentPR":
            guard let number = number(args) else { return bad("commentPR requires args.number") }
            guard let body = nonEmpty(args["body"]) else { return bad("commentPR requires args.body") }
            try await provider.addComment(repo, number: number, body: body)
            return ok("commented on #\(number)")

        case "reviewPR":
            guard let number = number(args) else { return bad("reviewPR requires args.number") }
            guard let raw = args["event"] as? String, let event = Self.reviewEvent(raw) else {
                return bad("reviewPR requires args.event — one of approve, requestChanges, comment")
            }
            try await provider.submitReview(
                repo, number: number, event: event,
                body: (args["body"] as? String) ?? "")
            return ok("submitted a \(raw) review on #\(number)")

        case "mergePR":
            guard let number = number(args) else { return bad("mergePR requires args.number") }
            let raw = (args["method"] as? String) ?? MergeMethod.merge.rawValue
            guard let method = MergeMethod(rawValue: raw) else {
                return bad("mergePR args.method must be merge, squash, or rebase")
            }
            try await provider.merge(repo, number: number, method: method)
            return ok("merged #\(number) (\(method.rawValue))")

        case "closePR":
            guard let number = number(args) else { return bad("closePR requires args.number") }
            try await provider.setPullRequestState(repo, number: number, state: .closed)
            return ok("closed #\(number)")

        default:
            return bad("pr_op: unsupported operation \"\(operation)\"")
        }
    }

    // MARK: - argument decoding

    /// JSON integers arrive as `NSNumber`; a string `"7"` is accepted too so a
    /// model that quotes the number does not get an unhelpful failure.
    private func number(_ args: [String: Any]) -> Int? {
        if let value = args["number"] as? Int { return value }
        if let text = args["number"] as? String { return Int(text) }
        return nil
    }

    private func nonEmpty(_ any: Any?) -> String? {
        guard let text = any as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    /// Accepts the model-facing spellings as well as the GitHub wire values.
    ///
    /// **This is the sink `GitMageMCPServer`'s `pr_review` guard resolves
    /// through.** The guard does not mirror this logic, it CALLS it, so the two
    /// cannot drift: any spelling added here that resolves to `.approve` is
    /// refused by the ungated tool automatically. `nonisolated` so
    /// `ArgumentValue.matches` can reach it. Keep it total and side-effect free.
    nonisolated static func reviewEvent(_ raw: String) -> ReviewEvent? {
        switch raw.lowercased() {
        case "approve", "approved": return .approve
        case "requestchanges", "request_changes": return .requestChanges
        case "comment": return .comment
        default: return nil
        }
    }

    // MARK: - rendering

    private func describe(
        _ detail: PullRequestDetail, files: [PRFile],
        commits: [PRCommit], comments: [ForgeComment]
    ) -> String {
        var lines = [
            "#\(detail.number) \(detail.title)",
            "\(detail.author) — \(detail.state)\(detail.isDraft ? " (draft)" : "") — \(detail.headBranch) → \(detail.baseBranch)",
            "mergeable: \(detail.mergeable.map(String.init) ?? "unknown") (\(detail.mergeableState)) — +\(detail.additions)/-\(detail.deletions)",
        ]
        if !detail.body.isEmpty { lines.append("\n\(detail.body)") }
        if !commits.isEmpty {
            lines.append("\ncommits:\n" + commits.map { "\($0.shortSHA) \($0.message)" }.joined(separator: "\n"))
        }
        if !files.isEmpty {
            lines.append("\nfiles:\n" + files.map { "\($0.status) \($0.filename)" }.joined(separator: "\n"))
        }
        if !comments.isEmpty {
            lines.append("\ncomments:\n" + comments.map { "\($0.author): \($0.body)" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    private func ok(_ text: String) -> AgentActionResult { AgentActionResult(text: text, isError: false) }
    private func bad(_ text: String) -> AgentActionResult { AgentActionResult(text: text, isError: true) }
}
