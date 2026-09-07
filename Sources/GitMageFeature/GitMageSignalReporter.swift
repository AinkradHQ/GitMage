import Foundation
import AinkradAppKit

/// Git Mage's notification vocabulary, in one place so the kinds stay
/// consistent and every emission decision is visible together.
///
/// **Derived from `GitMageViewModel.run(context:)`**, which every mutating git
/// operation already funnels through — fetch, pull, push, merge, rebase,
/// stash. That single choke point is why this is three kinds rather than one
/// per command: the operation's own name is data, not a taxonomy.
@MainActor
struct GitMageSignalReporter {
    let signals: PluginSignalEmitter

    /// How long an operation must take before its SUCCESS is worth a row.
    ///
    /// A 200ms `git status` refresh is not news. A four-minute clone or a push
    /// of a large branch is exactly the thing the user started and walked away
    /// from — which is the same editorial rule Raven's mail arrival and Lore's
    /// imports follow, and the one the M2 plan states for adopters generally.
    static let successThreshold: TimeInterval = 20

    /// A git operation failed.
    ///
    /// Always reported, whatever the duration: a failed push is a failed push
    /// whether it took a second or a minute, and the user's next action
    /// depends on knowing.
    ///
    /// Deduped per operation and repository, so a push that fails on every
    /// retry coalesces into one row with a count rather than filling the feed
    /// with the same authentication problem.
    func operationFailed(operation: String, repository: String, reason: String) {
        signals.emit(
            kind: "git.operation-failed",
            severity: .failure,
            title: "git \(operation) failed in \(Self.name(of: repository))",
            body: reason,
            // Not `.urgent`: the repository is not in a broken state, the
            // command simply did not run, and the user can act when they look.
            importance: .normal,
            dedupeKey: "gitmage.failed:\(repository):\(operation)")
    }

    /// A long operation finished cleanly.
    ///
    /// Reported ONLY past `successThreshold`. Nothing calls this for a short
    /// operation — see `GitMageViewModel.run(context:)`.
    func operationFinished(operation: String, repository: String, duration: TimeInterval) {
        signals.emit(
            kind: "git.operation-finished",
            severity: .success,
            title: "git \(operation) finished in \(Self.name(of: repository))",
            body: "Took \(Int(duration.rounded())) seconds.",
            importance: .normal,
            dedupeKey: "gitmage.finished:\(repository):\(operation)")
    }

    /// The working tree came out of an operation with conflicts.
    ///
    /// **The one `.urgent` kind here, and the reason this adoption is worth
    /// doing at all.** A conflict is not a failure — the command did what it
    /// was asked — but it leaves the repository in a state where nothing else
    /// can proceed until a human resolves it. A pull started before lunch that
    /// conflicted is the archetypal case: the user believes they are up to
    /// date, and every later command fails confusingly until they discover it.
    ///
    /// Deduped per repository rather than per operation: a repository has one
    /// conflicted state, however it got there, and two rows for one situation
    /// would be two things to resolve rather than one.
    func conflictsDetected(operation: String, repository: String, files: [String]) {
        guard !files.isEmpty else { return }
        let listed = files.prefix(5).joined(separator: ", ")
        let extra = files.count > 5 ? " and \(files.count - 5) more" : ""

        signals.emit(
            kind: "git.conflict",
            severity: .warning,
            title: "\(Self.name(of: repository)) has \(files.count) "
                + "conflicted file\(files.count == 1 ? "" : "s")",
            body: "git \(operation) left conflicts in \(listed)\(extra). "
                + "Nothing else will apply cleanly until these are resolved.",
            importance: .urgent,
            dedupeKey: "gitmage.conflict:\(repository)")
    }

    /// The repository's last path component — "AinkradRaven", not the whole
    /// absolute path. A notification title is read at a glance, and a
    /// full path pushes the part that identifies the repo off the end.
    private static func name(of repositoryPath: String) -> String {
        let trimmed = repositoryPath.hasSuffix("/")
            ? String(repositoryPath.dropLast())
            : repositoryPath
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? repositoryPath : name
    }
}
