import Foundation

/// Another app asking Git Mage to show a repository — and, optionally, one of its commits. Forge sends it from
/// its git peek and its blame card. Its own payload kind on the launcher's opaque string, so apps that read
/// only `AinkradLaunchIntent` ignore it.
struct ShowLaunch: Codable, Equatable {
    static let kind = "showInGitMage"

    let kind: String
    /// The repository's top-level folder.
    let path: String
    /// A commit to select in History; nil shows the working tree's changes.
    var sha: String?
    /// The commit's subject, for the diff's title before history loads.
    var title: String?

    /// The payload, when it is one of these (anything else is not ours, and is not an error).
    static func decode(_ payload: String?) -> ShowLaunch? {
        guard let data = payload?.data(using: .utf8), let launch = try? JSONDecoder().decode(ShowLaunch.self, from: data),
            launch.kind == kind, !launch.path.isEmpty
        else { return nil }
        return launch
    }
}

extension GitMageViewModel {
    /// A payload sent with opening this pane: open its repository (adding it to the library if new), then its
    /// commit in History, or the Changes area.
    func handleLaunch(_ payload: String?) {
        guard let launch = ShowLaunch.decode(payload) else { return }
        openRepositoryPath(launch.path)
        guard let sha = launch.sha, !sha.isEmpty else { return selectArea(.changes) }
        selectArea(.history)
        selectCommit(
            GitCommitSummary(
                id: sha, shortSHA: String(sha.prefix(7)), summary: launch.title ?? "", author: "", relativeDate: ""))
    }
}
