import AinkradAppKit
import SwiftUI

struct ChangesContextPane: View {
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
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: "Working tree clean",
                    message: "No changes to stage or commit.",
                    tokens: tokens
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        group(title: "STAGED", changes: staged, staged: true)
                        group(title: "UNSTAGED", changes: unstaged, staged: false)
                    }
                    .padding(12)
                }
            }
            CommitBox(model: model, tokens: tokens, accent: accent, stagedCount: staged.count)
        }
    }

    @ViewBuilder private func group(title: String, changes: [GitChange], staged: Bool) -> some View {
        if !changes.isEmpty {
            LazyVStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    GMHeaderLabel(text: title, tokens: tokens)
                    Text("\(changes.count)")
                        .font(AinkradFont.mono(9, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(tokens.surfaceElevated.opacity(0.6)))
                    Spacer()
                    if staged {
                        AinkradIconButton(systemName: "minus", size: 20, tooltip: "Unstage all") {
                            model.unstageAllChanges()
                        }
                    } else {
                        AinkradIconButton(systemName: "plus", size: 20, tooltip: "Stage all") {
                            model.stageAllChanges()
                        }
                    }
                }
                .padding(.horizontal, 4)

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
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var fileName: String { (change.path as NSString).lastPathComponent }
    private var directory: String {
        let dir = (change.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    private var status: GMFileStatus { GMFileStatus(change.kind) }
    private var badgeLetter: String { status.letter }
    private var badgeColor: Color { status.color(tokens) }

    var body: some View {
        // The kit row owns the hover wash and selection; this one only reveals the actions.
        AinkradListRow(
            isSelected: isSelected, onTap: onSelect, leading: { badge }, title: fileName,
            subtitle: directory.isEmpty ? nil : directory, trailing: { actions }
        )
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }

    private var badge: some View {
        Text(badgeLetter)
            .font(AinkradFont.mono(10, weight: .bold))
            .foregroundStyle(badgeColor)
            .frame(width: 20, height: 20)
            .background(
                ChamferShape(cut: AinkradRadius.sm)
                    .fill(badgeColor.opacity(0.16))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.sm)
                    .strokeBorder(badgeColor.opacity(0.35), lineWidth: 0.5)
            )
    }

    /// Always laid out (reserves width so nothing shifts); revealed on hover.
    /// Not hit-testable while hidden so it never steals a click.
    private var actions: some View {
        HStack(spacing: 4) {
            if staged {
                AinkradIconButton(systemName: "minus", size: 22, tooltip: "Unstage", action: onUnstage)
            } else {
                AinkradIconButton(systemName: "plus", size: 22, tooltip: "Stage", action: onStage)
                AinkradIconButton(
                    systemName: "arrow.uturn.backward", size: 22, tooltip: "Discard", action: onDiscard)
            }
        }
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
    }
}

struct CommitBox: View {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GMHeaderLabel(text: "COMMIT", tokens: tokens)
                Spacer()
                Text("\(stagedCount) staged")
                    .font(AinkradFont.mono(9, weight: .medium))
                    .foregroundStyle(stagedCount > 0 ? accent.opacity(0.9) : tokens.foreground.opacity(0.4))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill((stagedCount > 0 ? accent : tokens.foreground).opacity(0.12)))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.draftCommitMessage)
                    .font(AinkradFont.display(12))
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(height: 70)
                    .padding(7)
                if model.draftCommitMessage.isEmpty {
                    Text("Summary of your changes…")
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.35))
                        .padding(.horizontal, 12).padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .background(
                ChamferShape(cut: AinkradRadius.sm)
                    .fill(tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.sm)
                    .strokeBorder(
                        accent.opacity(editorFocused ? 0.6 : 0.2),
                        lineWidth: editorFocused ? 1.2 : 1)
            )
            .shadow(color: editorFocused ? accent.opacity(0.25) : .clear, radius: 8)

            HStack {
                Spacer()
                AinkradButton(title: "Commit", style: .primary, icon: "checkmark") {
                    model.commitChanges()
                }
                .disabled(!canCommit)
                .opacity(canCommit ? 1 : 0.5)
            }
        }
        .padding(12)
        .background(tokens.surface.opacity(0.4))
    }
}
