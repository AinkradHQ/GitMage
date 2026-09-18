import SwiftUI
import AinkradAppKit

/// Git Mage's **basic** mode: which repo, which branch, Fetch, Pull.
///
/// The three things Git Mage is actually opened for most of the time. Changes,
/// history, stashes, pull requests, issues, worktrees and advanced all stay in
/// advanced mode, and none of them is built here.
///
/// The saving is in the LOAD, not the view. `GitMageViewModel.loadScope` is set
/// to `.basic`, so the model fetches the branch list and stops — where the full
/// refresh also runs `git status`, `git stash list` and a diff of the first
/// changed file, none of which this screen shows. Trimming the view alone would
/// have saved nothing.
struct GitMageBasicView: View {
    let host: HostServices
    @ObservedObject var model: GitMageViewModel

    @Environment(\.ainkradTheme) private var kitTheme

    private var tokens: HostThemeTokens { host.theme.tokens }

    var body: some View {
        AinkradBasicShell(icon: "wand.and.stars",
                          title: model.activeRepo?.name ?? "Git Mage",
                          subtitle: subtitle) {
            // Switching repo belongs in basic mode: "which repo" is half of
            // what Fetch and Pull even mean, and sending someone to advanced to
            // answer it defeats the point of the mode. The kit's grouped select
            // rather than a local menu — it is searchable, which matters at 14
            // repos, and the design system forbids rolling one here.
            if model.repos.count > 1 {
                AinkradGroupedSelect(
                    sections: [AinkradGroupedSection(
                        header: "Repositories",
                        rows: model.repos.map {
                            AinkradGroupedRow(value: $0.id, title: $0.name,
                                              detail: $0.path, icon: "wand.and.stars")
                        })],
                    selection: Binding(
                        get: { model.activeRepoID ?? "" },
                        // `selectRepository` owns the whole switch — persisting
                        // the outgoing repo's state, resetting transient state
                        // and refreshing. In basic that refresh is the scoped
                        // branches-only one, so switching stays cheap.
                        set: { model.selectRepository($0) }),
                    triggerLabel: model.activeRepo?.name ?? "Repository",
                    searchPlaceholder: "Search repositories")
                .frame(maxWidth: 220)
            }
            AinkradButton(title: "Fetch", style: .secondary, icon: "arrow.down") {
                model.fetch()
            }
            .disabled(!model.hasActiveRepo || model.isLoading)
            AinkradButton(title: "Pull", style: .primary, icon: "arrow.down.to.line") {
                model.pull()
            }
            .disabled(!model.hasActiveRepo || model.isLoading)
        } content: {
            if model.hasActiveRepo {
                branchList
            } else {
                AinkradEmptyState(icon: "wand.and.stars",
                                  title: "No repository",
                                  message: "Add one in advanced mode.")
            }
        }
        // Scope the load BEFORE bootstrap: `bootstrapIfNeeded` calls `refresh`,
        // so setting this afterwards would pay for the full load once and then
        // be basic only from the second refresh onward.
        .task {
            model.loadScope = .basic
            model.bootstrapIfNeeded()
        }
        // The agent asks about "the repo" — without this it would read whichever
        // pane appeared last, which is the class of bug `PluginFocus` exists to
        // stop. Basic mode is a real pane and has to claim it like any other.
        .onAppear { GitMageRuntime.contextBridge(for: host).setActiveSource(model) }
    }

    /// Ahead/behind comes free with the branch list (`%(upstream:trackshort)`),
    /// so the one number worth knowing before a pull costs no extra subprocess.
    private var subtitle: String {
        guard let current = model.branches.first(where: { $0.isCurrent }) else {
            return model.selectedBranchName.isEmpty ? "—" : model.selectedBranchName
        }
        if let tracking = current.tracking, !tracking.isEmpty {
            return "\(current.name) · \(tracking)"
        }
        return current.name
    }

    private var branchList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(model.branches) { branch in
                    AinkradListRow(
                        isSelected: branch.isCurrent,
                        leading: {
                            Image(systemName: branch.isCurrent
                                  ? "arrow.triangle.branch" : "circle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(branch.isCurrent
                                                 ? tokens.accentPrimary
                                                 : tokens.foreground.opacity(0.35))
                                .frame(width: 20)
                        },
                        title: branch.name,
                        subtitle: branch.subtitle,
                        trailing: { EmptyView() }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { switchTo(branch) }
                }
            }
        }
    }

    /// Checkout runs through the model's own `checkoutSelectedBranch`, the same
    /// path advanced uses — so the guard rails on it (empty-name refusal, error
    /// reporting, the post-operation refresh) apply here unchanged.
    private func switchTo(_ branch: GitBranchSummary) {
        guard !branch.isCurrent else { return }
        model.selectedBranchName = branch.name
        model.checkoutSelectedBranch()
    }
}
