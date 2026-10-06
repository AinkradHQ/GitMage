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
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        // The kit row owns its own hover wash; this one only reveals the trash.
        AinkradListRow(
            isSelected: isSelected,
            onTap: branch.isCurrent ? nil : onCheckout,
            leading: { dot },
            title: branch.name,
            subtitle: branch.subtitle,
            trailing: {
                if branch.isCurrent {
                    AinkradBadge(text: "CURRENT", tint: tokens.accentPrimary)
                } else if hovering {
                    AinkradIconButton(
                        systemName: "trash", size: skin.size.s24, tooltip: "Delete branch", action: onDelete)
                }
            }
        )
        .overlay {
            if isSelected { Color.clear.cornerBrackets(length: skin.size.s8, inset: skin.size.s1) }
        }
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }

    /// Filled accent dot with a halo for the checked-out branch, a dim dot otherwise.
    private var dot: some View {
        ZStack {
            Circle()
                .fill(branch.isCurrent ? tokens.accentPrimary : tokens.foreground.opacity(0.25))
                .frame(width: 8, height: 8)
            if branch.isCurrent {
                Circle().stroke(tokens.accentPrimary.opacity(0.4), lineWidth: 4).frame(width: 8, height: 8)
            }
        }
        .frame(width: 16)
    }
}
