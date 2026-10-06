import AinkradAppKit
import AppKit
import SwiftUI

/// Git Mage's settings as DECLARED fields, so the host draws them in the shared
/// settings style. Its "Appearance" group is merged by the host into the one
/// Appearance tab (after Open as / Open in, before Blur).
@MainActor
enum GitMageSettingsCatalog {
    static func page(
        store: GitMageSettingsStore, state: GitMageSettingsPageState,
        host: HostServices
    ) -> SettingsPage {
        let root = SettingsPath([GitMageApp.id])
        return SettingsPage(
            path: root, title: GitMageApp.displayName, icon: GitMageApp.icon,
            group: .installedApps, order: 0,
            groups: [
                appearance(store, root), typography(store, root),
                shortcuts(store, state, root), github(state, host, root),
            ],
            appID: GitMageApp.id)
    }

    private static let defaults = GitMageSettings()

    private static func appearance(_ store: GitMageSettingsStore, _ root: SettingsPath) -> SettingsGroup {
        let group = root.appending("appearance")
        let s = store.settings
        return SettingsGroup(
            path: group, title: "Appearance",
            fields: [
                SettingsField(
                    path: group.appending("opacity"), label: "Background opacity",
                    help: "\(Int(s.backgroundOpacity * 100))%. Below 100%, the workspace backdrop shows through.",
                    keywords: ["opacity", "transparency", "translucent", "background"],
                    kind: .slider(
                        range: 0.2...1.0, step: 0.05,
                        value: Binding(
                            get: { store.settings.backgroundOpacity },
                            set: { v in store.update { $0.backgroundOpacity = v } })),
                    defaultDescription: "100%",
                    isModified: { store.settings.backgroundOpacity != defaults.backgroundOpacity },
                    reset: { store.update { $0.backgroundOpacity = defaults.backgroundOpacity } }),
                SettingsField(
                    path: group.appending("accent"), label: "Follow theme accent",
                    help: "Use the workspace accent colour for Git Mage's highlights.",
                    keywords: ["accent", "colour", "color", "theme"],
                    kind: .toggle(
                        Binding(
                            get: { store.settings.followThemeAccent },
                            set: { v in store.update { $0.followThemeAccent = v } })),
                    defaultDescription: "On",
                    isModified: { store.settings.followThemeAccent != defaults.followThemeAccent },
                    reset: { store.update { $0.followThemeAccent = defaults.followThemeAccent } }),
            ])
    }

    private static func typography(_ store: GitMageSettingsStore, _ root: SettingsPath) -> SettingsGroup {
        let group = root.appending("typography")
        let s = store.settings
        func font(
            _ id: String, _ label: String, _ options: [String],
            _ key: WritableKeyPath<GitMageSettings, String>
        ) -> SettingsField {
            SettingsField(
                path: group.appending(id), label: label, keywords: ["font", "typeface", label.lowercased()],
                kind: .select(
                    options: options.map { SettingsOption(id: $0, title: $0) },
                    selection: Binding(
                        get: { store.settings[keyPath: key] },
                        set: { v in store.update { $0[keyPath: key] = v } })),
                defaultDescription: defaults[keyPath: key],
                isModified: { store.settings[keyPath: key] != defaults[keyPath: key] },
                reset: { store.update { $0[keyPath: key] = defaults[keyPath: key] } })
        }
        return SettingsGroup(
            path: group, title: "Typography",
            fields: [
                SettingsField(
                    path: group.appending("scale"), label: "Text size",
                    help: "\(Int(s.textScale * 100))%. Scales every text in Git Mage.",
                    keywords: ["text", "size", "scale", "zoom"],
                    kind: .slider(
                        range: 0.8...1.3, step: 0.05,
                        value: Binding(
                            get: { store.settings.textScale },
                            set: { v in store.update { $0.textScale = (v * 20).rounded() / 20 } })),
                    defaultDescription: "100%",
                    isModified: { store.settings.textScale != defaults.textScale },
                    reset: { store.update { $0.textScale = defaults.textScale } }),
                SettingsField(
                    path: group.appending("diff-size"), label: "Diff text size",
                    help: "\(Int(s.diffFontSize)) pt, for the diff and code views.",
                    keywords: ["diff", "size", "code"],
                    kind: .slider(
                        range: 9...20, step: 1,
                        value: Binding(
                            get: { store.settings.diffFontSize },
                            set: { v in store.update { $0.diffFontSize = v.rounded() } })),
                    defaultDescription: "\(Int(defaults.diffFontSize)) pt",
                    isModified: { store.settings.diffFontSize != defaults.diffFontSize },
                    reset: { store.update { $0.diffFontSize = defaults.diffFontSize } }),
                font("display", "Display font", AinkradFont.displayFamilies, \.displayFontName),
                font("mono", "Mono font", AinkradFont.monoFamilies, \.monoFontName),
            ])
    }

    // MARK: - Shortcuts

