import AinkradAppKit
import SwiftUI

// MARK: - Shared HUD chip

/// A gaming-HUD trigger: translucent fill, gradient accent border, accent
/// glow on hover, glowing leading icon and a chevron affordance.
struct TopBarChip: View {
    let icon: String
    let label: String
    var tooltip: String? = nil
    var shortcut: String? = nil
    let tokens: HostThemeTokens
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        // No kit trigger chip yet (AinkradSelect keeps its trigger private), so the chip is local.
        Button(action: action) {  // design-lint: allow raw-control kit gap: trigger chip
            HStack(spacing: skin.size.s7) {
                Image(systemName: icon)
                    .font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "semibold")))
                    .foregroundStyle(tokens.accentSecondary)
                    .shadow(
                        color: tokens.accentSecondary.opacity(hovering ? skin.opacity.o80 : skin.opacity.o40),
                        radius: hovering ? skin.size.s5 : skin.size.s2)
                Text(label)
                    .font(AinkradFont.display(skin.type.sizes.t13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o92))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(skin.font(AinkradFontToken(sizeKey: "t8", weight: "bold")))
                    .foregroundStyle(tokens.foreground.opacity(hovering ? skin.opacity.o70 : skin.opacity.o40))
            }
            .padding(.horizontal, skin.spacing.md)
            .padding(.vertical, skin.size.s7)
            .hudButtonSurface(tokens: tokens, kind: .chip, hovering: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ainkradTooltip(shortcutTooltip(tooltip ?? label, shortcut))
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_14)) { hovering = h } }
    }
}

/// Composes a tooltip: "Fetch  ⌥⌘F" when a shortcut is bound, else just the label.
func shortcutTooltip(_ label: String, _ shortcut: String?) -> String {
    guard let shortcut, !shortcut.isEmpty else { return label }
    return "\(label)  \(shortcut)"
}
