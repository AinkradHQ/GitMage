import AinkradAppKit
import SwiftUI

/// A small capsule badge for status text (PR/issue state, op result). Uses
/// the same tinted-fill / full-color-text pattern across all status kinds so
/// pills read consistently regardless of theme.
struct StatusPill: View {
    let text: String
    let kind: GMStatusKind
    let tokens: HostThemeTokens

    var body: some View {
        AinkradBadge(text: text, tint: GMColor.status(kind, tokens))
    }
}
