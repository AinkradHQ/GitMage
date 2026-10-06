import AinkradAppKit
import Foundation

/// Errors surfaced by a `GitForgeProvider` implementation, mapped from
/// transport failures and non-2xx HTTP responses.
enum ForgeError: Error, LocalizedError, Equatable {
    case unauthorized
    case forbidden(String)
    case notFound
    /// A 422 the forge rejected on its merits — "No commits between base and
    /// head", "A pull request already exists for …", an invalid base/head. The
    /// reason is carried verbatim because it is the only thing that tells the
    /// caller (or the assistant driving `pr_create`) to change the request
    /// rather than retry the identical one.
    case invalidRequest(String)
    case server(Int)
    case decoding
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Invalid or missing GitHub token."
        case .forbidden(let message): return message
        case .notFound: return "Not found."
        case .invalidRequest(let message): return message
        case .server(let code): return "GitHub server error (\(code))."
        case .decoding: return "Unexpected response from GitHub."
        case .transport(let message): return message
        }
    }
}

/// A forge (e.g. GitHub) pull-request backend. Implementations map their
/// wire format to the plain models in `ForgeModels.swift`.
protocol GitForgeProvider {
    func verify() async throws -> ForgeUser
    func listPullRequests(_ repo: RepoRef, state: PRState) async throws -> [PullRequestSummary]
    /// Paginated PR search (text + labels) via the forge search API.
    func searchPullRequests(_ repo: RepoRef, state: PRState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<PullRequestSummary>
    func pullRequest(_ repo: RepoRef, number: Int) async throws -> PullRequestDetail
    func files(_ repo: RepoRef, number: Int) async throws -> [PRFile]
    func pullRequestCommits(_ repo: RepoRef, number: Int) async throws -> [PRCommit]
    func comments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment]
    func checks(_ repo: RepoRef, ref: String) async throws -> [CheckRun]
    func addComment(_ repo: RepoRef, number: Int, body: String) async throws
    func submitReview(_ repo: RepoRef, number: Int, event: ReviewEvent, body: String) async throws
    func merge(_ repo: RepoRef, number: Int, method: MergeMethod) async throws
    /// Opens a pull request and returns its number.
    func createPullRequest(
        _ repo: RepoRef, title: String, body: String,
        head: String, base: String, draft: Bool
    ) async throws -> Int
    /// Reopens or closes an existing pull request. `.all` is not a settable state.
    func setPullRequestState(_ repo: RepoRef, number: Int, state: PRState) async throws

    func listIssues(_ repo: RepoRef, state: IssueState) async throws -> [IssueSummary]
    /// Paginated issue search (text + labels) via the forge search API.
    func searchIssues(_ repo: RepoRef, state: IssueState, query: String, labels: [String], page: Int) async throws
        -> ForgePage<IssueSummary>
    func issue(_ repo: RepoRef, number: Int) async throws -> IssueDetail
    func issueComments(_ repo: RepoRef, number: Int) async throws -> [ForgeComment]
    func repoLabels(_ repo: RepoRef) async throws -> [IssueLabel]
    func assignableUsers(_ repo: RepoRef) async throws -> [ForgeUser]
    func createIssue(_ repo: RepoRef, title: String, body: String, labels: [String], assignees: [String]) async throws
        -> Int
    func addIssueComment(_ repo: RepoRef, number: Int, body: String) async throws
    func setIssueState(_ repo: RepoRef, number: Int, state: IssueState) async throws
    func setLabels(_ repo: RepoRef, number: Int, labels: [String]) async throws
    func setAssignees(_ repo: RepoRef, number: Int, assignees: [String]) async throws
}

/// Wraps the host's `PluginSecretStore` to read/write the GitHub token.
/// Never logs or persists the token outside the secret store.
struct GitForgeAuth {
    static let key = "github-token"

    private let secrets: PluginSecretStore

    init(secrets: PluginSecretStore) {
        self.secrets = secrets
    }

    func token() -> String? {
        secrets.secret(forKey: Self.key)
    }

    func setToken(_ value: String?) {
        let normalized = (value?.isEmpty ?? true) ? nil : value
        secrets.setSecret(normalized, forKey: Self.key)
    }

    func clear() {
        secrets.setSecret(nil, forKey: Self.key)
    }
}
