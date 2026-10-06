import AinkradAppKit
import SwiftUI

/// The shared context-pane header: a kerned title, a count pill, and optional
/// trailing actions — the same language as the Changes group headers.
struct PaneHeader<Trailing: View>: View {
    let title: String
    let count: Int
    /// Overrides the count pill text (e.g. "50 / 342"); defaults to `count`.
    let countText: String?
    let tokens: HostThemeTokens
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String, count: Int, countText: String? = nil, tokens: HostThemeTokens,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.count = count
        self.countText = countText
        self.tokens = tokens
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AinkradFont.display(10, weight: .semibold)).kerning(2)
                .foregroundStyle(tokens.foreground.opacity(0.5))
            Text(countText ?? "\(count)")
                .font(AinkradFont.mono(9, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.5))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(tokens.surfaceElevated.opacity(0.6)))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

/// Horizontal accent glow rule — the soft separator used across surfaces.
struct GlowRule: View {
    let tokens: HostThemeTokens
    var body: some View {
        LinearGradient(
            colors: [.clear, tokens.accentPrimary.opacity(0.4), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}
