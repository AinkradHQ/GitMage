import Foundation

/// Legacy single-repo state (schema v1). Retained only so the library store can
/// migrate an existing install into the multi-repo library.
struct GitMageWorkspaceState: Codable, Equatable {
    var repositoryPath: String
    var draftCommitMessage: String

    init(repositoryPath: String = "", draftCommitMessage: String = "") {
        self.repositoryPath = repositoryPath
        self.draftCommitMessage = draftCommitMessage
    }
}

/// One repository the user has added to the Git Mage library. Persisted per repo
/// so switching between repos restores each one's draft and last selection.
struct GitMageRepoConfig: Codable, Identifiable, Equatable {
    var id: String
    var path: String
    var name: String
    var draftCommitMessage: String
    var lastBranch: String
    var lastSelectedFileID: String?

    init(
        id: String,
        path: String,
        name: String,
        draftCommitMessage: String = "",
        lastBranch: String = "",
        lastSelectedFileID: String? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.draftCommitMessage = draftCommitMessage
        self.lastBranch = lastBranch
        self.lastSelectedFileID = lastSelectedFileID
    }
}

/// The full Git Mage library (schema v2): every added repo plus the active one.
struct GitMageLibraryState: Codable, Equatable {
    var repos: [GitMageRepoConfig]
    var activeRepoID: String?

    init(repos: [GitMageRepoConfig] = [], activeRepoID: String? = nil) {
        self.repos = repos
        self.activeRepoID = activeRepoID
    }

    var activeRepo: GitMageRepoConfig? {
        guard let activeRepoID else { return nil }
        return repos.first { $0.id == activeRepoID }
    }
}

/// A single entry from `git stash list`.
struct GitStashEntry: Identifiable, Equatable {
    let id: String  // e.g. "stash@{0}"
    let message: String
}

/// One commit from `git log`, for the History area.
struct GitCommitSummary: Identifiable, Equatable {
    let id: String  // full SHA
    let shortSHA: String
    let summary: String
    let author: String
    let relativeDate: String
}

struct GitRepositorySnapshot: Equatable {
    let rootPath: String
    let branchName: String
    let upstream: String?
    let aheadCount: Int
    let behindCount: Int
    let lastCommitSummary: String?
    let changes: [GitChange]

    var headline: String {
        if let lastCommitSummary, !lastCommitSummary.isEmpty {
            return lastCommitSummary
        }
        return "No commits yet"
    }

    var statusSummary: String {
        guard !changes.isEmpty else { return "Clean" }
        let changeCount = changes.count
        let stagedCount = changes.filter(\.isIndexStaged).count
        let untrackedCount = changes.filter(\.isUntracked).count
        let pieces = [
            "\(changeCount) changed",
            stagedCount > 0 ? "\(stagedCount) staged" : nil,
            untrackedCount > 0 ? "\(untrackedCount) untracked" : nil,
        ].compactMap { $0 }
        return pieces.joined(separator: " · ")
    }
}

struct GitBranchSummary: Identifiable, Equatable {
    let name: String
    let upstream: String?
    let isCurrent: Bool
    let tracking: String?

    var id: String { name }

    var subtitle: String {
        if let tracking, !tracking.isEmpty {
            return tracking
        }
        if let upstream, !upstream.isEmpty {
            return upstream
        }
        return isCurrent ? "current branch" : "local branch"
    }
}

struct GitDiffSnapshot: Equatable {
    let title: String
    let body: String
    let isEmpty: Bool

    /// A diff from raw `git` output; blank output reads "No diff available." and is flagged empty.
    init(title: String, output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: title, body: trimmed.isEmpty ? "No diff available." : trimmed, isEmpty: trimmed.isEmpty)
    }

    init(title: String, body: String, isEmpty: Bool) {
        self.title = title
        self.body = body
        self.isEmpty = isEmpty
    }
}

struct GitChange: Identifiable, Equatable {
    let id: String
    let path: String
    let filePath: String
    let sourcePath: String?
    let statusCode: String
    let kind: GitChangeKind

    var isUntracked: Bool { kind == .untracked }
    var isIndexStaged: Bool {
        guard !isUntracked, kind != .ignored else { return false }
        return statusCode.first != " "
    }
    var canUnstage: Bool {
        isIndexStaged && kind != .conflicted
    }

    /// True when the index column (statusCode[0]) reflects a staged change.
    var hasStagedComponent: Bool {
        guard kind != .ignored, !isUntracked else { return false }
        let idx = statusCode.first ?? " "
        return idx != " " && idx != "?"
    }

    /// True when the worktree column (statusCode[1]) reflects an unstaged change,
    /// or the file is untracked (its entire content is "unstaged").
    var hasUnstagedComponent: Bool {
        if isUntracked { return true }
        guard kind != .ignored else { return false }
        let chars = Array(statusCode)
        let work = chars.count > 1 ? chars[1] : " "
        return work != " "
    }
}

enum GitChangeKind: Equatable {
    case staged
    case modified
    case untracked
    case renamed
    case deleted
    case conflicted
    case ignored
}
