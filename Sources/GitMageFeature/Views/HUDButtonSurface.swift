import AinkradAppKit
import SwiftUI

// MARK: - Shared HUD surface finish

enum HUDButtonKind { case chip }

private struct HUDButtonSurface: ViewModifier {
    let tokens: HostThemeTokens
    let kind: HUDButtonKind
    let hovering: Bool

    // Single choke point: chamfering here cascades to every top-bar chip /
    // repo/branch switcher that finishes with `.hudButtonSurface`.
    private var shape: ChamferShape { ChamferShape(cut: AinkradRadius.sm) }

    // Flat kit chamfer surface — the bespoke gloss gradient, gradient rim, and
    // "powered edge" capsule were removed so the chip reads like `AinkradButton`
    // (chamfer fill + a single accent border + a hover-only accent glow).
    func body(content: Content) -> some View {
        content
            .background(fill.clipShape(shape))
            .overlay(
                shape.strokeBorder(tokens.accentSecondary.opacity(hovering ? 0.6 : 0.3), lineWidth: 1)
            )
            .shadow(color: glowColor, radius: glowRadius, y: hovering ? 3 : 1)
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .chip:
            LinearGradient(
                colors: [
                    tokens.surfaceElevated.opacity(hovering ? 0.85 : 0.5),
                    tokens.surfaceElevated.opacity(hovering ? 0.55 : 0.28),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var glowColor: Color {
        switch kind {
        case .chip: return tokens.accentPrimary.opacity(hovering ? 0.32 : 0.06)
        }
    }

    private var glowRadius: CGFloat {
        switch kind {
        case .chip: return hovering ? 11 : 3
        }
    }
}

extension View {
    func hudButtonSurface(tokens: HostThemeTokens, kind: HUDButtonKind, hovering: Bool) -> some View {
        modifier(HUDButtonSurface(tokens: tokens, kind: kind, hovering: hovering))
    }
}
