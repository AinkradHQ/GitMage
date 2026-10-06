import AinkradAppKit
import SwiftUI

struct ComingSoonView: View {
    let area: NavArea
    let tokens: HostThemeTokens

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: area.icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(tokens.accentPrimary.opacity(0.5))
            Text(area.title)
                .font(AinkradFont.display(18, weight: .semibold))
            Text("Coming in a later milestone.")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
