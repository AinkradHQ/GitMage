import AinkradAppKit
import SwiftUI

/// Detail pane for the Advanced area: one page of contextual actions — the
/// selected commit's ops (cherry-pick / revert / reset / tag-target), a rebase
/// card, and a tags card. No per-action page.
struct AdvancedDetailView: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: AdvancedViewModel
    let tokens: HostThemeTokens

    private var selectedCommit: GitCommitSummary? {
        guard let sha = model.selectedCommit else { return nil }
        return model.commits.first { $0.id == sha }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.spacing.lg) {
                if model.operationState.isActive { inProgressBanner }
                if let errorMessage = model.errorMessage {
                    AinkradBanner(message: errorMessage, status: .warning)
                }
                AutostashToggle(isOn: $model.autostash, tokens: tokens)
                commitActionsCard
                rebaseCard
                tagsCard
            }
            .padding(skin.size.s20)
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
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            HStack(spacing: skin.size.s6) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(tokens.accentTertiary)
                Text(model.operationState.label)
                    .font(AinkradFont.display(skin.type.sizes.t12, weight: .semibold))
            }
            Text("Resolve conflicts in Changes, then Continue.")
                .font(AinkradFont.display(skin.type.sizes.t11))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o60))
            HStack(spacing: skin.spacing.sm) {
                AinkradButton(title: "Continue", style: .primary) { Task { await model.continueOperation() } }
                    .disabled(model.isLoading)
                AinkradButton(title: "Abort", style: .danger) { Task { await model.abortOperation() } }
                    .disabled(model.isLoading)
            }
        }
        .padding(skin.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.accentTertiary.opacity(skin.opacity.o08)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentTertiary.opacity(skin.opacity.o35)))
    }

    // MARK: - Commit actions

    private var commitActionsCard: some View {
        card("SELECTED COMMIT") {
            if let commit = selectedCommit {
                VStack(alignment: .leading, spacing: skin.spacing.md) {
                    VStack(alignment: .leading, spacing: skin.size.s3) {
                        Text(commit.summary)
                            .font(AinkradFont.display(skin.type.sizes.t13, weight: .medium))
                            .foregroundStyle(tokens.foreground)
                            .lineLimit(2)
                        GMCommitMeta(
                            sha: commit.shortSHA, author: commit.author, date: commit.relativeDate, tokens: tokens,
                            size: skin.type.sizes.t10, limitLines: false)
                    }

                    HStack(spacing: skin.spacing.sm) {
                        AinkradButton(title: "Cherry-pick", style: .secondary, icon: "arrow.right.circle") {
                            Task { await model.cherryPick() }
                        }.disabled(model.isLoading)
                        AinkradButton(title: "Revert", style: .secondary, icon: "arrow.uturn.backward") {
                            Task { await model.revert() }
                        }.disabled(model.isLoading)
                        Spacer()
                    }

                    // Reset row
                    HStack(spacing: skin.spacing.sm) {
                        AinkradSegmentedPicker(
                            items: ResetMode.allCases,
                            selection: $model.resetMode,
                            label: { $0.rawValue.capitalized }
                        )
                        .frame(maxWidth: skin.size.s240)
                        AinkradButton(title: "Reset to here", style: .danger, icon: "arrow.counterclockwise") {
                            model.requestReset()
                        }.disabled(model.isLoading)
                        Spacer()
                    }
                }
            } else {
                Text("Select a commit from the list to cherry-pick, revert, reset, or tag it.")
                    .font(AinkradFont.display(skin.type.sizes.t12))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
            }
        }
    }

    // MARK: - Rebase

    private var rebaseCard: some View {
        card("REBASE") {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.spacing.sm) {
                    Text("Rebase \(model.currentBranchName) onto")
                        .font(AinkradFont.display(skin.type.sizes.t12))
                        .foregroundStyle(tokens.foreground.opacity(skin.opacity.o85))
                    AinkradSelect(
                        items: model.branchNames,
                        selection: Binding(
                            get: { model.rebaseBase ?? "" },
                            set: { model.rebaseBase = $0 }
                        ),
                        label: { $0.isEmpty ? "Choose a branch" : $0 }
                    )
                    .frame(width: skin.size.s180)
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
            VStack(alignment: .leading, spacing: skin.size.s10) {
                if model.tags.isEmpty {
                    Text("No tags yet.")
                        .font(AinkradFont.display(skin.type.sizes.t11))
                        .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: skin.size.s3) {
                            ForEach(model.tags) { tag in
                                TagRow(tag: tag, tokens: tokens) { Task { await model.deleteTag(tag.name) } }
                            }
                        }
                    }
                    .frame(maxHeight: skin.size.s180)
                }

                Text("NEW TAG AT \(tagTarget)")
                    .font(AinkradFont.display(skin.type.sizes.t9, weight: .semibold)).kerning(1)
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
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
        VStack(alignment: .leading, spacing: skin.size.s10) {
            GMHeaderLabel(text: title, tokens: tokens)
            content()
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(skin.opacity.o25)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.foreground.opacity(skin.opacity.o07)))
    }
}

/// Labeled HUD toggle row for the auto-stash option.
private struct AutostashToggle: View {
    @Environment(\.ainkradSkin) private var skin
    @Binding var isOn: Bool
    let tokens: HostThemeTokens

    var body: some View {
        HStack {
            Text("Auto-stash uncommitted changes before rebase/reset")
                .font(AinkradFont.display(skin.type.sizes.t12))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o85))
            Spacer()
            AinkradToggle(isOn: $isOn)
        }
    }
}

private struct TagRow: View {
    @Environment(\.ainkradSkin) private var skin
    let tag: GitTag
    let tokens: HostThemeTokens
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        // The kit row owns the hover wash; this one only reveals the trash.
        AinkradListRow(
            leading: {
                Image(systemName: "tag").font(skin.font(AinkradFontToken(sizeKey: "t10"))).foregroundStyle(tokens.accentSecondary.opacity(skin.opacity.o80))
                    .frame(width: skin.size.s14)
            },
            title: tag.name,
            subtitle: tag.message.flatMap { $0.isEmpty ? nil : $0 },
            trailing: {
                AinkradIconButton(systemName: "trash", size: skin.size.s20, tooltip: "Delete tag", action: onDelete)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
            }
        )
        .onHover { hovering = $0 }
    }
}
