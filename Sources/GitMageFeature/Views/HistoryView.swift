import AinkradAppKit
import SwiftUI

struct HistoryContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens

    /// "loaded / total" once the total is known, else just the loaded count.
    private var historyCountText: String {
        if let total = model.totalCommits { return "\(model.commits.count) / \(total)" }
        return "\(model.commits.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "HISTORY", count: model.commits.count,
                countText: historyCountText, tokens: tokens)

            if model.commits.isEmpty {
                AinkradEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No commits",
                    message: "This repository has no history yet."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.commits.enumerated()), id: \.element.id) { index, commit in
                            CommitRow(
                                commit: commit,
                                isSelected: model.selectedCommitID == commit.id,
                                isFirst: index == 0,
                                isLast: index == model.commits.count - 1 && !model.hasMoreCommits,
                                tokens: tokens,
                                onSelect: { model.selectCommit(commit) }
                            )
                            // Load the next page as the last row scrolls into view.
                            .onAppear {
                                if index == model.commits.count - 1 { model.loadMoreCommits() }
                            }
                        }

                        if model.isLoadingCommits { AinkradLoadingState() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

private struct CommitRow: View {
    @Environment(\.ainkradSkin) private var skin
    let commit: GitCommitSummary
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Git-graph rail: a continuous line with a node per commit.
            ZStack {
                Rectangle()
                    .fill(tokens.foreground.opacity(skin.opacity.o14))
                    .frame(width: 1)
                    .padding(.top, isFirst ? 14 : 0)
                    .padding(.bottom, isLast ? 14 : 0)
                Circle()
                    .fill(isSelected ? tokens.accentPrimary : tokens.accentSecondary.opacity(skin.opacity.o80))
                    .frame(width: 8, height: 8)
                    .shadow(color: isSelected ? tokens.accentPrimary.opacity(skin.opacity.o80) : .clear, radius: 4)
                    .overlay(
                        Circle().stroke(tokens.background, lineWidth: 2)
                            .frame(width: 8, height: 8)
                            .opacity(isSelected ? 0 : 1)
                    )
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(commit.summary)
                    .font(AinkradFont.display(skin.type.sizes.t12))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : skin.opacity.o90))
                    .lineLimit(1)
                GMCommitMeta(
                    sha: commit.shortSHA, author: commit.author, date: commit.relativeDate, tokens: tokens)
            }
            .padding(.vertical, 7)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 9)
        // The kit's row wash; the layout stays local (AinkradListRow is title + subtitle only).
        .ainkradRowBackground(isSelected: isSelected, isHovered: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
    }
}
