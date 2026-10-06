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
                AinkradEmptyState(
                    icon: "clock.arrow.circlepath", title: "No commits",
                    message: "This repository has no history yet."
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
    @Environment(\.ainkradSkin) private var skin
    let commit: GitCommitSummary
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void

    var body: some View {
        AinkradListRow(
            isSelected: isSelected, onTap: onSelect,
            leading: {
                Image(systemName: "circle.fill")
                    .font(skin.font(AinkradFontToken(sizeKey: "t6")))
                    .foregroundStyle(isSelected ? tokens.accentPrimary : tokens.accentSecondary.opacity(skin.opacity.o60))
                    .frame(width: 12)
            },
            title: commit.summary,
            subtitle: GMCommitMeta.text(sha: commit.shortSHA, author: commit.author, date: commit.relativeDate),
            trailing: { EmptyView() }
        )
    }
}
