import Foundation

/// Drives the Pull Requests area of the UI: lists PRs for the active repo,
/// loads a selected PR's detail/files/comments/checks, and performs write
/// actions (comment/review/merge). Gated on having both a recognized repo
/// remote and a configured GitHub token.
@MainActor
final class PullRequestsViewModel: ObservableObject {
    @Published var pullRequests: [PullRequestSummary] = []
    @Published var selectedPRNumber: Int?
    @Published var detail: PullRequestDetail?
    @Published var files: [PRFile] = []
    @Published var commits: [PRCommit] = []
    @Published var comments: [ForgeComment] = []
    @Published var checks: [CheckRun] = []
    @Published var filter: PRState = .open
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var authState: ForgeAuthState = .unknown

    // Search + label filter + pagination.
    @Published var searchText = ""
    @Published var selectedLabels: Set<String> = []
    @Published var availableLabels: [IssueLabel] = []
    @Published var totalCount = 0
    @Published var hasMore = false
    private var page = 1

    private let repo: RepoRef?
    // SAFETY: immutable, only accessed on the main actor
    private nonisolated(unsafe) let provider: GitForgeProvider?
    private let auth: GitForgeAuth

    init(repo: RepoRef?, provider: GitForgeProvider?, auth: GitForgeAuth) {
        self.repo = repo
        self.provider = provider
        self.auth = auth
    }

    func verify() async {
        guard let token = auth.token(), !token.isEmpty else {
            authState = .missingToken
            return
        }
        guard let provider else {
            authState = .missingToken
            return
        }
        do {
            let user = try await provider.verify()
            authState = .valid(user.login)
        } catch let error as ForgeError {
            if error == .unauthorized {
                authState = .invalid(error.errorDescription ?? "Invalid token.")
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads (or reloads) the first page for the current filter/search/labels.
    func load() async {
        guard let repo, let provider else {
            pullRequests = []
            return
        }
        page = 1
        isLoading = true
        defer { isLoading = false }
        if availableLabels.isEmpty {
            availableLabels = (try? await provider.repoLabels(repo)) ?? []
        }
        do {
            let result = try await provider.searchPullRequests(
                repo, state: filter, query: searchText, labels: Array(selectedLabels), page: 1)
            pullRequests = result.items
            totalCount = result.totalCount
            hasMore = pullRequests.count < result.totalCount
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Appends the next page as the list scrolls to the bottom.
    func loadMore() async {
        guard let repo, let provider, hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        do {
            let result = try await provider.searchPullRequests(
                repo, state: filter, query: searchText, labels: Array(selectedLabels), page: next)
            page = next
            pullRequests.append(contentsOf: result.items)
            totalCount = result.totalCount
            hasMore = pullRequests.count < result.totalCount
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleLabel(_ name: String) {
        if selectedLabels.contains(name) { selectedLabels.remove(name) } else { selectedLabels.insert(name) }
        Task { await load() }
    }

    func select(_ number: Int) async {
        guard let repo, let provider else { return }
        selectedPRNumber = number
        do {
            let detail = try await provider.pullRequest(repo, number: number)
            self.detail = detail
            self.files = (try? await provider.files(repo, number: number)) ?? []
            self.commits = (try? await provider.pullRequestCommits(repo, number: number)) ?? []
            self.comments = (try? await provider.comments(repo, number: number)) ?? []
            self.checks = (try? await provider.checks(repo, ref: detail.headBranch)) ?? []
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func comment(_ body: String) async {
        guard let repo, let provider, let number = selectedPRNumber else { return }
        do {
            try await provider.addComment(repo, number: number, body: body)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func review(_ event: ReviewEvent, body: String) async {
        guard let repo, let provider, let number = selectedPRNumber else { return }
        do {
            try await provider.submitReview(repo, number: number, event: event, body: body)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func merge(_ method: MergeMethod) async {
        guard let repo, let provider, let number = selectedPRNumber else { return }
        do {
            try await provider.merge(repo, number: number, method: method)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleForgeError(_ error: ForgeError) {
        errorMessage = error.errorDescription
        if error == .unauthorized {
            authState = .invalid(error.errorDescription ?? "Invalid token.")
        }
    }
}
