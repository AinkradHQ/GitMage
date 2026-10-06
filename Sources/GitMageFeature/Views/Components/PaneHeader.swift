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
    @Environment(\.ainkradSkin) private var skin

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
        HStack(spacing: skin.spacing.sm) {
            GMHeaderLabel(text: title, tokens: tokens)
            AinkradBadge(text: countText ?? "\(count)")
            Spacer()
            trailing()
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.spacing.sm)
    }
}

/// The small kerned caption above a group: "COMMIT", "STAGED", a pane title.
struct GMHeaderLabel: View {
    let text: String
    let tokens: HostThemeTokens
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(text)
            .font(AinkradFont.display(skin.type.sizes.t10, weight: .semibold)).kerning(2)
            .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
    }
}
