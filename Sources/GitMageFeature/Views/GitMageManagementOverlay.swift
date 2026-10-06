import AinkradAppKit
import SwiftUI

/// Which management surface the full-screen overlay is showing.
enum GitMageManagementKind: Identifiable {
    case repos
    case branches
    var id: Int { self == .repos ? 0 : 1 }
}

// MARK: - Overlay host

/// Full-surface, dimmed HUD overlay hosting the repo/branch managers, in the
/// same visual language as the host Launcher & Settings overlays.
struct GitMageManagementOverlay: View {
    @ObservedObject var model: GitMageViewModel
    let tokens: HostThemeTokens
    let kind: GitMageManagementKind
    let dismiss: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                panel
                    .frame(width: min(max(620, geo.size.width * 0.5), 760))
                    .offset(y: -40)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.98).combined(with: .opacity),
                            removal: .opacity
                        ))
            }
        }
    }

    @ViewBuilder private var panel: some View {
        switch kind {
        case .repos:
            RepoManagerPanel(model: model, tokens: tokens, dismiss: dismiss)
        case .branches:
            BranchManagerPanel(model: model, tokens: tokens, dismiss: dismiss)
        }
    }
}
