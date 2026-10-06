import AinkradAppKit
import SwiftUI

// MARK: - Overlay pieces

/// Mono, kerned section label (matches launcher "APPS").
struct SectionLabel: View {
    let text: String
    let tokens: HostThemeTokens
    @Environment(\.ainkradSkin) private var skin
    var body: some View {
        Text(text)
            .font(AinkradFont.mono(skin.type.sizes.t9, weight: .medium))
            .kerning(2.5)
            .foregroundStyle(tokens.foreground.opacity(skin.opacity.o40))
            .padding(.horizontal, skin.size.s18)
            .padding(.top, skin.size.s14)
            .padding(.bottom, skin.size.s6)
    }
}
