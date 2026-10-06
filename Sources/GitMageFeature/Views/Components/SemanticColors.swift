import AinkradAppKit
import SwiftUI

/// Semantic status categories used across Git Mage surfaces (PR/issue state,
/// operation results, informational rows). Kept small and closed so every
/// call site is exhaustive.
enum GMStatusKind {
    case open
    case closedMerged
    case warning
    case success
    case neutral
}

/// Centralized semantic color mapping. Every color here is derived from the
/// host's `HostThemeTokens` EXCEPT the diff add/remove and success greens,
/// which are the one intentional non-token semantic pair in the app: diffs
/// and success/failure need fixed, accessible red/green regardless of the
/// active theme's accent palette. If that pair ever needs to change, this is
/// the single place to do it.
enum GMColor {
    /// Fixed accessible green — diff additions and `.success` status.
    private static let accessibleGreen = Color(red: 0.30, green: 0.75, blue: 0.42)
    /// Fixed accessible red — diff removals.
    private static let accessibleRed = Color(red: 0.92, green: 0.35, blue: 0.35)

    static func diffAdd(_ tokens: HostThemeTokens) -> Color {
        accessibleGreen
    }

    static func diffRemove(_ tokens: HostThemeTokens) -> Color {
        accessibleRed
    }

    static func status(_ kind: GMStatusKind, _ tokens: HostThemeTokens) -> Color {
        switch kind {
        case .open:
            return tokens.accentPrimary
        case .closedMerged:
            return tokens.accentSecondary
        case .warning:
            return tokens.accentTertiary
        case .success:
            return accessibleGreen
        case .neutral:
            return tokens.foreground.opacity(0.5)
        }
    }
}
