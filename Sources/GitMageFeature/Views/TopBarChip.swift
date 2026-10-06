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
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.accentSecondary)
                    .shadow(color: tokens.accentSecondary.opacity(hovering ? 0.8 : 0.4), radius: hovering ? 5 : 2)
                Text(label)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.92))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tokens.foreground.opacity(hovering ? 0.7 : 0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .hudButtonSurface(tokens: tokens, kind: .chip, hovering: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ainkradTooltip(shortcutTooltip(tooltip ?? label, shortcut))
        .onHover { h in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hovering = h } }
    }
}

/// Composes a tooltip: "Fetch  ⌥⌘F" when a shortcut is bound, else just the label.
func shortcutTooltip(_ label: String, _ shortcut: String?) -> String {
    guard let shortcut, !shortcut.isEmpty else { return label }
    return "\(label)  \(shortcut)"
}
