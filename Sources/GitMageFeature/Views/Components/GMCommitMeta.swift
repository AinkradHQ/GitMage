import AinkradAppKit
import SwiftUI

/// The "sha · author · date" line under a commit's subject.
struct GMCommitMeta: View {
    let sha: String
    let author: String
    let date: String
    let tokens: HostThemeTokens
    var size: CGFloat = 9
    /// Truncate the author and date to one line (rows); the detail card lets them wrap.
    var limitLines = true

    var body: some View {
        HStack(spacing: 8) {
            Text(sha)
                .font(AinkradFont.mono(size, weight: .medium))
                .foregroundStyle(tokens.accentSecondary)
            Text(author)
                .font(AinkradFont.display(size))
                .foregroundStyle(tokens.foreground.opacity(0.5))
                .lineLimit(limitLines ? 1 : nil)
            Text(date)
                .font(AinkradFont.display(size))
                .foregroundStyle(tokens.foreground.opacity(0.4))
                .lineLimit(limitLines ? 1 : nil)
        }
    }

    /// The same line as plain text, for a kit row's subtitle.
    static func text(sha: String, author: String, date: String) -> String { "\(sha) · \(author) · \(date)" }
}
