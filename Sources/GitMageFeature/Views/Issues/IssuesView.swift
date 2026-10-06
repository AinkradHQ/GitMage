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

    var body: some View {
        VStack(spacing: 0) {
            switch gate {
            case .needsGitHubRemote:
                gateMessage("Issues need a GitHub `origin` remote.")
            case .needsToken:
                gateMessage("Add a GitHub token in Settings.")
            case .invalidToken(let message):
                gateMessage(message)
            case .ready:
                toolbar
                list
            }
        }
        .ainkradModal(isPresented: $model.showNew) {
            NewIssueSheet(model: model, tokens: tokens)
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
        EmptyStateView(icon: "smallcircle.filled.circle", title: "Issues", message: text, tokens: tokens)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countText: String {
        model.totalCount > 0 ? "\(model.issues.count) / \(model.totalCount)" : "\(model.issues.count)"
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            PaneHeader(title: "ISSUES", count: model.issues.count, countText: countText, tokens: tokens) {
                AinkradIconButton(systemName: "plus", size: 22, tooltip: "New issue") { model.showNew = true }
            }
            AinkradSegmentedPicker(
                items: [IssueState.open, IssueState.closed],
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
                text: $model.searchText, placeholder: "Search issues…",
                onSubmit: { Task { await model.load() } }
            )
            .padding(.horizontal, 12)
            if !model.repoLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.repoLabels) { label in
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
        } else if model.issues.isEmpty {
            EmptyStateView(
                icon: "smallcircle.filled.circle", title: "No issues",
                message: "Nothing matches this filter.", tokens: tokens
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.issues.enumerated()), id: \.element.id) { index, issue in
                        IssueRow(
                            issue: issue,
                            tokens: tokens,
                            isSelected: model.selectedNumber == issue.number,
                            onSelect: { Task { await model.select(issue.number) } }
                        )
                        .onAppear {
                            if index == model.issues.count - 1 { Task { await model.loadMore() } }
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
        .gmListRowChrome(tokens: tokens, isSelected: isSelected, hovering: $hovering)
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
                Text(name)
                    .font(AinkradFont.display(9, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.7))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(tokens.surfaceElevated.opacity(0.7), in: ChamferShape(cut: AinkradRadius.sm))
            }
        }
    }
}

/// Colored label chip, used where a hex color is available (e.g. issue
/// detail's editable labels control).
struct ColoredLabelChip: View {
    let label: IssueLabel

    var body: some View {
        Text(label.name)
            .font(AinkradFont.display(9, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(hex: label.color).opacity(0.85), in: ChamferShape(cut: AinkradRadius.sm))
    }
}
