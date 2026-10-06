import AinkradAppKit
import SwiftUI

/// Centered placeholder shown when a list/pane has no content — e.g. no
/// worktrees, no open PRs. Shared across areas to keep empty-state chrome
/// consistent.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let tokens: HostThemeTokens

    var body: some View {
        // Adopt the kit empty-state (clean 1:1 for the icon/title/message
        // contract; no call site takes an action). `tokens` retained on the
        // API so call sites stay untouched — the kit reads the injected theme.
        AinkradEmptyState(icon: icon, title: title, message: message)
    }
}

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
