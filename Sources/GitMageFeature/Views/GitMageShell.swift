import AinkradAppKit
import SwiftUI

struct GitMageShell: View {
    let host: HostServices
    let settingsStore: GitMageSettingsStore
    @StateObject var model: GitMageViewModel
    @State var prModel: PullRequestsViewModel?
    @State var prHasGitHubRemote = false
    @State var issuesModel: IssuesViewModel?
    @State var issuesHasGitHubRemote = false
    @State var worktreesModel: WorktreesViewModel?
    @State var advancedModel: AdvancedViewModel?
    @State private var management: GitMageManagementKind?
    @Namespace private var navNamespace
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    init(host: HostServices, settingsStore: GitMageSettingsStore) {
        self.host = host
        self.settingsStore = settingsStore
        _model = StateObject(wrappedValue: GitMageViewModel(documents: host.documents, signals: host.signals))
    }

    var tokens: HostThemeTokens { host.theme.tokens }
    /// Bridges GitMage's per-plugin typography into the kit's `\.ainkradTypography`
    /// env so swapped kit components (text fields, editors, search, and later
    /// waves) honor the user's display font + text scale. Recomputes with `body`,
    /// so changing the font/scale in Settings restyles kit controls live.
    /// NOTE(mono-loss): `AinkradTypography` carries only one (display) family and
    /// the kit hardcodes mono → JetBrains Mono, so `settings.monoFontName` does
    /// NOT reach kit components (accepted loss, M6 W1).
    private var kitTypography: AinkradTypography {
        let s = settingsStore.settings
        return AinkradTypography(fontFamilyName: s.displayFontName, scale: CGFloat(s.textScale))
    }
    var appearance: GitMageRenderAppearance {
        GitMageAppearanceResolver.resolve(settings: settingsStore.settings, tokens: tokens)
    }
    private var contextBridge: GitMageContextBridge { GitMageRuntime.contextBridge(for: host) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                if let errorMessage = model.errorMessage {
                    AinkradBanner(message: errorMessage, status: .warning, onDismiss: model.dismissError)
                        .padding([.horizontal, .bottom])
                }
                HStack(spacing: 0) {
                    navRail
                    if model.hasActiveRepo {
                        contextPane
                            .frame(width: 300)
                            .background(tokens.surface.opacity(0.35))
                        detailPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        emptyLibraryState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            if let management {
                GitMageManagementOverlay(
                    model: model,
                    tokens: tokens,
                    kind: management,
                    dismiss: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { self.management = nil } }
                )
            }

        }
        // Kit confirm dialog for the "initialize repository?" prompt. Bound to
        // `showInitPrompt`; the setter clears the pending path on any dismiss
        // (mirrors the old `cancelInitPendingRepository`). Confirm dispatches the
        // init synchronously via `confirmInitPendingRepository` (it captures the
        // path locally before the dialog dismisses).
        .ainkradConfirmDialog(
            isPresented: Binding(
                get: { model.showInitPrompt },
                set: { presented in
                    if !presented {
                        model.showInitPrompt = false
                        model.cancelInitPendingRepository()
                    }
                }
            ),
            title: "Initialize a new Git repository?",
            message:
                "\(model.pendingInitPath ?? "") is not a Git repository yet. Initialize it and add it to your library?",
            confirmTitle: "Initialize",
            onConfirm: { model.confirmInitPendingRepository() }
        )
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: management)
        .background(
            ShortcutLayer(
                shortcuts: settingsStore.settings.shortcuts,
                hasActiveRepo: model.hasActiveRepo,
                perform: perform
            )
        )
        .background(tokens.surface.opacity(appearance.backgroundOpacity))
        .foregroundStyle(tokens.foreground)
        .task { model.bootstrapIfNeeded() }
        .onAppear { contextBridge.setActiveSource(model) }
        .onDisappear { contextBridge.clearActiveSource(model) }
        .task(id: PRTaskKey(area: model.selectedArea, repoID: model.activeRepoID)) {
            await buildPRModelIfNeeded()
        }
        .task(id: IssuesTaskKey(area: model.selectedArea, repoID: model.activeRepoID)) {
            await buildIssuesModelIfNeeded()
        }
        .task(id: WorktreesTaskKey(isActive: model.selectedArea == .worktrees, repoID: model.activeRepoID)) {
            await buildWorktreesModelIfNeeded()
        }
        .task(id: AdvancedTaskKey(isActive: model.selectedArea == .advanced, repoID: model.activeRepoID)) {
            await buildAdvancedModelIfNeeded()
        }
        .ainkradModal(isPresented: $model.showClonePrompt) { cloneSheet }
        // Inject GitMage's typography at the OUTERMOST level so every kit
        // control — including the management overlay, confirm dialog, and clone
        // modal (all attached outside the inner content) — honors the user's
        // display font + scale. Kit controls read this dynamically, so it
        // updates on settings change without needing to be under `.id`.
        .environment(\.ainkradTypography, kitTypography)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            RepoSwitcher(model: model, tokens: tokens, shortcut: hint(.openRepos)) {
                openManagement(.repos)
            }
            if model.hasActiveRepo {
                BranchChip(model: model, tokens: tokens, shortcut: hint(.openBranches)) {
                    openManagement(.branches)
                }
            }
            Spacer()
            if model.hasActiveRepo {
                AinkradButton(
                    title: "Fetch", style: .secondary, icon: "arrow.down.circle",
                    isLoading: model.activeOperation == "fetch"
                ) { model.fetch() }
                .ainkradTooltip(shortcutTooltip("Fetch", hint(.fetch)))
                AinkradButton(
                    title: "Pull", style: .secondary, icon: "arrow.down.to.line",
                    isLoading: model.activeOperation == "pull"
                ) { model.pull() }
                .ainkradTooltip(shortcutTooltip("Pull", hint(.pull)))
                AinkradButton(
                    title: "Push", style: .primary, icon: "arrow.up.to.line",
                    isLoading: model.activeOperation == "push"
                ) { model.push() }
                .ainkradTooltip(shortcutTooltip("Push", hint(.push)))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    /// Display string for a command's bound chord, or nil when unbound.
    private func hint(_ command: GitMageCommand) -> String? {
        settingsStore.settings.shortcuts[command.rawValue]?.display
    }

    /// Display string for the "Go to <area>" command, or nil when unbound.
    private func areaHint(_ area: NavArea) -> String? {
        guard let command = GitMageCommand.areaCommands.first(where: { $0.area == area }) else { return nil }
        return hint(command)
    }

    private func openManagement(_ kind: GitMageManagementKind) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)) { management = kind }
    }

    /// Central handler for every keyboard-dispatched command.
    private func perform(_ command: GitMageCommand) {
        switch command {
        case .openRepos: openManagement(.repos)
        case .openBranches: if model.hasActiveRepo { openManagement(.branches) }
        case .fetch: model.fetch()
        case .pull: model.pull()
        case .push: model.push()
        default:
            if let area = command.area {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.74)) {
                    model.selectArea(area)
                }
            }
        }
    }

    private var navRail: some View {
        VStack(spacing: 6) {
            ForEach(NavArea.built) { area in
                NavRailItem(
                    area: area,
                    isActive: model.selectedArea == area,
                    tokens: tokens,
                    namespace: navNamespace,
                    shortcut: areaHint(area),
                    action: { model.selectArea(area) }
                )
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.74), value: model.selectedArea)
    }


    private var emptyLibraryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars").font(.system(size: 34, weight: .light)).foregroundStyle(
                tokens.accentPrimary.opacity(0.6))
            Text("No repository").font(AinkradFont.display(18, weight: .semibold))
            Text("Add a local folder or clone one to begin.").font(AinkradFont.display(12)).foregroundStyle(
                tokens.foreground.opacity(0.5))
            HStack {
                Button("Add…") { model.addRepositoryFolder() }.font(AinkradFont.display(12))
                Button("Clone…") { model.startClone() }.font(AinkradFont.display(12))
            }
        }
    }
}
