import AinkradAppKit
import SwiftUI

struct ChangesContextPane: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let accent: Color

    /// Group-scoped selection key ("staged:<id>" / "unstaged:<id>") so a file that
    /// appears in both groups only highlights the side the user actually clicked.
    /// The VM's `selectedChangeID` (plain change id) still drives which change the
    /// stage/unstage/discard actions target and is left untouched.
    @State private var selectedRowID: String?

    var body: some View {
        // Computed once per render — previously `staged`/`unstaged` were
        // computed properties re-filtering the whole change list on every
        // access (three times: the empty check, the two groups, and the
        // commit box's staged count).
        let allChanges = model.snapshot?.changes ?? []
        let staged = allChanges.filter { $0.hasStagedComponent }
        let unstaged = allChanges.filter { $0.hasUnstagedComponent }
        VStack(spacing: 0) {
            if staged.isEmpty && unstaged.isEmpty {
                AinkradEmptyState(
                    icon: "checkmark.seal",
                    title: "Working tree clean",
                    message: "No changes to stage or commit."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: skin.spacing.lg) {
                        group(title: "STAGED", changes: staged, staged: true)
                        group(title: "UNSTAGED", changes: unstaged, staged: false)
                    }
                    .padding(skin.spacing.md)
                }
            }
            CommitBox(model: model, tokens: tokens, accent: accent, stagedCount: staged.count)
        }
    }

    @ViewBuilder private func group(title: String, changes: [GitChange], staged: Bool) -> some View {
        if !changes.isEmpty {
            LazyVStack(alignment: .leading, spacing: skin.size.s5) {
                HStack(spacing: skin.spacing.sm) {
                    GMHeaderLabel(text: title, tokens: tokens)
                    AinkradBadge(text: "\(changes.count)")
                    Spacer()
                    if staged {
                        AinkradIconButton(systemName: "minus", size: skin.size.s20, tooltip: "Unstage all") {
                            model.unstageAllChanges()
                        }
                    } else {
                        AinkradIconButton(systemName: "plus", size: skin.size.s20, tooltip: "Stage all") {
                            model.stageAllChanges()
                        }
                    }
                }
                .padding(.horizontal, skin.spacing.xs)

                ForEach(changes, id: \.id) { change in
                    let rowID = "\(staged ? "staged" : "unstaged"):\(change.id)"
                    ChangeRow(
                        change: change, isSelected: selectedRowID == rowID, staged: staged, tokens: tokens,
                        onSelect: {
                            selectedRowID = rowID
                            model.selectChange(change)
                        },
                        onStage: {
                            selectedRowID = rowID
                            model.selectChange(change)
                            model.stageSelectedChange()
                        },
                        onUnstage: {
                            selectedRowID = rowID
                            model.selectChange(change)
                            model.unstageSelectedChange()
                        },
                        onDiscard: {
                            selectedRowID = rowID
                            model.selectChange(change)
                            model.discardSelectedChange()
                        })
                }
            }
        }
    }
}

struct ChangeRow: View {
    let change: GitChange
    let isSelected: Bool
    let staged: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onDiscard: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var fileName: String { (change.path as NSString).lastPathComponent }
    private var directory: String {
        let dir = (change.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    private var status: GMFileStatus { GMFileStatus(change.kind) }
    private var badgeLetter: String { status.letter }
    private var badgeColor: Color { status.color(tokens, skin) }

    var body: some View {
        // The kit row owns the hover wash and selection; this one only reveals the actions.
        AinkradListRow(
            isSelected: isSelected, onTap: onSelect, leading: { badge }, title: fileName,
            subtitle: directory.isEmpty ? nil : directory, trailing: { actions }
        )
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: hovering)
    }

    private var badge: some View {
        Text(badgeLetter)
            .font(AinkradFont.mono(skin.type.sizes.t10, weight: .bold))
            .foregroundStyle(badgeColor)
            .frame(width: skin.size.s20, height: skin.size.s20)
            .background(
                skin.shape(cut: AinkradRadius.sm)
                    .fill(badgeColor.opacity(skin.opacity.o16))
            )
            .overlay(
                skin.shape(cut: AinkradRadius.sm)
                    .strokeBorder(badgeColor.opacity(skin.opacity.o35), lineWidth: 0.5)
            )
    }

    /// Always laid out (reserves width so nothing shifts); revealed on hover.
    /// Not hit-testable while hidden so it never steals a click.
    private var actions: some View {
        HStack(spacing: skin.spacing.xs) {
            if staged {
                AinkradIconButton(systemName: "minus", size: skin.size.s22, tooltip: "Unstage", action: onUnstage)
            } else {
                AinkradIconButton(systemName: "plus", size: skin.size.s22, tooltip: "Stage", action: onStage)
                AinkradIconButton(
                    systemName: "arrow.uturn.backward", size: 22, tooltip: "Discard", action: onDiscard)
            }
        }
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
    }
}

struct CommitBox: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let accent: Color
    let stagedCount: Int
    @FocusState private var editorFocused: Bool

    private var canCommit: Bool {
        !model.isLoading && stagedCount > 0
            && !model.draftCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack {
                GMHeaderLabel(text: "COMMIT", tokens: tokens)
                Spacer()
                if stagedCount > 0 {
                    AinkradBadge(text: "\(stagedCount) staged", tint: accent)
                } else {
                    AinkradBadge(text: "\(stagedCount) staged")
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.draftCommitMessage)
                    .font(AinkradFont.display(skin.type.sizes.t12))
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(height: skin.size.s70)
                    .padding(skin.size.s7)
                if model.draftCommitMessage.isEmpty {
                    Text("Summary of your changes…")
                        .font(AinkradFont.display(skin.type.sizes.t12))
                        .foregroundStyle(tokens.foreground.opacity(skin.opacity.o35))
                        .padding(.horizontal, skin.spacing.md).padding(.vertical, skin.size.s15)
                        .allowsHitTesting(false)
                }
            }
            .background(
                skin.shape(cut: AinkradRadius.sm)
                    .fill(tokens.surfaceElevated.opacity(skin.opacity.o50))
            )
            .overlay(
                skin.shape(cut: AinkradRadius.sm)
                    .strokeBorder(
                        accent.opacity(editorFocused ? skin.opacity.o60 : skin.opacity.o20),
                        lineWidth: editorFocused ? 1.2 : 1)
            )
            .shadow(color: editorFocused ? accent.opacity(skin.opacity.o25) : .clear, radius: skin.size.s8)

            HStack {
                Spacer()
                AinkradButton(title: "Commit", style: .primary, icon: "checkmark") {
                    model.commitChanges()
                }
                .disabled(!canCommit)
                .opacity(canCommit ? 1 : skin.opacity.o50)
            }
        }
        .padding(skin.spacing.md)
        .background(tokens.surface.opacity(skin.opacity.o40))
    }
}
