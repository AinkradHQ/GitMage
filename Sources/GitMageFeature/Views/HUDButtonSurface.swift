import AinkradAppKit
import SwiftUI

// MARK: - Shared HUD surface finish

enum HUDButtonKind { case chip }

private struct HUDButtonSurface: ViewModifier {
    let tokens: HostThemeTokens
    let kind: HUDButtonKind
    let hovering: Bool
    @Environment(\.ainkradSkin) private var skin

    // Single choke point: chamfering here cascades to every top-bar chip /
    // repo/branch switcher that finishes with `.hudButtonSurface`.
    private var shape: AinkradSkinShape { skin.shape(cut: AinkradRadius.sm) }

    // Flat kit chamfer surface — the bespoke gloss gradient, gradient rim, and
    // "powered edge" capsule were removed so the chip reads like `AinkradButton`
    // (chamfer fill + a single accent border + a hover-only accent glow).
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *), skin.usesNativeGlass {
            // Liquid Glass: a toolbar-style glass capsule; the glass answers
            // hover and press itself.
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            kitBody(content)
        }
    }

    private func kitBody(_ content: Content) -> some View {
        content
            .background(fill.clipShape(shape))
            .overlay(
                shape.strokeBorder(
                    tokens.accentSecondary.opacity(hovering ? skin.opacity.o60 : skin.opacity.o30), lineWidth: 1)
            )
            .shadow(color: glowColor, radius: glowRadius, y: hovering ? 3 : 1)
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .chip:
            LinearGradient(
                colors: [
                    tokens.surfaceElevated.opacity(hovering ? skin.opacity.o85 : skin.opacity.o50),
                    tokens.surfaceElevated.opacity(hovering ? skin.opacity.o55 : skin.opacity.o28),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var glowColor: Color {
        switch kind {
        case .chip: return tokens.accentPrimary.opacity(hovering ? skin.opacity.o32 : skin.opacity.o06)
        }
    }

    private var glowRadius: CGFloat {
        switch kind {
        case .chip: return hovering ? skin.size.s11 : skin.size.s3
        }
    }
}

extension View {
    func hudButtonSurface(tokens: HostThemeTokens, kind: HUDButtonKind, hovering: Bool) -> some View {
        modifier(HUDButtonSurface(tokens: tokens, kind: kind, hovering: hovering))
    }
}
