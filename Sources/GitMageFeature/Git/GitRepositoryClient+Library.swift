import Foundation

extension GitRepositoryClient {
    /// Initializes a plain directory as a new git repository.
    func initRepository(at path: String) async throws {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw GitRepositoryError.pathDoesNotExist(path)
        }
        _ = try await runGit(["init"], in: URL(fileURLWithPath: expanded, isDirectory: true))
        rootCache[path] = nil
    }

    /// Clones `remoteURL` into `parentDirectory` and returns the new repository path.
    func clone(remoteURL: String, into parentDirectory: String) async throws -> String {
        let trimmedURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw GitRepositoryError.invalidRemoteURL }
        // Transport allowlist. `runGit`'s guard already blocks `ext::` and
        // leading-dash options, but a clone URL selects a *transport*, and git
        // will happily invoke any `git-remote-<helper>` on PATH for a scheme it
        // doesn't recognise. Checking here names the real constraint at the one
        // place a URL enters the system.
        if let rejected = GitArgumentGuard.rejectedCloneURL(trimmedURL) {
            throw GitRepositoryError.unsafeArgument(rejected)
        }

        let parentExpanded = (parentDirectory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentExpanded, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw GitRepositoryError.pathDoesNotExist(parentDirectory)
        }

        let parentURL = URL(fileURLWithPath: parentExpanded, isDirectory: true)
        let destinationURL = parentURL.appendingPathComponent(
            GitRepositoryClient.repositoryName(fromRemote: trimmedURL),
            isDirectory: true
        )
        _ = try await runGit(["clone", trimmedURL, destinationURL.path], in: parentURL)
        return destinationURL.path
    }

    static func repositoryName(fromRemote remote: String) -> String {
        var trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        if trimmed.hasSuffix(".git") { trimmed = String(trimmed.dropLast(4)) }
        let separators = CharacterSet(charactersIn: "/:")
        let components = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }
        return components.last ?? "repository"
    }

    func remoteInfo(in path: String) async throws -> RepoRef? {
        let rootURL = try await repositoryRootURL(for: path)
        let url = (try? await runGit(["remote", "get-url", "origin"], in: rootURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url, !url.isEmpty else { return nil }
        return RemoteInfoParser.parse(remoteURL: url)
    }
}
