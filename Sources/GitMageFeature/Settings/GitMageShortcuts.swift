import SwiftUI

/// Every user-triggerable command that can carry a keyboard shortcut.
enum GitMageCommand: String, CaseIterable, Identifiable {
    case openRepos, openBranches, fetch, pull, push
    case areaChanges, areaHistory, areaStashes
    case areaPullRequests, areaWorktrees, areaIssues, areaAdvanced

    var id: String { rawValue }

    /// Full label for Settings rows.
    var title: String {
        switch self {
        case .openRepos: return "Repositories overlay"
        case .openBranches: return "Branches overlay"
        case .fetch: return "Fetch"
        case .pull: return "Pull"
        case .push: return "Push"
        case .areaChanges: return "Go to Changes"
        case .areaHistory: return "Go to History"
        case .areaStashes: return "Go to Stashes"
        case .areaPullRequests: return "Go to Pull Requests"
        case .areaWorktrees: return "Go to Worktrees"
        case .areaIssues: return "Go to Issues"
        case .areaAdvanced: return "Go to Advanced"
        }
    }

    /// The area a "Go to …" command selects, else nil.
    var area: NavArea? {
        switch self {
        case .areaChanges: return .changes
        case .areaHistory: return .history
        case .areaStashes: return .stashes
        case .areaPullRequests: return .pullRequests
        case .areaWorktrees: return .worktrees
        case .areaIssues: return .issues
        case .areaAdvanced: return .advanced
        default: return nil
        }
    }

    var isAction: Bool { area == nil }

    /// Whether the command needs an active repository to run.
    var requiresRepo: Bool { self != .openRepos }

    /// Actions first (in bar order), then areas (in rail order).
    static var actions: [GitMageCommand] { [.openRepos, .openBranches, .fetch, .pull, .push] }
    static var areaCommands: [GitMageCommand] {
        [
            .areaChanges, .areaHistory, .areaStashes,
            .areaPullRequests, .areaWorktrees, .areaIssues, .areaAdvanced,
        ]
    }
}

/// A key + modifier combination, persisted and rendered on demand.
struct KeyChord: Codable, Equatable, Hashable {
    var key: String  // single, lowercased base character ("f", "1")
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    init(
        key: String, command: Bool = false, option: Bool = false,
        control: Bool = false, shift: Bool = false
    ) {
        self.key = key.lowercased()
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// Builds a chord from a captured key press; nil for keys without a
    /// representable character (pure modifiers, arrows, etc.).
    init?(_ press: KeyPress) {
        let ch = press.key.character
        guard ch.isLetter || ch.isNumber else { return nil }
        self.init(
            key: String(ch),
            command: press.modifiers.contains(.command),
            option: press.modifiers.contains(.option),
            control: press.modifiers.contains(.control),
            shift: press.modifiers.contains(.shift)
        )
    }

    var keyEquivalent: KeyEquivalent? {
        guard let ch = key.first else { return nil }
        return KeyEquivalent(ch)
    }

    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if command { m.insert(.command) }
        if option { m.insert(.option) }
        if control { m.insert(.control) }
        if shift { m.insert(.shift) }
        return m
    }

    /// Requires at least one modifier — bare keys are rejected to avoid
    /// hijacking typing.
    var hasModifier: Bool { command || option || control || shift }

    /// macOS-canonical glyph order: ⌃⌥⇧⌘ then the key.
    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        s += key.uppercased()
        return s
    }
}

/// The out-of-box bindings — ⌥⌘ everywhere; areas on ⌥⌘1…8 (rail order).
enum GitMageShortcutDefaults {
    static var map: [String: KeyChord] {
        [
            GitMageCommand.openRepos.rawValue: KeyChord(key: "o", command: true, option: true),
            GitMageCommand.openBranches.rawValue: KeyChord(key: "b", command: true, option: true),
            GitMageCommand.fetch.rawValue: KeyChord(key: "f", command: true, option: true),
            GitMageCommand.pull.rawValue: KeyChord(key: "l", command: true, option: true),
            GitMageCommand.push.rawValue: KeyChord(key: "u", command: true, option: true),
            GitMageCommand.areaChanges.rawValue: KeyChord(key: "1", control: true),
            GitMageCommand.areaHistory.rawValue: KeyChord(key: "2", control: true),
            GitMageCommand.areaStashes.rawValue: KeyChord(key: "3", control: true),
            GitMageCommand.areaPullRequests.rawValue: KeyChord(key: "4", control: true),
            GitMageCommand.areaWorktrees.rawValue: KeyChord(key: "5", control: true),
            GitMageCommand.areaIssues.rawValue: KeyChord(key: "6", control: true),
            GitMageCommand.areaAdvanced.rawValue: KeyChord(key: "7", control: true),
        ]
    }
}
