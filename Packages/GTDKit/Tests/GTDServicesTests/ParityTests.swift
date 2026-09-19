import Foundation
import GTDAppCore
import GTDFixtures
import GTDModel
import GTDServices
import GTDVault
import Testing

/// The contract between the two backends: **the same commands produce the same vault.**
///
/// `InMemoryBackend` is the reducer alone; `VaultBackend` is the reducer plus a diff, a codec and
/// a file system. Every feature is developed against the first and ships on the second, so any
/// difference between them is a bug the features cannot see. The comparison is made against a
/// **fresh scan** of the vault, not against what `VaultBackend` remembers — the claim is about
/// the files, not about a cache.
@Suite("Both backends, one result")
struct ParityTests {

    @Test func theSameCommandScriptGivesTheSameSnapshot() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()

        // Both start from the same place: what the vault says after housekeeping.
        let start = await vault.backend.currentSnapshot()
        let memory = InMemoryBackend(
            snapshot: start, env: { Fixtures.reducerEnv(deviceID: "test-device") })

        for step in CommandScript.steps {
            let snapshot = await memory.currentSnapshot()
            let command = try #require(step.make(snapshot), "no command for step \(step.name)")

            let inMemory = await outcome { try await memory.perform(command) }
            let onDisk = await outcome { try await vault.backend.perform(command) }
            #expect(inMemory == onDisk, "step \(step.name) behaved differently")

            let scanned = SnapshotShape(try vault.rescan())
            let expected = SnapshotShape(await memory.currentSnapshot())
            #expect(scanned == expected, """
                after step \(step.name):
                \(scanned.difference(from: expected))
                """)
        }

        // Nothing unreadable was written along the way.
        #expect(try vault.rescan().issues.isEmpty)
    }

    /// Parity also has to hold for a refusal: the reducer says no *before* anything is written,
    /// so the vault must be untouched on both sides.
    @Test func aRefusedCommandChangesNeitherBackend() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()
        let memory = InMemoryBackend(
            snapshot: start, env: { Fixtures.reducerEnv(deviceID: "test-device") })
        let before = try vault.files()

        // The sample vault sits at 14/15; two more Next actions are one too many.
        let fill = GTDCommand.createAction(ActionDraft(title: "Fills the last slot", status: .next))
        let overflow = GTDCommand.createAction(ActionDraft(title: "One too many", status: .next))

        _ = try await memory.perform(fill)
        _ = try await vault.backend.perform(fill)

        let inMemory = await outcome { try await memory.perform(overflow) }
        let onDisk = await outcome { try await vault.backend.perform(overflow) }
        #expect(inMemory.contains("nextCapReached"), "got \(inMemory)")
        #expect(onDisk == inMemory)

        let after = try vault.files()
        #expect(after.count == before.count + 1, "only the first action was written")
        #expect(SnapshotShape(try vault.rescan()) == SnapshotShape(await memory.currentSnapshot()))
    }

    /// Both backends answer `undoLabel()` with the same sentence, so the toast reads the same
    /// on fixtures and on the real vault (STYLEGUIDE §3.8).
    @Test func undoLabelsAgree() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()
        let memory = InMemoryBackend(
            snapshot: start, env: { Fixtures.reducerEnv(deviceID: "test-device") })

        for step in CommandScript.steps.prefix(14) {
            let command = try #require(step.make(await memory.currentSnapshot()))
            _ = try? await memory.perform(command)
            _ = try? await vault.backend.perform(command)
            let expected = await memory.undoLabel()
            let actual = await vault.backend.undoLabel()
            #expect(actual == expected, "after \(step.name)")
        }
    }

    /// Runs the work and reduces it to a comparable string: both backends must succeed with the
    /// same prompts or fail with the same error.
    private func outcome(_ work: () async throws -> [AppPrompt]) async -> String {
        do {
            let prompts = try await work()
            return "ok \(prompts.map { "\($0)" }.sorted())"
        } catch {
            return "error \(error)"
        }
    }
}
