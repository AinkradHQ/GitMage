import AinkradAppKit
import Foundation
import Testing

@testable import GitMageFeature

// MARK: - evasion cases
//
// File-scope (not nested in the suite) because `@Test(arguments:)` reads the
// table from outside the actor, and the suite is `@MainActor`.

/// One spelling of a dangerous argument. The value is built by a closure so the
/// table can hold heterogeneous JSON values and still be `Sendable`.
struct Evasion: Sendable, CustomStringConvertible {
    let label: String
    let value: @Sendable () -> Any
    init(_ label: String, _ value: @escaping @Sendable () -> Any) {
        self.label = label
        self.value = value
    }
    var description: String { label }
}

/// Casings, types and wrappings a caller could try in place of the literal
/// `mode: "hard"` that `reset`'s guard rejects.
let resetEvasions: [Evasion] = [
    Evasion("capitalised") { "Hard" },
    Evasion("upper-cased") { "HARD" },
    Evasion("leading space") { " hard" },
    Evasion("trailing space") { "hard " },
    Evasion("number") { 1 },
    Evasion("array wrapping the string") { ["hard"] },
    Evasion("object wrapping the string") { ["mode": "hard"] },
]

/// The same, for the literal `force: true` that `remove_worktree`'s guard
/// rejects. (`1` is covered separately — it bridges to `NSNumber` and IS caught.)
let forceEvasions: [Evasion] = [
    Evasion("string \"true\"") { "true" },
    Evasion("string \"TRUE\"") { "TRUE" },
    Evasion("string \"yes\"") { "yes" },
    Evasion("array wrapping true") { [true] },
    Evasion("object wrapping true") { ["force": true] },
]

