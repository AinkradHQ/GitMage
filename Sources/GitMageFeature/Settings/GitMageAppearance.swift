import AinkradAppKit
import SwiftUI

/// Fully-resolved appearance Git Mage renders with. `Equatable` so SwiftUI only
/// re-applies on real change.
struct GitMageRenderAppearance: Equatable {
    let backgroundOpacity: Double
    let accent: Color
    let diffFontSize: Double
}

/// Pure resolution of settings + theme tokens. No AppKit — unit-testable.
enum GitMageAppearanceResolver {
    static func resolve(settings: GitMageSettings, tokens: HostThemeTokens) -> GitMageRenderAppearance {
        GitMageRenderAppearance(
            backgroundOpacity: min(1, max(0.2, settings.backgroundOpacity)),
            accent: settings.followThemeAccent ? tokens.accentPrimary : tokens.accentSecondary,
            diffFontSize: min(20, max(9, settings.diffFontSize))
        )
    }
}
