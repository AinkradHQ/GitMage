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

    func buildPRModelIfNeeded() async {
        guard model.selectedArea == .pullRequests else { return }
        let remote = await model.currentRemote()
        prHasGitHubRemote = remote?.host.lowercased().contains("github.com") == true
        let auth = GitForgeAuth(secrets: host.secrets)
        let token = auth.token()
        let provider: GitForgeProvider? = token.map { GitHubProvider(token: $0) }
        let newModel = PullRequestsViewModel(repo: remote, provider: provider, auth: auth)
        prModel = newModel
        await newModel.verify()
        if remote != nil && token != nil {
            await newModel.load()
        }
    }

    func buildIssuesModelIfNeeded() async {
        guard model.selectedArea == .issues else { return }
        let remote = await model.currentRemote()
        issuesHasGitHubRemote = remote?.host.lowercased().contains("github.com") == true
        let auth = GitForgeAuth(secrets: host.secrets)
        let token = auth.token()
        let provider: GitForgeProvider? = token.map { GitHubProvider(token: $0) }
        let newModel = IssuesViewModel(repo: remote, provider: provider, auth: auth)
        issuesModel = newModel
        await newModel.verify()
        if remote != nil && token != nil {
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
