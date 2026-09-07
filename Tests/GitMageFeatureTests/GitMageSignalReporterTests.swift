import Testing
import Foundation
import AinkradAppKit
@testable import GitMageFeature

@MainActor
@Suite("Git Mage's notification vocabulary")
struct GitMageSignalReporterTests {
    private final class RecordingEmitter: PluginSignalEmitter {
        struct Call {
            let kind: String
            let severity: SignalSeverity
            let title: String
            let body: String?
            let importance: SignalImportance
            let dedupeKey: String?
        }
        var calls: [Call] = []

        func emit(kind: String, severity: SignalSeverity, title: String, body: String?,
                  importance: SignalImportance, deepLink: SignalDeepLink?,
                  actions: [SignalAction], dedupeKey: String?) {
            calls.append(Call(kind: kind, severity: severity, title: title, body: body,
                              importance: importance, dedupeKey: dedupeKey))
        }
        func own(limit: Int) -> [SignalEvent] { [] }
        func handleAction(_ actionID: String,
                          _ handler: @escaping @MainActor () async -> Void) -> AgentActionToken {
            AgentActionToken()
        }
        func removeActionHandler(_ token: AgentActionToken) {}
    }

    private func reporter() -> (GitMageSignalReporter, RecordingEmitter) {
        let emitter = RecordingEmitter()
        return (GitMageSignalReporter(signals: emitter), emitter)
    }

    @Test("a failed operation names the repo by its folder, not its whole path")
    func failureNamesTheRepo() {
        // A notification title is read at a glance; an absolute path pushes the
        // part that identifies the repo off the end.
        let (reporter, emitter) = self.reporter()
        reporter.operationFailed(operation: "push",
                                 repository: "/Users/x/Home/Projects/Ainkrad/AinkradRaven",
                                 reason: "rejected: non-fast-forward")
        #expect(emitter.calls.count == 1)
        #expect(emitter.calls[0].kind == "git.operation-failed")
        #expect(emitter.calls[0].severity == .failure)
        #expect(emitter.calls[0].title == "git push failed in AinkradRaven")
        #expect(emitter.calls[0].importance == .normal, "a failed command is not urgent")
    }

    @Test("a trailing slash does not produce an empty repo name")
    func trailingSlash() {
        let (reporter, emitter) = self.reporter()
        reporter.operationFailed(operation: "fetch", repository: "/Users/x/repo/",
                                 reason: "timeout")
        #expect(emitter.calls[0].title.contains("repo"))
    }

    @Test("retrying a failing push coalesces into one row")
    func failuresDedupePerOperationAndRepo() {
        let (reporter, emitter) = self.reporter()
        reporter.operationFailed(operation: "push", repository: "/a/b", reason: "denied")
        #expect(emitter.calls[0].dedupeKey == "gitmage.failed:/a/b:push")
    }

    @Test("a conflict is the urgent case, and says nothing will apply until resolved")
    func conflictIsUrgent() {
        // A conflict is not a failure — the command did what it was asked —
        // but the repository is stuck until a human resolves it.
        let (reporter, emitter) = self.reporter()
        reporter.conflictsDetected(operation: "pull", repository: "/a/AinkradLore",
                                   files: ["Sources/A.swift", "Sources/B.swift"])
        #expect(emitter.calls[0].kind == "git.conflict")
        #expect(emitter.calls[0].severity == .warning)
        #expect(emitter.calls[0].importance == .urgent)
        #expect(emitter.calls[0].title == "AinkradLore has 2 conflicted files")
        #expect(emitter.calls[0].body?.contains("Sources/A.swift") == true)
        #expect(emitter.calls[0].body?.contains("until these are resolved") == true)
    }

    @Test("one conflicted file reads as singular")
    func singleConflict() {
        let (reporter, emitter) = self.reporter()
        reporter.conflictsDetected(operation: "merge", repository: "/a/r", files: ["X.swift"])
        #expect(emitter.calls[0].title == "r has 1 conflicted file")
    }

    @Test("a long conflict list is truncated with a count, not dumped")
    func manyConflicts() {
        let (reporter, emitter) = self.reporter()
        reporter.conflictsDetected(operation: "rebase", repository: "/a/r",
                                   files: (1...9).map { "F\($0).swift" })
        #expect(emitter.calls[0].body?.contains("and 4 more") == true)
    }

    @Test("conflicts dedupe per REPOSITORY, not per operation")
    func conflictDedupeIsPerRepo() {
        // A repository has one conflicted state however it got there; two rows
        // for one situation would read as two things to resolve.
        let (reporter, emitter) = self.reporter()
        reporter.conflictsDetected(operation: "pull", repository: "/a/r", files: ["X"])
        reporter.conflictsDetected(operation: "rebase", repository: "/a/r", files: ["X"])
        #expect(emitter.calls[0].dedupeKey == emitter.calls[1].dedupeKey)
    }

    @Test("an empty conflict list emits nothing at all")
    func noConflictsIsSilent() {
        let (reporter, emitter) = self.reporter()
        reporter.conflictsDetected(operation: "pull", repository: "/a/r", files: [])
        #expect(emitter.calls.isEmpty)
    }

    @Test("a long success is reported with its duration")
    func longSuccess() {
        let (reporter, emitter) = self.reporter()
        reporter.operationFinished(operation: "clone", repository: "/a/r", duration: 214)
        #expect(emitter.calls[0].kind == "git.operation-finished")
        #expect(emitter.calls[0].severity == .success)
        #expect(emitter.calls[0].body?.contains("214 seconds") == true)
    }

    @Test("every kind Git Mage emits is one the host will accept")
    func kindsAreValid() {
        let (reporter, emitter) = self.reporter()
        reporter.operationFailed(operation: "push", repository: "/a/r", reason: "x")
        reporter.operationFinished(operation: "clone", repository: "/a/r", duration: 99)
        reporter.conflictsDetected(operation: "pull", repository: "/a/r", files: ["X"])
        #expect(emitter.calls.count == 3)
        for call in emitter.calls {
            #expect(SignalKind.isValid(call.kind), "\(call.kind) would be rejected at ingest")
        }
    }
}
