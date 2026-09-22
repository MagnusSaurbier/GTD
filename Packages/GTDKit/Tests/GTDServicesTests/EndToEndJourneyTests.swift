import Testing
import Foundation
import GTDModel
import GTDMarkdown
import GTDAppCore
import GTDFixtures
import GTDServices
import GTDVault

/// One person's week, driven through the **real** stack: `AppModel` → `VaultBackend` →
/// `FileVaultStore` → `PlainFileSystem` over a temp copy of the sample vault (T41).
///
/// Every other suite tests one seam. This one tests that the seams hold together: what a view
/// would send arrives as bytes on disk, a cold re-scan of those bytes reproduces what the app
/// shows, and undo puts the bytes back. It never touches the real vault (CLAUDE.md rule 1) —
/// `SampleVault.copyToTemporaryDirectory()` is the only source of files.
@MainActor
@Suite struct EndToEndJourneyTests {

    /// Capture → process → cap → promote → wait → review → undo → archive, in one vault,
    /// in the order a Saturday morning actually happens in.
    @Test func aWholeWeekThroughTheRealBackend() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        // ── 1. Capture (C1/C3) ────────────────────────────────────────────────────────────────
        // A Shortcut writes straight into `Inbox/` with neither the app nor Obsidian running.
        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(text: "renew the Semesterticket",
                                          at: Fixtures.date(Fixtures.today, 9, 30))
        // C3 — the capture is named after its text, and the title carried all of it.
        #expect(captured.path == "Inbox/renew the Semesterticket.md")
        #expect(try vault.text(captured.path) == "---\ncreated: 2026-09-19T09:30:00+02:00\n---\n")
        await vault.store.simulateChangeForTesting()
        let arrived = await settle(model) { snapshot in snapshot.inbox.contains { $0.id == captured } }
        #expect(arrived, "an external capture reaches the app without a restart")
        #expect(model.snapshot.inboxItem(captured)?.title == "renew the Semesterticket")

        // The card's title is the file name: editing it renames the file within `Inbox/`.
        try await model.send(.renameInboxItem(captured, title: "renew the Semesterticket online"))
        let renamed = NoteID(path: "Inbox/renew the Semesterticket online.md")
        #expect(try vault.text(captured.path) == nil)
        #expect(try vault.text(renamed.path)?.contains("created: 2026-09-19T09:30:00+02:00") == true)
        #expect(model.snapshot.inboxItem(renamed) != nil)
        #expect(model.undoLabel == "Renamed")

