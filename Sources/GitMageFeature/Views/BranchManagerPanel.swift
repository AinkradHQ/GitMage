import AinkradAppKit
import SwiftUI

// MARK: - Branch manager

struct BranchManagerPanel: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let dismiss: () -> Void

    @State private var picker = OverlaySelection()
    @FocusState private var focused: Bool

    private var filtered: [GitBranchSummary] {
        picker.filter(model.branches) { [$0.name] }
    }

    /// When the search matches nothing, the query becomes a create candidate.
    private var createName: String {
        picker.query.trimmingCharacters(in: .whitespaces)
    }
    private var canCreate: Bool {
        !createName.isEmpty && !model.branches.contains { $0.name == createName }
    }

    var body: some View {
        let results = filtered
        VStack(alignment: .leading, spacing: 0) {
            AinkradCommandField(
                "Search or name a new branch…", text: $picker.query, focus: $focused,
                onArrow: { picker.move($0, count: results.count) },
                onSubmit: { activate(results) },
                onEscape: dismiss
            )
            SectionLabel(text: "BRANCHES · \(model.branches.count)", tokens: tokens)

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, branch in
                            BranchRow(
                                branch: branch,
                                isSelected: index == picker.selected,
                                tokens: tokens,
                                onCheckout: {
                                    picker.selected = index
                                    activate(results)
                                },
                                onDelete: { model.deleteBranch(branch.name) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 340)
            }

            HStack(spacing: 10) {
                AinkradButton(
                    title: canCreate ? "Create \"\(createName)\"" : "Create Branch",
                    style: .primary, icon: "arrow.branch"
                ) {
                    create()
                }
                .disabled(!canCreate)
                Spacer()
                Text("↑↓ navigate   ↩ checkout   esc close")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.35))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .ainkradPanel()
        .onAppear { focused = true }
        .onChange(of: picker.query) { _, _ in picker.selected = 0 }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EmptyStateView(
                icon: "arrow.triangle.branch",
                title: canCreate ? "No matching branch" : "No branches",
                message: canCreate ? "Press ↩ or Create to make \"\(createName)\"." : "Create your first branch below.",
                tokens: tokens
            )
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    /// Return key: if the query matches branches, checkout the selected one;
    /// otherwise treat the query as a new branch name.
    private func activate(_ results: [GitBranchSummary]) {
        if results.isEmpty && canCreate {
            create()
            return
        }
        guard results.indices.contains(picker.selected) else { return }
        let branch = results[picker.selected]
        guard !branch.isCurrent else { return }
        model.selectedBranchName = branch.name
        model.checkoutSelectedBranch()
        dismiss()
    }

    private func create() {
        guard canCreate else { return }
        model.newBranchName = createName
        model.createBranch()
        dismiss()
    }
}

private struct BranchRow: View {
    let branch: GitBranchSummary
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onCheckout: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(branch.isCurrent ? tokens.accentPrimary : tokens.foreground.opacity(0.25))
                    .frame(width: 8, height: 8)
                if branch.isCurrent {
                    Circle().stroke(tokens.accentPrimary.opacity(0.4), lineWidth: 4).frame(width: 8, height: 8)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(branch.name)
                    .font(AinkradFont.display(13, weight: branch.isCurrent ? .semibold : .regular))
                    .foregroundStyle(tokens.foreground.opacity(branch.isCurrent ? 1 : 0.9))
                Text(branch.subtitle)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.42)).lineLimit(1)
            }
            Spacer(minLength: 6)

            if branch.isCurrent {
                Text("CURRENT")
                    .font(AinkradFont.mono(8, weight: .bold)).tracking(1)
                    .foregroundStyle(tokens.accentPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(tokens.accentPrimary.opacity(0.16)))
            } else if hovering {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                .buttonStyle(.plain).help("Delete branch")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(
            ChamferShape(cut: AinkradRadius.sm)
                .fill(
                    branch.isCurrent
                        ? tokens.accentPrimary.opacity(0.09)
                        : ((hovering || isSelected) ? tokens.accentPrimary.opacity(0.10) : .clear))
        )
        .overlay(
            GMTargetingBrackets()
                .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.5)
                .padding(1)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !branch.isCurrent { onCheckout() } }
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}
