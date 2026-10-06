import AinkradAppKit
import AppKit
import SwiftUI

/// Detail pane for the selected worktree, plus the Add-worktree sheet.
struct WorktreeDetailView: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens
    var fontSize: Double = 12

    private var selected: GitWorktree? {
        model.worktrees.first { $0.path == model.selectedPath }
    }

    var body: some View {
        Group {
            if let wt = selected {
                graphView(for: wt)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ainkradModal(isPresented: $model.showAdd) {
            AddWorktreeSheet(model: model, tokens: tokens)
        }
    }

    private var emptyState: some View {
        AinkradEmptyState(
            icon: "rectangle.split.3x1", title: "Worktrees",
            message: "Select a worktree to browse its commit graph.")
    }

    // MARK: - Graph view

    private func graphView(for wt: GitWorktree) -> some View {
        VStack(spacing: 0) {
            header(for: wt)

            if model.isLoadingGraph {
                AinkradLoadingState()
            } else if model.graphRows.isEmpty {
                AinkradEmptyState(
                    icon: "point.3.connected.trianglepath.dotted", title: "No history",
                    message: "This worktree has no commits yet."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                graphAndDiff
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(for wt: GitWorktree) -> some View {
        HStack(spacing: skin.size.s10) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                HStack(spacing: skin.spacing.sm) {
                    Text((wt.path as NSString).lastPathComponent)
                        .font(AinkradFont.display(skin.type.sizes.t15, weight: .semibold))
                        .foregroundStyle(tokens.foreground)
                    if model.isCurrent(wt) {
                        AinkradBadge(text: "CURRENT", tint: tokens.accentPrimary)
                    }
                }
                HStack(spacing: skin.size.s6) {
                    Image(systemName: "arrow.triangle.branch").font(skin.font(AinkradFontToken(sizeKey: "t9"))).foregroundStyle(
                        tokens.foreground.opacity(skin.opacity.o50))
                    Text(wt.branch ?? "detached")
                        .font(AinkradFont.mono(skin.type.sizes.t11))
                        .foregroundStyle(
                            wt.branch != nil ? tokens.accentPrimary.opacity(skin.opacity.o85) : tokens.foreground.opacity(skin.opacity.o55))
                }
            }
            Spacer()
            AinkradButton(title: "Open", style: .primary, icon: "arrow.up.forward.square") {
                model.open(wt)
            }
        }
        .padding(.horizontal, skin.spacing.lg).padding(.vertical, skin.spacing.md)
    }

    private var graphAndDiff: some View {
        let maxLanes = model.graphRows.map(\.laneCount).max() ?? 1
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.graphRows) { row in
                        GraphCommitRow(
                            row: row,
                            laneCount: maxLanes,
                            isSelected: model.selectedCommitSHA == row.commit.sha,
                            tokens: tokens,
                            onSelect: { model.selectCommit(row.commit.sha) }
                        )
                    }
                }
                .padding(.vertical, skin.size.s6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let diff = model.selectedCommitDiff {
                FileDiffList(
                    files: DiffFileSplitter.split(diff.body), tokens: tokens,
                    fontSize: fontSize, fallbackTitle: diff.title
                )
                .frame(height: skin.size.s300)
            }
        }
    }

}

private struct AddWorktreeSheet: View {
    @Environment(\.ainkradSkin) private var skin
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens
    @State private var destination: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: skin.spacing.lg) {
            Text("Add Worktree")
                .font(AinkradFont.display(skin.type.sizes.t18, weight: .semibold))

            destinationPicker
            modePicker
            modeInput

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(AinkradFont.display(skin.type.sizes.t11))
                    .foregroundStyle(tokens.accentTertiary.opacity(skin.opacity.o90))
            }

            HStack {
                Spacer()
                AinkradButton(title: "Cancel", style: .secondary) { model.showAdd = false }
                AinkradButton(title: "Add", style: .primary, icon: "plus") {
                    Task { await model.add(destination: destination) }
                }
                .disabled(!canAdd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(tokens.foreground)
    }

    private var canAdd: Bool {
        guard !destination.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch model.addMode {
        case .newBranch: return !model.addBranchName.trimmingCharacters(in: .whitespaces).isEmpty
        case .existingBranch: return !(model.addExistingBranch ?? "").isEmpty
        case .detached: return !model.addRef.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: skin.spacing.xs) {
            Text("DESTINATION")
                .font(AinkradFont.display(skin.type.sizes.t9, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
            HStack(spacing: skin.spacing.sm) {
                Text(destination.isEmpty ? "No folder chosen" : destination)
                    .font(AinkradFont.mono(skin.type.sizes.t11))
                    .foregroundStyle(tokens.foreground.opacity(destination.isEmpty ? skin.opacity.o40 : skin.opacity.o85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                AinkradButton(title: "Choose…", style: .secondary, icon: "folder") { chooseDestination() }
            }
        }
    }

    private var modePicker: some View {
        AinkradSegmentedPicker(
            items: [.newBranch, .existingBranch, .detached],
            selection: $model.addMode,
            label: { mode in
                switch mode {
                case .newBranch: return "New branch"
                case .existingBranch: return "Existing"
                case .detached: return "Detached"
                }
            }
        )
    }

    @ViewBuilder private var modeInput: some View {
        switch model.addMode {
        case .newBranch:
            AinkradTextField(text: $model.addBranchName, placeholder: "Branch name")
        case .existingBranch:
            AinkradSelect(
                items: model.branchNames,
                selection: Binding(
                    get: { model.addExistingBranch ?? "" },
                    set: { model.addExistingBranch = $0 }
                ),
                label: { $0.isEmpty ? "Choose a branch" : $0 }
            )
        case .detached:
            AinkradTextField(text: $model.addRef, placeholder: "Ref (commit, tag, branch)")
        }
    }

    private func chooseDestination() {
        if let url = FolderPicker.pick() {
            destination = url.path
        }
    }
}
