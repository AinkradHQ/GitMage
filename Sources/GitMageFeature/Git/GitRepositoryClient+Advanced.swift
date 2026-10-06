import Foundation

// MARK: - Advanced ops (rebase, cherry-pick, revert, reset, tags, op-state)

extension GitRepositoryClient {
    func rebase(onto base: String, autostash: Bool, in path: String) async throws {
        let root = try await repositoryRootURL(for: path)
        var args = ["rebase"]
        if autostash { args.append("--autostash") }
        args.append(base)
        _ = try await runGit(args, in: root)
    }

    func cherryPick(sha: String, in path: String) async throws {
        let root = try await repositoryRootURL(for: path)
        _ = try await runGit(["cherry-pick", sha], in: root)
    }

    func revert(sha: String, in path: String) async throws {
        let root = try await repositoryRootURL(for: path)
        _ = try await runGit(["revert", "--no-edit", sha], in: root)
    }

    func reset(to ref: String, mode: ResetMode, autostash: Bool, in path: String) async throws {
        let root = try await repositoryRootURL(for: path)
        if autostash {
            let status = try await runGit(["status", "--porcelain"], in: root)
            if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try await runGit(["stash", "push", "--include-untracked"], in: root)
            }
        }
        _ = try await runGit(["reset", "--\(mode.rawValue)", ref], in: root)
    }

    func loadTags(in path: String) async throws -> [GitTag] {
        let root = try await repositoryRootURL(for: path)
        let out = try await runGit(["tag", "--list", "--format=%(refname:short)%09%(subject)"], in: root)
        return GitTagParser.parse(out)
    }

    func createTag(name: String, message: String?, at ref: String? = nil, in path: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitRepositoryError.invalidTagName }
        let root = try await repositoryRootURL(for: path)
        var args: [String]
        if let message, !message.isEmpty {
            args = ["tag", "-a", trimmed, "-m", message]
        } else {
            args = ["tag", trimmed]
        }
        if let ref, !ref.isEmpty { args.append(ref) }
        _ = try await runGit(args, in: root)
    }

    func deleteTag(name: String, in path: String) async throws {
        let root = try await repositoryRootURL(for: path)
        _ = try await runGit(["tag", "-d", name], in: root)
    }

    func operationState(in path: String) async throws -> GitOperationState {
        let root = try await repositoryRootURL(for: path)
        let gitDir = try await runGit(["rev-parse", "--git-dir"], in: root).trimmingCharacters(
            in: .whitespacesAndNewlines)
        let base = gitDir.hasPrefix("/") ? URL(fileURLWithPath: gitDir) : root.appendingPathComponent(gitDir)
        let fm = FileManager.default
        if fm.fileExists(atPath: base.appendingPathComponent("rebase-merge").path)
            || fm.fileExists(atPath: base.appendingPathComponent("rebase-apply").path)
        {
            return .rebasing
        }
        if fm.fileExists(atPath: base.appendingPathComponent("CHERRY_PICK_HEAD").path) { return .cherryPicking }
        if fm.fileExists(atPath: base.appendingPathComponent("REVERT_HEAD").path) { return .reverting }
        return .none
    }

    func continueOperation(in path: String) async throws {
        let root = try await repositoryRootURL(for: path)
        let env = ["GIT_EDITOR": "true"]
        switch try await operationState(in: path) {
        case .rebasing: _ = try await runGit(["rebase", "--continue"], in: root, environment: env)
        case .cherryPicking: _ = try await runGit(["cherry-pick", "--continue"], in: root, environment: env)
        case .reverting: _ = try await runGit(["revert", "--continue"], in: root, environment: env)
        case .none: break
        }
    }

    func abortOperation(in path: String) async throws {
        let root = try await repositoryRootURL(for: path)
        switch try await operationState(in: path) {
        case .rebasing: _ = try await runGit(["rebase", "--abort"], in: root)
        case .cherryPicking: _ = try await runGit(["cherry-pick", "--abort"], in: root)
        case .reverting: _ = try await runGit(["revert", "--abort"], in: root)
        case .none: break
        }
    }
}
