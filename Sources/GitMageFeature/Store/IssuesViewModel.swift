import Foundation

/// Drives the Issues area of the UI: lists issues for the active repo, loads
/// a selected issue's detail/comments, and performs write actions
/// (create/comment/state/labels/assignees). Gated on having both a recognized
/// repo remote and a configured GitHub token.
@MainActor
final class IssuesViewModel: ObservableObject {
    @Published var issues: [IssueSummary] = []
    @Published var selectedNumber: Int?
    @Published var detail: IssueDetail?
    @Published var comments: [ForgeComment] = []
    @Published var repoLabels: [IssueLabel] = []
    @Published var assignableUsers: [ForgeUser] = []
    @Published var filter: IssueState = .open
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var authState: ForgeAuthState = .unknown

    // Search + label filter + pagination.
    @Published var searchText = ""
    @Published var selectedLabels: Set<String> = []
    @Published var totalCount = 0
    @Published var hasMore = false
    private var page = 1

    @Published var showNew = false
    @Published var newTitle = ""
    @Published var newBody = ""
    @Published var newLabels: Set<String> = []
    @Published var newAssignees: Set<String> = []

    private let repo: RepoRef?
    // SAFETY: `provider` is a `let` set once in `init` and never mutated;
    // all access happens on the main actor via this @MainActor class's
    // isolated methods, so concurrent mutation cannot occur.
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
            issues = []
            return
        }
        page = 1
        isLoading = true
        defer { isLoading = false }
        if repoLabels.isEmpty {
            repoLabels = (try? await provider.repoLabels(repo)) ?? []
        }
        if assignableUsers.isEmpty {
            assignableUsers = (try? await provider.assignableUsers(repo)) ?? []
        }
        do {
            let result = try await provider.searchIssues(
                repo, state: filter, query: searchText, labels: Array(selectedLabels), page: 1)
            issues = result.items
            totalCount = result.totalCount
            hasMore = issues.count < result.totalCount
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
            let result = try await provider.searchIssues(
                repo, state: filter, query: searchText, labels: Array(selectedLabels), page: next)
            page = next
            issues.append(contentsOf: result.items)
            totalCount = result.totalCount
            hasMore = issues.count < result.totalCount
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
        selectedNumber = number
        do {
            let detail = try await provider.issue(repo, number: number)
            self.detail = detail
            self.comments = (try? await provider.issueComments(repo, number: number)) ?? []
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func comment(_ body: String) async {
        guard let repo, let provider, let number = selectedNumber else { return }
        do {
            try await provider.addIssueComment(repo, number: number, body: body)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create() async {
        guard let repo, let provider else { return }
        do {
            _ = try await provider.createIssue(
                repo,
                title: newTitle,
                body: newBody,
                labels: Array(newLabels),
                assignees: Array(newAssignees)
            )
            showNew = false
            newTitle = ""
            newBody = ""
            newLabels = []
            newAssignees = []
            await load()
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleState() async {
        guard let repo, let provider, let number = selectedNumber, let detail else { return }
        let newState: IssueState = detail.state == "open" ? .closed : .open
        do {
            try await provider.setIssueState(repo, number: number, state: newState)
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLabels(_ labels: Set<String>) async {
        guard let repo, let provider, let number = selectedNumber else { return }
        do {
            try await provider.setLabels(repo, number: number, labels: Array(labels))
            await select(number)
        } catch let error as ForgeError {
            handleForgeError(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAssignees(_ assignees: Set<String>) async {
        guard let repo, let provider, let number = selectedNumber else { return }
        do {
            try await provider.setAssignees(repo, number: number, assignees: Array(assignees))
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
