import Testing
import Foundation
import GTDModel
@testable import GTDAppCore

/// A backend that writes behind the UI reports a refused write *after* `perform` returned.
/// `AppModel` keeps it where the shell's alert finds it — and where the next command, which
/// clears `lastError`, cannot take it away before the person has read it.
@MainActor
struct WriteFailureTests {

    private struct Refusal: Error {}

    @Test func aReportedWriteFailureStaysUntilItIsDismissed() async throws {
        let backend = ReportingBackend()
        let model = AppModel(backend: backend)
        await backend.subscribed()

        backend.report(WriteFailure(label: "Filed to Next", reason: Refusal(), discarded: 2))
        try await eventually { model.writeFailure != nil }
        #expect(model.writeFailure?.label == "Filed to Next")

        #expect(await model.perform(.archiveCompleted))
        #expect(model.writeFailure != nil, "a later command does not dismiss it")

        model.clearError()
        #expect(model.writeFailure == nil)
    }

    @Test func theMessageSaysWhatWasRevertedAndWhatWentWithIt() {
        let text = WriteFailure(label: "Done", reason: Refusal(), discarded: 1).description
        #expect(text.contains("“Done” could not be saved"))
        #expect(text.contains("One later change was reverted with it."))
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(condition())
    }
}

/// `InMemoryBackend` plus a `writeFailures()` stream the test feeds.
private final class ReportingBackend: GTDBackend, @unchecked Sendable {
    private let inner = InMemoryBackend(snapshot: .empty)
    private let lock = NSLock()
    private var continuation: AsyncStream<WriteFailure>.Continuation?

    func writeFailures() -> AsyncStream<WriteFailure> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func subscribed() async {
        while !isSubscribed { try? await Task.sleep(nanoseconds: 1_000_000) }
    }

    private var isSubscribed: Bool { lock.withLock { continuation != nil } }

    func report(_ failure: WriteFailure) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(failure)
    }

    func snapshots() -> AsyncStream<SnapshotUpdate> { inner.snapshots() }
    func currentUpdate() async -> SnapshotUpdate { await inner.currentUpdate() }
    func perform(_ command: GTDCommand) async throws -> [AppPrompt] { try await inner.perform(command) }
    func undo() async throws { try await inner.undo() }
    func undoLabel() async -> String? { await inner.undoLabel() }
}
