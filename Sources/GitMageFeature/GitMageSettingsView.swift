import SwiftUI
import AinkradAppKit

struct GitMageSettingsView: View {
    let settingsStore: GitMageSettingsStore
    let theme: HostTheme
    let host: HostServices

    @State private var tokenDraft: String = ""
    @State private var githubStatus: String?
    @State private var isVerifying: Bool = false
    @State private var recordingCommand: GitMageCommand?
    @State private var reassignNote: String?

    private var tokens: HostThemeTokens { theme.tokens }
    private var settings: GitMageSettings { settingsStore.settings }
    private var auth: GitForgeAuth { GitForgeAuth(secrets: host.secrets) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                surfaceSection
                appearanceSection
                typographySection
                shortcutsSection
                githubSection
                aboutSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(tokens.background)
        .foregroundStyle(tokens.foreground)
        .onAppear {
            if auth.token() != nil {
                githubStatus = "A token is saved."
            }
        }
    }

    /// How the host surfaces Git Mage. First, above appearance: it decides what
    /// you get when you open the app, which matters before what colour it is.
    private var surfaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AinkradSectionHeader(title: "SURFACE")
            AinkradSurfaceSettings(appName: "Git Mage",
                                   presentation: host.presentation,
                                   mode: host.mode)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AinkradSectionHeader(title: "APPEARANCE")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Background opacity")
                        .font(AinkradFont.fixedDisplay(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    Spacer()
                    Text("\(Int(settings.backgroundOpacity * 100))%")
                        .font(AinkradFont.fixedMono(11))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }
                AinkradSlider(
                    value: Binding(
                        get: { settings.backgroundOpacity },
                        set: { v in settingsStore.update { $0.backgroundOpacity = v } }
                    ),
                    in: 0.2...1.0
                )
                Text("Below 100%, the workspace backdrop shows through. Blur is managed by the host.")
                    .font(AinkradFont.fixedDisplay(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }

            HStack {
                Text("Follow theme accent")
                    .font(AinkradFont.fixedDisplay(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer()
                NeonToggle(
                    isOn: Binding(
                        get: { settings.followThemeAccent },
                        set: { v in settingsStore.update { $0.followThemeAccent = v } }
                    ),
                    tokens: tokens
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Diff text size")
                        .font(AinkradFont.fixedDisplay(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    Spacer()
                    Text("\(Int(settings.diffFontSize)) pt")
                        .font(AinkradFont.fixedMono(11))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }
                AinkradSlider(
                    value: Binding(
                        get: { settings.diffFontSize },
                        set: { v in settingsStore.update { $0.diffFontSize = v.rounded() } }
                    ),
                    in: 9...20
                )
            }
        }
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AinkradSectionHeader(title: "TYPOGRAPHY")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Text size")
                        .font(AinkradFont.fixedDisplay(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    Spacer()
                    Text("\(Int(settings.textScale * 100))%")
                        .font(AinkradFont.fixedMono(11))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }
                AinkradSlider(
                    value: Binding(
                        get: { settings.textScale },
                        set: { v in settingsStore.update { $0.textScale = (v * 20).rounded() / 20 } }
                    ),
                    in: 0.8...1.3
                )
                Text("Scales every text in Git Mage. The sample below updates live.")
                    .font(AinkradFont.fixedDisplay(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }

            fontPicker(title: "Display font", selection: settings.displayFontName,
                       options: AinkradFont.displayFamilies) { name in
                settingsStore.update { $0.displayFontName = name }
            }
            fontPicker(title: "Mono font", selection: settings.monoFontName,
                       options: AinkradFont.monoFamilies) { name in
                settingsStore.update { $0.monoFontName = name }
            }

            // Live sample — uses the SCALED fonts so it previews the setting.
            VStack(alignment: .leading, spacing: 3) {
                Text("The quick brown fox — Git Mage")
                    .font(AinkradFont.display(14, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text("feat/typography · a1b2c3d · +128 −44")
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.4)))
        }
    }

    private func fontPicker(title: String, selection: String, options: [String],
                            onSelect: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title)
                .font(AinkradFont.fixedDisplay(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer()
            AinkradSelect(
                items: options,
                selection: Binding(get: { selection }, set: onSelect),
                label: { $0 },
                searchPlaceholder: "Search fonts…"
            )
            .frame(width: 200)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                AinkradSectionHeader(title: "KEYBOARD SHORTCUTS")
                Spacer()
                Button("Reset to defaults") { resetShortcuts() }
                    .buttonStyle(.plain)
                    .font(AinkradFont.fixedDisplay(11, weight: .medium))
                    .foregroundStyle(tokens.accentPrimary.opacity(0.9))
            }

            Text("Click a shortcut to record a new combination, or × to unbind. A combination in use elsewhere moves here and unbinds the other command.")
                .font(AinkradFont.fixedDisplay(11))
                .foregroundStyle(tokens.foreground.opacity(0.45))

            if let reassignNote {
                Text(reassignNote)
                    .font(AinkradFont.fixedDisplay(11, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary)
            }

            shortcutGroup("ACTIONS", GitMageCommand.actions)
            shortcutGroup("AREAS", GitMageCommand.areaCommands)
        }
    }

    private func shortcutGroup(_ title: String, _ commands: [GitMageCommand]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AinkradFont.fixedMono(9, weight: .medium))
                .kerning(2)
                .foregroundStyle(tokens.foreground.opacity(0.35))
                .padding(.top, 4)
            ForEach(commands) { command in
                ShortcutRecorderRow(
                    command: command,
                    chord: settings.shortcuts[command.rawValue],
                    isRecording: recordingCommand == command,
                    tokens: tokens,
                    onStart: { recordingCommand = command; reassignNote = nil },
                    onCapture: { record($0, for: command) },
                    onCancel: { recordingCommand = nil },
                    onClear: { clearShortcut(command) }
                )
            }
        }
    }

    private func record(_ chord: KeyChord, for command: GitMageCommand) {
        var displaced: GitMageCommand?
        settingsStore.update { s in
            for (key, value) in s.shortcuts where value == chord && key != command.rawValue {
                s.shortcuts.removeValue(forKey: key)
                displaced = GitMageCommand(rawValue: key)
            }
            s.shortcuts[command.rawValue] = chord
        }
        reassignNote = displaced.map { "\(chord.display) reassigned from \($0.title) — now unbound." }
        recordingCommand = nil
    }

    private func clearShortcut(_ command: GitMageCommand) {
        settingsStore.update { $0.shortcuts.removeValue(forKey: command.rawValue) }
        if recordingCommand == command { recordingCommand = nil }
    }

    private func resetShortcuts() {
        settingsStore.update { $0.shortcuts = GitMageShortcutDefaults.map }
        reassignNote = nil
        recordingCommand = nil
    }

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AinkradSectionHeader(title: "GITHUB")

            VStack(alignment: .leading, spacing: 6) {
                Text("Personal access token")
                    .font(AinkradFont.fixedDisplay(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))

                AinkradSecureField(text: $tokenDraft, placeholder: "Personal access token")

                HStack(spacing: 10) {
                    Button {
                        saveAndVerify()
                    } label: {
                        HStack(spacing: 6) {
                            if isVerifying {
                                AinkradSpinner(size: 12)
                            }
                            Text("Save & Verify")
                        }
                        .font(AinkradFont.fixedDisplay(12, weight: .medium))
                        .foregroundStyle(tokens.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            ChamferShape(cut: AinkradRadius.sm)
                                .fill(tokens.surfaceElevated.opacity(0.5))
                        )
                        .overlay(
                            ChamferShape(cut: AinkradRadius.sm)
                                .strokeBorder(tokens.accentPrimary.opacity(0.2))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(tokenDraft.isEmpty || isVerifying)

                    if auth.token() != nil {
                        Button {
                            signOut()
                        } label: {
                            Text("Sign out")
                                .font(AinkradFont.fixedDisplay(12, weight: .medium))
                                .foregroundStyle(tokens.foreground.opacity(0.85))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    ChamferShape(cut: AinkradRadius.sm)
                                        .fill(tokens.surfaceElevated.opacity(0.5))
                                )
                                .overlay(
                                    ChamferShape(cut: AinkradRadius.sm)
                                        .strokeBorder(tokens.accentPrimary.opacity(0.2))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let githubStatus {
                    Text(githubStatus)
                        .font(AinkradFont.fixedDisplay(11))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                }

                Text("Create a token with the `repo` scope at github.com → Settings → Developer settings → Personal access tokens.")
                    .font(AinkradFont.fixedDisplay(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
        }
    }

    private func saveAndVerify() {
        auth.setToken(tokenDraft)
        let token = tokenDraft
        isVerifying = true
        githubStatus = nil
        Task { @MainActor in
            defer { isVerifying = false }
            do {
                let provider = GitHubProvider(token: token)
                let user = try await provider.verify()
                githubStatus = "Signed in as \(user.login)."
            } catch let error as ForgeError {
                githubStatus = error.errorDescription
            } catch {
                githubStatus = error.localizedDescription
            }
        }
    }

    private func signOut() {
        auth.clear()
        tokenDraft = ""
        githubStatus = nil
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AinkradSectionHeader(title: "STORAGE")
            Text("Your repository library and settings are stored in Git Mage's app-scoped document store.")
                .font(AinkradFont.fixedDisplay(11))
                .foregroundStyle(tokens.foreground.opacity(0.45))
        }
    }
}

/// One command's shortcut row: label on the left, a capture chip on the right
/// that records a new chord (Esc cancels) and an × to unbind.
private struct ShortcutRecorderRow: View {
    let command: GitMageCommand
    let chord: KeyChord?
    let isRecording: Bool
    let tokens: HostThemeTokens
    let onStart: () -> Void
    let onCapture: (KeyChord) -> Void
    let onCancel: () -> Void
    let onClear: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(command.title)
                .font(AinkradFont.fixedDisplay(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Spacer()
            if chord != nil && !isRecording {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.foreground.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help("Unbind")
            }
            captureChip
        }
        .padding(.vertical, 3)
    }

    private var captureChip: some View {
        Button(action: onStart) {
            Text(isRecording ? "Press keys…" : (chord?.display ?? "Add shortcut"))
                .font(AinkradFont.fixedMono(11, weight: .medium))
                .foregroundStyle(chipTextColor)
                .frame(minWidth: 92)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    ChamferShape(cut: AinkradRadius.sm)
                        .fill(isRecording ? tokens.accentSecondary.opacity(0.14)
                              : tokens.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    ChamferShape(cut: AinkradRadius.sm)
                        .strokeBorder(isRecording ? tokens.accentSecondary.opacity(0.8)
                                      : tokens.accentPrimary.opacity(0.2),
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusable(isRecording)
        .focused($focused)
        .onChange(of: isRecording) { _, recording in focused = recording }
        .onKeyPress(phases: .down) { press in
            guard isRecording else { return .ignored }
            if press.key == .escape { onCancel(); return .handled }
            if let newChord = KeyChord(press), newChord.hasModifier {
                onCapture(newChord)
            }
            return .handled  // swallow bare keys; keep recording
        }
    }

    private var chipTextColor: Color {
        if isRecording { return tokens.accentSecondary }
        return chord == nil ? tokens.foreground.opacity(0.45) : tokens.foreground.opacity(0.9)
    }
}
