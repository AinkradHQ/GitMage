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

    var body: some View {
        VStack(spacing: 0) {
            switch gate {
            case .needsGitHubRemote:
                gateMessage("Pull Requests need a GitHub `origin` remote.")
            case .needsToken:
                gateMessage("Add a GitHub token in Settings.")
            case .invalidToken(let message):
                gateMessage(message)
            case .ready:
                filterBar
                list
            }
        }
    }

    private enum Gate {
        case needsGitHubRemote
        case needsToken
        case invalidToken(String)
        case ready
    }

    private var gate: Gate {
        guard hasGitHubRemote else { return .needsGitHubRemote }
        switch model.authState {
        case .missingToken: return .needsToken
        case .invalid(let message): return .invalidToken(message)
        case .unknown, .valid: return .ready
        }
    }

    private func gateMessage(_ text: String) -> some View {
        EmptyStateView(icon: "arrow.triangle.pull", title: "Pull Requests", message: text, tokens: tokens)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countText: String {
        model.totalCount > 0 ? "\(model.pullRequests.count) / \(model.totalCount)" : "\(model.pullRequests.count)"
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            PaneHeader(title: "PULL REQUESTS", count: model.pullRequests.count, countText: countText, tokens: tokens)
            AinkradSegmentedPicker(
                items: [PRState.open, PRState.closed],
                selection: Binding(
                    get: { model.filter },
                    set: { newValue in
                        if model.filter != newValue {
                            model.filter = newValue
                            Task { await model.load() }
                        }
                    }
                ),
                label: { $0 == .open ? "Open" : "Closed" }
            )
            .padding(.horizontal, 12)
            AinkradSearchField(
                text: $model.searchText, placeholder: "Search pull requests…",
                onSubmit: { Task { await model.load() } }
            )
            .padding(.horizontal, 12)
            if !model.availableLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.availableLabels) { label in
                            AinkradSwatchChip(
                                label: label.name,
                                swatch: Color(hex: label.color),
                                isOn: model.selectedLabels.contains(label.name),
                                onTap: { model.toggleLabel(label.name) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var list: some View {
        if model.isLoading {
            AinkradSpinner(size: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            gateMessage(errorMessage)
        } else if model.pullRequests.isEmpty {
            EmptyStateView(
                icon: "arrow.triangle.pull", title: "No pull requests",
                message: "Nothing matches this filter.", tokens: tokens
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.pullRequests.enumerated()), id: \.element.id) { index, pr in
                        PullRequestRow(
                            pr: pr,
                            tokens: tokens,
                            isSelected: model.selectedPRNumber == pr.number,
                            onSelect: { Task { await model.select(pr.number) } }
                        )
                        .onAppear {
                            if index == model.pullRequests.count - 1 { Task { await model.loadMore() } }
                        }
                    }
                    if model.isLoadingMore {
                        HStack {
                            Spacer()
                            AinkradSpinner(size: 16)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
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
