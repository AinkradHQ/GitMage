import AinkradAppKit
import SwiftUI

extension GitMageShell {
    var cloneSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clone a Repository").font(AinkradFont.display(18, weight: .semibold))
            Text("Enter a Git remote URL. You'll then choose a destination folder.")
                .font(AinkradFont.display(12)).foregroundStyle(tokens.foreground.opacity(0.7))
            AinkradTextField(
                text: $model.cloneRemoteURL,
                placeholder: "https://github.com/owner/repo.git"
            )
            .frame(minWidth: 380)
            HStack {
                Spacer()
                AinkradButton(title: "Cancel", style: .secondary) { model.showClonePrompt = false }
                AinkradButton(title: "Choose Destination & Clone", style: .primary) { model.performClone() }
                    .disabled(model.cloneRemoteURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(tokens.foreground)
    }
}
