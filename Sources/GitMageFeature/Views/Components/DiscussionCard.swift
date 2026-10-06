import AinkradAppKit
import SwiftUI

/// A discussion entry — a PR/issue description or a comment — rendered like the
/// GitHub web timeline: an author avatar-initial + name + date header strip
/// over the markdown body. Shared by the PR and Issue detail panes.
struct DiscussionCard: View {
    @Environment(\.ainkradSkin) private var skin
    let author: String
    let timestamp: String
    let text: String
    /// The opening description reads as primary (accent-bordered); comments don't.
    let isPrimary: Bool
    let tokens: HostThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: skin.spacing.sm) {
                ZStack {
                    Circle().fill(tokens.accentPrimary.opacity(skin.opacity.o18))
                    Text(String(author.prefix(1)).uppercased())
                        .font(AinkradFont.display(skin.type.sizes.t10, weight: .bold))
                        .foregroundStyle(tokens.accentPrimary)
                }
                .frame(width: skin.size.s22, height: skin.size.s22)
                Text(author)
                    .font(AinkradFont.display(skin.type.sizes.t12, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o90))
                Text(ForgeDate.short(timestamp))
                    .font(AinkradFont.mono(skin.type.sizes.t9))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
                Spacer()
                if isPrimary {
                    AinkradBadge(text: "AUTHOR", tint: tokens.accentSecondary)
                }
            }
            .padding(.horizontal, skin.spacing.md).padding(.vertical, skin.spacing.sm)
            .background(tokens.surfaceElevated.opacity(skin.opacity.o50))

            Group {
                if text.isEmpty {
                    Text("No description provided.")
                        .font(AinkradFont.display(skin.type.sizes.t12))
                        .foregroundStyle(tokens.foreground.opacity(skin.opacity.o40))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownText(markdown: text, tokens: tokens)
                }
            }
            .padding(skin.spacing.md)
        }
        .background(tokens.surface.opacity(skin.opacity.o40))
        .clipShape(ChamferShape(cut: AinkradRadius.md))
        .overlay(
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(isPrimary ? tokens.accentPrimary.opacity(skin.opacity.o30) : tokens.foreground.opacity(skin.opacity.o08))
        )
    }
}
