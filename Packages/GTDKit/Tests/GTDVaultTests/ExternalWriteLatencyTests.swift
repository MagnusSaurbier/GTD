#if os(macOS)
import Foundation
import GTDFixtures
import GTDModel
import Testing
@testable import GTDVault

/// The whole pipeline on a real folder: FSEvents → hint → debounce → targeted re-index → the
/// store's stream. The write is a **plain** one — no `NSFileCoordinator`, exactly what Obsidian
/// or a script does — which is the case the presenter never hears about and that used to wait
/// for the 5 s poll.
@Suite("An external write reaches the snapshot at once", .serialized)
struct ExternalWriteLatencyTests {

    @Test func aPlainFileDroppedIntoTheInboxShowsUpWellUnderASecond() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileVaultStore(root: root)       // the production file system and watchers
        try await store.activate()
        defer { Task { await store.close() } }
        try await Task.sleep(nanoseconds: 300_000_000)   // let the FSEvents stream come up

        let started = ContinuousClock.now
        try "call the dentist\n".write(
            to: root.appendingPathComponent("Inbox/From a script.md"),
            atomically: true, encoding: .utf8)

        let arrived = try await eventually {
            await store.currentSnapshot.inbox.contains { $0.text == "call the dentist" }
        }
        let latency = arrived - started
        #expect(latency < .milliseconds(1_000), "took \(latency) — the 5 s poll would be the only other way")
    }

    @Test func anEditAMoveAndARemovalArriveToo() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileVaultStore(root: root)
        try await store.activate()
        defer { Task { await store.close() } }
        try await Task.sleep(nanoseconds: 300_000_000)

        let action = try #require(await store.currentSnapshot.actions.first { $0.status == .next })
        let file = root.appendingPathComponent(action.id.path)

        // An edit in place, as Obsidian saves.
        let text = try String(contentsOf: file, encoding: .utf8)
        try text.replacingOccurrences(of: "status: next", with: "status: someday")
            .write(to: file, atomically: false, encoding: .utf8)
        try await eventually {
            await store.currentSnapshot.action(action.id)?.status == .someday
        }

        // A rename in the same folder.
        let renamed = file.deletingLastPathComponent().appendingPathComponent("Renamed outside.md")
        try FileManager.default.moveItem(at: file, to: renamed)
        try await eventually {
            let snapshot = await store.currentSnapshot
            return snapshot.action(action.id) == nil
                && snapshot.actions.contains { $0.title == "Renamed outside" }
        }

        // And gone.
        try FileManager.default.removeItem(at: renamed)
        try await eventually {
            await !store.currentSnapshot.actions.contains { $0.title == "Renamed outside" }
        }
    }

    /// Polls every 10 ms, up to 3 s — below the 5 s poll, so only the event path can pass.
    @discardableResult
    private func eventually(_ condition: () async -> Bool) async throws -> ContinuousClock.Instant {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await condition() { return ContinuousClock.now }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("the change never arrived through the event path")
        return ContinuousClock.now
    }
}
#endif
