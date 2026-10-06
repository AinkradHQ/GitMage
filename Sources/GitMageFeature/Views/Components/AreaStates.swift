import AinkradAppKit
import SwiftUI

/// A tokened inline banner for surfacing an error/warning message without a
/// hard divider line.
struct ErrorBanner: View {
    let message: String
    let tokens: HostThemeTokens

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.accentTertiary)
            Text(message)
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.accentTertiary.opacity(0.12))
        )
    }
}
