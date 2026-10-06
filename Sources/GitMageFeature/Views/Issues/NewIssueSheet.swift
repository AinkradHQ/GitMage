import AinkradAppKit
import SwiftUI

/// Sheet for composing a new issue: title, body, and optional labels/assignees.
struct NewIssueSheet: View {
    @ObservedObject var model: IssuesViewModel
    let tokens: HostThemeTokens

    private var canCreate: Bool {
        !model.newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Issue").font(AinkradFont.display(18, weight: .semibold))

            AinkradTextField(text: $model.newTitle, placeholder: "Title")

            AinkradTextArea(text: $model.newBody, placeholder: "Description…")

            HStack(spacing: 10) {
                labelsMenu
                assigneesMenu
            }

            HStack {
                Spacer()
                AinkradButton(title: "Cancel", style: .secondary) { model.showNew = false }
                AinkradButton(title: "Create", style: .primary) { Task { await model.create() } }
                    .disabled(!canCreate || model.isLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(tokens.foreground)
    }

    private var labelsMenu: some View {
        AinkradMultiSelect(
            items: model.repoLabels.map(\.name),
            selection: $model.newLabels,
            label: { $0 },
            swatch: { name in
                model.repoLabels.first { $0.name == name }.flatMap { Color(hex: $0.color) }  // design-lint: allow hex-color GitHub label data
            }
        )
    }

    private var assigneesMenu: some View {
        AinkradMultiSelect(
            items: model.assignableUsers.map(\.login),
            selection: $model.newAssignees,
            label: { $0 }
        )
    }
}
