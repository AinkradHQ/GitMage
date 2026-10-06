import AinkradAppKit
import Foundation

final class GitHubProvider: GitForgeProvider {
    private let token: String
    private let session: URLSession
    private let base = URL(string: "https://api.github.com")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func verify() async throws -> ForgeUser {
        try await get("/user", as: GHUser.self).toModel()
    }
    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary] {
        try await get("/repos/\(repo.owner)/\(repo.name)/pulls?state=\(state.rawValue)&per_page=50", as: [GHPull].self)
            .map { $0.toSummary() }
    }
    func searchPullRequests(_ repo: RepoRef, state: PRState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<PullRequestSummary>
    {
        let env = try await searchIssuesRaw(
            repo, isPR: true, state: state.rawValue, query: query, labels: labels, page: page)
        return ForgePage(items: env.items.map { $0.toPRSummary() }, totalCount: env.totalCount)
    }
    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail {
        try await get("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)", as: GHPull.self).toDetail()
    }
    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile] {
        try await get("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/files?per_page=100", as: [GHFile].self).map {
            $0.toModel()
        }
    }
    func pullRequestCommits(_ repo: RepoRef, number: Int) async throws -> [PRCommit] {
        try await get("/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/commits?per_page=100", as: [GHPRCommit].self)
            .map { $0.toModel() }
    }
    func comments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] {
        try await get("/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments?per_page=50", as: [GHComment].self)
            .map { $0.toModel() }
    }
    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun] {
        try await get("/repos/\(repo.owner)/\(repo.name)/commits/\(ref)/check-runs", as: GHCheckRunsEnvelope.self)
            .checkRuns.map { $0.toModel() }
    }
    func addComment(_ repo: RepoRef, number: Int, body: String) async throws {
        try await send("POST", "/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments", json: ["body": body])
    }
    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws {
        try await send(
            "POST", "/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/reviews",
            json: ["event": event.rawValue, "body": body])
    }
    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws {
        try await send(
            "PUT", "/repos/\(repo.owner)/\(repo.name)/pulls/\(number)/merge", json: ["merge_method": method.rawValue])
    }
    func createPullRequest(
        _ repo: RepoRef, title: String, body: String,
        head: String, base: String, draft: Bool
    ) async throws -> Int {
        let created: GHPull = try await sendReturning(
            "POST", "/repos/\(repo.owner)/\(repo.name)/pulls",
            json: ["title": title, "body": body, "head": head, "base": base, "draft": draft])
        return created.number
    }
    func setPullRequestState(_ repo: RepoRef, number: Int, state: PRState) async throws {
        try await send(
            "PATCH", "/repos/\(repo.owner)/\(repo.name)/pulls/\(number)",
            json: ["state": state.rawValue])
    }

    // MARK: - Issues
    func listIssues(_ repo: RepoRef, state: IssueState) async throws -> [IssueSummary] {
        let items = try await get(
            "/repos/\(repo.owner)/\(repo.name)/issues?state=\(state.rawValue)&per_page=50", as: [GHIssue].self)
        return items.filter { !$0.isPullRequest }.map { $0.toSummary() }
    }
    func searchIssues(_ repo: RepoRef, state: IssueState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<IssueSummary>
    {
        let env = try await searchIssuesRaw(
            repo, isPR: false, state: state.rawValue, query: query, labels: labels, page: page)
        return ForgePage(items: env.items.map { $0.toSummary() }, totalCount: env.totalCount)
    }

    /// Shared `GET /search/issues` builder for both PRs and issues.
    static let searchPageSize = 30
    private static let searchQueryAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private func searchIssuesRaw(
        _ repo: RepoRef, isPR: Bool, state: String,
        query: String, labels: [String], page: Int
    ) async throws -> GHSearchEnvelope {
        var qualifiers = ["repo:\(repo.owner)/\(repo.name)", isPR ? "is:pr" : "is:issue"]
        if state == "open" || state == "closed" { qualifiers.append("state:\(state)") }
        for label in labels where !label.isEmpty { qualifiers.append("label:\"\(label)\"") }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { qualifiers.append(text) }

        let q = qualifiers.joined(separator: " ")
        let encoded = q.addingPercentEncoding(withAllowedCharacters: Self.searchQueryAllowed) ?? q
        let path =
            "/search/issues?q=\(encoded)&per_page=\(Self.searchPageSize)&page=\(max(1, page))&sort=created&order=desc"
        return try await get(path, as: GHSearchEnvelope.self)
    }
    func issue(_ repo: RepoRef, number: Int) async throws -> IssueDetail {
        try await get("/repos/\(repo.owner)/\(repo.name)/issues/\(number)", as: GHIssue.self).toDetail()
    }
    func issueComments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment] {
        try await get("/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments?per_page=100", as: [GHComment].self)
            .map { $0.toModel() }
    }
    func repoLabels(_ repo: RepoRef) async throws -> [IssueLabel] {
        try await get("/repos/\(repo.owner)/\(repo.name)/labels?per_page=100", as: [GHLabel].self).map { $0.toModel() }
    }
    func assignableUsers(_ repo: RepoRef) async throws -> [ForgeUser] {
        try await get("/repos/\(repo.owner)/\(repo.name)/assignees?per_page=100", as: [GHUser].self).map {
            $0.toModel()
        }
    }
    func createIssue(_ repo: RepoRef, title: String, body: String, labels: [String], assignees: [String]) async throws
        -> Int
    {
        let created: GHIssue = try await sendReturning(
            "POST", "/repos/\(repo.owner)/\(repo.name)/issues",
            json: ["title": title, "body": body, "labels": labels, "assignees": assignees])
        return created.number
    }
    func addIssueComment(_ repo: RepoRef, number: Int, body: String) async throws {
        try await send("POST", "/repos/\(repo.owner)/\(repo.name)/issues/\(number)/comments", json: ["body": body])
    }
    func setIssueState(_ repo: RepoRef, number: Int, state: IssueState) async throws {
        try await send("PATCH", "/repos/\(repo.owner)/\(repo.name)/issues/\(number)", json: ["state": state.rawValue])
    }
    func setLabels(_ repo: RepoRef, number: Int, labels: [String]) async throws {
        try await send("PATCH", "/repos/\(repo.owner)/\(repo.name)/issues/\(number)", json: ["labels": labels])
    }
    func setAssignees(_ repo: RepoRef, number: Int, assignees: [String]) async throws {
        try await send("PATCH", "/repos/\(repo.owner)/\(repo.name)/issues/\(number)", json: ["assignees": assignees])
    }

    // MARK: - Transport
    private func makeRequest(_ method: String, _ path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: base) else {
            throw ForgeError.invalidRequest("Invalid path: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return req
    }
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let (data, resp) = try await run(makeRequest("GET", path))
        try Self.check(resp, data)
        do { return try decoder().decode(T.self, from: data) } catch { throw ForgeError.decoding }
    }
    private func send(_ method: String, _ path: String, json: [String: Any]) async throws {
        var req = try makeRequest(method, path)
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await run(req)
        try Self.check(resp, data)
    }
    private func sendReturning<T: Decodable>(_ method: String, _ path: String, json: [String: Any]) async throws -> T {
        var req = try makeRequest(method, path)
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await run(req)
        try Self.check(resp, data)
        do { return try decoder().decode(T.self, from: data) } catch { throw ForgeError.decoding }
    }
    private func run(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: req) } catch { throw ForgeError.transport(error.localizedDescription) }
    }
    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw ForgeError.decoding }
        switch http.statusCode {
        case 200...299: return
        case 401: throw ForgeError.unauthorized
        case 403: throw ForgeError.forbidden(message(data) ?? "Forbidden (check token scope or rate limit).")
        case 404: throw ForgeError.notFound
        // 422 is GitHub's answer to the most common `createPullRequest`
        // failures — no commits between base and head, a PR that already
        // exists, an unknown base/head. Collapsing it to `.server(422)` left
        // the caller with a status code and no reason, whose only sensible
        // next move is to retry the identical call. The body carries the
        // reason, so it is extracted like the 403 branch above.
        case 422: throw ForgeError.invalidRequest(validationMessage(data) ?? "Rejected by GitHub (422).")
        default: throw ForgeError.server(http.statusCode)
        }
    }
    private static func message(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
    }
    /// The 422 reason. GitHub's top-level `message` is usually just
    /// "Validation Failed"; the actionable text lives in `errors[].message`
    /// (or, when it has none, the field/code pair), so both are joined.
    private static func validationMessage(_ data: Data) -> String? {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let top = root?["message"] as? String
        let details = (root?["errors"] as? [[String: Any]] ?? []).compactMap { entry -> String? in
            if let text = entry["message"] as? String, !text.isEmpty { return text }
            guard let field = entry["field"] as? String else { return entry["code"] as? String }
            return [field, entry["code"] as? String].compactMap { $0 }.joined(separator: ": ")
        }
        let parts = [top].compactMap { $0 } + details
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }
}
