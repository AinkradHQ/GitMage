import Foundation
import Testing

@testable import GitMageFeature

@Suite("Git Mage — forge date formatting")
struct ForgeDateTests {

    @Test("An empty string stays empty")
    func empty() {
        #expect(ForgeDate.short("") == "")
    }

    @Test("A GitHub timestamp becomes 'MMM d, yyyy'")
    func formatsATimestamp() {
        // Built from local noon so the expectation holds in any time zone.
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 7
        parts.day = 1
        parts.hour = 12
        let date = Calendar.current.date(from: parts)!
        let iso = ISO8601DateFormatter().string(from: date)
        #expect(ForgeDate.short(iso) == "Jul 1, 2026")
    }

    @Test("Text that is not a plain ISO-8601 timestamp is returned unchanged")
    func unparseableIsEchoed() {
        #expect(ForgeDate.short("yesterday") == "yesterday")
        #expect(ForgeDate.short("2026-07-01") == "2026-07-01")
        #expect(ForgeDate.short("2026-07-01T12:00:00.123Z") == "2026-07-01T12:00:00.123Z", "fractional seconds are not parsed")
    }
}

@Suite("Git Mage — default shortcuts")
struct GitMageShortcutDefaultsTests {

    @Test("Every command has a default, and nothing else does")
    func coversEveryCommand() {
        #expect(Set(GitMageShortcutDefaults.map.keys) == Set(GitMageCommand.allCases.map(\.rawValue)))
    }

    @Test("Every default carries a modifier and no two commands share a chord")
    func modifiersAndUniqueness() {
        let chords = Array(GitMageShortcutDefaults.map.values)
        #expect(chords.allSatisfy { $0.hasModifier })
        #expect(Set(chords).count == chords.count)
    }

    @Test("Actions sit on option-command letters, as shown in the Settings rows")
    func actionBindings() {
        let map = GitMageShortcutDefaults.map
        let expected: [(GitMageCommand, String)] = [
            (.openRepos, "⌥⌘O"), (.openBranches, "⌥⌘B"), (.fetch, "⌥⌘F"), (.pull, "⌥⌘L"), (.push, "⌥⌘U"),
        ]
        for (command, display) in expected { #expect(map[command.rawValue]?.display == display) }
    }

    @Test("Areas sit on control-1 to control-7 in rail order")
    func areaBindings() {
        let map = GitMageShortcutDefaults.map
        let areas = GitMageCommand.areaCommands
        #expect(areas.count == 7)
        for (offset, command) in areas.enumerated() {
            #expect(map[command.rawValue]?.display == "⌃\(offset + 1)", "\(command.rawValue)")
        }
    }
}
