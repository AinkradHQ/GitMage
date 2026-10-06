import AinkradAppKit
import SwiftUI

/// Semantic status categories for PR/issue state. Kept small and closed so
/// every call site is exhaustive.
enum GMStatusKind {
    case open
    case closedMerged
}

/// Centralized semantic color mapping, all from the theme: diff additions and
/// removals read the skin's success and danger colours, states the accents.
enum GMColor {
    static func diffAdd(_ skin: AinkradSkin) -> Color {
        skin.color(.palette("success", 1))
    }

    static func diffRemove(_ skin: AinkradSkin) -> Color {
        skin.color(.palette("danger", 1))
    }

    static func status(_ kind: GMStatusKind, _ tokens: HostThemeTokens) -> Color {
        switch kind {
        case .open:
            return tokens.accentPrimary
        case .closedMerged:
            return tokens.accentSecondary
        }
    }
}
