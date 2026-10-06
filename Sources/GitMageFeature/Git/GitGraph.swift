import Foundation

/// A commit with its parent SHAs — the input to the commit-graph lane layout.
struct GraphCommit: Identifiable, Equatable {
    let sha: String
    let shortSHA: String
    let summary: String
    let author: String
    let relativeDate: String
    let parents: [String]
    var id: String { sha }
}

/// A laid-out graph row: the commit, its node column, and the lane occupancy
/// entering from above (`before`) and exiting below (`after`), keyed by column.
/// `before[i] == previous row's after[i]`, so lanes connect across rows.
struct GraphRow: Identifiable {
    let commit: GraphCommit
    let col: Int
    let before: [String?]
    let after: [String?]
    var id: String { commit.sha }
    var laneCount: Int { max(before.count, after.count, col + 1) }
}

/// Assigns each commit a column and tracks branch/merge lanes — the classic
/// git-graph layout. Commits must be newest-first (as `git log` returns them).
enum GitGraphBuilder {
    static func build(_ commits: [GraphCommit]) -> [GraphRow] {
        var lanes: [String?] = []  // sha each column is currently waiting for
        var rows: [GraphRow] = []

        for commit in commits {
            let before = lanes  // == previous row's `after`
            let sha = commit.sha

            // The node's column: a lane already waiting for it, else a new lane.
            let col: Int
            if let existing = lanes.firstIndex(of: sha) {
                col = existing
            } else if let empty = lanes.firstIndex(where: { $0 == nil }) {
                col = empty
                lanes[col] = sha
            } else {
                col = lanes.count
                lanes.append(sha)
            }

            // Every lane waiting for this sha collapses into the node.
            for i in lanes.indices where lanes[i] == sha { lanes[i] = nil }

            // Place parents so that EACH sha occupies exactly one lane — a
            // parent already tracked keeps its lane (no duplicate column, which
            // was the cause of crossed/disconnected connectors). The first
            // parent prefers the node's own column.
            for (k, parent) in commit.parents.enumerated() {
                if lanes.contains(parent) { continue }
                if k == 0, lanes[col] == nil {
                    lanes[col] = parent
                } else if let empty = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[empty] = parent
                } else {
                    lanes.append(parent)
                }
            }
            while let last = lanes.last, last == nil { lanes.removeLast() }

            rows.append(GraphRow(commit: commit, col: col, before: before, after: lanes))
        }
        return rows
    }
}

/// Parses `git log` output formatted with a unit-separator (\u{1f}) between
/// fields: sha, shortSHA, summary, author, relative date, space-joined parents.
enum GitGraphParser {
    static func parse(_ output: String) -> [GraphCommit] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { rawLine in
            let fields = String(rawLine).components(separatedBy: "\u{1f}")
            guard fields.count >= 5 else { return nil }
            let parents =
                fields.count >= 6
                ? fields[5].split(separator: " ").map(String.init)
                : []
            return GraphCommit(
                sha: fields[0], shortSHA: fields[1], summary: fields[2],
                author: fields[3], relativeDate: fields[4], parents: parents
            )
        }
    }
}
