import SwiftUI
import AinkradAppKit

/// Detail pane for the Issues area: header, editable labels/assignees, body,
/// comments, and a composer with close/reopen.
struct IssueDetailView: View {
    @ObservedObject var model: IssuesViewModel
    let tokens: HostThemeTokens

    @State private var composerText = ""

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.detail {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        header(detail)
                        editors(detail)
                        DiscussionCard(author: detail.author, timestamp: detail.createdAt,
                                       text: detail.body, isPrimary: true, tokens: tokens)
                        if !model.comments.isEmpty {
                            Text("\(model.comments.count) comment\(model.comments.count == 1 ? "" : "s")")
                                .font(AinkradFont.display(10, weight: .semibold)).kerning(1.5)
                                .foregroundStyle(tokens.foreground.opacity(0.45))
                                .padding(.top, 2)
                        }
                        ForEach(model.comments) { comment in
                            DiscussionCard(author: comment.author, timestamp: comment.createdAt,
                                           text: comment.body, isPrimary: false, tokens: tokens)
                        }
                    }
                    .padding(16)
                }
                composer(detail)
            } else {
                EmptyStateView(icon: "smallcircle.filled.circle", title: "No issue",
                               message: "Select an issue to read and respond to it.", tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The "New Issue" modal is hosted once at the Issues area root
        // (`IssuesContextPane`), which shares this `IssuesViewModel`. Any
        // `model.showNew = true` (the context pane's "+" button, or the view
        // model itself) triggers that single modal — no duplicate here.
    }

    private func header(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(detail.title)
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("#\(detail.number)")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.accentSecondary)
                Spacer()
                StatusPill(text: detail.state.lowercased() == "open" ? "Open" : "Closed",
                           kind: detail.state.lowercased() == "open" ? .open : .closedMerged, tokens: tokens)
            }
            Text("opened by \(detail.author) · \(ForgeDate.short(detail.createdAt))")
                .font(AinkradFont.mono(10))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
    }

    private func editors(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelsEditor(model: model, detail: detail, tokens: tokens)
            AssigneesEditor(model: model, detail: detail, tokens: tokens)
        }
    }

    private func composer(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowRule(tokens: tokens)
            AinkradTextArea(text: $composerText, placeholder: "Leave a comment…", minHeight: 34, maxHeight: 80,
                            onSubmit: {
                                guard !model.isLoading,
                                      !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                Task { await model.comment(composerText); composerText = "" }
                            })
            HStack(spacing: 8) {
                AinkradButton(title: "Comment", style: .secondary, icon: "text.bubble") {
                    Task { await model.comment(composerText); composerText = "" }
                }
                .disabled(model.isLoading)
                Spacer()
                if detail.state.lowercased() == "open" {
                    AinkradButton(title: "Close", style: .danger, icon: "xmark.circle") {
                        Task { await model.toggleState() }
                    }
                    .disabled(model.isLoading)
                } else {
                    AinkradButton(title: "Reopen", style: .primary, icon: "arrow.counterclockwise") {
                        Task { await model.toggleState() }
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .padding(16)
    }
}

/// Editable labels control: a menu of repo labels with checkmarks on those
/// currently applied, rendering colored chips for the current selection.
private struct LabelsEditor: View {
    @ObservedObject var model: IssuesViewModel
    let detail: IssueDetail
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 6) {
            AinkradMultiSelect(
                items: model.repoLabels.map(\.name),
                selection: Binding(
                    // The applied-label set is derived from `detail.labels`;
                    // writing back diffs into the async `setLabels` side effect.
                    get: { Set(detail.labels.map(\.name)) },
                    set: { names in Task { await model.setLabels(names) } }
                ),
                label: { $0 },
                swatch: { name in
                    model.repoLabels.first { $0.name == name }.map { Color(hex: $0.color) }
                }
            )

            ForEach(detail.labels) { label in
                ColoredLabelChip(label: label)
            }
        }
    }
}

/// Editable assignees control: a menu of assignable users with checkmarks on
/// those currently assigned.
private struct AssigneesEditor: View {
    @ObservedObject var model: IssuesViewModel
    let detail: IssueDetail
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 6) {
            AinkradMultiSelect(
                items: model.assignableUsers.map(\.login),
                selection: Binding(
                    // Derived from `detail.assignees`; write-back diffs into the
                    // async `setAssignees` side effect.
                    get: { Set(detail.assignees) },
                    set: { logins in Task { await model.setAssignees(logins) } }
                ),
                label: { $0 }
            )

            ForEach(detail.assignees, id: \.self) { login in
                HStack(spacing: 4) {
                    ZStack {
                        Circle().fill(tokens.accentSecondary.opacity(0.2))
                        Text(String(login.prefix(1)).uppercased())
                            .font(AinkradFont.display(8, weight: .bold))
                            .foregroundStyle(tokens.accentSecondary)
                    }
                    .frame(width: 15, height: 15)
                    Text(login)
                        .font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.75))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(tokens.surfaceElevated.opacity(0.5)))
            }
        }
    }
}
