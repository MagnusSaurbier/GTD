import Testing
import Foundation
import GTDModel
import GTDMarkdown
import GTDAppCore
import GTDFixtures
import GTDServices
import GTDVault

/// N3 through the whole stack: two devices, a late sync and a conflict copy, on a temp copy of
/// the sample vault (T41).
///
/// `GTDVaultTests` proves each piece on its own. This suite runs the situations that only appear
/// when two `VaultBackend`s (or a backend and "Obsidian") touch the same folder — the ones that
/// would cost the user data rather than a redraw.
@Suite struct SyncScenarioTests {

    /// N3 §7.2 — the routine log is one file per day **per device**, so two devices logging the
    /// same routine on the same day must produce two files and lose nothing. This is the one
    /// place the app appends to "the same" note from two machines.
    @Test func twoDevicesLoggingTheSameRoutineOnTheSameDayKeepBothLogs() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mac = try backend(at: root, deviceID: "mac-1")
        let phone = try backend(at: root, deviceID: "iphone-2")
        defer { mac.cleanUp(); phone.cleanUp() }
        try await mac.vault.start()
        try await phone.vault.start()

        let snapshot = await mac.vault.currentSnapshot()
        let routine = try #require(snapshot.routines.first { $0.title == "Morning" })
        let first = routine.steps[0].id
        let second = routine.steps[1].id

        // The two devices interleave, each unaware of the other until it re-scans.
        _ = try await mac.vault.perform(.logRoutineStep(routine: routine.id, stepID: first, .done))
        _ = try await phone.vault.perform(.logRoutineStep(routine: routine.id, stepID: first, .skipped))
        _ = try await mac.vault.perform(.logRoutineStep(routine: routine.id, stepID: second, .done))

