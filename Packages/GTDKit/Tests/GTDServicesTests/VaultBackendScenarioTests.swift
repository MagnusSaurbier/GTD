import Foundation
import GTDFixtures
import GTDMarkdown
import GTDModel
import GTDServices
import GTDVault
import Testing

/// The acceptance scenarios of T16, asserted on **file contents** — a copy of the sample vault
/// in a temp directory, driven through `VaultBackend`, then read back from disk.
@Suite("Commands as they land in the vault")
struct VaultBackendScenarioTests {

    // MARK: - Inbox processing (I4)

    @Test func theFourInboxDecisionsEachLandInTheRightFile() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()
        let layout = VaultLayout.default

        func capture(_ prefix: String) throws -> InboxItem {
            try #require(start.inbox.first { $0.text.hasPrefix(prefix) })
        }
        let toAction = try capture("call the Hausverwaltung")
        let toKnowledge = try capture("ask Marie")
        let toList = try capture("buy new running shoes")
        let toTrash = try capture("idea: a script")

        // 1 — an action. R-4: the note is named after the capture text, and the capture's
        // `created` follows it into the note (A1, I4).
        _ = try await vault.backend.perform(.fileInbox(toAction.id, .action(ActionDraft(
            title: "ignored — the capture text is the title (R-4)",
            status: .next,
            contexts: ["mac"],
            timeEstimate: 10,
            why: "The handle has been broken for two weeks.",
            what: "Ask for a repair date."))))

