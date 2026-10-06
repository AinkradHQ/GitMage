import AinkradAppKit
import SwiftUI

/// The comment box under a pull request or issue: a text area that submits on
/// return, a Comment button, and whatever else the screen puts beside it.
struct GMCommentComposer<Actions: View>: View {
    @Binding var text: String
    let isLoading: Bool
    let tokens: HostThemeTokens
    /// Posts the comment; the box clears once it returns.
    let comment: (String) async -> Void
    /// More buttons after Comment, in the same row.
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowRule(tokens: tokens)
            AinkradTextArea(
                text: $text, placeholder: "Leave a comment…", minHeight: 34, maxHeight: 80,
                onSubmit: {
                    guard !isLoading, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { return }
                    post()
                })
            HStack(spacing: 8) {
                AinkradButton(title: "Comment", style: .secondary, icon: "text.bubble") { post() }
                    .disabled(isLoading)
                actions()
            }
        }
        .padding(16)
    }

    private func post() {
        Task {
            await comment(text)
            text = ""
        }
    }
}