        let files = try SampleVault.read(tree: root)
        let day = Fixtures.today.iso
        let macLog = try #require(files["GTD/RoutineLog/\(day)--mac-1.md"],
                                  "the Mac's own log for today")
        let phoneLog = try #require(files["GTD/RoutineLog/\(day)--iphone-2.md"],
                                    "the phone's own log for today — never the Mac's file")
        #expect(macLog.contains("result: done"))
        #expect(phoneLog.contains("result: skipped"))

        // A cold scan sees both devices' entries for today, and nothing was overwritten.
        let rescanned = try rescan(root)
        let today = rescanned.routineLog.filter { $0.day == Fixtures.today && $0.routine == "Morning" }
        #expect(Set(today.map(\.device)) == ["mac-1", "iphone-2"])
        #expect(today.filter { $0.device == "mac-1" }.count == 2)
        #expect(today.filter { $0.device == "iphone-2" }.count == 1)
        #expect(rescanned.issues.isEmpty)
    }

    /// N6 × N3 — undo is refused, never forced, when a file it would rewrite changed behind the
    /// app's back. The vault must be exactly as the other writer left it.
    @Test func anUndoIsRefusedAfterAnotherWriterTouchedTheSameFile() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        try await vault.backend.start()

        let snapshot = await vault.backend.currentSnapshot()
        let action = try #require(snapshot.actions.first { $0.status == .next })
        _ = try await vault.backend.perform(.setStatus(action.id, .backlog, waiting: nil))

        // "Obsidian on the other device" edits the same note a moment later.
        let edited = try #require(try vault.text(action.id.path)) + "\nA line typed elsewhere.\n"
        try vault.fileSystem.writeText(edited, to: action.id.path)
        let before = try vault.filesOutsideTheTrash()

        await #expect(throws: ServiceError.undoStale(path: action.id.path)) {
            try await vault.backend.undo()
        }
        #expect(try vault.filesOutsideTheTrash() == before,
                "a refused undo must not write a single byte")
        #expect(try #require(try vault.text(action.id.path)).contains("A line typed elsewhere."))
    }

    /// N3 §7.5 — a conflict copy is *reported*, never resolved for the user, and the real note
    /// keeps working while it sits there.
    @Test func aConflictCopyIsReportedAndNothingIsTouched() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        try await vault.backend.start()

        let snapshot = await vault.backend.currentSnapshot()
        let action = try #require(snapshot.actions.first { $0.status == .next })
        let original = try #require(try vault.text(action.id.path))
        let copyPath = action.id.path.replacingOccurrences(of: ".md", with: " 2.md")
        try vault.fileSystem.writeText(original, to: copyPath)

        let rescanned = try vault.rescan()
        #expect(rescanned.issues.contains { $0.path == copyPath },
                "the conflict copy is a VaultIssue: \(rescanned.issues)")
        #expect(rescanned.actions.contains { $0.id == action.id }, "the real note still loads")

        // Working on the real note is unaffected, and the copy is left exactly as it was.
        _ = try await vault.backend.perform(.setStatus(action.id, .backlog, waiting: nil))
        #expect(try vault.text(copyPath) == original, "the app never rewrites a conflict copy")
        #expect(try #require(try vault.text(action.id.path)).contains("status: backlog"))
    }

    /// A file another device has not finished syncing is an issue, not a silent hole: it is
    /// reported, its download is requested, and the rest of the vault still loads.
    @Test func anEvictedFileBecomesAnIssueAndItsDownloadIsRequested() async throws {
        let fileSystem = InMemoryFileSystem(files: SampleVault.files)
        let evicted = "Actions/Book the dentist appointment.md"
        #expect(SampleVault.files[evicted] != nil, "the fixture this test is built on")
        fileSystem.evict(evicted)

        var index = VaultIndex()
        try index.refresh(using: fileSystem)
        let snapshot = index.snapshot(today: Fixtures.today)

        #expect(snapshot.issues.contains { $0.path == evicted })
        #expect(fileSystem.requestedDownloads.contains(evicted))
        #expect(!snapshot.actions.isEmpty, "everything that did download is still there")
        #expect(fileSystem.snapshotOfFiles[evicted] != nil, "and the file itself is untouched")
    }

    // MARK: - Rename while the note is open somewhere else

    /// The last of the brief's sync scenarios: a note is **renamed while a detail view holds it
    /// open**. A rename is the one edit that changes a note's identity (`Actions/<Title>.md`,
    /// A1), so everything still pointing at the old `NoteID` — the open editor, the project
    /// note's step link, the navigation path — has to follow or refuse. It must never write the
    /// old path back, which would resurrect a second copy of the action.
    ///
    /// `ActionEditModel` (`FeatureOverviewTests`) covers the editor's half: it re-points itself
    /// after its own rename and reports `isMissing` when the note disappeared under it. This
    /// covers the vault's half, on real files.
    @Test func renamingANoteThatIsOpenElsewhereNeverResurrectsTheOldFile() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mac = try backend(at: root, deviceID: "mac-1")
        defer { mac.cleanUp() }
        try await mac.vault.start()

        // An action with a project, so the step link has to follow the rename too.
        let snapshot = await mac.vault.currentSnapshot()
        let original = try #require(snapshot.actions.first {
            $0.project != nil && !$0.status.isClosed
        })
        let projectID = try #require(original.project)
        let project = try #require(snapshot.project(projectID))
        #expect(project.steps.contains { $0.promotedTo == original.id },
                "the fixture must have a step pointing at this action")

        // Somewhere else in the app — a second window, a list row, the review deck — the old
        // value is still in hand. This is the copy an open detail view would be holding.
        let stale = original

        var renamed = original
        renamed.title = "Renamed while open"
        _ = try await mac.vault.perform(.updateAction(renamed))

        let newID = NoteID(path: "Actions/Renamed while open.md")
        let afterRename = try rescan(root)
        #expect(afterRename.action(original.id) == nil, "the old path is gone")
        let moved = try #require(afterRename.action(newID))
        #expect(moved.why == original.why, "the body travelled with the file")
        #expect(moved.passthrough == original.passthrough, "N2: unknown keys travelled too")
        let movedProject = try #require(afterRename.project(project.id))
        #expect(movedProject.steps.contains { $0.promotedTo == newID },
                "the project's step link followed the rename, in the same commit")

        // The stale command the open view would send on its next autosave.
        await #expect(throws: GTDError.notFound(stale.id)) {
            _ = try await mac.vault.perform(.updateAction(stale))
        }

        let afterStaleWrite = try rescan(root)
        #expect(afterStaleWrite.action(original.id) == nil,
                "a refused command must not recreate the file at the old path")
        #expect(afterStaleWrite.actions.count == afterRename.actions.count)
        #expect(afterStaleWrite.issues.isEmpty)
    }

    /// The same situation across two devices, where the second one cannot know yet: the phone's
    /// snapshot still has the note at its old path because nothing has told it otherwise.
    ///
    /// **This is a documented limitation, not a fixed bug** (ARCHITECTURE §7 "one writer per
    /// file where possible"): a device acting on a snapshot older than the rename writes the old
    /// path, and the vault ends up with two notes instead of one. Nothing is *lost* — both files
    /// are on disk with their content intact, and the user resolves it like any duplicate. The
    /// test pins the actual behaviour so it cannot get quietly worse, and
    /// `docs/follow-ups/53-stale-write-guard.md` is the follow-up that would refuse the write.
    @Test func aDeviceWritingFromABeforeTheRenameSnapshotDuplicatesRatherThanLoses() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mac = try backend(at: root, deviceID: "mac-1")
        let phone = try backend(at: root, deviceID: "iphone-2")
        defer { mac.cleanUp(); phone.cleanUp() }
        try await mac.vault.start()
        try await phone.vault.start()          // both now hold the same snapshot

        let snapshot = await phone.vault.currentSnapshot()
        let original = try #require(snapshot.actions.first { $0.status == .backlog })

        var renamed = original
        renamed.title = "Renamed on the Mac"
        _ = try await mac.vault.perform(.updateAction(renamed))

        // The phone never saw it (its watcher is a `NullVaultWatcher` here, as it would be while
        // the device is asleep) and edits the note it still believes in.
        var edited = original
        edited.why = "edited on the phone"
        _ = try await phone.vault.perform(.updateAction(edited))

        let after = try rescan(root)
        let macCopy = try #require(after.action(NoteID(path: "Actions/Renamed on the Mac.md")))
        let phoneCopy = try #require(after.action(original.id))
        #expect(macCopy.why == original.why)
        #expect(phoneCopy.why == "edited on the phone")
        #expect(after.issues.isEmpty, "two real notes, not a corrupt one")
    }

    // MARK: - Helpers

    /// A second backend over the **same** folder, with its own device id and its own
    /// Application Support state (the undo journal is device-local, ARCHITECTURE §3).
    private struct Device {
        let vault: VaultBackend
        let stateDirectory: URL
        func cleanUp() { try? FileManager.default.removeItem(at: stateDirectory) }
    }

    private func backend(at root: URL, deviceID: String) throws -> Device {
        let store = FileVaultStore(
            fileSystem: PlainFileSystem(root: root),
            watcher: NullVaultWatcher(),
            today: { Fixtures.today })
        let stateDirectory = TestVault.temporaryDirectory()
        return Device(
            vault: VaultBackend(
                store: store,
                deviceID: deviceID,
                journal: UndoJournal(directory: stateDirectory),
                stateDirectory: stateDirectory,
                env: { Fixtures.reducerEnv(deviceID: deviceID) }),
            stateDirectory: stateDirectory)
    }

    private func rescan(_ root: URL) throws -> VaultSnapshot {
        var index = VaultIndex()
        try index.refresh(using: PlainFileSystem(root: root))
        return index.snapshot(today: Fixtures.today)
    }
}
