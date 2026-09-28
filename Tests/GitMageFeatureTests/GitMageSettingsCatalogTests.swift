import XCTest
import AppKit
import AinkradAppKit
@testable import GitMageFeature

@MainActor
final class GitMageSettingsCatalogTests: XCTestCase {
    private func page(_ store: GitMageSettingsStore, _ state: GitMageSettingsPageState = .init()) -> SettingsPage {
        GitMageSettingsCatalog.page(store: store, state: state, host: FakeHostServices(context: RecordingContextRegistry()))
    }

    /// Declared tabs, no custom rows; "Appearance" is the group the host
    /// merges into its own Appearance tab.
    func testPageIsDeclared() {
        let p = page(GitMageSettingsStore(documents: MemoryDocumentStore()))
        XCTAssertEqual(p.groups.map(\.title), ["Appearance", "Typography", "Shortcuts", "GitHub"])
        XCTAssertFalse(p.groups.flatMap(\.fields).contains { if case .custom = $0.kind { true } else { false } })
    }

    func testOpacitySliderWritesThroughAndResets() throws {
        let store = GitMageSettingsStore(documents: MemoryDocumentStore())
        let field = try XCTUnwrap(page(store).groups[0].fields.first { $0.label == "Background opacity" })
        guard case .slider(_, _, let value) = field.kind else { return XCTFail("not a slider") }
        value.wrappedValue = 0.5
        XCTAssertEqual(store.settings.backgroundOpacity, 0.5)
        XCTAssertTrue(field.isModified())
        field.reset?()
        XCTAssertEqual(store.settings.backgroundOpacity, 1.0)
    }

    /// Recording a combination another command uses moves it here and says so.
    func testAssigningATakenChordMovesItAndNotes() throws {
        let store = GitMageSettingsStore(documents: MemoryDocumentStore())
        let (taken, owner) = try XCTUnwrap(store.settings.shortcuts.first)
        let owningCommand = try XCTUnwrap(GitMageCommand(rawValue: taken))
        let target = try XCTUnwrap(GitMageCommand.actions.first { $0 != owningCommand })
        let state = GitMageSettingsPageState()
        state.assign(owner, to: target, in: store)
        XCTAssertEqual(store.settings.shortcuts[target.rawValue], owner)
        XCTAssertNil(store.settings.shortcuts[taken])
        XCTAssertEqual(state.reassignNote, "\(owner.display) reassigned from \(owningCommand.title) — now unbound.")
    }

    func testChordFromAKeyEvent() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: 0, context: nil, characters: "P", charactersIgnoringModifiers: "p",
            isARepeat: false, keyCode: 35))
        XCTAssertEqual(KeyChord(event), KeyChord(key: "p", command: true, shift: true))
    }
}
