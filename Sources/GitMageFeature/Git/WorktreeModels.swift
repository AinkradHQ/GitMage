import Foundation

/// One entry from `git worktree list --porcelain`.
struct GitWorktree: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let head: String
    let branch: String?
    let isBare: Bool
    let isDetached: Bool
    let isLocked: Bool
    let isPrunable: Bool
}

/// The starting point for a newly added worktree.
enum WorktreeBase: Equatable {
    case newBranch(String)
    case existingBranch(String)
    case detached(ref: String)
}
