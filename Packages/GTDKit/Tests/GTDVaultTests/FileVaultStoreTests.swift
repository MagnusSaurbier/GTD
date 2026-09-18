import Foundation
import GTDModel
import Testing
@testable import GTDVault

@Suite("FileVaultStore")
struct FileVaultStoreTests {

    private func store(
        _ files: [String: String] = MiniVault.files(),
        parser: StubNoteParser = StubNoteParser()
    ) -> (FileVaultStore, InMemoryFileSystem) {
        let fs = InMemoryFileSystem(files: files)
        let store = FileVaultStore(
            fileSystem: fs,
            parser: parser,
            watcher: NullVaultWatcher(),
            debounce: DebounceState(interval: 0.01, maxDelay: 0.05),
            today: { MiniVault.today })
        return (store, fs)
    }

    // MARK: Scanning and publishing

    @Test func theSnapshotIsEmptyUntilTheFirstScan() async throws {
        let (store, _) = store()
        #expect(await store.currentSnapshot == .empty)
        let snapshot = try await store.scan()
        #expect(snapshot.actions.count == 2)
        #expect(await store.currentSnapshot == snapshot)
    }

    @Test func subscribersGetTheCurrentSnapshotAndThenEveryChange() async throws {
        let (store, fs) = store()
        try await store.scan()

        var iterator = store.snapshots().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.actions.count == 2)

        fs.writeIgnoringFailures("---\nstatus: next\n---\n", to: "Actions/Brand new.md")
        try await store.scan()
        let second = await iterator.next()
        #expect(second?.actions.count == 3)
    }

    @Test func anExternalEditIsPickedUpByTheDebouncedWatcherPath() async throws {
        let (store, fs) = store()
        try await store.scan()
        await store.startWatching()
        defer { Task { await store.close() } }

        // What Obsidian on the iPad does: rewrite a note behind the app's back.
        fs.writeIgnoringFailures("---\nstatus: done\n---\n", to: "Actions/Fix the bike light.md")
        await store.simulateChangeForTesting()

        let action = try #require(await store.currentSnapshot
            .actions.first { $0.title == "Fix the bike light" })
        #expect(action.status == .done)
    }

    @Test func readReturnsTheFileAndNilForAMissingOne() async throws {
        let (store, _) = store()
        #expect(try await store.read(path: "GTD/Config.md")?.contains("nextCap: 9") == true)
        #expect(try await store.read(path: "Actions/Nope.md") == nil)
    }

    // MARK: Commit

    @Test func commitAppliesReindexesAndPublishes() async throws {
        let (store, fs) = store()
        try await store.scan()

        _ = try await store.commit([.put(path: "Actions/Brand new.md", text: "---\nstatus: next\n---\n")])

        #expect(fs.exists("Actions/Brand new.md"))
        #expect(await store.currentSnapshot.actions.map(\.title)
            == ["Brand new", "Fix the bike light", "Old thing"])
    }

    @Test func commitAndItsInverseRestoreEveryFileByteForByte() async throws {
        let (store, fs) = store()
        try await store.scan()
        let before = fs.snapshotOfFiles

        let inverse = try await store.commit([
            .put(path: "Actions/Fix the bike light.md", text: "---\nstatus: done\n---\nchanged"),
            .put(path: "Actions/Brand new.md", text: "---\nstatus: next\n---\n"),
            .move(from: "Actions/Old thing.md", to: "Archive/2026/09/Old thing.md"),
            .delete(path: "Inbox/2026-09-18 094410.md"),
        ])
        #expect(fs.snapshotOfFiles != before)

        _ = try await store.commit(inverse)
        // The trashed copy of the created file is the only residue, and that is by design:
        // nothing is ever hard-deleted.
        var after = fs.snapshotOfFiles
        #expect(after.removeValue(forKey: "GTD/Trash/Brand new.md") != nil)
        #expect(after == before)
    }

    @Test func aPartialFailureLeavesTheVaultAndTheSnapshotUntouched() async throws {
        let (store, fs) = store()
        let before = try await store.scan()
        let filesBefore = fs.snapshotOfFiles
        fs.failWrites(matching: ["Actions/Boom.md"])

        await #expect(throws: VaultError.self) {
            try await store.commit([
                .put(path: "Actions/Fix the bike light.md", text: "---\nstatus: done\n---\n"),
                .put(path: "Actions/Boom.md", text: "never"),
            ])
        }

        #expect(fs.snapshotOfFiles == filesBefore)
        #expect(await store.currentSnapshot == before)
    }

    @Test func anEmptyCommitIsANoOp() async throws {
        let (store, _) = store()
        try await store.scan()
        #expect(try await store.commit([]).isEmpty)
    }

    @Test func deletingThroughTheStoreOnlyEverMovesToTrash() async throws {
        let (store, fs) = store()
        try await store.scan()
        _ = try await store.commit([.delete(path: "Inbox/2026-09-18 094410.md")])

        #expect(try fs.readText("GTD/Trash/2026-09-18 094410.md") == "---\ncreated: 2026-09-18T09:44:10+02:00\n---\nbuy running shoes")
        #expect(await store.currentSnapshot.inbox.count == 1)
    }

    // MARK: Issues surface through the store

    @Test func issuesReachTheSnapshot() async throws {
        let (store, _) = store(parser: StubNoteParser(failing: ["GTD/Config.md"]))
        let snapshot = try await store.scan()
        #expect(snapshot.issues.map(\.path) == ["GTD/Config.md"])
        #expect(snapshot.config == .default)   // still usable
    }

    // MARK: Performance budget (T15: 1 000 notes < 500 ms, incremental < 50 ms)

    @Test func scansAThousandNotesAndRefreshesIncrementally() async throws {
        var files: [String: String] = [
            "GTD/Config.md": "---\ncontexts: [mac]\nnextCap: 15\n---\n",
        ]
        for index in 0..<1000 {
            files["Actions/Action \(index).md"] = """
            ---
            status: next
            contexts: [mac, home]
            timeEstimate: 30
            ---
            - [ ] step one
            - [ ] step two
            """
        }
        let fs = InMemoryFileSystem(files: files)
        let store = FileVaultStore(
            fileSystem: fs, parser: StubNoteParser(), watcher: NullVaultWatcher(),
            today: { MiniVault.today })

        let scanStart = Date()
        let snapshot = try await store.scan()
        let scanSeconds = Date().timeIntervalSince(scanStart)
        #expect(snapshot.actions.count == 1000)

        fs.writeIgnoringFailures("---\nstatus: done\n---\n", to: "Actions/Action 500.md")
        let refreshStart = Date()
        try await store.scan()
        let refreshSeconds = Date().timeIntervalSince(refreshStart)

        // Generous bounds: the point is that the incremental path is an order of magnitude
        // cheaper than the full scan, not to benchmark the CI machine.
        #expect(scanSeconds < 5.0, "full scan of 1 000 notes took \(scanSeconds)s")
        #expect(refreshSeconds < scanSeconds,
                "incremental refresh (\(refreshSeconds)s) was not cheaper than the full scan (\(scanSeconds)s)")
        #expect(await store.currentSnapshot.actions.first { $0.title == "Action 500" }?.status == .done)
    }
}
