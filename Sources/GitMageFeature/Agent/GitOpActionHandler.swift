import AinkradAppKit
import Foundation

/// Thin adapter that maps a gated `gitmage.git_op` action to `GitRepositoryClient`
/// calls (including its `+Advanced` extension). Local git only — reuses the
/// existing actor wholesale, no re-implemented git. The only ops it rejects with
/// "unsupported operation" are the change-value ones (discard / stage / unstage a
/// GitChange, stashDrop a GitStashEntry) whose args aren't string-expressible.
struct GitOpActionHandler {
    let client: GitRepositoryClient

    func run(_ json: String) async -> AgentActionResult {
        guard let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let operation = obj["operation"] as? String,
            let repoPath = obj["repoPath"] as? String
        else {
            return AgentActionResult(text: "git_op: malformed input", isError: true)
        }
        let args = obj["args"] as? [String: Any] ?? [:]
        do {
            switch operation {
            case "status":
                let snap = try await client.loadSnapshot(at: repoPath)
                let changes = snap.changes.map { $0.path }.joined(separator: ", ")
                return ok("branch \(snap.branchName) — \(snap.statusSummary)\nchanges: \(changes)")
            case "commit":
                guard let message = args["message"] as? String else { return bad("commit requires args.message") }
                try await client.commit(message: message, in: repoPath)
                return ok("committed: \(message)")
            case "createBranch":
                guard let name = args["name"] as? String else { return bad("createBranch requires args.name") }
                try await client.createBranch(name, in: repoPath)
                return ok("created branch \(name)")
            case "checkout":
                guard let name = args["name"] as? String else { return bad("checkout requires args.name") }
                try await client.checkoutBranch(name, in: repoPath)
                return ok("checked out \(name)")
            case "deleteBranch":
                guard let name = args["name"] as? String else { return bad("deleteBranch requires args.name") }
                try await client.deleteBranch(name, in: repoPath)
                return ok("deleted branch \(name)")
            case "push":
                try await client.push(in: repoPath)
                return ok("pushed")
            case "pull":
                try await client.pull(in: repoPath)
                return ok("pulled")
            case "fetch":
                try await client.fetch(in: repoPath)
                return ok("fetched")
            case "stageAll":
                try await client.stageAllChanges(in: repoPath)
                return ok("staged all changes")
            case "unstageAll":
                try await client.unstageAllChanges(in: repoPath)
                return ok("unstaged all changes")
            case "stashPush":
                try await client.stashPush(in: repoPath)
                return ok("stashed changes")
            case "stashPop":
                try await client.stashPop(in: repoPath)
                return ok("popped stash")
            case "log":
                let limit = (args["limit"] as? Int) ?? 20
                let commits = try await client.loadLog(limit: limit, in: repoPath)
                return ok(commits.map { "\($0.shortSHA) \($0.summary)" }.joined(separator: "\n"))
            case "rebase":
                guard let onto = args["onto"] as? String else { return bad("rebase requires args.onto") }
                try await client.rebase(onto: onto, autostash: (args["autostash"] as? Bool) ?? false, in: repoPath)
                return ok("rebased onto \(onto)")
            case "cherryPick":
                guard let sha = args["sha"] as? String else { return bad("cherryPick requires args.sha") }
                try await client.cherryPick(sha: sha, in: repoPath)
                return ok("cherry-picked \(sha)")
            case "revert":
                guard let sha = args["sha"] as? String else { return bad("revert requires args.sha") }
                try await client.revert(sha: sha, in: repoPath)
                return ok("reverted \(sha)")
            case "reset":
                guard let ref = args["ref"] as? String else { return bad("reset requires args.ref") }
                guard let mode = ResetMode(rawValue: (args["mode"] as? String) ?? "mixed") else {
                    return bad("reset args.mode must be soft, mixed, or hard")
                }
                try await client.reset(
                    to: ref, mode: mode, autostash: (args["autostash"] as? Bool) ?? false, in: repoPath)
                return ok("reset (\(mode.rawValue)) to \(ref)")
            case "createTag":
                guard let name = args["name"] as? String else { return bad("createTag requires args.name") }
                try await client.createTag(
                    name: name, message: args["message"] as? String,
                    at: args["ref"] as? String, in: repoPath)
                return ok("created tag \(name)")
            case "deleteTag":
                guard let name = args["name"] as? String else { return bad("deleteTag requires args.name") }
                try await client.deleteTag(name: name, in: repoPath)
                return ok("deleted tag \(name)")
            case "tags":
                let tags = try await client.loadTags(in: repoPath)
                return ok(tags.map { $0.name }.joined(separator: "\n"))
            case "removeWorktree":
                guard let path = args["path"] as? String else { return bad("removeWorktree requires args.path") }
                try await client.removeWorktree(path: path, force: (args["force"] as? Bool) ?? false, in: repoPath)
                return ok("removed worktree \(path)")
            case "opState":
                let state = try await client.operationState(in: repoPath)
                return ok("operation state: \(state.label)")
            case "continueOp":
                try await client.continueOperation(in: repoPath)
                return ok("continued the in-progress operation")
            case "abortOperation":
                try await client.abortOperation(in: repoPath)
                return ok("aborted the in-progress operation")
            default:
                return bad("unsupported operation: \(operation)")
            }
        } catch let error as GitRepositoryError {
            return AgentActionResult(text: error.errorDescription ?? "git error", isError: true)
        } catch {
            return AgentActionResult(text: error.displayMessage, isError: true)
        }
    }

    private func ok(_ text: String) -> AgentActionResult { AgentActionResult(text: text, isError: false) }
    private func bad(_ text: String) -> AgentActionResult { AgentActionResult(text: text, isError: true) }
}
