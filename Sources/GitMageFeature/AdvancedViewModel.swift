import Foundation

/// Drives the Advanced Ops surface: rebase, cherry-pick, revert, reset, and tag
/// management for the active repository. Destructive ops (rebase, hard reset)
/// are confirm-gated via `pendingConfirm`; cherry-pick/revert/tags run directly.
@MainActor
final class AdvancedViewModel: ObservableObject {
    enum AdvancedOp: CaseIterable, Identifiable {
        case rebase
        case cherryPick
        case revert
        case reset
        case tags

        var id: Self { self }

        var title: String {
            switch self {
            case .rebase: return "Rebase"
            case .cherryPick: return "Cherry-pick"
            case .revert: return "Revert"
            case .reset: return "Reset"
            case .tags: return "Tags"
            }
        }
    }

    struct PendingAction: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let perform: () async -> Void
    }

    @Published var commits: [GitCommitSummary] = []
    @Published var tags: [GitTag] = []
    @Published var operationState: GitOperationState = .none
    @Published var selectedOp: AdvancedOp = .rebase
    @Published var rebaseBase: String?
    @Published var selectedCommit: String?
    @Published var resetMode: ResetMode = .mixed
    @Published var autostash: Bool = true
    @Published var newTagName: String = ""
    @Published var newTagMessage: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingConfirm: PendingAction?

    private let client: GitRepositoryClient
    private let repositoryPath: String
    private let branches: [GitBranchSummary]
    private let onChanged: () -> Void

    init(
        client: GitRepositoryClient,
        repositoryPath: String,
        branches: [GitBranchSummary],
        onChanged: @escaping () -> Void
    ) {
        self.client = client
        self.repositoryPath = repositoryPath
        self.branches = branches
        self.onChanged = onChanged
    }

    var branchNames: [String] { branches.map(\.name) }

    var currentBranchName: String {
        branches.first(where: \.isCurrent)?.name ?? "HEAD"
    }

    func load() async {
        guard !repositoryPath.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        do {
            commits = try await client.loadLog(limit: 200, in: repositoryPath)
            tags = try await client.loadTags(in: repositoryPath)
            operationState = try await client.operationState(in: repositoryPath)
        } catch {
            report(error)
        }
        isLoading = false
    }

    func requestRebase() {
        guard !repositoryPath.isEmpty, let base = rebaseBase, !base.isEmpty else { return }
        let stashNote = autostash ? " (autostash enabled)" : ""
        pendingConfirm = PendingAction(
            title: "Rebase",
            message: "Rebase \(currentBranchName) onto \(base)\(stashNote).",
            perform: { [weak self] in
                guard let self else { return }
                await self.runMutation {
                    try await self.client.rebase(onto: base, autostash: self.autostash, in: self.repositoryPath)
                }
            }
        )
    }

    func requestReset() {
        guard !repositoryPath.isEmpty, let target = selectedCommit, !target.isEmpty else { return }
        let short = String(target.prefix(7))
        var message = "Reset (\(resetMode.rawValue)) to \(short)."
        if resetMode == .hard {
            message += autostash ? " (auto-stashed first)" : " This discards uncommitted changes."
        }
        pendingConfirm = PendingAction(
            title: "Reset",
            message: message,
            perform: { [weak self] in
                guard let self else { return }
                await self.runMutation {
                    try await self.client.reset(
                        to: target, mode: self.resetMode, autostash: self.autostash, in: self.repositoryPath)
                }
            }
        )
    }

    func confirmPending() async {
        guard let action = pendingConfirm else { return }
        await action.perform()
        pendingConfirm = nil
    }

    func cancelPending() {
        pendingConfirm = nil
    }

    func cherryPick() async {
        guard !repositoryPath.isEmpty, let sha = selectedCommit, !sha.isEmpty else { return }
        await runMutation { [self] in
            try await client.cherryPick(sha: sha, in: repositoryPath)
        }
    }

    func revert() async {
        guard !repositoryPath.isEmpty, let sha = selectedCommit, !sha.isEmpty else { return }
        await runMutation { [self] in
            try await client.revert(sha: sha, in: repositoryPath)
        }
    }

    func createTag() async {
        guard !repositoryPath.isEmpty else { return }
        let name = newTagName
        let message = newTagMessage.isEmpty ? nil : newTagMessage
        let target = selectedCommit  // tag the selected commit, else HEAD
        await runMutation { [self] in
            try await client.createTag(name: name, message: message, at: target, in: repositoryPath)
        }
        if errorMessage == nil {
            newTagName = ""
            newTagMessage = ""
        }
    }

    func deleteTag(_ name: String) async {
        guard !repositoryPath.isEmpty else { return }
        await runMutation { [self] in
            try await client.deleteTag(name: name, in: repositoryPath)
        }
    }

    func continueOperation() async {
        guard !repositoryPath.isEmpty else { return }
        await runMutation { [self] in
            try await client.continueOperation(in: repositoryPath)
        }
    }

    func abortOperation() async {
        guard !repositoryPath.isEmpty else { return }
        await runMutation { [self] in
            try await client.abortOperation(in: repositoryPath)
        }
    }

    // MARK: - Private

    /// Runs a mutating client call, then refreshes state and notifies. A thrown
    /// error is only surfaced as `errorMessage` when the reload shows no active
    /// operation — an active operation after a throw means the failure was a
    /// merge/cherry-pick conflict, not a genuine error, and is represented via
    /// `operationState` instead.
    private func runMutation(_ operation: @escaping () async throws -> Void) async {
        do {
            try await operation()
            await finishMutation()
        } catch {
            await load()
            if !operationState.isActive {
                report(error)
            }
            onChanged()
        }
    }

    private func finishMutation() async {
        await load()
        onChanged()
    }

    private func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
