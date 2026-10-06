import AinkradAppKit
import SwiftUI

extension GitMageShell {
    struct PRTaskKey: Equatable {
        let area: NavArea
        let repoID: String?
    }

    struct IssuesTaskKey: Equatable {
        let area: NavArea
        let repoID: String?
    }

    struct WorktreesTaskKey: Equatable {
        let isActive: Bool
        let repoID: String?
    }

    struct AdvancedTaskKey: Equatable {
        let isActive: Bool
        let repoID: String?
    }

    /// What the Pull Requests and Issues models both start from: the repo's
    /// remote, whether it is on GitHub, and the stored token's provider.
    struct ForgeSetup {
        let remote: RepoRef?
        let hasGitHubRemote: Bool
        let auth: GitForgeAuth
        let provider: GitForgeProvider?

        /// A remote and a token are both there, so listing can start.
        var canLoad: Bool { remote != nil && provider != nil }
    }

    func makeForgeSetup() async -> ForgeSetup {
        let remote = await model.currentRemote()
        let auth = GitForgeAuth(secrets: host.secrets)
        return ForgeSetup(
            remote: remote,
            hasGitHubRemote: remote?.host.lowercased().contains("github.com") == true,
            auth: auth,
            provider: auth.token().map { GitHubProvider(token: $0) })
    }

    func buildPRModelIfNeeded() async {
        guard model.selectedArea == .pullRequests else { return }
        let setup = await makeForgeSetup()
        prHasGitHubRemote = setup.hasGitHubRemote
        let newModel = PullRequestsViewModel(repo: setup.remote, provider: setup.provider, auth: setup.auth)
        prModel = newModel
        await newModel.verify()
        if setup.canLoad {
            await newModel.load()
        }
    }

    func buildIssuesModelIfNeeded() async {
        guard model.selectedArea == .issues else { return }
        let setup = await makeForgeSetup()
        issuesHasGitHubRemote = setup.hasGitHubRemote
        let newModel = IssuesViewModel(repo: setup.remote, provider: setup.provider, auth: setup.auth)
        issuesModel = newModel
        await newModel.verify()
        if setup.canLoad {
            await newModel.load()
        }
    }

    func buildWorktreesModelIfNeeded() async {
        guard model.selectedArea == .worktrees, model.hasActiveRepo else { return }
        let newModel = WorktreesViewModel(
            client: GitRepositoryClient(),
            repositoryPath: model.repositoryPath,
            currentRoot: model.snapshot?.rootPath ?? "",
            branches: model.branches,
            onOpen: { path in model.openRepositoryPath(path) }
        )
        worktreesModel = newModel
        await newModel.load()
    }

    func buildAdvancedModelIfNeeded() async {
        guard model.selectedArea == .advanced, model.hasActiveRepo else { return }
        let newModel = AdvancedViewModel(
            client: GitRepositoryClient(),
            repositoryPath: model.repositoryPath,
            branches: model.branches,
            onChanged: { Task { @MainActor in model.refresh() } }
        )
        advancedModel = newModel
        await newModel.load()
    }
}
