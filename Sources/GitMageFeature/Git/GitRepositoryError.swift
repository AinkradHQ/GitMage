import Foundation

enum GitRepositoryError: Error, LocalizedError, Equatable {
    case missingPath
    case pathDoesNotExist(String)
    case notARepository(String)
    case invalidCommitMessage
    case invalidBranchName
    case invalidTagName
    case invalidRemoteURL
    case nothingToCommit
    case detachedHead
    case commandFailed(String)
    /// An argument git would read as an option (or a transport helper) that
    /// this module did not author — see `GitArgumentGuard`.
    case unsafeArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingPath:
            return "Select a repository path first."
        case .pathDoesNotExist(let path):
            return "Path does not exist: \(path)"
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .invalidCommitMessage:
            return "Enter a non-empty commit message."
        case .invalidBranchName:
            return "Enter a non-empty branch name."
        case .invalidTagName:
            return "Enter a non-empty tag name."
        case .invalidRemoteURL:
            return "Enter a repository URL to clone."
        case .nothingToCommit:
            return "There are no staged changes to commit."
        case .detachedHead:
            return "You are not on a branch (detached HEAD). Check out a branch first."
        case .commandFailed(let message):
            return message
        case .unsafeArgument(let argument):
            return "Refused: \"\(argument)\" would be read by git as an option, not as a value."
        }
    }
}
