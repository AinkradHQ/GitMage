import AinkradAppKit
import SwiftUI

/// Detail pane for the Issues area: header, editable labels/assignees, body,
/// comments, and a composer with close/reopen.
struct IssueDetailView: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: IssuesViewModel
    let tokens: HostThemeTokens

    @State private var composerText = ""

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.detail {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: skin.spacing.md) {
                        header(detail)
                        editors(detail)
                        DiscussionCard(
                            author: detail.author, timestamp: detail.createdAt,
                            text: detail.body, isPrimary: true, tokens: tokens)
                        if !model.comments.isEmpty {
                            Text("\(model.comments.count) comment\(model.comments.count == 1 ? "" : "s")")
                                .font(AinkradFont.display(skin.type.sizes.t10, weight: .semibold)).kerning(1.5)
                                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
                                .padding(.top, skin.size.s2)
                        }
                        ForEach(model.comments) { comment in
                            DiscussionCard(
                                author: comment.author, timestamp: comment.createdAt,
                                text: comment.body, isPrimary: false, tokens: tokens)
                        }
                    }
                    .padding(skin.spacing.lg)
                }
                composer(detail)
            } else {
                AinkradEmptyState(
                    icon: "smallcircle.filled.circle", title: "No issue",
                    message: "Select an issue to read and respond to it."
                )
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
        VStack(alignment: .leading, spacing: skin.size.s5) {
            HStack(spacing: skin.spacing.sm) {
                Text(detail.title)
                    .font(AinkradFont.display(skin.type.sizes.t16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("#\(detail.number)")
                    .font(AinkradFont.mono(skin.type.sizes.t12))
                    .foregroundStyle(tokens.accentSecondary)
                Spacer()
                AinkradBadge(
                    text: detail.state.lowercased() == "open" ? "Open" : "Closed",
                    tint: GMColor.status(detail.state.lowercased() == "open" ? .open : .closedMerged, tokens))
            }
            Text("opened by \(detail.author) · \(ForgeDate.short(detail.createdAt))")
                .font(AinkradFont.mono(skin.type.sizes.t10))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
        }
    }

    private func editors(_ detail: IssueDetail) -> some View {
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            LabelsEditor(model: model, detail: detail)
            AssigneesEditor(model: model, detail: detail, tokens: tokens)
        }
    }

    private func composer(_ detail: IssueDetail) -> some View {
        GMCommentComposer(
            text: $composerText, isLoading: model.isLoading, tokens: tokens,
            comment: { await model.comment($0) }
        ) {
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
}

/// Editable labels control: a menu of repo labels with checkmarks on those
/// currently applied, rendering colored chips for the current selection.
private struct LabelsEditor: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: IssuesViewModel
    let detail: IssueDetail

    var body: some View {
        HStack(spacing: skin.size.s6) {
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
                    model.repoLabels.first { $0.name == name }.flatMap { Color(hex: $0.color) }  // design-lint: allow hex-color GitHub label data
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
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: IssuesViewModel
    let detail: IssueDetail
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: skin.size.s6) {
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
                HStack(spacing: skin.spacing.xs) {
                    ZStack {
                        Circle().fill(tokens.accentSecondary.opacity(skin.opacity.o20))
                        Text(String(login.prefix(1)).uppercased())
                            .font(AinkradFont.display(skin.type.sizes.t8, weight: .bold))
                            .foregroundStyle(tokens.accentSecondary)
                    }
                    .frame(width: skin.size.s15, height: skin.size.s15)
                    Text(login)
                        .font(AinkradFont.mono(skin.type.sizes.t10))
                        .foregroundStyle(tokens.foreground.opacity(skin.opacity.o75))
                }
                .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s2)
                .background(Capsule().fill(tokens.surfaceElevated.opacity(skin.opacity.o50)))
            }
        }
    }
}
