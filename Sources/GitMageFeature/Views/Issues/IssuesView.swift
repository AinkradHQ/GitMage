import AinkradAppKit
import SwiftUI

/// Context pane (left rail) for the Issues area: filter + issue list + New
/// Issue entry point, gated on having a GitHub remote and a valid token.
struct IssuesContextPane: View {
    @ObservedObject var model: IssuesViewModel
    let tokens: HostThemeTokens
    /// Whether the active repo resolved a GitHub `origin` remote. Passed in
    /// from the shell, since the view model does not expose its `repo`.
    let hasGitHubRemote: Bool

    private var gate: ForgeGate { ForgeGate(hasGitHubRemote: hasGitHubRemote, authState: model.authState) }

    var body: some View {
        VStack(spacing: 0) {
            if let message = gate.message(area: "Issues") {
                ForgeMessage(icon: "smallcircle.filled.circle", title: "Issues", message: message, tokens: tokens)
            } else {
                ForgeFilterToolbar(
                    title: "ISSUES", loaded: model.issues.count, total: model.totalCount, tokens: tokens,
                    filters: [IssueState.open, IssueState.closed], filter: $model.filter,
                    filterLabel: { $0 == .open ? "Open" : "Closed" }, searchText: $model.searchText,
                    searchPlaceholder: "Search issues…", labels: model.repoLabels,
                    selectedLabels: model.selectedLabels, toggleLabel: { model.toggleLabel($0) },
                    load: { Task { await model.load() } }
                ) {
                    AinkradIconButton(systemName: "plus", size: 22, tooltip: "New issue") { model.showNew = true }
                }
                ForgeItemList(
                    items: model.issues, isLoading: model.isLoading, isLoadingMore: model.isLoadingMore,
                    errorMessage: model.errorMessage, icon: "smallcircle.filled.circle", areaTitle: "Issues",
                    emptyTitle: "No issues", tokens: tokens,
                    loadMore: { Task { await model.loadMore() } }
                ) { issue in
                    IssueRow(
                        issue: issue,
                        tokens: tokens,
                        isSelected: model.selectedNumber == issue.number,
                        onSelect: { Task { await model.select(issue.number) } }
                    )
                }
            }
        }
        .ainkradModal(isPresented: $model.showNew) {
            NewIssueSheet(model: model, tokens: tokens)
        }
    }
}

private struct IssueRow: View {
    let issue: IssueSummary
    let tokens: HostThemeTokens
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    private var isOpen: Bool { issue.state.lowercased() == "open" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isOpen ? "smallcircle.filled.circle" : "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(isOpen ? GMColor.status(.open, tokens) : GMColor.status(.closedMerged, tokens))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : 0.9))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("#\(issue.number)")
                        .font(AinkradFont.mono(9, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary)
                    Text(issue.author)
                        .font(AinkradFont.mono(9))
                        .foregroundStyle(tokens.foreground.opacity(0.5)).lineLimit(1)
                    if issue.commentCount > 0 {
                        Label("\(issue.commentCount)", systemImage: "bubble.left")
                            .font(AinkradFont.mono(9))
                            .foregroundStyle(tokens.foreground.opacity(0.45))
                    }
                }
                if !issue.labelNames.isEmpty {
                    LabelChipsRow(names: issue.labelNames, tokens: tokens)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        // The kit's row wash; the layout stays local (AinkradListRow is title + subtitle only).
        .ainkradRowBackground(isSelected: isSelected, isHovered: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
    }
}

/// Small row of neutral label chips, used where only label names (not colors)
/// are available (e.g. issue list rows).
struct LabelChipsRow: View {
    let names: [String]
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 4) {
            ForEach(names, id: \.self) { name in
                AinkradChip(label: name)
            }
        }
    }
}

/// Colored label chip, used where a hex color is available (e.g. issue
/// detail's editable labels control).
struct ColoredLabelChip: View {
    let label: IssueLabel

    var body: some View {
        AinkradSwatchChip(label: label.name, swatch: Color(hex: label.color))  // design-lint: allow hex-color GitHub label data
    }
}
