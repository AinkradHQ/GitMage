import AinkradAppKit
import SwiftUI

/// Context pane for the Advanced area: the commit list. Selecting a commit
/// drives the contextual actions (cherry-pick / revert / reset / tag) in the
/// detail pane — there is no per-action page.
struct AdvancedContextPane: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "COMMITS", count: model.commits.count, tokens: tokens) {
                if model.isLoading { AinkradSpinner(size: 16) }
            }

            if model.commits.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath", title: "No commits",
                    message: "This repository has no history yet.", tokens: tokens
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.commits) { commit in
                            AdvancedCommitRow(
                                commit: commit,
                                isSelected: model.selectedCommit == commit.id,
                                tokens: tokens,
                                onSelect: { model.selectedCommit = commit.id }
                            )
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
    }
}

/// A selectable commit row (git node dot + summary + sha·author·date).
struct AdvancedCommitRow: View {
    let commit: GitCommitSummary
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(isSelected ? tokens.accentPrimary : tokens.accentSecondary.opacity(0.6))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : 0.9))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(commit.shortSHA).font(AinkradFont.mono(9, weight: .medium)).foregroundStyle(
                        tokens.accentSecondary)
                    Text(commit.author).font(AinkradFont.display(9)).foregroundStyle(tokens.foreground.opacity(0.5))
                        .lineLimit(1)
                    Text(commit.relativeDate).font(AinkradFont.display(9)).foregroundStyle(
                        tokens.foreground.opacity(0.4))
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(
                    isSelected
                        ? tokens.accentPrimary.opacity(0.13)
                        : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear))
        )
        .overlay(alignment: .leading) {
            Capsule().fill(tokens.accentPrimary).frame(width: 3, height: 16)
                .shadow(color: tokens.accentPrimary.opacity(0.8), radius: 4)
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
