import AinkradAppKit
import SwiftUI

// MARK: - Repo manager

struct RepoManagerPanel: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let dismiss: () -> Void

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filtered: [GitMageRepoConfig] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.repos }
        return model.repos.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
    }

    var body: some View {
        let results = filtered
        VStack(alignment: .leading, spacing: 0) {
            OverlaySearchField(
                placeholder: "Search repositories…",
                text: $query, tokens: tokens, focus: $focused,
                onMove: { move($0, count: results.count) },
                onActivate: { activate(results) },
                onEscape: dismiss
            )
            GlowRule(tokens: tokens)
            SectionLabel(text: "REPOSITORIES · \(model.repos.count)", tokens: tokens)

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, repo in
                            RepoCard(
                                repo: repo,
                                isActive: repo.id == model.activeRepoID,
                                isSelected: index == selected,
                                tokens: tokens,
                                onSelect: {
                                    selected = index
                                    activate(results)
                                },
                                onRemove: { model.removeRepository(repo.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 340)
            }

            GlowRule(tokens: tokens)
            HStack(spacing: 10) {
                AinkradButton(title: "Add Local", style: .primary, icon: "plus") {
                    dismiss()
                    model.addRepositoryFolder()
                }
                AinkradButton(title: "Clone", style: .secondary, icon: "arrow.down.doc") {
                    dismiss()
                    model.startClone()
                }
                Spacer()
                Text("↑↓ navigate   ↩ open   esc close")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.35))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .hudPanelChrome(tokens)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "square.stack.3d.up.slash",
            title: query.isEmpty ? "No repositories yet" : "No matches",
            message: query.isEmpty ? "Add a local folder or clone one to begin." : "Try a different search.",
            tokens: tokens
        )
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    private func activate(_ results: [GitMageRepoConfig]) {
        guard results.indices.contains(selected) else { return }
        model.selectRepository(results[selected].id)
        dismiss()
    }
}

private struct RepoCard: View {
    let repo: GitMageRepoConfig
    let isActive: Bool
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? tokens.accentPrimary : tokens.foreground.opacity(0.6))
                Spacer()
                if isActive {
                    Text("ACTIVE")
                        .font(AinkradFont.mono(8, weight: .bold)).tracking(1)
                        .foregroundStyle(tokens.accentPrimary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(tokens.accentPrimary.opacity(0.16)))
                } else if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 11))
                            .foregroundStyle(tokens.foreground.opacity(0.55))
                    }
                    .buttonStyle(.plain).help("Remove from library")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(AinkradFont.display(14, weight: .semibold))
                    .foregroundStyle(tokens.foreground).lineLimit(1)
                Text(repo.path)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(height: 96, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(
                    isActive
                        ? tokens.accentPrimary.opacity(0.10)
                        : tokens.surfaceElevated.opacity(hovering || isSelected ? 0.7 : 0.4))
        )
        .overlay(
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(
                    isActive
                        ? tokens.accentPrimary.opacity(0.55)
                        : tokens.foreground.opacity(hovering ? 0.14 : 0.06),
                    lineWidth: isActive ? 1.2 : 1)
        )
        .overlay(
            GMTargetingBrackets()
                .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.5)
                .padding(2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}
