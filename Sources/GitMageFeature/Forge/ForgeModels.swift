import Foundation

/// Formats GitHub ISO-8601 timestamps for display (e.g. "Jul 1, 2026").
enum ForgeDate {
    static func short(_ isoString: String) -> String {
        guard !isoString.isEmpty else { return "" }
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: isoString) else { return isoString }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }
}

/// Identifies a forge (e.g. GitHub) repository by host/owner/name, parsed from
/// a git remote URL. Used to gate forge-backed features (like Pull Requests)
/// to repositories with a recognized origin remote.
struct RepoRef: Equatable {
    let host: String
    let owner: String
    let name: String
}

enum PRState: String, Codable {
    case open
    case closed
    case all
}

enum ReviewEvent: String {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}

enum MergeMethod: String, CaseIterable {
    case merge
    case squash
    case rebase
}

struct ForgeUser: Equatable {
    let login: String
}

/// One page of a forge search: the items plus the total match count, so the
/// UI can show "loaded / total" and know whether more pages remain.
struct ForgePage<Item> {
    let items: [Item]
    let totalCount: Int
}

struct PullRequestSummary: Identifiable, Equatable {
    let id: Int
    let number: Int
    let title: String
    let author: String
    let state: String
    let isDraft: Bool
    let headBranch: String
    let baseBranch: String
}

struct PullRequestDetail: Equatable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let isDraft: Bool
    let author: String
    let createdAt: String
    let mergeable: Bool?
    let mergeableState: String
    let additions: Int
    let deletions: Int
    let headBranch: String
    let baseBranch: String
}

/// One commit on a pull request.
struct PRCommit: Identifiable, Equatable {
    let sha: String
    let shortSHA: String
    let message: String  // first line of the commit message
    let author: String
    let date: String
    var id: String { sha }
}

struct ForgeComment: Identifiable, Equatable {
    let id: Int
    let author: String
    let body: String
    let createdAt: String
}

struct PRFile: Identifiable, Equatable {
    var id: String { filename }
    let filename: String
    let status: String
    let patch: String?
}

struct CheckRun: Identifiable, Equatable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
}

enum IssueState: String, Codable {
    case open
    case closed
    case all
}

struct IssueLabel: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let color: String
}

struct IssueSummary: Identifiable, Equatable {
    let id: Int
    let number: Int
    let title: String
    let author: String
    let state: String
    let labelNames: [String]
    let commentCount: Int
}

struct IssueDetail: Equatable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let author: String
    let createdAt: String
    let labels: [IssueLabel]
    let assignees: [String]
}
