import SwiftUI
import AinkradAppKit

struct BranchesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    @State private var newName = ""
    @FocusState private var creating: Bool

    private var canCreate: Bool { !newName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "BRANCHES", count: model.branches.count, tokens: tokens)

            createBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if model.branches.isEmpty {
                EmptyStateView(
                    icon: "arrow.triangle.branch",
                    title: "No branches",
                    message: "Create your first branch above.",
                    tokens: tokens
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.branches) { branch in
                            BranchPaneRow(
                                branch: branch,
                                isSelected: model.selectedBranchName == branch.name,
                                tokens: tokens,
                                onSelect: { model.selectedBranchName = branch.name },
                                onCheckout: { model.selectedBranchName = branch.name; model.checkoutSelectedBranch() },
                                onDelete: { model.deleteBranch(branch.name) }
                            )
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
    }

    private var createBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12)).foregroundStyle(tokens.foreground.opacity(0.4))
                TextField("new-branch", text: $newName)
                    .textFieldStyle(.plain).font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground)
                    .focused($creating)
                    .onSubmit(create)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.5)))
            .overlay(ChamferShape(cut: AinkradRadius.sm)
                .strokeBorder(tokens.accentPrimary.opacity(creating ? 0.5 : 0.18)))

            AinkradIconButton(systemName: "arrow.branch", size: 22, tooltip: "Create branch", action: create)
                .opacity(canCreate ? 1 : 0.4)
                .allowsHitTesting(canCreate)
        }
    }

    private func create() {
        guard canCreate else { return }
        model.newBranchName = newName
        model.createBranch()
        newName = ""
    }
}

private struct BranchPaneRow: View {
    let branch: GitBranchSummary
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    let onCheckout: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(branch.isCurrent ? tokens.accentPrimary : tokens.foreground.opacity(0.25))
                    .frame(width: 8, height: 8)
                if branch.isCurrent {
                    Circle().stroke(tokens.accentPrimary.opacity(0.4), lineWidth: 4).frame(width: 8, height: 8)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(branch.name)
                    .font(AinkradFont.display(12, weight: branch.isCurrent ? .semibold : .regular))
                    .foregroundStyle(tokens.foreground.opacity(branch.isCurrent ? 1 : 0.9))
                    .lineLimit(1)
                Text(branch.subtitle)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45)).lineLimit(1)
            }
            Spacer(minLength: 4)

            if branch.isCurrent {
                AinkradBadge(text: "CURRENT", tint: tokens.accentPrimary)
            } else {
                HStack(spacing: 4) {
                    AinkradIconButton(systemName: "arrow.right", size: 22, tooltip: "Checkout", action: onCheckout)
                    AinkradIconButton(systemName: "trash", size: 22, tooltip: "Delete", action: onDelete)
                }
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.13)
                      : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear))
        )
        .overlay(alignment: .leading) {
            Capsule().fill(tokens.accentPrimary)
                .frame(width: 3, height: 18)
                .shadow(color: tokens.accentPrimary.opacity(0.8), radius: 4)
                .padding(.leading, 1)
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onCheckout)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
    }
}