        // ── 2. Process the inbox (I1–I4) ──────────────────────────────────────────────────────
        // Filing to Next takes the vault to the cap exactly: 14 counting + 1 = 15.
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == 14)
        try await model.send(.fileInbox(renamed, .action(ActionDraft(
            title: "Renew the Semesterticket",
            status: .next,
            contexts: ["campus"],
            timeEstimate: 30,
            why: "It expires at the end of the month.",
            what: "Pay at the Studierendenwerk counter."))))
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == 15)
        #expect(try vault.text(renamed.path) == nil, "the capture file left the inbox")
        // C3 — the note keeps the inbox note's file name, not the draft's title.
        let filed = try #require(try vault.text("Actions/renew the Semesterticket online.md"))
        #expect(filed.contains("status: next"))
        #expect(filed.contains("created: 2026-09-19T09:30:00+02:00"),
                "the capture's own created stamp survives filing (I1)")
        #expect(model.undoLabel == "Filed to Next")

        // ── 3. The cap refuses the next one, and changes nothing (I4/A3) ──────────────────────
        let bytesAtCap = try vault.filesOutsideTheTrash()
        let second = try #require(model.snapshot.inbox.first {
            $0.reviewReason == nil && $0.title.hasPrefix("ask Marie")
        })
        await #expect(throws: GTDError.nextCapReached(cap: 15)) {
            try await model.send(.fileInbox(second.id, .action(ActionDraft(
                title: "Should not exist",
                status: .next,
                contexts: ["mac"],
                timeEstimate: 10,
                why: "Because the cap must refuse a *complete* card too.",
                what: "Ask her."))))
        }
        #expect(try vault.filesOutsideTheTrash() == bytesAtCap, "a refused command writes nothing")
        #expect(model.snapshot.inbox.contains { $0.id == second.id }, "the card stays in the queue")

        // Someday is the way out, and it is not capped.
        try await model.send(.fileInbox(second.id, .action(ActionDraft(
            title: "", status: .someday, what: "Ask her."))))
        #expect(try vault.text(
            "Actions/ask Marie whether she still needs the monitor.md") != nil)

        // ── 4. Promote a project step (P5) ────────────────────────────────────────────────────
        let daadBefore = try #require(try vault.text("Projects/Applications/DAAD/DAAD.md"))
        let daad = try #require(model.snapshot.projects.first { $0.title == "DAAD" })
        let stepIndex = try #require(daad.steps.firstIndex { $0.text == "Ask Prof. Weber for a reference" })
        try await model.send(.promoteStep(project: daad.id, stepIndex: stepIndex, ActionDraft(
            title: "Ask Prof. Weber for a reference", status: .someday, contexts: ["mac"])))
        let daadNote = try #require(try vault.text("Projects/Applications/DAAD/DAAD.md"))
        #expect(daadNote.contains(
            "- [ ] Ask Prof. Weber for a reference → [[Actions/Ask Prof. Weber for a reference]]"),
            "the step and the note it created are written in one transaction")

        // ── 5. Waiting needs who + follow-up (W1) ─────────────────────────────────────────────
        let promoted = NoteID(path: "Actions/Ask Prof. Weber for a reference.md")
        // W1/D39/R-3 — the follow-up date is what `waiting` requires; who is optional.
        await #expect(throws: GTDError.missingFields([.followUpDate])) {
            try await model.send(.setStatus(promoted, .waiting, waiting: nil))
        }
        try await model.send(.setStatus(promoted, .waiting, waiting: WaitingInfo(
            who: "Prof. Weber", followUp: Fixtures.day(7))))
        let waitingNote = try #require(try vault.text("Actions/Ask Prof. Weber for a reference.md"))
        #expect(waitingNote.contains("status: waiting"))
        #expect(waitingNote.contains("waitingFor: \"Prof. Weber\""))
        #expect(waitingNote.contains("followUpDate: 2026-09-26"))

        // ── 6. Undo walks back, byte for byte (N6) ────────────────────────────────────────────
        await model.undo()
        #expect(model.lastError == nil)
        let backToSomeday = try #require(try vault.text("Actions/Ask Prof. Weber for a reference.md"))
        #expect(backToSomeday.contains("status: someday"))
        #expect(!backToSomeday.contains("waitingFor"))
        #expect(model.snapshot.action(promoted)?.status == .someday)

        // VaultBackend's journal is 20 deep, so ⌘Z keeps going: the promotion goes too.
        await model.undo()
        #expect(model.lastError == nil)
        let daadAfterUndo = try #require(try vault.text("Projects/Applications/DAAD/DAAD.md"))
        #expect(daadAfterUndo == daadBefore, "the project note is back byte for byte")
        #expect(try vault.text("Actions/Ask Prof. Weber for a reference.md") == nil,
                "the note the promotion created is gone from Actions/ …")
        #expect(try vault.files().keys.contains { $0.hasPrefix("GTD/Trash/") },
                "… and is in the trash, because nothing is ever hard-deleted")

        // ── 7. The weekly review note (§10.4, N2) ─────────────────────────────────────────────
        let week = Fixtures.today.isoWeek
        try await model.send(.saveWeeklyReview(WeeklyReview(
            year: week.year,
            week: week.week,
            wantedToAchieve: "Submit the DAAD form",
            achieved: "Motivation letter drafted",
            goalForNextWeek: "Send it",
            systemFixNotes: [
                "the whole Erasmus vs DAAD decision (deferred: It is a decision, not an action.) → give decisions their own note",
                "A second line with a colon: and a — dash",
            ],
            savedAt: Fixtures.date(Fixtures.today, 11, 0))))
        let reviewNote = try #require(try vault.text("GTD/Reviews/2026/KW 38.md"))
        #expect(reviewNote.contains("give decisions their own note"))

        // The round trip that matters is the *file*: decode what was written.
        let decoded = try NoteCodec.decodeWeeklyReview(
            id: NoteID(path: "GTD/Reviews/2026/KW 38.md"), text: reviewNote,
            timeZone: Fixtures.calendar.timeZone)
        #expect(decoded.systemFixNotes.count == 2)
        #expect(decoded.systemFixNotes[1] == "A second line with a colon: and a — dash")
        #expect(decoded.goalForNextWeek == "Send it")

        // ── 8. A cold re-scan agrees with the app ─────────────────────────────────────────────
        let rescanned = try vault.rescan()
        #expect(rescanned.lastReview?.systemFixNotes == decoded.systemFixNotes)
        // C3 — both notes kept the file names they had in the inbox.
        #expect(rescanned.actions.first { $0.title == "renew the Semesterticket online" }?.status == .next)
        #expect(rescanned.actions.first {
            $0.title == "ask Marie whether she still needs the monitor"
        }?.status == .someday)
        #expect(rescanned.issues.isEmpty, "the whole week left no unreadable file behind")
        #expect(Rules.countsTowardCap(rescanned, today: Fixtures.today) == 15)
    }

    // MARK: - Archive (A5) — the stale-wikilink bug T16 found

    /// Archiving moves a promoted action out of `Actions/`. The project step that points at it
    /// must be retargeted, or the `# Steps` line keeps a wikilink to a file that is not there
    /// any more (T16 Result "Archiving leaves a stale wikilink"; fixed in T41).
    @Test func archivingRetargetsThePromotedStepInsteadOfLeavingADeadLink() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }

        let before = try #require(try vault.text("Projects/Applications/DAAD/DAAD.md"))
        #expect(before.contains("→ [[Actions/Collect DAAD transcripts]]"))

        // `start()` runs the daily housekeeping archive.
        try await vault.backend.start()

        #expect(try vault.text("Actions/Collect DAAD transcripts.md") == nil)
        #expect(try vault.text("Archive/2026/08/Collect DAAD transcripts.md") != nil)

        let after = try #require(try vault.text("Projects/Applications/DAAD/DAAD.md"))
        #expect(!after.contains("→ [[Actions/Collect DAAD transcripts]]"), "the dead link is gone")
        #expect(after.contains("→ [[Archive/2026/08/Collect DAAD transcripts]]"))

        // And the snapshot the app holds says the same thing as the file.
        let scanned = try vault.rescan()
        let daad = try #require(scanned.projects.first { $0.title == "DAAD" })
        let step = try #require(daad.steps.first { $0.text == "Collect transcripts" })
        #expect(step.promotedTo == NoteID(path: "Archive/2026/08/Collect DAAD transcripts.md"))
        #expect(await vault.backend.currentSnapshot().projects
            .first { $0.title == "DAAD" }?.steps.first?.promotedTo == step.promotedTo)
    }

    // MARK: - The two backends stay interchangeable

    /// `InMemoryBackend` (previews, `-useFixtures`) and `VaultBackend` (the real vault) must
    /// agree on *which* commands are undoable and on what the toast says — they now read the
    /// same `Rules.isUndoable` and the same `UndoLabel` table (T41), so this is structural
    /// rather than two hand-kept lists.
    @Test func bothBackendsAgreeOnUndoabilityAndWording() async throws {
        let vault = TestVault.inMemory()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let snapshot = await vault.backend.currentSnapshot()
        let memory = InMemoryBackend(
            snapshot: snapshot,
            deviceID: "test-device",
            env: { Fixtures.reducerEnv(deviceID: "test-device") })

        let action = try #require(snapshot.actions.first { $0.status == .next })
        let routine = try #require(snapshot.routines.first)
        let commands: [GTDCommand] = [
            .setStatus(action.id, .someday, waiting: nil),
            .updateConfig(snapshot.config),                                   // not undoable
            .logRoutineStep(routine: routine.id, stepID: routine.steps[0].id, .done),  // not undoable
            .createAction(ActionDraft(title: "A brand new action", what: "Do it.")),
        ]

        for command in commands {
            let labelBefore = await vault.backend.undoLabel()
            _ = try await vault.backend.perform(command)
            _ = try await memory.perform(command)

            let fromVault = await vault.backend.undoLabel()
            let fromMemory = await memory.undoLabel()
            #expect(fromVault == fromMemory, "\(command)")

            if Rules.isUndoable(command) {
                #expect(fromVault == UndoLabel.of(command, in: snapshot), "\(command)")
            } else {
                #expect(fromVault == labelBefore,
                        "a command outside N6 must not become the undo target: \(command)")
            }
        }
    }

    // MARK: - Helpers

    /// `AppModel` is fed by an `AsyncStream`, and a store change reaches it over three hops
    /// (store hub → backend forwarding → model observation). Wait for the value, not for a
    /// fixed number of turns — a sleep-free poll keeps the suite deterministic.
    @discardableResult
    private func settle(
        _ model: AppModel, until condition: @MainActor (VaultSnapshot) -> Bool
    ) async -> Bool {
        for _ in 0..<2_000 {
            if condition(model.snapshot) { return true }
            await Task.yield()
        }
        return condition(model.snapshot)
    }
}
