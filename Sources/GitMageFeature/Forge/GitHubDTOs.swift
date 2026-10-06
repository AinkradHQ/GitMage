import Foundation

// GitHub REST v3 wire types. Decoded with `JSONDecoder.keyDecodingStrategy =
// .convertFromSnakeCase`, so property names here are camelCase and no
// explicit CodingKeys are declared (that would double-convert).

struct GHUser: Codable {
    let login: String

    func toModel() -> ForgeUser {
        ForgeUser(login: login)
    }
}

struct GHRef: Codable {
    let ref: String
}

struct GHPull: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let draft: Bool?
    let user: GHUser
    let createdAt: String?
    let head: GHRef
    let base: GHRef
    let mergeable: Bool?
    let mergeableState: String?
    let additions: Int?
    let deletions: Int?

    func toSummary() -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            number: number,
            title: title,
            author: user.login,
            state: state,
            isDraft: draft ?? false,
            headBranch: head.ref,
            baseBranch: base.ref
        )
    }

    func toDetail() -> PullRequestDetail {
        PullRequestDetail(
            number: number,
            title: title,
            body: body ?? "",
            state: state,
            isDraft: draft ?? false,
            author: user.login,
            createdAt: createdAt ?? "",
            mergeable: mergeable,
            mergeableState: mergeableState ?? "unknown",
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            headBranch: head.ref,
            baseBranch: base.ref
        )
    }
}

struct GHPRCommit: Codable {
    let sha: String
    let commit: CommitInfo
    let author: GHUser?

    struct CommitInfo: Codable {
        let message: String
        let author: CommitAuthor
    }
    struct CommitAuthor: Codable {
        let name: String
        let date: String
    }

    func toModel() -> PRCommit {
        let firstLine = commit.message.split(separator: "\n").first.map(String.init) ?? commit.message
        return PRCommit(
            sha: sha,
            shortSHA: String(sha.prefix(7)),
            message: firstLine,
            author: author?.login ?? commit.author.name,
            date: commit.author.date
        )
    }
}

struct GHComment: Codable {
    let id: Int
    let user: GHUser
    let body: String
    let createdAt: String

    func toModel() -> ForgeComment {
        ForgeComment(id: id, author: user.login, body: body, createdAt: createdAt)
    }
}

struct GHFile: Codable {
    let filename: String
    let status: String
    let patch: String?

    func toModel() -> PRFile {
        PRFile(filename: filename, status: status, patch: patch)
    }
}

struct GHCheckRun: Codable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?

    func toModel() -> CheckRun {
        CheckRun(id: id, name: name, status: status, conclusion: conclusion)
    }
}

struct GHCheckRunsEnvelope: Codable {
    let checkRuns: [GHCheckRun]
}

struct GHLabel: Codable {
    let name: String
    let color: String

    func toModel() -> IssueLabel {
        IssueLabel(name: name, color: color)
    }
}

struct GHPullRequestMarker: Codable {}  // presence indicates the "issue" is actually a PR

/// Envelope returned by `GET /search/issues` (total_count → totalCount).
struct GHSearchEnvelope: Codable {
    let totalCount: Int
    let items: [GHIssue]
}

struct GHIssue: Codable {
    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: GHUser
    let labels: [GHLabel]
    let assignees: [GHUser]
    let comments: Int
    let createdAt: String?
    let draft: Bool?  // present on PR items from the search API
    let pullRequest: GHPullRequestMarker?  // JSON "pull_request" via convertFromSnakeCase

    var isPullRequest: Bool { pullRequest != nil }

    func toSummary() -> IssueSummary {
        IssueSummary(
            id: number, number: number, title: title, author: user.login,
            state: state, labelNames: labels.map { $0.name }, commentCount: comments)
    }

    /// Maps a search-API PR item to a list summary. Head/base branches are not
    /// returned by search — the detail fetch on select fills them in.
    func toPRSummary() -> PullRequestSummary {
        PullRequestSummary(
            id: number, number: number, title: title, author: user.login,
            state: state, isDraft: draft ?? false, headBranch: "", baseBranch: "")
    }

    func toDetail() -> IssueDetail {
        IssueDetail(
            number: number, title: title, body: body ?? "", state: state,
            author: user.login, createdAt: createdAt ?? "",
            labels: labels.map { $0.toModel() },
            assignees: assignees.map { $0.login })
    }
}
