import AinkradAppKit
import SwiftUI

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
                AinkradEmptyState(
                    icon: "tray.2",
                    title: "No stashes",
                    message: "Stash your working changes to set them aside."
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
                                onSelect: {
                                    selectedStashID = stash.id
                                    model.selectStash(stash)
                                },
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
    @Environment(\.ainkradSkin) private var skin
    let stash: GitStashEntry
    let isSelected: Bool
    let tokens: HostThemeTokens
    let onSelect: () -> Void
    let onApply: () -> Void
    let onDrop: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        // The kit row owns the hover wash and selection; this one only reveals the actions.
        AinkradListRow(
            isSelected: isSelected, onTap: onSelect,
            leading: {
                Image(systemName: "tray.full")
                    .font(skin.font(AinkradFontToken(sizeKey: "t12")))
                    .foregroundStyle(isSelected ? tokens.accentPrimary : tokens.accentSecondary.opacity(0.7))
                    .frame(width: 16)
            },
            title: stash.message, subtitle: stash.id,
            trailing: {
                HStack(spacing: 4) {
                    AinkradIconButton(systemName: "arrow.down.circle", size: 22, tooltip: "Apply", action: onApply)
                    AinkradIconButton(systemName: "trash", size: 22, tooltip: "Drop", action: onDrop)
                }
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
        )
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
