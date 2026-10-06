import Foundation

/// Refuses to hand git any argument that would be read as an *option* unless
/// this codebase is the thing that wrote it.
///
/// ## Why this shape
///
/// git's option surface includes several flags that execute arbitrary commands:
/// `--upload-pack=<cmd>` and `--receive-pack=<cmd>` on remote operations,
/// `--exec=<cmd>` on rebase, `-c core.pager=<cmd>`, and the `ext::` transport
/// helper, whose entire purpose is running a shell command. Any of those
/// reaching git as a "branch name", "ref" or "clone URL" is remote code
/// execution — and every one of those values is user- or agent-supplied.
///
/// The obvious fix is `--` (or `--end-of-options`) at each call site. This
/// codebase already does that correctly for *file paths* — fourteen call sites
/// terminate options before a path. The gap was the ref/URL surface: `clone`,
/// `rebase`, `checkout`, `reset`, `cherry-pick`, `revert`, tags and worktrees
/// all interpolate a value straight into the argument vector.
///
/// Adding `--end-of-options` to twenty call sites would fix today's gap and
/// regress the first time someone adds the twenty-first. So the check lives in
/// `runGit` instead — the single choke point every git invocation passes
/// through — and it is an **allowlist**: every option string this codebase
/// actually uses is a compile-time literal, so they can be enumerated, and
/// anything else that looks like an option is by definition not ours.
///
/// A denylist would have been the wrong choice for exactly the reason the audit
/// found the original bug: it enumerates the attacks you thought of.
enum GitArgumentGuard {

    /// Exact option strings the callers in this module pass as literals.
    /// Keep in sync when adding a git invocation — a missing entry surfaces
    /// immediately as `unsafeArgument`, never as a silent bypass.
    static let allowedOptions: Set<String> = [
        // porcelain / plumbing selectors
        "--abbrev-ref", "--abort", "--all", "--autostash", "--branch", "--cached",
        "--continue", "--count", "--detach", "--ff-only", "--force", "--git-dir",
        "--include-untracked", "--list", "--name-only", "--no-color", "--no-edit",
        "--no-ext-diff", "--no-index", "--porcelain", "--prune", "--reason",
        "--short", "--show-toplevel", "--source=HEAD", "--staged",
        "--symbolic-full-name", "--topo-order", "--verify", "--worktree",
        // `git reset --<mode>`
        "--soft", "--mixed", "--hard", "--merge", "--keep",
        // option terminators — always safe, that is their job
        "--", "--end-of-options",
        // short flags
        "-1", "-a", "-A", "-b", "-C", "-d", "-f", "-m", "-p", "-r", "-u",
    ]

    /// Prefixes for options whose value is interpolated by this module
    /// (`--max-count=\(limit)`, `--pretty=format:…`). The *prefix* is ours; the
    /// interpolated tail is a number or a literal format string, never a
    /// user-supplied value.
    static let allowedOptionPrefixes: [String] = [
        "--format=", "--pretty=format:", "--max-count=", "--skip=", "--unified=",
    ]

    /// The first argument git would read as an option that this module did not
    /// author — or nil when every argument is safe.
    static func rejectedArgument(in arguments: [String]) -> String? {
        var optionsTerminated = false
        for argument in arguments {
            if argument == "--" || argument == "--end-of-options" {
                optionsTerminated = true
                continue
            }
            // After a terminator git treats everything as data, so a leading
            // dash is harmless there — but a transport helper is not an option
            // and is still dangerous, so that check stays unconditional.
            if isTransportHelper(argument) { return argument }
            guard !optionsTerminated else { continue }
            guard argument.hasPrefix("-") else { continue }
            if allowedOptions.contains(argument) { continue }
            if allowedOptionPrefixes.contains(where: { argument.hasPrefix($0) }) { continue }
            return argument
        }
        return nil
    }

    /// `ext::<command>` is git's escape hatch for a custom transport: git runs
    /// the command. It needs no leading dash, so the option check above cannot
    /// see it. `file://`-adjacent helpers (`ext`, `fd`) are rejected the same way.
    static func isTransportHelper(_ argument: String) -> Bool {
        let lowered = argument.lowercased()
        return lowered.hasPrefix("ext::") || lowered.hasPrefix("fd::")
    }

    // MARK: - Clone URLs

    /// Transports a clone URL may use.
    ///
    /// An allowlist rather than a denylist, for the same reason as the option
    /// check: git's transport surface is extensible (`remote-<helper>` binaries
    /// on PATH, plus the built-in `ext::`/`fd::` helpers that exist *to* run a
    /// command), so enumerating the dangerous ones enumerates only the ones we
    /// happened to think of.
    ///
    /// `file` is included deliberately — cloning a local repo is ordinary and
    /// runs no remote helper. `ssh`/`git`/`http(s)` are the real transports.
    static let allowedCloneSchemes: Set<String> = ["https", "http", "ssh", "git", "file"]

    /// Rejects a clone URL whose transport isn't allowlisted. Returns nil when
    /// the URL is acceptable.
    ///
    /// Accepts scp-style `user@host:path` (how `git@github.com:o/r.git` is
    /// written) and bare local paths, neither of which carries a scheme.
    static func rejectedCloneURL(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isTransportHelper(trimmed) { return trimmed }
        if trimmed.hasPrefix("-") { return trimmed }

        // `scheme://…` — the only form that names a transport explicitly.
        if let separator = trimmed.range(of: "://") {
            let scheme = String(trimmed[trimmed.startIndex..<separator.lowerBound]).lowercased()
            return allowedCloneSchemes.contains(scheme) ? nil : trimmed
        }
        // `helper::target` — any remaining `::` form is a transport helper we
        // did not allowlist above.
        if trimmed.contains("::") { return trimmed }
        // scp-style or a local path: no transport is being selected.
        return nil
    }
}
