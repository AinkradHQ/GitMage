import Foundation

enum NavArea: String, CaseIterable, Identifiable {
    case changes, history, stashes
    case pullRequests, issues, worktrees, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .changes: return "Changes"
        case .history: return "History"
        case .stashes: return "Stashes"
        case .pullRequests: return "Pull Requests"
        case .issues: return "Issues"
        case .worktrees: return "Worktrees"
        case .advanced: return "Advanced"
        }
    }

    /// SF Symbol name, tinted from theme at the call site.
    var icon: String {
        switch self {
        case .changes: return "square.and.pencil"
        case .history: return "clock.arrow.circlepath"
        case .stashes: return "tray.and.arrow.down"
        case .pullRequests: return "arrow.triangle.pull"
        case .issues: return "smallcircle.filled.circle"
        case .worktrees: return "rectangle.split.3x1"
        case .advanced: return "slider.horizontal.3"
        }
    }

    /// The rail order, which differs from declaration order.
    static var built: [NavArea] { [.changes, .history, .stashes, .pullRequests, .worktrees, .issues, .advanced] }
}
