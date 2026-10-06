import AinkradAppKit
import Foundation

/// The minimal read-only surface `GitMageContextBridge` needs from the active
/// GitMage view model. A protocol (not the concrete VM) so the bridge is
/// unit-testable without a live model. Class-constrained so the bridge can hold
/// it weakly and compare identity.
@MainActor
protocol GitContextSource: AnyObject {
    /// The active repository snapshot, or nil when no repo is active.
    func agentRepositorySnapshot() -> GitRepositorySnapshot?
    /// Display name of the active repo, if known (else the bridge derives one).
    func agentRepositoryName() -> String?
}

/// Per-host bridge that publishes the active repo's status as read-only agent
/// context. Registered once per host by `GitMageRuntime`; holds a weak
/// reference to the currently-shown shell's view model and reads it on demand.
/// Returns nil when no source is active or no repo is loaded — so a torn-down
/// shell simply produces no context, with no teardown call needed.
@MainActor
final class GitMageContextBridge {
    private weak var activeSource: (any GitContextSource)?

    func setActiveSource(_ source: any GitContextSource) {
        activeSource = source
    }

    /// Clears only if `source` is still the active one — so a late-disappearing
    /// shell can't wipe a newer shell's registration.
    func clearActiveSource(_ source: any GitContextSource) {
        if activeSource === source { activeSource = nil }
    }

    func snapshot() -> AgentContextSnapshot? {
        guard let source = activeSource, let repo = source.agentRepositorySnapshot() else { return nil }
        let name = source.agentRepositoryName() ?? (repo.rootPath as NSString).lastPathComponent
        let branchPart: String
        let ab = aheadBehind(ahead: repo.aheadCount, behind: repo.behindCount)
        branchPart = ab.isEmpty ? repo.branchName : "\(repo.branchName)(\(ab))"
        let text = "\(repo.rootPath) · \(branchPart) · \(repo.statusSummary)\nHEAD: \(repo.headline)"
        return AgentContextSnapshot(kind: "git", title: "Git — \(name)", text: text)
    }

    private func aheadBehind(ahead: Int, behind: Int) -> String {
        var parts: [String] = []
        if ahead > 0 { parts.append("+\(ahead)") }
        if behind > 0 { parts.append("-\(behind)") }
        return parts.joined(separator: "/")
    }
}

extension GitMageViewModel: GitContextSource {
    func agentRepositorySnapshot() -> GitRepositorySnapshot? { snapshot }
    func agentRepositoryName() -> String? { activeRepo?.name }
}
