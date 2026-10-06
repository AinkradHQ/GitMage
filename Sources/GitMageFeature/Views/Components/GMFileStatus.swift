import AinkradAppKit
import SwiftUI

/// The single-letter badge and colour for a changed file, shared by the
/// working-tree rows and the pull-request file list.
enum GMFileStatus {
    case added, modified, deleted, renamed, conflicted, ignored

    var letter: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .conflicted: return "C"
        case .ignored: return "I"
        }
    }

    func color(_ tokens: HostThemeTokens) -> Color {
        switch self {
        case .added: return GMColor.diffAdd(tokens)
        case .deleted: return GMColor.diffRemove(tokens)
        case .conflicted, .modified: return tokens.accentTertiary
        case .renamed: return tokens.accentSecondary
        case .ignored: return tokens.foreground.opacity(0.4)
        }
    }

    init(_ kind: GitChangeKind) {
        switch kind {
        case .untracked: self = .added
        case .modified, .staged: self = .modified
        case .deleted: self = .deleted
        case .renamed: self = .renamed
        case .conflicted: self = .conflicted
        case .ignored: self = .ignored
        }
    }

    /// From a forge file status ("added", "removed", "renamed", anything else is a modification).
    init(forgeStatus: String) {
        switch forgeStatus.lowercased() {
        case "added": self = .added
        case "removed": self = .deleted
        case "renamed": self = .renamed
        default: self = .modified
        }
    }
}
