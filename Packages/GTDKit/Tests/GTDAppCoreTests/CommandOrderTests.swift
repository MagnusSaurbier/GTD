import Testing
import Foundation
import GTDModel
@testable import GTDAppCore

/// T40-2: commands are serialised, and `send(deriving:)` builds its command only once it is its
/// turn. Without that, a command built from `snapshot` while another one is already in flight
/// writes the other one's fields back — which is exactly how the autosaving action editor
/// (`FeatureOverview.ActionEditModel`) used to lose a remote change mid-edit.
@MainActor
struct CommandOrderTests {

    /// A place an escaping `@MainActor` closure can record what it saw.
    @MainActor private final class Box {
        var seen: String?
    }

    private func makeModel() -> (AppModel, NoteID) {
        let id = NoteID(path: "Actions/Thing.md")
        var snapshot = VaultSnapshot.empty
        snapshot.actions = [
            Action(id: id, title: "Thing", status: .backlog, why: "old why", what: "old what"),
        ]
        let model = AppModel(
            backend: InMemoryBackend(snapshot: snapshot), snapshot: snapshot)
        return (model, id)
    }

    @Test func aDerivedCommandSeesWhatTheCommandBeforeItWrote() async throws {
        let (model, id) = makeModel()
        var remote = try #require(model.snapshot.action(id))
        remote.what = "remote what"

        let first = Task { try await model.send(.updateAction(remote)) }
        await Task.yield()                       // let it reach the backend and take the queue

        let box = Box()
        try await model.send(deriving: {
            box.seen = model.snapshot.action(id)?.what
            guard var next = model.snapshot.action(id) else { return nil }
            next.why = "my why"
            return .updateAction(next)
        })
        try await first.value

        // The derived command was built *after* the in-flight one landed …
        #expect(box.seen == "remote what")
        // … so it did not write the old value back.
        #expect(model.snapshot.action(id)?.what == "remote what")
        #expect(model.snapshot.action(id)?.why == "my why")
    }

    @Test func returningNilCancelsTheCommand() async throws {
        let (model, _) = makeModel()
        let before = model.snapshot
        try await model.send(deriving: { nil })
        #expect(model.snapshot == before)
    }

    @Test func commandsRunInCallOrder() async throws {
        let (model, id) = makeModel()
        var first = try #require(model.snapshot.action(id))
        first.why = "first"
        var second = first
        second.why = "second"

        let a = Task { try await model.send(.updateAction(first)) }
        await Task.yield()
        let b = Task { try await model.send(.updateAction(second)) }
        try await a.value
        try await b.value

        #expect(model.snapshot.action(id)?.why == "second")
    }
}
