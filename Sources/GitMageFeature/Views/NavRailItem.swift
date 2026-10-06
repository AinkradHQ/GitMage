import AinkradAppKit
import SwiftUI

// MARK: - Nav rail item

/// A single icon in the left nav rail, in the gaming-HUD language: a glowing
/// leading "spine" indicator and a bordered accent tile slide to the active
/// area via a shared matched-geometry namespace; hover lifts inactive icons.
struct NavRailItem: View {
    let area: NavArea
    let isActive: Bool
    let tokens: HostThemeTokens
    let namespace: Namespace.ID
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Leading spine — the moving active indicator.
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tokens.accentSecondary)
                            .frame(width: 3, height: 20)
                            .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 5)
                            .matchedGeometryEffect(id: "navSpine", in: namespace)
                    }
                }
                .frame(width: 5)

                ZStack {
                    if isActive {
                        ChamferShape(cut: AinkradRadius.md)
                            .fill(tokens.accentPrimary.opacity(0.16))
                            .overlay(
                                ChamferShape(cut: AinkradRadius.md)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                tokens.accentSecondary.opacity(0.6),
                                                tokens.accentPrimary.opacity(0.25),
                                            ],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: tokens.accentPrimary.opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "navTile", in: namespace)
                    } else if hovering {
                        ChamferShape(cut: AinkradRadius.md)
                            .fill(tokens.surfaceElevated.opacity(0.5))
                    }

                    Image(systemName: area.icon)
                        .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(
                            isActive
                                ? tokens.accentPrimary
                                : tokens.foreground.opacity(hovering ? 0.9 : 0.6)
                        )
                        .shadow(color: isActive ? tokens.accentPrimary.opacity(0.7) : .clear, radius: 5)
                }
                .frame(width: 40, height: 36)
            }
            .frame(width: 52, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ainkradTooltip(shortcutTooltip(area.title, shortcut))
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}
