import AinkradAppKit
import SwiftUI

/// Detail pane for the Pull Requests area: header + Conversation/Files switch.
struct PullRequestDetailView: View {
    @ObservedObject var model: PullRequestsViewModel
    let tokens: HostThemeTokens
    let fontSize: Double

    @State private var tab: Tab = .conversation
    @State private var composerText = ""
    /// Currently-shown merge method in the merge picker's trigger. Picking any
    /// row (even the same one) re-fires the merge, preserving the old action-
    /// menu behavior where every pick immediately merges with that method.
    @State private var mergeMethod: MergeMethod = .merge

    private enum Tab: String, CaseIterable {
        case conversation = "Conversation"
        case commits = "Commits"
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.detail {
                header(detail)
                AinkradSegmentedPicker(
                    items: Tab.allCases,
                    selection: $tab,
                    label: { "\($0.rawValue) \(tabCount($0))" }
                )
                .padding(.horizontal, 16).padding(.vertical, 10)

                switch tab {
                case .conversation:
                    conversation(detail)
                case .commits:
                    commitsTab
                case .files:
                    filesTab
                }
            } else {
                EmptyStateView(
                    icon: "arrow.triangle.pull", title: "No pull request",
                    message: "Select a pull request to see its conversation and files.", tokens: tokens
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(detail.title)
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("#\(detail.number)")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.accentSecondary)
                Spacer()
                if detail.isDraft {
                    StatusPill(text: "Draft", kind: .neutral, tokens: tokens)
                }
                StatusPill(
                    text: detail.state.capitalized,
                    kind: detail.state.lowercased() == "open" ? .open : .closedMerged, tokens: tokens)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10)).foregroundStyle(tokens.foreground.opacity(0.5))
                Text("\(detail.baseBranch) ← \(detail.headBranch)")
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
            }
            Text(statusSummary(detail))
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    private func statusSummary(_ detail: PullRequestDetail) -> String {
        let mergeability: String
        switch detail.mergeable {
        case true: mergeability = "Mergeable"
        case false: mergeability = "Not mergeable (\(detail.mergeableState))"
        case nil: mergeability = "Checking mergeability…"
        }
        let checksText =
            model.checks.isEmpty
            ? "no checks"
            : "\(model.checks.filter { $0.conclusion == "success" }.count)/\(model.checks.count) checks passing"
        return "\(mergeability) · \(checksText) · +\(detail.additions) −\(detail.deletions)"
    }

    // MARK: - Tabs

    private func tabCount(_ t: Tab) -> Int {
        switch t {
        case .conversation: return model.comments.count
        case .commits: return model.commits.count
        case .files: return model.files.count
        }
    }

    // MARK: - Conversation

    private func conversation(_ detail: PullRequestDetail) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DiscussionCard(
                        author: detail.author, timestamp: detail.createdAt,
                        text: detail.body, isPrimary: true, tokens: tokens)
                    ForEach(model.comments) { comment in
                        DiscussionCard(
                            author: comment.author, timestamp: comment.createdAt,
                            text: comment.body, isPrimary: false, tokens: tokens)
                    }
                }
                .padding(16)
            }
            composer
        }
    }

    // MARK: - Commits

    private var commitsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if model.commits.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath", title: "No commits",
                        message: "This pull request has no commits.", tokens: tokens
                    )
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(model.commits) { commit in
                        PRCommitRow(commit: commit, tokens: tokens)
                    }
                }
            }
            .padding(12)
        }
    }

    private var composer: some View {
        GMCommentComposer(
            text: $composerText, isLoading: model.isLoading, tokens: tokens,
            comment: { await model.comment($0) }
        ) {
            AinkradButton(title: "Approve", style: .secondary, icon: "checkmark.seal") {
                Task {
                    await model.review(.approve, body: composerText)
                    composerText = ""
                }
            }
            .disabled(model.isLoading)
            AinkradButton(title: "Request changes", style: .danger, icon: "exclamationmark.bubble") {
                Task {
                    await model.review(.requestChanges, body: composerText)
                    composerText = ""
                }
            }
            .disabled(model.isLoading)
            Spacer()
            mergeMenu
        }
    }

    private var mergeMenu: some View {
        let canMerge = !(model.isLoading || model.detail?.mergeable == false)
        return AinkradSelect(
            items: MergeMethod.allCases,
            selection: Binding(
                get: { mergeMethod },
                set: { method in
                    mergeMethod = method
                    Task { await model.merge(method) }
                }
            ),
            label: { $0.rawValue.capitalized }
        )
        .disabled(!canMerge)
    }

    // MARK: - Files

    private var filesTab: some View {
        FileDiffList(
            files: model.files.map {
                DiffFile(id: $0.filename, filename: $0.filename, status: $0.status, patch: $0.patch)
            },
            tokens: tokens,
            fontSize: fontSize
        )
    }
}

private struct PRCommitRow: View {
    let commit: PRCommit
    let tokens: HostThemeTokens

    var body: some View {
        AinkradListRow(
            leading: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.7))
                    .frame(width: 14)
            },
            title: commit.message,
            subtitle: GMCommitMeta.text(sha: commit.shortSHA, author: commit.author, date: ForgeDate.short(commit.date)),
            trailing: { EmptyView() }
        )
    }
}
