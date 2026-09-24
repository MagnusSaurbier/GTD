import Testing
import Foundation
import GTDModel
import GTDMarkdown
import GTDAppCore
import GTDFixtures
import GTDServices
import GTDVault

/// N3 through the whole stack: two devices, a late sync, a conflict copy and the stale-write
/// guard, on a temp copy of the sample vault (T41, brief 53).
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
        _ = try await vault.backend.perform(.setStatus(action.id, .someday, waiting: nil))

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
        _ = try await vault.backend.perform(.setStatus(action.id, .someday, waiting: nil))
        #expect(try vault.text(copyPath) == original, "the app never rewrites a conflict copy")
        #expect(try #require(try vault.text(action.id.path)).contains("status: someday"))
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
    /// N3 — the stale-write guard (ARCHITECTURE §6, 2026-09-24): the phone's write is **refused**,
    /// the old path is not written back, and the phone is re-read so it now shows the rename.
    /// Before brief 53 this produced two notes; nothing was lost, but the user had a duplicate to
    /// reconcile by hand.
    @Test func aDeviceWritingFromABeforeTheRenameSnapshotIsRefusedRatherThanDuplicating() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mac = try backend(at: root, deviceID: "mac-1")
        let phone = try backend(at: root, deviceID: "iphone-2")
        defer { mac.cleanUp(); phone.cleanUp() }
        try await mac.vault.start()
        try await phone.vault.start()          // both now hold the same snapshot

        let snapshot = await phone.vault.currentSnapshot()
        let original = try #require(snapshot.actions.first { $0.status == .someday })

        var renamed = original
        renamed.title = "Renamed on the Mac"
        _ = try await mac.vault.perform(.updateAction(renamed))
        let afterRename = try rescan(root)

        // The phone never saw it (its watcher is a `NullVaultWatcher` here, as it would be while
        // the device is asleep) and edits the note it still believes in.
        var edited = original
        edited.why = "edited on the phone"
        await #expect(throws: ServiceError.staleWrite(path: original.id.path)) {
            _ = try await phone.vault.perform(.updateAction(edited))
        }

        let after = try rescan(root)
        let newID = NoteID(path: "Actions/Renamed on the Mac.md")
        #expect(after.action(original.id) == nil, "the old path was not written back")
        #expect(try #require(after.action(newID)).why == original.why, "the Mac's note is untouched")
        #expect(after.actions.count == afterRename.actions.count, "one note, not two")
        #expect(after.issues.isEmpty)

        // The refusal re-read the vault: what the phone shows now is the rename, so reopening
        // the note and making the change again works on the fresh file.
        let phoneNow = await phone.vault.currentSnapshot()
        #expect(phoneNow.action(original.id) == nil)
        #expect(phoneNow.action(newID) != nil)
        var again = try #require(phoneNow.action(newID))
        again.why = "edited on the phone"
        _ = try await phone.vault.perform(.updateAction(again))
        #expect(try rescan(root).action(newID)?.why == "edited on the phone")
    }

    /// The other shape of the same race: no rename, just a field. The Mac changes the status,
    /// the phone (still on the old snapshot) saves the whole note with a new *why* — which would
    /// carry the old status back over the Mac's. Refused; the Mac's edit stays.
    @Test func aFieldEditedElsewhereIsNotOverwrittenByAStaleSnapshot() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mac = try backend(at: root, deviceID: "mac-1")
        let phone = try backend(at: root, deviceID: "iphone-2")
        defer { mac.cleanUp(); phone.cleanUp() }
        try await mac.vault.start()
        try await phone.vault.start()

        let snapshot = await phone.vault.currentSnapshot()
        let original = try #require(snapshot.actions.first { $0.status == .next })
        _ = try await mac.vault.perform(.setStatus(original.id, .someday, waiting: nil))

        var edited = original
        edited.why = "edited on the phone"
        await #expect(throws: ServiceError.staleWrite(path: original.id.path)) {
            _ = try await phone.vault.perform(.updateAction(edited))
        }

        let onDisk = try #require(try rescan(root).action(original.id))
        #expect(onDisk.status == .someday, "the Mac's status survived")
        #expect(onDisk.why == original.why, "and the phone's edit was not merged in")
    }

    /// Offline, or on a slow sync, a stale snapshot is the normal case — and it must not stop
    /// the person working. The Mac changes two other notes; the phone, which has seen none of
    /// it, edits a third note twice. Both writes land, because the files *it* touches did not
    /// change. Nothing may ever refuse a write merely because the snapshot is old.
    @Test func aLongStaleSnapshotStillCommitsWhenItsOwnFilesDidNotChange() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mac = try backend(at: root, deviceID: "mac-1")
        let phone = try backend(at: root, deviceID: "iphone-2")
        defer { mac.cleanUp(); phone.cleanUp() }
        try await mac.vault.start()
        try await phone.vault.start()

        let snapshot = await phone.vault.currentSnapshot()
        let open = snapshot.actions.filter { !$0.status.isClosed }
        let macFirst = try #require(open.first)
        let macSecond = try #require(open.dropFirst().first)
        let phoneNote = try #require(open.dropFirst(2).first)

        var renamed = macFirst
        renamed.title = "Renamed on the Mac while the phone slept"
        _ = try await mac.vault.perform(.updateAction(renamed))
        _ = try await mac.vault.perform(.setStatus(macSecond.id, .someday, waiting: nil))

        // The phone is a world behind — and edits a note nobody else touched. Twice: the second
        // command is reduced on the first one's snapshot, whose file the phone itself just wrote.
        var edited = phoneNote
        edited.why = "edited on the phone"
        _ = try await phone.vault.perform(.updateAction(edited))
        _ = try await phone.vault.perform(.setStatus(phoneNote.id, .someday, waiting: nil))

        let after = try rescan(root)
        let phoneOnDisk = try #require(after.action(phoneNote.id))
        #expect(phoneOnDisk.why == "edited on the phone")
        #expect(phoneOnDisk.status == .someday)
        #expect(after.action(NoteID(path: "Actions/Renamed on the Mac while the phone slept.md")) != nil)
        #expect(after.action(macSecond.id)?.status == .someday)
        #expect(after.issues.isEmpty)
    }

    /// A command that *creates* a file has nothing to compare — so it expects the file to be
    /// absent. Two devices creating the same title while apart: the second one is refused, not
    /// written over the first.
    @Test func aNoteCreatedElsewhereUnderTheSameTitleIsNotOverwritten() async throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let mac = try backend(at: root, deviceID: "mac-1")
        let phone = try backend(at: root, deviceID: "iphone-2")
        defer { mac.cleanUp(); phone.cleanUp() }
        try await mac.vault.start()
        try await phone.vault.start()

        func draft(_ why: String) -> ActionDraft {
            ActionDraft(title: "Created on both devices", status: .someday,
                        contexts: ["mac"], why: why, what: "Find out which one wins.")
        }
        _ = try await mac.vault.perform(.createAction(draft("from the Mac")))
        let path = "Actions/Created on both devices.md"
        await #expect(throws: ServiceError.staleWrite(path: path)) {
            _ = try await phone.vault.perform(.createAction(draft("from the phone")))
        }
        #expect(try rescan(root).action(NoteID(path: path))?.why == "from the Mac")
    }

    /// N3 §7.2 — the routine log is per device by construction, so it is exempt from the guard:
    /// even when this device's own log file changed under it (a restored backup, a sync of the
    /// same device's file from elsewhere), logging a step is never refused.
    @Test func loggingARoutineStepIsNeverRefused() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        try await vault.backend.start()

        let snapshot = await vault.backend.currentSnapshot()
        let routine = try #require(snapshot.routines.first { $0.title == "Morning" })
        _ = try await vault.backend.perform(
            .logRoutineStep(routine: routine.id, stepID: routine.steps[0].id, .done))

        let logPath = "GTD/RoutineLog/\(Fixtures.today.iso)--mac-1.md"
        let logged = try #require(try vault.text(logPath))
        try vault.fileSystem.writeText(logged + "\n<!-- touched elsewhere -->\n", to: logPath)

        _ = try await vault.backend.perform(
            .logRoutineStep(routine: routine.id, stepID: routine.steps[1].id, .skipped))
        let rescanned = try vault.rescan()
        let today = rescanned.routineLog.filter { $0.day == Fixtures.today && $0.device == "mac-1" }
        #expect(today.count == 2, "both steps are in today's log: \(today)")
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
                env: { Fixtures.reducerEnv(deviceID: deviceID) },
            writes: .awaited),
            stateDirectory: stateDirectory)
    }

    private func rescan(_ root: URL) throws -> VaultSnapshot {
        var index = VaultIndex()
        try index.refresh(using: PlainFileSystem(root: root))
        return index.snapshot(today: Fixtures.today)
    }
}