        let actionPath = "Actions/call the Hausverwaltung about the broken window handle.md"
        let action = try #require(try vault.text(actionPath))
        #expect(action.contains("status: next"))
        #expect(action.contains("contexts: [mac]"))
        #expect(action.contains("timeEstimate: 10"))
        #expect(action.contains("# Why?"))
        #expect(action.contains("Ask for a repair date."))
        let decoded = try NoteCodec.decodeAction(id: NoteID(path: actionPath), text: action)
        #expect(decoded.created == toAction.created, "the capture time is kept (A1)")
        #expect(decoded.preamble.isEmpty, "the title held the whole capture, so no lead paragraph")
        #expect(try vault.text(toAction.id.path) == nil, "the capture left Inbox/")
        #expect(try vault.text("\(layout.trash)/\(toAction.id.title).md") == nil,
                "R-4: the capture file *became* the action note, so nothing went to the trash")

        // 2 — knowledge: the capture becomes the note, keeping its `created`, and the notes
        // panel is its body (I4b).
        _ = try await vault.backend.perform(.fileInbox(
            toKnowledge.id, .knowledge(.folder("Thesis"), notes: "She has the cable too.")))
        let knowledge = try #require(try vault.text(
            "Knowledge/Thesis/ask Marie whether she still needs the monitor.md"))
        #expect(knowledge.contains("created: 2026-09-18T09:44:10+02:00"))
        #expect(knowledge.contains("She has the cable too."))
        #expect(try vault.text(toKnowledge.id.path) == nil)

        // 3 — a list item (§5a): the same move, no commitment attached.
        _ = try await vault.backend.perform(.fileInbox(toList.id, .list(name: "Wish", notes: "")))
        #expect(try vault.text(
            "Lists/Wish/buy new running shoes before the knee gets worse.md") != nil)
        #expect(try vault.text(toList.id.path) == nil)

        // 4 — trash: nothing is hard-deleted, the file is in GTD/Trash/.
        let trashedText = try #require(try vault.text(toTrash.id.path))
        _ = try await vault.backend.perform(.fileInbox(toTrash.id, .trash))
        #expect(try vault.text(toTrash.id.path) == nil)
        #expect(try vault.text("\(layout.trash)/\(toTrash.id.title).md") == trashedText)

        // The vault still reads cleanly, and the four captures are gone from the queue.
        let scanned = try vault.rescan()
        #expect(scanned.issues.isEmpty, "\(scanned.issues)")
        #expect(scanned.inbox.count == start.inbox.count - 4)
    }

    /// R-8/I4a — the `+ project` chip creating its project: **one** command, one commit, and one
    /// undo that puts every file back byte for byte (N6).
    @Test func aProjectChipCreatesTheProjectLinksTheActionAndUndoesInOneStep() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = try vault.filesOutsideTheTrash()
        let start = await vault.backend.currentSnapshot()
        let item = try #require(start.inbox.first { $0.text.hasPrefix("Steuererklärung") })
        let captureText = try #require(try vault.text(item.id.path))

        _ = try await vault.backend.perform(.fileInbox(item.id, .action(ActionDraft(
            title: "",
            status: .next,
            contexts: ["mac"],
            timeEstimate: 30,
            newProjectTitle: "Steuererklärung 2025",
            why: "The semester ticket may be deductible.",
            what: "Ask in the student forum."))))

        // The project note exists, area-less, and the action links to it with a wikilink.
        let project = try #require(try vault.text(
            "Projects/Steuererklärung 2025/Steuererklärung 2025.md"))
        #expect(project.contains("kind: project"))
        #expect(project.contains("status: active"))
        let actionPath = "Actions/Steuererklärung — find out whether the semester ticket is.md"
        let action = try #require(try vault.text(actionPath))
        #expect(action.contains(
            "project: \"[[Projects/Steuererklärung 2025/Steuererklärung 2025]]\""))
        // R-4 — the title was cut at a word boundary, so the whole dictation stays in the note.
        #expect(action.contains("Steuererklärung — find out whether the semester ticket is deductible"))
        #expect(try vault.text(item.id.path) == nil, "the capture became the action note")

        // N6 — one command, one undo: the capture is back, byte for byte, and the project is
        // gone again.
        try await vault.backend.undo()
        #expect(try vault.text(item.id.path) == captureText)
        #expect(try vault.text(actionPath) == nil)
        #expect(try vault.filesOutsideTheTrash() == before)
        // The project note the command created cannot be hard-deleted, so undoing it leaves its
        // tombstone in `GTD/Trash/` (ARCHITECTURE §3) — and nothing else.
        #expect(try vault.files().keys.filter { $0.hasPrefix("GTD/Trash/") }
                == ["GTD/Trash/Steuererklärung 2025.md"])
    }

    /// I4/A3 — a refused command must not have written anything at all.
    @Test func theCapErrorLeavesEveryFileUntouched() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        _ = try await vault.backend.perform(
            .createAction(ActionDraft(
                title: "Fills the last slot", status: .next, contexts: ["mac"], timeEstimate: 10,
                why: "The last slot.", what: "Do it.")))
        let before = try vault.files()

        await #expect(throws: GTDError.nextCapReached(cap: 15)) {
            try await vault.backend.perform(
                .createAction(ActionDraft(
                    title: "One too many", status: .next, contexts: ["mac"], timeEstimate: 10,
                    why: "One too many.", what: "Do it.")))
        }
        #expect(try vault.files() == before)
    }

    // MARK: - Completion (P4, A5)

    @Test func completingAProjectActionUpdatesBothFiles() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()

        let action = try #require(start.actions.first { $0.title == "Reply to the DAAD info mail" })
        let projectPath = "Projects/Applications/DAAD/DAAD.md"
        let projectBefore = try #require(try vault.text(projectPath))

        _ = try await vault.backend.perform(.complete(action.id))

        let actionText = try #require(try vault.text(action.id.path))
        #expect(actionText.contains("status: done"))
        #expect(actionText.contains("completedDate: "))

        let projectText = try #require(try vault.text(projectPath))
        #expect(projectText != projectBefore, "the project note gained a log line (P4)")
        #expect(projectText.contains("- \(Fixtures.today.iso) Reply to the DAAD info mail"))
        // Everything else in the project note survived the patch (N2).
        #expect(projectText.contains("# Outcome"))
        #expect(projectText.contains("Shortlisted three target universities"))
    }

    /// A promoted step is ticked in the project note when its action is completed (P4).
    @Test func completingAPromotedActionTicksTheStep() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()
        let action = try #require(start.actions.first { $0.title == "Read candidate thesis papers" })
        let projectPath = "Projects/Karriereplanung/Masterarbeit/Masterarbeit.md"

        _ = try await vault.backend.perform(.complete(action.id))

        let text = try #require(try vault.text(projectPath))
        #expect(text.contains("- [x] Read three candidate papers → [[Actions/Read candidate thesis papers]]"))
    }

    // MARK: - Rename (A1) and wikilink upkeep

    @Test func renamingAnActionMovesTheFileAndFixesTheLinkInOneTransaction() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()

        var action = try #require(start.actions.first {
            $0.title == "Compare Erasmus partner universities"
        })
        let oldPath = action.id.path
        let body = try #require(try vault.text(oldPath))
        action.title = "Compare Erasmus partners"

        _ = try await vault.backend.perform(.updateAction(action))

        #expect(try vault.text(oldPath) == nil, "the old file is gone")
        let moved = try #require(try vault.text("Actions/Compare Erasmus partners.md"))
        #expect(moved == body, "a pure rename does not rewrite the note")

        let project = try #require(try vault.text("Projects/Applications/Erasmus/Erasmus.md"))
        #expect(project.contains("→ [[Actions/Compare Erasmus partners]]"))
        #expect(!project.contains("Compare Erasmus partner universities"))
    }

    /// The same transaction when the rename comes with an edit: one move, one write.
    @Test func renamingAndEditingAtOnceWritesTheNewFileOnce() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()

        var action = try #require(start.actions.first { $0.title == "Cancel the gym membership" })
        action.title = "Cancel the gym contract"
        action.status = .someday
        _ = try await vault.backend.perform(.updateAction(action))

        #expect(try vault.text("Actions/Cancel the gym membership.md") == nil)
        let text = try #require(try vault.text("Actions/Cancel the gym contract.md"))
        #expect(text.contains("status: someday"))
        #expect(text.contains("Send the cancellation form by email before the 30th."))
    }

    /// A2 — the action's note is superseded, its checkboxes become the project's steps.
    @Test func turningAnActionIntoAProjectMovesTheNoteToTheTrash() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()
        let action = try #require(start.actions.first { $0.title == "Prepare the lab presentation" })

        let prompts = try await vault.backend.perform(.convertActionToProject(
            action.id,
            ProjectDraft(title: "Lab presentation", outcome: "Fifteen good minutes.", steps: [])))

        #expect(prompts == [.whatsNext(project: NoteID(path: "Projects/Lab presentation/Lab presentation.md"))])
        #expect(try vault.text(action.id.path) == nil)
        #expect(try vault.text("GTD/Trash/Prepare the lab presentation.md") != nil)
        let note = try #require(try vault.text("Projects/Lab presentation/Lab presentation.md"))
        #expect(note.contains("- [ ] Outline five slides"))
        #expect(note.contains("- [ ] Rehearse once out loud"))
    }

    // MARK: - Archive (A5)

    @Test func housekeepingArchivesOldNotesAndKeepsTheRestInPlace() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        // `start()` runs `archiveCompleted` once per day (A5).
        try await vault.backend.start()

        // Done 40 days ago → archived under the month it was closed in.
        #expect(try vault.text("Actions/Collect DAAD transcripts.md") == nil)
        #expect(try vault.text("Archive/2026/08/Collect DAAD transcripts.md") != nil)
        // Done yesterday → still an action.
        #expect(try vault.text("Actions/Renew the bike insurance.md") != nil)

        let scanned = try vault.rescan()
        #expect(scanned.actions.first { $0.title == "Collect DAAD transcripts" } == nil)
        #expect(scanned.issues.isEmpty)
    }

    /// A5 × T15 — an archive that could not move its files must be **retried**, not written off.
    /// `HousekeepingState` records the day only when the command succeeded, so a vault that was
    /// read-only, busy or half-synced at launch is archived at the next one (T41).
    @Test func aFailedArchiveIsRetriedAtTheNextLaunchInsteadOfBeingSkipped() async throws {
        let files = SampleVault.files
        let stateDirectory = TestVault.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        func backend(over fileSystem: InMemoryFileSystem) -> VaultBackend {
            VaultBackend(
                store: FileVaultStore(fileSystem: fileSystem, watcher: NullVaultWatcher(),
                                      today: { Fixtures.today }),
                deviceID: "mac-1",
                journal: UndoJournal(directory: stateDirectory),
                stateDirectory: stateDirectory,
                env: { Fixtures.reducerEnv(deviceID: "mac-1") })
        }

        let archived = "Archive/2026/08/Collect DAAD transcripts.md"
        let failing = InMemoryFileSystem(files: files)
        failing.failMoves(to: [archived])
        let first = backend(over: failing)
        try await first.start()

        #expect(await first.lastHousekeepingError != nil, "the failure is recorded, not hidden")
        #expect(failing.snapshotOfFiles["Actions/Collect DAAD transcripts.md"] != nil,
                "the transaction rolled back, so the note is still where it was")
        #expect(failing.snapshotOfFiles[archived] == nil)

        // A second launch over a healthy vault, with the same device-local state.
        let healthy = InMemoryFileSystem(files: files)
        let second = backend(over: healthy)
        try await second.start()

        #expect(await second.lastHousekeepingError == nil)
        #expect(healthy.snapshotOfFiles[archived] != nil,
                "the day was never recorded, so the archive ran again")
    }

    /// The archive keeps a note's own file name (T11), so a second note with that name needs a
    /// free one — otherwise the whole transaction would fail on `VaultError.destinationExists`.
    @Test func anArchiveCollisionGetsAFreeNameInsteadOfFailing() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        let folder = root.appendingPathComponent("Archive/2026/08", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "An older note with the same name.\n".write(
            to: folder.appendingPathComponent("Collect DAAD transcripts.md"),
            atomically: true, encoding: .utf8)

        try await vault.backend.start()

        #expect(try vault.text("Archive/2026/08/Collect DAAD transcripts.md")
            == "An older note with the same name.\n", "the older file is untouched")
        let archived = try #require(try vault.text("Archive/2026/08/Collect DAAD transcripts 2.md"))
        #expect(archived.contains("Picked up both certified copies."))
    }

    @Test func archivingRunsOnceADayNotOnEveryCommand() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let afterFirst = try vault.files()

        // Put a candidate back and start again: the same day must not archive a second time.
        let text = try #require(afterFirst["Archive/2026/08/Collect DAAD transcripts.md"])
        (vault.fileSystem as? InMemoryFileSystem)?
            .writeIgnoringFailures(text, to: "Actions/Collect DAAD transcripts.md")

        _ = try await vault.backend.perform(.createAction(ActionDraft(title: "Anything", what: "Do it.")))
        #expect(try vault.text("Actions/Collect DAAD transcripts.md") != nil,
                "housekeeping already ran today")
    }

    // MARK: - Failures

    /// T15-1 — a commit is all-or-nothing. When the second write fails, the first is rolled back,
    /// the command throws, and nothing about the backend moved: no snapshot, no undo entry.
    @Test func aFailingWriteRollsBackAndLeavesNothingToUndo() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let before = try vault.files()
        let snapshotBefore = await vault.backend.currentSnapshot()
        let action = try #require(snapshotBefore.actions.first {
            $0.title == "Read candidate thesis papers"
        })

        // Completing this action also writes its project note (log + step). Make that fail.
        (vault.fileSystem as? InMemoryFileSystem)?
            .failWrites(matching: ["Projects/Karriereplanung/Masterarbeit/Masterarbeit.md"])

        await #expect(throws: (any Error).self) {
            try await vault.backend.perform(.complete(action.id))
        }
        #expect(try vault.files() == before, "the action file was rolled back too")
        #expect(await vault.backend.undoLabel() == nil, "a failed command is not undoable")
        #expect(SnapshotShape(await vault.backend.currentSnapshot()) == SnapshotShape(snapshotBefore))
    }

    /// A knowledge note that would land on an existing file is a collision the *user* resolves —
    /// the app does not invent a name for a note the user titled (unlike the trash and archive).
    @Test func aKnowledgeNoteThatWouldOverwriteAFileIsRefused() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let root = try #require(vault.root)
        let folder = root.appendingPathComponent("Knowledge/Thesis", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "Older notes.\n".write(
            to: folder.appendingPathComponent("ask Marie whether she still needs the monitor.md"),
            atomically: true, encoding: .utf8)
        let before = try vault.files()

        let item = try #require(await vault.backend.currentSnapshot().inbox.first {
            $0.text.hasPrefix("ask Marie")
        })
        await #expect(throws: GTDError.titleCollision(
            "ask Marie whether she still needs the monitor")) {
            try await vault.backend.perform(
                .fileInbox(item.id, .knowledge(.folder("Thesis"), notes: "")))
        }
        #expect(try vault.files() == before)
    }

    // MARK: - Housekeeping

    @Test func theFolderSkeletonIsCreatedInAnEmptyVault() async throws {
        let fileSystem = InMemoryFileSystem()
        let store = FileVaultStore(
            fileSystem: fileSystem, watcher: NullVaultWatcher(), today: { Fixtures.today })
        let directory = TestVault.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = VaultBackend(
            store: store, deviceID: "test-device",
            journal: UndoJournal(directory: directory), stateDirectory: directory,
            env: { Fixtures.reducerEnv(deviceID: "test-device") })

        try await backend.start()

        let folders = try fileSystem.listFolders()
        for folder in VaultLayout.default.requiredFolders {
            #expect(folders.contains(folder), "missing \(folder)")
        }
    }

    // MARK: - Weekly review (§10.4)

    @Test func theWeeklyReviewNoteIsWrittenByTheBackend() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()

        _ = try await vault.backend.perform(.saveWeeklyReview(WeeklyReview(
            year: 2026,
            week: 38,
            wantedToAchieve: "A first full draft.",
            achieved: "Outline and two sections.",
            goalForNextWeek: "Letter finished.",
            systemFixNotes: ["Decisions need their own place."])))

        let text = try #require(try vault.text("GTD/Reviews/2026/KW 38.md"))
        #expect(text.contains("kind: review"))
        #expect(text.contains("week: 38"))
        #expect(text.contains("savedAt: "))
        #expect(text.contains("A first full draft."))
        #expect(text.contains("- Decisions need their own place."))
        #expect(try vault.rescan().lastReview?.week == 38)
    }

    // MARK: - Routine log (R5, N3)

    @Test func routineStepsGoIntoThisDevicesOwnLogFile() async throws {
        let vault = try TestVault.onDisk(deviceID: "iPhone")
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let start = await vault.backend.currentSnapshot()
        let routine = try #require(start.routines.first { $0.title == "Morning" })

        _ = try await vault.backend.perform(
            .logRoutineStep(routine: routine.id, stepID: routine.steps[0].id, .done))
        _ = try await vault.backend.perform(
            .logRoutineStep(routine: routine.id, stepID: routine.steps[1].id, .skipped))

        let path = "GTD/RoutineLog/\(Fixtures.today.iso)--iPhone.md"
        let text = try #require(try vault.text(path))
        #expect(text.contains("result: done"))
        #expect(text.contains("result: skipped"))
        // Another device's file for the same day is never rewritten (N3 §7.2).
        let others = try vault.files().keys.filter {
            $0.hasPrefix("GTD/RoutineLog/") && $0 != path
        }
        #expect(!others.isEmpty)
        for other in others {
            #expect(!(try #require(try vault.text(other))).contains("iPhone"))
        }
    }
}
