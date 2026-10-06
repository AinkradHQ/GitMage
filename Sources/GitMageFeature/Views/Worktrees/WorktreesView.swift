import AinkradAppKit
import SwiftUI

/// Context pane (left rail) for the Worktrees area: header actions + worktree list.
struct WorktreesContextPane: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        PaneHeader(title: "WORKTREES", count: model.worktrees.count, tokens: tokens) {
            HStack(spacing: skin.size.s6) {
                AinkradIconButton(systemName: "plus", size: skin.size.s22, tooltip: "Add worktree") { model.showAdd = true }
                AinkradIconButton(systemName: "sparkles", size: skin.size.s22, tooltip: "Prune stale worktrees") {
                    Task { await model.prune() }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            AinkradLoadingState()
        } else if let errorMessage = model.errorMessage {
            AinkradEmptyState(icon: "rectangle.split.3x1", title: "Worktrees", message: errorMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.worktrees.isEmpty {
            AinkradEmptyState(
                icon: "rectangle.split.3x1", title: "No worktrees",
                message: "Add a linked worktree to work on multiple branches at once."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s3) {
                    ForEach(model.worktrees) { wt in
                        WorktreeRow(
                            worktree: wt,
                            tokens: tokens,
                            isSelected: model.selectedPath == wt.path,
                            isCurrent: model.isCurrent(wt),
                            onSelect: { model.select(wt.path) },
                            onOpen: { model.open(wt) },
                            onToggleLock: {
                                Task {
                                    if wt.isLocked {
                                        await model.unlock(wt)
                                    } else {
                                        await model.lock(wt)
                                    }
                                }
                            },
                            onRemove: { Task { await model.remove(wt, force: false) } }
                        )
                    }
                }
                .padding(.horizontal, skin.spacing.md).padding(.bottom, skin.spacing.md)
            }
        }
    }
}

private struct WorktreeRow: View {
    @Environment(\.ainkradSkin) private var skin
    let worktree: GitWorktree
    let tokens: HostThemeTokens
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onToggleLock: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var lastPathComponent: String {
        (worktree.path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.spacing.xs) {
            topLine
            Text(worktree.path)
                .font(AinkradFont.mono(skin.type.sizes.t9))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
                .lineLimit(1).truncationMode(.middle)
            bottomLine
            actionsRow
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .frame(height: skin.size.s22)
        }
        .padding(.horizontal, skin.size.s9).padding(.vertical, skin.spacing.sm)
        // The kit's row wash; the layout stays local (AinkradListRow is title + subtitle only).
        .ainkradRowBackground(isSelected: isSelected, isHovered: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: hovering)
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
    }

    private var topLine: some View {
        HStack(spacing: skin.size.s6) {
            Text(lastPathComponent)
                .font(AinkradFont.display(skin.type.sizes.t12, weight: .bold))
                .lineLimit(1)
            if isCurrent {
                AinkradBadge(text: "current", tint: tokens.accentPrimary)
            }
            Spacer()
            if worktree.isLocked {
                Image(systemName: "lock.fill")
                    .font(skin.font(AinkradFontToken(sizeKey: "t10")))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
            }
            if worktree.isPrunable {
                Image(systemName: "exclamationmark.triangle")
                    .font(skin.font(AinkradFontToken(sizeKey: "t10")))
                    .foregroundStyle(tokens.accentTertiary.opacity(skin.opacity.o90))
            }
        }
    }

    private var bottomLine: some View {
        Text(worktree.branch ?? "detached")
            .font(AinkradFont.display(skin.type.sizes.t10, weight: .medium))
            .foregroundStyle(
                worktree.branch != nil ? tokens.accentPrimary.opacity(skin.opacity.o85) : tokens.foreground.opacity(skin.opacity.o50))
    }

    private var actionsRow: some View {
        HStack(spacing: skin.spacing.xs) {
            AinkradIconButton(systemName: "arrow.up.forward.square", size: skin.size.s20, tooltip: "Open", action: onOpen)
            AinkradIconButton(
                systemName: worktree.isLocked ? "lock.open" : "lock",
                size: 20, tooltip: worktree.isLocked ? "Unlock" : "Lock", action: onToggleLock)
            AinkradIconButton(systemName: "trash", size: skin.size.s20, tooltip: "Remove", action: onRemove)
            Spacer()
        }
    }
}
