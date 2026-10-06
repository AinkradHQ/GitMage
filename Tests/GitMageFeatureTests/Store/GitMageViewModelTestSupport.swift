import Foundation
import AinkradAppKit
import Testing

@testable import GitMageFeature

extension GitMageViewModel {
    /// The tests hold a whole fake host; the model takes only the two capabilities it uses.
    convenience init(host: HostServices) {
        self.init(documents: host.documents, signals: host.signals)
    }
}

/// Shared setup for the `GitMageViewModel` suites. The model's loads are
/// `Task { @MainActor }`, so tests poll instead of sleeping a fixed time.
@MainActor
func makeViewModel(_ paths: [String], active: String? = nil) -> GitMageViewModel {
    let model = GitMageViewModel(host: FakeHostServices(context: RecordingContextRegistry()))
    model.repos = paths.map {
        GitMageRepoConfig(id: $0, path: $0, name: ($0 as NSString).lastPathComponent, draftCommitMessage: "", lastBranch: "")
    }
    model.activeRepoID = active ?? paths.first
    return model
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 15, _ what: String = "condition", _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    Issue.record("timed out waiting for \(what)")
}

/// True once nothing is loading and no operation is in flight.
@MainActor
func isIdle(_ model: GitMageViewModel) -> Bool { !model.isLoading && model.activeOperation == nil }
