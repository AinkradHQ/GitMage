import SwiftUI
import AinkradAppKit

struct StashesContextPane: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    @State private var selectedStashID: String?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "STASHES", count: model.stashes.count, tokens: tokens) {
                HStack(spacing: 6) {
                    AinkradIconButton(systemName: "tray.and.arrow.down", size: 22, tooltip: "Stash changes") {
                        model.stashChanges()
                    }
                    AinkradIconButton(systemName: "tray.and.arrow.up", size: 22, tooltip: "Pop latest stash") {
                        model.popLatestStash()
                    }
                    .opacity(model.stashes.isEmpty || model.isLoading ? 0.4 : 1)
                    .allowsHitTesting(!model.stashes.isEmpty && !model.isLoading)
                }
            }

            if model.stashes.isEmpty {
                EmptyStateView(
                    icon: "tray.2",
                    title: "No stashes",
                    message: "Stash your working changes to set them aside.",
                    tokens: tokens
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.stashes) { stash in
                            StashRow(
                                stash: stash,
                                isSelected: selectedStashID == stash.id,
                                tokens: tokens,
                                onSelect: { selectedStashID = stash.id; model.selectStash(stash) },
                                onApply: { model.applyStash(stash) },
                                onDrop: { model.dropStash(stash) }
                            )
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
    }
}

private struct StashRow: View {
    let stash: GitStashEntry
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    let onApply: () -> Void
    let onDrop: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? tokens.accentPrimary : tokens.accentSecondary.opacity(0.7))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(stash.message)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 1 : 0.88))
                    .lineLimit(2)
                Text(stash.id)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
            Spacer(minLength: 4)

            HStack(spacing: 4) {
                AinkradIconButton(systemName: "arrow.down.circle", size: 22, tooltip: "Apply", action: onApply)
                AinkradIconButton(systemName: "trash", size: 22, tooltip: "Drop", action: onDrop)
            }
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(
            ChamferShape(cut: AinkradRadius.md)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.13)
                      : (hovering ? tokens.surfaceElevated.opacity(0.5) : .clear))
        )
        .overlay(alignment: .leading) {
            Capsule().fill(tokens.accentPrimary)
                .frame(width: 3, height: 20)
                .shadow(color: tokens.accentPrimary.opacity(0.8), radius: 4)
                .padding(.leading, 1)
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
    }
}