// MARK: - tests

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GitMageMCPServerTests {
    /// Mirrors `GitOpTool.destructiveOperations` in the host, verbatim.
    static let hostDestructiveOperations: Set<String> = [
        "push", "deleteBranch", "deleteTag", "abortOperation",
        "rebase", "cherryPick", "revert",
    ]

    /// Every operation `GitOpTool.parametersSchema` advertises.
    static let hostOperations: [String] = [
        "status", "commit", "createBranch", "checkout", "deleteBranch", "push", "pull",
        "fetch", "stashPush", "stashPop", "stageAll", "unstageAll", "log", "rebase",
        "cherryPick", "revert", "reset", "createTag", "deleteTag", "tags",
        "removeWorktree", "opState", "continueOp", "abortOperation",
    ]

    /// Only the git half is under test here; the PR half has its own suite
    /// (`GitMagePROpTests`), so its forwarder is a tripwire — if a git tool ever
    /// routed to it, the assertion in `callForwardsOperationAndArguments` and
    /// friends would see no payload at all.
    private func makeServer(_ recorder: RecordingForwarder) -> (MCPAppServer, [String]) {
        GitMageMCPServer.make(
            appID: "gitmage",
            forward: { await recorder.forward($0) },
            forwardPR: { _ in AgentActionResult(text: "pr", isError: false) }
        )
    }

    @Test func everyToolRegistersSuccessfully() async {
        let (_, failures) = makeServer(RecordingForwarder())
        #expect(failures.isEmpty, "addTool rejected: \(failures)")
    }

    @Test func publishesEveryHostOperation() async {
        let (server, _) = makeServer(RecordingForwarder())
        let published = Set(GitMageMCPServer.gitTools.map(\.operation))
        for operation in Self.hostOperations {
            #expect(published.contains(operation), "missing operation \(operation)")
        }
        // Every published tool is actually listed over the wire.
        let listed = Set(await listedTools(server).compactMap { $0["name"] as? String })
        #expect(listed == Set(GitMageMCPServer.tools.map(\.name)))
    }

    @Test func destructiveHintsMatchTheHostSet() async {
        let (server, _) = makeServer(RecordingForwarder())
        let listed = await listedTools(server)
        for tool in GitMageMCPServer.gitTools {
            guard let entry = listed.first(where: { $0["name"] as? String == tool.name }) else {
                Issue.record("tool \(tool.name) was not listed")
                continue
            }
            // The two injecting variants are destructive by construction; every
            // other tool follows the host's operation-token set exactly.
            let expected =
                tool.name == "reset_hard" || tool.name == "remove_worktree_force"
                ? true
                : Self.hostDestructiveOperations.contains(tool.operation)
            #expect(destructiveHint(entry) == expected, "wrong destructiveHint for \(tool.name)")
        }
    }

    /// Invariant 1 of the split-tool pattern, enforced over the WHOLE table
    /// (git + PR) rather than by naming the pairs: a tool that injects a
    /// dangerous argument itself must carry `destructive: true`, because that
    /// flag is the only thing routing the call to the host's approval gate.
    /// Adding a third pair without the flag would be a silent, ungated
    /// irreversible tool — this fails instead.
    @Test func everyInjectingToolIsDestructive() {
        for tool in GitMageMCPServer.tools {
            for rule in tool.injects {
                let reason =
                    "\(tool.name) injects args.\(rule.key) = \(rule.value.described) "
                    + "but is not destructive: true — it would be ungated"
                #expect(tool.destructive, Comment(rawValue: reason))
            }
        }
    }

    /// Invariant 2, also table-driven: every key a tool refuses must remain
    /// reachable through SOME published twin for the same operation that
    /// injects it. Without that, the safe half refuses a capability nothing
    /// else can supply — the pattern would silently delete functionality
    /// instead of gating it.
    ///
    /// With `rejects`/`injects` as arrays, a multi-rule tool's keys do NOT need
    /// one single twin that injects all of them together — a caller who needs
    /// two dangerous arguments at once is already asking for the fully
    /// dangerous operation, which is exactly what "some twin injects this key"
    /// captures per key. Requiring one twin to cover the whole set would fail
    /// on a perfectly reasonable design where two independent dangerous
    /// arguments each get their own dedicated destructive tool. So the check is
    /// per rejected key: for every `(operation, key, value)` a safe tool
    /// refuses, some published tool on that same operation injects a value the
    /// rejecting rule would catch. The twin is matched structurally (operation,
    /// key, and value), so a future pair is covered without being named here.
    @Test func everyRejectedArgumentHasAPublishedInjectingTwin() async {
        let (server, _) = makeServer(RecordingForwarder())
        let listed = Set(await listedTools(server).compactMap { $0["name"] as? String })
        for tool in GitMageMCPServer.tools {
            for rule in tool.rejects {
                let twin = GitMageMCPServer.tools.first { candidate in
                    guard candidate.name != tool.name, candidate.operation == tool.operation else { return false }
                    return candidate.injects.contains { injected in
                        injected.key == rule.key && rule.value.matches(injected.value.foundation)
                    }
                }
                guard let twin else {
                    let reason =
                        "\(tool.name) refuses args.\(rule.key) = \(rule.value.described) "
                        + "but no tool injects it — the capability is gone, not gated"
                    Issue.record(Comment(rawValue: reason))
                    continue
                }
                #expect(
                    listed.contains(twin.name),
                    Comment(
                        rawValue: "\(twin.name) is the twin for \(tool.name)'s "
                            + "args.\(rule.key) but was not published"))
            }
        }
    }

    @Test func splitVariantsExistAndAreDestructive() async {
        let (server, _) = makeServer(RecordingForwarder())
        let listed = await listedTools(server)
        for name in ["reset_hard", "remove_worktree_force"] {
            guard let entry = listed.first(where: { $0["name"] as? String == name }) else {
                Issue.record("missing \(name)")
                continue
            }
            #expect(destructiveHint(entry))
        }
    }

    @Test func callForwardsOperationAndArguments() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(
            server, "commit",
            arguments: ["repoPath": "/r", "args": ["message": "hello"]])
        #expect(outcome.isError == false)
        #expect(outcome.text == "ok")
        let payload = recorder.lastObject
        #expect(payload?["operation"] as? String == "commit")
        #expect(payload?["repoPath"] as? String == "/r")
        #expect((payload?["args"] as? [String: Any])?["message"] as? String == "hello")
    }

    @Test func resetRejectsHardMode() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(
            server, "reset",
            arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "mode": "hard"]])
        #expect(outcome.isError)
        #expect(recorder.payloads.isEmpty, "a rejected call must never reach the handler")
    }

    @Test func resetAllowsSafeModes() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(
            server, "reset",
            arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "mode": "soft"]])
        #expect(outcome.isError == false)
        #expect((recorder.lastObject?["args"] as? [String: Any])?["mode"] as? String == "soft")
    }

    @Test func resetHardInjectsHardMode() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(server, "reset_hard", arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1"]])
        #expect(recorder.lastObject?["operation"] as? String == "reset")
        #expect((recorder.lastObject?["args"] as? [String: Any])?["mode"] as? String == "hard")
    }

    @Test func removeWorktreeRejectsForce() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(
            server, "remove_worktree",
            arguments: ["repoPath": "/r", "args": ["path": "/w", "force": true]])
        #expect(outcome.isError)
        #expect(recorder.payloads.isEmpty, "a rejected call must never reach the handler")
    }

    @Test func removeWorktreeForceInjectsForce() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(
            server, "remove_worktree_force",
            arguments: ["repoPath": "/r", "args": ["path": "/w"]])
        #expect(recorder.lastObject?["operation"] as? String == "removeWorktree")
        #expect((recorder.lastObject?["args"] as? [String: Any])?["force"] as? Bool == true)
    }

    // MARK: - evasion of the ungated tools' guards
    //
    // The property under test is NOT "the call returned an error" — an error
    // string would still read as a pass if the dangerous argument leaked past
    // it. It is: **a hard reset / a forced worktree removal never happens
    // through the ungated tool**. So every case asserts on the payload actually
    // forwarded to `GitOpActionHandler`, resolved through the handler's OWN
    // coercion expression (`resolvedMode` / `resolvedForce` below).

    /// The exact expression `GitOpActionHandler.run` uses for `reset`'s mode
    /// (`ResetMode(rawValue: (args["mode"] as? String) ?? "mixed")`). Mirrored
    /// here so an evasion case is judged by what the SINK would do, not by what
    /// the guard happens to catch.
    private func resolvedMode(_ payload: [String: Any]?) -> ResetMode? {
        guard let payload else { return nil }  // nothing forwarded → nothing ran
        let args = payload["args"] as? [String: Any] ?? [:]
        return ResetMode(rawValue: (args["mode"] as? String) ?? "mixed")
    }

    /// The exact expression `GitOpActionHandler.run` uses for `removeWorktree`'s
    /// force flag: `(args["force"] as? Bool) ?? false`.
    private func resolvedForce(_ payload: [String: Any]?) -> Bool {
        guard let payload else { return false }
        let args = payload["args"] as? [String: Any] ?? [:]
        return (args["force"] as? Bool) ?? false
    }

    @Test(arguments: resetEvasions)
    func resetNeverPerformsAHardResetHoweverModeIsSpelled(evasion: Evasion) async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(
            server, "reset",
            arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "mode": evasion.value()]])
        #expect(
            resolvedMode(recorder.lastObject) != .hard,
            "reset reached a hard reset via \(evasion.label)")
    }

    @Test func resetIgnoresANestedOrDifferentlyCasedModeKey() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)

        // A nested `args.args.mode` — neither the guard nor the sink reads it.
        _ = await call(
            server, "reset",
            arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "args": ["mode": "hard"]]])
        #expect(resolvedMode(recorder.lastObject) != .hard, "a nested args.mode reached the sink")

        // A `"Mode"` key: missed by the guard, and equally missed by the sink.
        _ = await call(
            server, "reset",
            arguments: ["repoPath": "/r", "args": ["ref": "HEAD~1", "Mode": "hard"]])
        #expect(resolvedMode(recorder.lastObject) != .hard, "a differently-cased Mode key reached the sink")
    }

    @Test(arguments: forceEvasions)
    func removeWorktreeNeverForcesHoweverForceIsSpelled(evasion: Evasion) async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        _ = await call(
            server, "remove_worktree",
            arguments: ["repoPath": "/r", "args": ["path": "/w", "force": evasion.value()]])
        #expect(
            resolvedForce(recorder.lastObject) == false,
            "remove_worktree reached a forced removal via \(evasion.label)")
    }

    @Test func removeWorktreeRejectsNumericTrueAndIgnoresNearMissKeys() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)

        // `1` bridges to NSNumber, which `as? Bool` accepts — so BOTH the guard
        // and the sink read it as true. The guard must therefore reject it, and
        // nothing may be forwarded.
        let numeric = await call(
            server, "remove_worktree",
            arguments: ["repoPath": "/r", "args": ["path": "/w", "force": 1]])
        #expect(numeric.isError)
        #expect(recorder.payloads.isEmpty, "force: 1 was forwarded instead of rejected")

        _ = await call(
            server, "remove_worktree",
            arguments: ["repoPath": "/r", "args": ["path": "/w", "args": ["force": true]]])
        #expect(resolvedForce(recorder.lastObject) == false, "a nested args.force reached the sink")

        _ = await call(
            server, "remove_worktree",
            arguments: ["repoPath": "/r", "args": ["path": "/w", "Force": true]])
        #expect(resolvedForce(recorder.lastObject) == false, "a differently-cased Force key reached the sink")
    }

    /// Pins the coupling the `reset` guard depends on, **through the real
    /// sink**. The guard rejects only the LITERAL `mode: "hard"`; every spelling
    /// in `resetEvasions` is safe solely because `GitOpActionHandler` parses the
    /// mode with an exact, case-sensitive `ResetMode(rawValue:)` and refuses
    /// anything else before it reaches git.
    ///
    /// This drives the actual handler rather than a mirror of it, so making it
    /// tolerant (`rawValue: mode.lowercased()`, a trimming step, an alias table)
    /// fails HERE — which is the whole point: a mirrored expression in the test
    /// would keep passing while `"Hard"` became a live, ungated hard reset.
    ///
    /// Git-free: the `reset` branch validates `ref` and then `mode`, returning
    /// the mode error before it ever calls `GitRepositoryClient`.
    @Test func theResetSinkRejectsEveryNonExactSpellingOfHard() async {
        let handler = GitOpActionHandler(client: GitRepositoryClient())
        for spelling in ["Hard", "HARD", " hard", "hard "] {
            let payload =
                #"{"operation":"reset","repoPath":"/nonexistent","args":{"ref":"HEAD~1","mode":"\#(spelling)"}}"#
            let result = await handler.run(payload)
            #expect(result.isError, "GitOpActionHandler now accepts mode \"\(spelling)\"")
            #expect(
                result.text.contains("must be soft, mixed, or hard"),
                "GitOpActionHandler now coerces mode \"\(spelling)\" instead of refusing it — widen GitMageMCPServer's reset guard in lockstep, or the ungated reset tool becomes a live hard reset"
            )
        }
        // The exact spelling is the one the guard already refuses, so it must
        // stay the ONLY spelling the sink accepts.
        #expect(ResetMode(rawValue: "hard") == .hard)
    }

    @Test func runtimeCachesOneServerPerHostAndEvictsIt() async {
        let host = FakeHostServices(context: RecordingContextRegistry())
        let first = GitMageRuntime.mcpServer(for: host)
        #expect(GitMageRuntime.mcpServer(for: host) === first)

        GitMageRuntime.teardown(instance: GitMageRuntime.instance(of: host), host: host)
        #expect(GitMageRuntime.mcpServer(for: host) !== first)
    }

    @Test func appPublishesTheRuntimeServer() async {
        let host = FakeHostServices(context: RecordingContextRegistry())
        #expect(GitMageApp.makeMCPServer(host: host) === GitMageRuntime.mcpServer(for: host))
    }

    // MARK: - multi-guard capability (array shape)
    //
    // No real git operation needs two guarded arguments today, so this drives
    // a test-only fixture pair through the REAL gate/inject logic in
    // `GitMageMCPServer.invoke` rather than inventing a fabricated git
    // operation. It proves the array shape actually supports what a single
    // optional could not: a tool refusing on ANY of several rules, and its
    // twin injecting ALL of them.

    /// A hypothetical safe tool that must refuse `mode: "hard"` OR
    /// `force: true`, individually or together.
    private static let fixtureSafe = GitMageMCPServer.Tool(
        "fixture_multi_safe", "fixtureMulti", "test-only two-guard fixture",
        argsHint: "None.",
        rejects: [
            GitMageMCPServer.GuardRule("mode", .string("hard")),
            GitMageMCPServer.GuardRule("force", .bool(true)),
        ])

    /// Its destructive twin, which must inject BOTH values.
    private static let fixtureDestructive = GitMageMCPServer.Tool(
        "fixture_multi_destructive", "fixtureMulti", "test-only two-guard fixture twin",
        destructive: true, argsHint: "None.",
        injects: [
            GitMageMCPServer.GuardRule("mode", .string("hard")),
            GitMageMCPServer.GuardRule("force", .bool(true)),
        ])

    private func invokeFixture(
        _ tool: GitMageMCPServer.Tool, args: [String: Any],
        recorder: RecordingForwarder
    ) async -> (text: String, isError: Bool) {
        let payload: [String: Any] = ["repoPath": "/r", "args": args]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let result = await GitMageMCPServer.invoke(
            tool, arguments: String(decoding: data, as: UTF8.self),
            forward: { await recorder.forward($0) })
        return (result.text, result.isError)
    }

    @Test func fixtureSafeToolRefusesEitherGuardedArgumentAlone() async {
        let recorder = RecordingForwarder()
        let byMode = await invokeFixture(Self.fixtureSafe, args: ["mode": "hard"], recorder: recorder)
        #expect(byMode.isError)
        #expect(recorder.payloads.isEmpty, "mode: hard alone must be refused, not forwarded")

        let byForce = await invokeFixture(Self.fixtureSafe, args: ["force": true], recorder: recorder)
        #expect(byForce.isError)
        #expect(recorder.payloads.isEmpty, "force: true alone must be refused, not forwarded")
    }

    @Test func fixtureSafeToolRefusesBothGuardedArgumentsTogether() async {
        let recorder = RecordingForwarder()
        let outcome = await invokeFixture(
            Self.fixtureSafe, args: ["mode": "hard", "force": true],
            recorder: recorder)
        #expect(outcome.isError)
        #expect(recorder.payloads.isEmpty, "mode: hard + force: true together must be refused")
    }

    @Test func fixtureSafeToolAllowsNeitherGuardedArgument() async {
        let recorder = RecordingForwarder()
        let outcome = await invokeFixture(Self.fixtureSafe, args: ["mode": "soft"], recorder: recorder)
        #expect(outcome.isError == false)
        #expect(recorder.lastObject != nil)
    }

    @Test func fixtureDestructiveTwinInjectsBothGuardedArguments() async {
        let recorder = RecordingForwarder()
        _ = await invokeFixture(Self.fixtureDestructive, args: [:], recorder: recorder)
        let args = recorder.lastObject?["args"] as? [String: Any]
        #expect(args?["mode"] as? String == "hard")
        #expect(args?["force"] as? Bool == true)
    }

    @Test func missingRepoPathIsAnErrorNotAForwardedCall() async {
        let recorder = RecordingForwarder()
        let (server, _) = makeServer(recorder)
        let outcome = await call(server, "status", arguments: [:])
        #expect(outcome.isError)
        #expect(recorder.payloads.isEmpty)
    }
}
