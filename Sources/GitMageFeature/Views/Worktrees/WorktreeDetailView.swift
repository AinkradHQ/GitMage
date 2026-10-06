import AinkradAppKit
import AppKit
import SwiftUI

/// Detail pane for the selected worktree, plus the Add-worktree sheet.
struct WorktreeDetailView: View {
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
        EmptyStateView(
            icon: "rectangle.split.3x1", title: "Worktrees",
            message: "Select a worktree to browse its commit graph.", tokens: tokens)
    }

    // MARK: - Graph view

    private func graphView(for wt: GitWorktree) -> some View {
        VStack(spacing: 0) {
            header(for: wt)
            GlowRule(tokens: tokens)

            if model.isLoadingGraph {
                AinkradSpinner(size: 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.graphRows.isEmpty {
                EmptyStateView(
                    icon: "point.3.connected.trianglepath.dotted", title: "No history",
                    message: "This worktree has no commits yet.", tokens: tokens
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                graphAndDiff
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(for wt: GitWorktree) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text((wt.path as NSString).lastPathComponent)
                        .font(AinkradFont.display(15, weight: .semibold))
                        .foregroundStyle(tokens.foreground)
                    if model.isCurrent(wt) {
                        Text("CURRENT")
                            .font(AinkradFont.mono(8, weight: .bold)).tracking(1)
                            .foregroundStyle(tokens.accentPrimary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(tokens.accentPrimary.opacity(0.16)))
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9)).foregroundStyle(
                        tokens.foreground.opacity(0.5))
                    Text(wt.branch ?? "detached")
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(
                            wt.branch != nil ? tokens.accentPrimary.opacity(0.85) : tokens.foreground.opacity(0.55))
                }
            }
            Spacer()
            AinkradButton(title: "Open", style: .primary, icon: "arrow.up.forward.square") {
                model.open(wt)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let diff = model.selectedCommitDiff {
                GlowRule(tokens: tokens)
                FileDiffList(
                    files: DiffFileSplitter.split(diff.body), tokens: tokens,
                    fontSize: fontSize, fallbackTitle: diff.title
                )
                .frame(height: 300)
            }
        }
    }

}

private struct AddWorktreeSheet: View {
    @ObservedObject var model: WorktreesViewModel
    let tokens: HostThemeTokens
    @State private var destination: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Worktree")
                .font(AinkradFont.display(18, weight: .semibold))

            destinationPicker
            modePicker
            modeInput

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.accentTertiary.opacity(0.9))
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
        VStack(alignment: .leading, spacing: 4) {
            Text("DESTINATION")
                .font(AinkradFont.display(9, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.45))
            HStack(spacing: 8) {
                Text(destination.isEmpty ? "No folder chosen" : destination)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(destination.isEmpty ? 0.4 : 0.85))
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }
}
