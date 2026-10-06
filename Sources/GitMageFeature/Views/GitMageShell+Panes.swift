import AinkradAppKit
import SwiftUI

extension GitMageShell {
    @ViewBuilder var contextPane: some View {
        switch model.selectedArea {
        case .changes: ChangesContextPane(model: model, tokens: tokens, accent: appearance.accent)
        case .history: HistoryContextPane(model: model, tokens: tokens)
        case .stashes: StashesContextPane(model: model, tokens: tokens)
        case .pullRequests:
            if let prModel {
                PullRequestsContextPane(model: prModel, tokens: tokens, hasGitHubRemote: prHasGitHubRemote)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .issues:
            if let issuesModel {
                IssuesContextPane(model: issuesModel, tokens: tokens, hasGitHubRemote: issuesHasGitHubRemote)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .worktrees:
            if let worktreesModel {
                WorktreesContextPane(model: worktreesModel, tokens: tokens)
            } else {
                selectRepoPlaceholder
            }
        case .advanced:
            if let advancedModel {
                AdvancedContextPane(model: advancedModel, tokens: tokens)
            } else {
                selectRepoPlaceholder
            }
        default: EmptyView()
        }
    }

    @ViewBuilder var detailPane: some View {
        switch model.selectedArea {
        case .changes: DiffView(diff: model.diffSnapshot, tokens: tokens, fontSize: appearance.diffFontSize)
        case .history:
            if let commitDiff = model.commitDiff {
                FileDiffList(
                    files: DiffFileSplitter.split(commitDiff.body), tokens: tokens,
                    fontSize: appearance.diffFontSize, fallbackTitle: commitDiff.title)
            } else {
                AinkradEmptyState(
                    icon: "clock.arrow.circlepath", title: "History",
                    message: "Select a commit to inspect its changed files.")
            }
        case .stashes:
            if let selectedStashDiff = model.selectedStashDiff {
                FileDiffList(
                    files: DiffFileSplitter.split(selectedStashDiff.body), tokens: tokens,
                    fontSize: appearance.diffFontSize, fallbackTitle: selectedStashDiff.title)
            } else {
                AinkradEmptyState(
                    icon: "tray.2",
                    title: "Stashes",
                    message: "Select a stash to preview its changed files."
                )
            }
        case .pullRequests:
            if let prModel {
                PullRequestDetailView(model: prModel, tokens: tokens, fontSize: appearance.diffFontSize)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .issues:
            if let issuesModel {
                IssueDetailView(model: issuesModel, tokens: tokens)
            } else {
                ComingSoonView(area: model.selectedArea, tokens: tokens)
            }
        case .worktrees:
            if let worktreesModel {
                WorktreeDetailView(model: worktreesModel, tokens: tokens, fontSize: appearance.diffFontSize)
            } else {
                selectRepoPlaceholder
            }
        case .advanced:
            if let advancedModel {
                AdvancedDetailView(model: advancedModel, tokens: tokens)
            } else {
                selectRepoPlaceholder
            }
        default: ComingSoonView(area: model.selectedArea, tokens: tokens)
        }
    }

    /// Shown while an area's model is still being built for the active repository.
    private var selectRepoPlaceholder: some View {
        AinkradEmptyState(
            icon: "rectangle.split.3x1", title: model.selectedArea.title, message: "Select a repository.")
    }
}