    private static func shortcuts(
        _ store: GitMageSettingsStore, _ state: GitMageSettingsPageState,
        _ root: SettingsPath
    ) -> SettingsGroup {
        let group = root.appending("shortcuts")
        var fields = [
            SettingsField(
                path: group.appending("reset"), label: "Reset shortcuts",
                help: "Restore every command's default combination.",
                keywords: ["shortcuts", "reset", "defaults"],
                kind: .action(title: "Reset to defaults") { state.resetShortcuts(in: store) })
        ]
        for (section, commands) in [("Actions", GitMageCommand.actions), ("Areas", GitMageCommand.areaCommands)] {
            for command in commands {
                let chord = store.settings.shortcuts[command.rawValue]
                let recording = state.recording == command
                fields.append(
                    SettingsField(
                        path: group.appending(command.rawValue), label: command.title,
                        help: recording
                            ? "Press a combination with a modifier. Esc cancels, Delete unbinds."
                            : section,
                        keywords: ["shortcut", "keyboard", section.lowercased()],
                        kind: .action(title: recording ? "Press keys…" : (chord?.display ?? "Add shortcut")) {
                            state.record(command, in: store)
                        }))
            }
        }
        return SettingsGroup(
            path: group, title: "Shortcuts",
            footerNote: state.reassignNote
                ?? "Click a shortcut to record a new combination. A combination in use elsewhere "
                + "moves here and unbinds the other command.",
            fields: fields)
    }

    // MARK: - GitHub

    private static func github(
        _ state: GitMageSettingsPageState, _ host: HostServices,
        _ root: SettingsPath
    ) -> SettingsGroup {
        let group = root.appending("github")
        let auth = GitForgeAuth(secrets: host.secrets)
        var fields = [
            SettingsField(
                path: group.appending("token"), label: "Personal access token",
                help: "Create one with the repo scope at github.com → Settings → "
                    + "Developer settings → Personal access tokens.",
                keywords: ["github", "token", "pat", "auth"],
                kind: .secure(Binding(get: { state.tokenDraft }, set: { state.tokenDraft = $0 }))),
            SettingsField(
                path: group.appending("verify"), label: "Save & verify",
                help: state.isVerifying
                    ? "Verifying…"
                    : state.githubStatus ?? (auth.token() != nil ? "A token is saved." : "No token saved."),
                kind: .action(title: "Save & Verify") { state.saveAndVerify(auth) }),
        ]
        if auth.token() != nil {
            fields.append(
                SettingsField(
                    path: group.appending("sign-out"), label: "Sign out",
                    help: "Removes the saved token from your Keychain.",
                    kind: .action(title: "Sign out") {
                        auth.clear()
                        state.tokenDraft = ""
                        state.githubStatus = nil
                    }))
        }
        return SettingsGroup(
            path: group, title: "GitHub",
            footerNote: "Your repository library and settings are stored in Git Mage's "
                + "app-scoped document store.",
            fields: fields)
    }
}

/// What the declared page must remember between the host's rebuilds of it:
/// the token being typed, verification status, and which shortcut is recording.
@MainActor @Observable
final class GitMageSettingsPageState {
    var tokenDraft = ""
    var githubStatus: String?
    var isVerifying = false
    var reassignNote: String?
    private(set) var recording: GitMageCommand?
    @ObservationIgnored private var monitor: Any?

    /// Starts listening for the next key combination for `command`. A local
    /// event monitor, because a declared row is a button, not a focusable
    /// capture field: Esc cancels, Delete unbinds, a bare key is swallowed.
    func record(_ command: GitMageCommand, in store: GitMageSettingsStore) {
        stopRecording()
        recording = command
        reassignNote = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let command = self.recording else { return event }
            switch event.keyCode {
            case 53: self.stopRecording()  // esc
            case 51, 117: self.clear(command, in: store)  // delete, fwd delete
            default:
                if let chord = KeyChord(event), chord.hasModifier { self.assign(chord, to: command, in: store) }
            }
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    /// Unbinds `command` and ends the recording.
    func clear(_ command: GitMageCommand, in store: GitMageSettingsStore) {
        store.update { $0.shortcuts.removeValue(forKey: command.rawValue) }
        stopRecording()
    }

    /// Restores every default combination and drops any reassignment note.
    func resetShortcuts(in store: GitMageSettingsStore) {
        stopRecording()
        store.update { $0.shortcuts = GitMageShortcutDefaults.map }
        reassignNote = nil
    }

    func assign(_ chord: KeyChord, to command: GitMageCommand, in store: GitMageSettingsStore) {
        var displaced: GitMageCommand?
        store.update { s in
            for (key, value) in s.shortcuts where value == chord && key != command.rawValue {
                s.shortcuts.removeValue(forKey: key)
                displaced = GitMageCommand(rawValue: key)
            }
            s.shortcuts[command.rawValue] = chord
        }
        reassignNote = displaced.map { "\(chord.display) reassigned from \($0.title) — now unbound." }
        stopRecording()
    }

    func saveAndVerify(_ auth: GitForgeAuth) {
        guard !tokenDraft.isEmpty, !isVerifying else { return }
        auth.setToken(tokenDraft)
        let token = tokenDraft
        isVerifying = true
        githubStatus = nil
        Task { @MainActor in
            defer { isVerifying = false }
            do {
                githubStatus = "Signed in as \(try await GitHubProvider(token: token).verify().login)."
            } catch let error as ForgeError {
                githubStatus = error.errorDescription
            } catch {
                githubStatus = error.displayMessage
            }
        }
    }
}

extension KeyChord {
    /// A chord from a raw key event — the declared page's recorder has no
    /// SwiftUI `KeyPress` to read.
    init?(_ event: NSEvent) {
        guard let ch = event.charactersIgnoringModifiers?.lowercased().first,
            ch.isLetter || ch.isNumber
        else { return nil }
        let flags = event.modifierFlags
        self.init(
            key: String(ch), command: flags.contains(.command), option: flags.contains(.option),
            control: flags.contains(.control), shift: flags.contains(.shift))
    }
}
