import AinkradAppKit
import SwiftUI

/// Context pane (left rail) for the Pull Requests area: filter + PR list,
/// gated on having a GitHub remote and a valid token.
struct PullRequestsContextPane: View {
    @ObservedObject var model: PullRequestsViewModel
    let tokens: HostThemeTokens
    /// Whether the active repo resolved a GitHub `origin` remote. Passed in
    /// from the shell, since the view model does not expose its `repo`.
    let hasGitHubRemote: Bool

    private var gate: ForgeGate { ForgeGate(hasGitHubRemote: hasGitHubRemote, authState: model.authState) }

    var body: some View {
        VStack(spacing: 0) {
            if let message = gate.message(area: "Pull Requests") {
                ForgeMessage(icon: "arrow.triangle.pull", title: "Pull Requests", message: message, tokens: tokens)
            } else {
                ForgeFilterToolbar(
                    title: "PULL REQUESTS", loaded: model.pullRequests.count, total: model.totalCount,
                    tokens: tokens, filters: [PRState.open, PRState.closed], filter: $model.filter,
                    filterLabel: { $0 == .open ? "Open" : "Closed" }, searchText: $model.searchText,
                    searchPlaceholder: "Search pull requests…", labels: model.availableLabels,
                    selectedLabels: model.selectedLabels, toggleLabel: { model.toggleLabel($0) },
                    load: { Task { await model.load() } })
                ForgeItemList(
                    items: model.pullRequests, isLoading: model.isLoading, isLoadingMore: model.isLoadingMore,
                    errorMessage: model.errorMessage, icon: "arrow.triangle.pull", areaTitle: "Pull Requests",
                    emptyTitle: "No pull requests", tokens: tokens,
                    loadMore: { Task { await model.loadMore() } }
                ) { pr in
                    PullRequestRow(
                        pr: pr,
                        tokens: tokens,
                        isSelected: model.selectedPRNumber == pr.number,
                        onSelect: { Task { await model.select(pr.number) } }
                    )
                }
            }
        }
    }
}

private struct PullRequestRow: View {
    let pr: PullRequestSummary
    let tokens: HostThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    private var isOpen: Bool { pr.state.lowercased() == "open" }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 12))
                .foregroundStyle(isOpen ? GMColor.status(.open, tokens) : GMColor.status(.closedMerged, tokens))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(pr.title)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : 0.9))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("#\(pr.number)")
                        .font(AinkradFont.mono(9, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary)
                    Text(pr.author)
                        .font(AinkradFont.mono(9))
                        .foregroundStyle(tokens.foreground.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if pr.isDraft {
                StatusPill(text: "Draft", kind: .neutral, tokens: tokens)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .gmListRowChrome(tokens: tokens, isSelected: isSelected, hovering: $hovering)
        .onTapGesture(perform: onSelect)
    }
}
