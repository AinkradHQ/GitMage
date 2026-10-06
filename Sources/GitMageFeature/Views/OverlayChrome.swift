import AinkradAppKit
import SwiftUI

// MARK: - Overlay pieces

/// Mono, kerned section label (matches launcher "APPS").
struct SectionLabel: View {
    let text: String
    let tokens: HostThemeTokens
    var body: some View {
        Text(text)
            .font(AinkradFont.mono(9, weight: .medium))
            .kerning(2.5)
            .foregroundStyle(tokens.foreground.opacity(0.4))
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}
