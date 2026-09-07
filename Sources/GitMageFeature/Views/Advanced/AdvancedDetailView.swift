import SwiftUI
import AinkradAppKit

/// Detail pane for the Advanced area: one page of contextual actions — the
/// selected commit's ops (cherry-pick / revert / reset / tag-target), a rebase
/// card, and a tags card. No per-action page.
struct AdvancedDetailView: View {
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    private var selectedCommit: GitCommitSummary? {
        guard let sha = model.selectedCommit else { return nil }
        return model.commits.first { $0.id == sha }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.operationState.isActive { inProgressBanner }
                if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage, tokens: tokens)
                }
                AutostashToggle(isOn: $model.autostash, tokens: tokens)
                commitActionsCard
                rebaseCard
                tagsCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Kit confirm dialog for destructive Advanced ops (rebase / hard reset).
        // Bound to `pendingConfirm != nil`. Confirm CAPTURES and consumes the
        // pending action synchronously, then dispatches its `perform` — the
        // dialog's own dismiss (which fires right after confirm) niling
        // `pendingConfirm` therefore cannot race the destructive op away.
        .ainkradConfirmDialog(
            isPresented: Binding(
                get: { model.pendingConfirm != nil },
                set: { presented in if !presented { model.cancelPending() } }
            ),
            title: model.pendingConfirm?.title ?? "",
            message: model.pendingConfirm?.message ?? "",
            confirmTitle: "Confirm",
            isDestructive: true,
            onConfirm: {
                guard let action = model.pendingConfirm else { return }
                model.cancelPending()
                Task { await action.perform() }
            }
        )
    }

    // MARK: - In-progress banner

    private var inProgressBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(tokens.accentTertiary)
                Text(model.operationState.label)
                    .font(AinkradFont.display(12, weight: .semibold))
            }
            Text("Resolve conflicts in Changes, then Continue.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.6))
            HStack(spacing: 8) {
                AinkradButton(title: "Continue", style: .primary) { Task { await model.continueOperation() } }
                    .disabled(model.isLoading)
                AinkradButton(title: "Abort", style: .danger) { Task { await model.abortOperation() } }
                    .disabled(model.isLoading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.accentTertiary.opacity(0.08)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentTertiary.opacity(0.35)))
    }

    // MARK: - Commit actions

    private var commitActionsCard: some View {
        card("SELECTED COMMIT") {
            if let commit = selectedCommit {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(commit.summary)
                            .font(AinkradFont.display(13, weight: .medium))
                            .foregroundStyle(tokens.foreground)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(commit.shortSHA).font(AinkradFont.mono(10, weight: .medium)).foregroundStyle(tokens.accentSecondary)
                            Text(commit.author).font(AinkradFont.display(10)).foregroundStyle(tokens.foreground.opacity(0.5))
                            Text(commit.relativeDate).font(AinkradFont.display(10)).foregroundStyle(tokens.foreground.opacity(0.4))
                        }
                    }

                    HStack(spacing: 8) {
                        AinkradButton(title: "Cherry-pick", style: .secondary, icon: "arrow.right.circle") {
                            Task { await model.cherryPick() }
                        }.disabled(model.isLoading)
                        AinkradButton(title: "Revert", style: .secondary, icon: "arrow.uturn.backward") {
                            Task { await model.revert() }
                        }.disabled(model.isLoading)
                        Spacer()
                    }

                    // Reset row
                    HStack(spacing: 8) {
                        AinkradSegmentedPicker(
                            items: ResetMode.allCases,
                            selection: $model.resetMode,
                            label: { $0.rawValue.capitalized }
                        )
                        .frame(maxWidth: 240)
                        AinkradButton(title: "Reset to here", style: .danger, icon: "arrow.counterclockwise") {
                            model.requestReset()
                        }.disabled(model.isLoading)
                        Spacer()
                    }
                }
            } else {
                Text("Select a commit from the list to cherry-pick, revert, reset, or tag it.")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
    }

    // MARK: - Rebase

    private var rebaseCard: some View {
        card("REBASE") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Rebase \(model.currentBranchName) onto")
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    AinkradSelect(
                        items: model.branchNames,
                        selection: Binding(
                            get: { model.rebaseBase ?? "" },
                            set: { model.rebaseBase = $0 }
                        ),
                        label: { $0.isEmpty ? "Choose a branch" : $0 }
                    )
                    .frame(width: 180)
                }
                AinkradButton(title: "Rebase", style: .primary, icon: "arrow.triangle.merge") {
                    model.requestRebase()
                }
                .disabled(model.isLoading || model.rebaseBase == nil || model.rebaseBase?.isEmpty == true)
            }
        }
    }

    // MARK: - Tags

    private var tagTarget: String {
        if let commit = selectedCommit { return commit.shortSHA }
        return "HEAD (\(model.currentBranchName))"
    }

    private var tagsCard: some View {
        card("TAGS") {
            VStack(alignment: .leading, spacing: 10) {
                if model.tags.isEmpty {
                    Text("No tags yet.")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(model.tags) { tag in
                                TagRow(tag: tag, tokens: tokens) { Task { await model.deleteTag(tag.name) } }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                Text("NEW TAG AT \(tagTarget)")
                    .font(AinkradFont.display(9, weight: .semibold)).kerning(1)
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                AinkradTextField(text: $model.newTagName, placeholder: "Tag name")
                AinkradTextField(text: $model.newTagMessage, placeholder: "Message (optional)")
                AinkradButton(title: "Create tag", style: .primary, icon: "tag") {
                    Task { await model.createTag() }
                }
                .disabled(model.isLoading || model.newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Card chrome

    @ViewBuilder private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AinkradFont.display(10, weight: .semibold)).kerning(2)
                .foregroundStyle(tokens.foreground.opacity(0.5))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.25)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.foreground.opacity(0.07)))
    }
}

/// Labeled HUD toggle row for the auto-stash option.
private struct AutostashToggle: View {
    @Binding var isOn: Bool
    let tokens: HostThemeTokens

    var body: some View {
        HStack {
            Text("Auto-stash uncommitted changes before rebase/reset")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer()
            NeonToggle(isOn: $isOn, tokens: tokens)
        }
    }
}

private struct TagRow: View {
    let tag: GitTag
    let tokens: HostThemeTokens
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag").font(.system(size: 10)).foregroundStyle(tokens.accentSecondary.opacity(0.8)).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name).font(AinkradFont.display(12, weight: .medium)).foregroundStyle(tokens.foreground.opacity(0.9))
                if let message = tag.message, !message.isEmpty {
                    Text(message)
                        .font(AinkradFont.display(10))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer()
            AinkradIconButton(systemName: "trash", size: 20, tooltip: "Delete tag", action: onDelete)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(hovering ? tokens.surfaceElevated.opacity(0.5) : .clear, in: ChamferShape(cut: AinkradRadius.md))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
