import AinkradAppKit
import SwiftUI

// MARK: - Keyboard shortcut dispatch

/// An invisible layer of zero-size buttons, one per bound command, each
/// carrying its `.keyboardShortcut`. Placed in the shell background so the
/// bindings fire window-wide without depending on which control is on screen.
struct ShortcutLayer: View {
    let shortcuts: [String: KeyChord]
    let hasActiveRepo: Bool
    let perform: (GitMageCommand) -> Void

    var body: some View {
        ZStack {
            ForEach(GitMageCommand.allCases) { command in
                if let chord = shortcuts[command.rawValue],
                    chord.hasModifier,
                    let equivalent = chord.keyEquivalent
                {
                    Button(action: { perform(command) }) { Color.clear.frame(width: 0, height: 0) }
                        .buttonStyle(.plain)
                        .frame(width: 0, height: 0)
                        .keyboardShortcut(equivalent, modifiers: chord.eventModifiers)
                        .disabled(command.requiresRepo && !hasActiveRepo)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}
