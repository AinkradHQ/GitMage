import SwiftUI
import AinkradAppKit

/// Context pane (left rail) for the Worktrees area: header actions + worktree list.
struct WorktreesContextPane: View {
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
            HStack(spacing: 6) {
                AinkradIconButton(systemName: "plus", size: 22, tooltip: "Add worktree") { model.showAdd = true }
                AinkradIconButton(systemName: "sparkles", size: 22, tooltip: "Prune stale worktrees") {
                    Task { await model.prune() }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            AinkradSpinner(size: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            EmptyStateView(icon: "rectangle.split.3x1", title: "Worktrees", message: errorMessage, tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.worktrees.isEmpty {
            EmptyStateView(icon: "rectangle.split.3x1", title: "No worktrees",
                           message: "Add a linked worktree to work on multiple branches at once.", tokens: tokens)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
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
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
    }
}

private struct WorktreeRow: View {
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
        VStack(alignment: .leading, spacing: 4) {
            topLine
            Text(worktree.path)
                .font(AinkradFont.mono(9))
                .foregroundStyle(tokens.foreground.opacity(0.45))
                .lineLimit(1).truncationMode(.middle)
            bottomLine
            actionsRow
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .frame(height: 22)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.13)
                      : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear))
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(tokens.accentPrimary).frame(width: 3, height: 20)
                    .shadow(color: tokens.accentPrimary.opacity(0.8), radius: 4).padding(.leading, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
    }

    private var topLine: some View {
        HStack(spacing: 6) {
            Text(lastPathComponent)
                .font(AinkradFont.display(12, weight: .bold))
                .lineLimit(1)
            if isCurrent {
                AinkradBadge(text: "current", tint: tokens.accentPrimary)
            }
            Spacer()
            if worktree.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            if worktree.isPrunable {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.accentTertiary.opacity(0.9))
            }
        }
    }

    private var bottomLine: some View {
        Text(worktree.branch ?? "detached")
            .font(AinkradFont.display(10, weight: .medium))
            .foregroundStyle(worktree.branch != nil ? tokens.accentPrimary.opacity(0.85) : tokens.foreground.opacity(0.5))
    }

    private var actionsRow: some View {
        HStack(spacing: 4) {
            AinkradIconButton(systemName: "arrow.up.forward.square", size: 20, tooltip: "Open", action: onOpen)
            AinkradIconButton(systemName: worktree.isLocked ? "lock.open" : "lock",
                              size: 20, tooltip: worktree.isLocked ? "Unlock" : "Lock", action: onToggleLock)
            AinkradIconButton(systemName: "trash", size: 20, tooltip: "Remove", action: onRemove)
            Spacer()
        }
    }
}
