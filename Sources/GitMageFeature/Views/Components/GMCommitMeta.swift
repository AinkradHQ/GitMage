import AinkradAppKit
import SwiftUI

/// The "sha · author · date" line under a commit's subject.
struct GMCommitMeta: View {
    let sha: String
    let author: String
    let date: String
    let tokens: HostThemeTokens
    /// The type size; the skin's 9 pt when nil.
    var size: CGFloat? = nil
    /// Truncate the author and date to one line (rows); the detail card lets them wrap.
    var limitLines = true

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.spacing.sm) {
            Text(sha)
                .font(AinkradFont.mono(size ?? skin.type.sizes.t9, weight: .medium))
                .foregroundStyle(tokens.accentSecondary)
            Text(author)
                .font(AinkradFont.display(size ?? skin.type.sizes.t9))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
                .lineLimit(limitLines ? 1 : nil)
            Text(date)
                .font(AinkradFont.display(size ?? skin.type.sizes.t9))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o40))
                .lineLimit(limitLines ? 1 : nil)
        }
    }

    /// The same line as plain text, for a kit row's subtitle.
    static func text(sha: String, author: String, date: String) -> String { "\(sha) · \(author) · \(date)" }
}
