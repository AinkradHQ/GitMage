import AinkradAppKit
import SwiftUI

extension GitMageShell {
    var cloneSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clone a Repository").font(AinkradFont.display(skin.type.sizes.t18, weight: .semibold))
            Text("Enter a Git remote URL. You'll then choose a destination folder.")
                .font(AinkradFont.display(skin.type.sizes.t12)).foregroundStyle(tokens.foreground.opacity(skin.opacity.o70))
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
