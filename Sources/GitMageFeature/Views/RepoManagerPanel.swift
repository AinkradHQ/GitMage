import AinkradAppKit
import SwiftUI

// MARK: - Repo manager

struct RepoManagerPanel: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let dismiss: () -> Void

    @State private var picker = OverlaySelection()
    @FocusState private var focused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filtered: [GitMageRepoConfig] {
        picker.filter(model.repos) { [$0.name, $0.path] }
    }

    var body: some View {
        let results = filtered
        VStack(alignment: .leading, spacing: 0) {
            AinkradCommandField(
                "Search repositories…", text: $picker.query, focus: $focused,
                onArrow: { picker.move($0, count: results.count) },
                onSubmit: { activate(results) },
                onEscape: dismiss
            )
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
                                isSelected: index == picker.selected,
                                tokens: tokens,
                                onSelect: {
                                    picker.selected = index
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
        .ainkradPanel()
        .onAppear { focused = true }
        .onChange(of: picker.query) { _, _ in picker.selected = 0 }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "square.stack.3d.up.slash",
            title: picker.query.isEmpty ? "No repositories yet" : "No matches",
            message: picker.query.isEmpty ? "Add a local folder or clone one to begin." : "Try a different search.",
            tokens: tokens
        )
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func activate(_ results: [GitMageRepoConfig]) {
        guard results.indices.contains(picker.selected) else { return }
        model.selectRepository(results[picker.selected].id)
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
    @Environment(\.ainkradSkin) private var skin
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
        .overlay {
            if isSelected { Color.clear.cornerBrackets(length: skin.size.s8, inset: skin.size.s2) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}
