import AinkradAppKit
import SwiftUI

/// A discussion entry — a PR/issue description or a comment — rendered like the
/// GitHub web timeline: an author avatar-initial + name + date header strip
/// over the markdown body. Shared by the PR and Issue detail panes.
struct DiscussionCard: View {
    let author: String
    let timestamp: String
    let text: String
    /// The opening description reads as primary (accent-bordered); comments don't.
    let isPrimary: Bool
    let tokens: HostThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(tokens.accentPrimary.opacity(0.18))
                    Text(String(author.prefix(1)).uppercased())
                        .font(AinkradFont.display(10, weight: .bold))
                        .foregroundStyle(tokens.accentPrimary)
                }
                .frame(width: 22, height: 22)
                Text(author)
                    .font(AinkradFont.display(12, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text(ForgeDate.short(timestamp))
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                Spacer()
                if isPrimary {
                    AinkradBadge(text: "AUTHOR", tint: tokens.accentSecondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(tokens.surfaceElevated.opacity(0.5))

            Group {
                if text.isEmpty {
                    Text("No description provided.")
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownText(markdown: text, tokens: tokens)
                }
            }
            .padding(12)
        }
        .background(tokens.surface.opacity(0.4))
        .clipShape(ChamferShape(cut: AinkradRadius.md))
        .overlay(
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(isPrimary ? tokens.accentPrimary.opacity(0.3) : tokens.foreground.opacity(0.08))
        )
    }
}
