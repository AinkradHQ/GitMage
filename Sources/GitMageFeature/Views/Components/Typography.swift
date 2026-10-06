import SwiftUI

/// The two brand typefaces — see 06 Brand/Brand Identity.md. Exo 2 for
/// display/UI text, JetBrains Mono for data and HUD readouts. These fonts are
/// registered process-wide by the host; this app resolves them by name. Falls
/// back to the system face automatically if a face isn't registered.
///
/// Family and a global size scale are user-configurable in Git Mage's
/// settings; `GitMageSettingsStore` pushes changes into `Config` and every
/// `display`/`mono` call reads it, so the whole UI restyles live.
enum AinkradFont {
    /// Sentinel family name that maps to the platform system face.
    static let systemFamily = "System"

    /// Curated family choices offered in Settings. `.custom` falls back to the
    /// system face for any unresolved name, so these degrade gracefully.
    static let displayFamilies = ["Exo 2", systemFamily, "Avenir Next", "Helvetica Neue"]
    static let monoFamilies = ["JetBrains Mono", systemFamily, "Menlo", "Monaco", "Courier New"]

    /// Live typography configuration. Mutated only on the main actor when
    /// settings change; read from view bodies (also main actor).
    struct Config {
        var scale: CGFloat = 1.0
        var displayFamily = "Exo 2"
        var monoFamily = "JetBrains Mono"
    }
    // SAFETY: only mutated on the main actor (settings apply) and read on the
    // main actor (view bodies).
    nonisolated(unsafe) static var config = Config()

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * config.scale
        if config.displayFamily == systemFamily {
            return .system(size: scaled).weight(weight)
        }
        return .custom(config.displayFamily, size: scaled).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * config.scale
        if config.monoFamily == systemFamily {
            return .system(size: scaled, design: .monospaced).weight(weight)
        }
        return .custom(config.monoFamily, size: scaled).weight(weight)
    }

    // Fixed brand faces that ignore the user's typography config — used for
    // Git Mage's own Settings chrome, so configuring the font never restyles
    // the panel you're configuring it from.
    static func fixedDisplay(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Exo 2", size: size).weight(weight)
    }
    static func fixedMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}
