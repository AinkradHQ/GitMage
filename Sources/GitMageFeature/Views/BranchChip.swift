import AinkradAppKit
import SwiftUI

/// Top-bar chip that opens the full-surface branch-management overlay.
struct BranchChip: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    var shortcut: String? = nil
    let onOpen: () -> Void

    var body: some View {
        TopBarChip(
            icon: "arrow.triangle.branch",
            label: model.snapshot?.branchName ?? "—",
            tooltip: "Branches",
            shortcut: shortcut,
            tokens: tokens,
            action: onOpen
        )
    }
}
