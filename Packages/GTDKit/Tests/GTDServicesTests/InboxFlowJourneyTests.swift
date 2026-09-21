import Testing
import Foundation
import GTDModel
import GTDMarkdown
import GTDAppCore
import GTDFixtures
import GTDServices
import GTDVault

/// The **two-step inbox flow** of the 2026-09-21 rework, end to end through the real stack —
/// `AppModel` → `VaultBackend` → `FileVaultStore` → `PlainFileSystem` over a temp copy of the
/// sample vault. `EndToEndJourneyTests` walks one whole week; this suite walks the *new* exits
/// one at a time and asserts on the **files**, because that is what the user keeps.
///
/// Every journey here is the model half of a card the person drives in `docs/MANUAL_TEST.md`
/// §2–§3: the session layer (`InboxSession`) cannot be reached from `GTDServices` — a feature
/// target may not be imported here (ARCHITECTURE §2) — so the exits arrive as the commands the
/// session sends. The session's own state machine is `FeatureInboxTests`.
///
/// Never the real vault (CLAUDE.md rule 1): `SampleVault.copyToTemporaryDirectory()` is the only
/// source of files.
@MainActor
@Suite("The two-step inbox flow, on disk")
struct InboxFlowJourneyTests {

    // MARK: (a) Step 1 → Action → refused → filled → cap → demote → Next

    /// The full action branch of STYLEGUIDE §3.6, in the order it happens: a dictation is
    /// captured, the card is opened as an Action, filing to Next is **refused** for the fields
    /// R-3 demands, the filled card is then refused again by the cap (D14), one Next item is
    /// demoted, and the card lands in Next — renamed to the capture text (R-4) with the full
    /// dictation kept in the body. A refusal writes nothing at any point.
    @Test func anActionCardIsRefusedForItsFieldsThenForTheCapAndThenLandsInNext() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        // ── 1. Capture: a long dictation, more than a file name can hold (C1/C3, R-4) ─────────
        let dictation = """
            ring the Hausverwaltung about the broken window handle in the bedroom \
            and ask whether they send somebody or whether I book the Handwerker myself
            """
        #expect(dictation.count > CaptureText.titleLimit, "the fixture has to be a *long* dictation")
        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(text: dictation, at: Fixtures.date(Fixtures.today, 12, 5))
        await vault.store.simulateChangeForTesting()
        #expect(await settle(model) { $0.inbox.contains { $0.id == captured } },
                "the capture reaches the app without a restart (I7)")
        // I1 — LIFO: the newest capture is the card the session opens first.
        #expect(Rules.inboxQueue(model.snapshot).first?.id == captured)

        let bytesBefore = try vault.filesOutsideTheTrash()

        // ── 2. Step 1 → Action → `→ Next` on an empty card: refused (R-3) ─────────────────────
        // The session pre-validates, but the reducer is the authority — this is the reducer's
        // refusal, arriving exactly as `InboxSession.take(.next)` would deliver it.
        await #expect(throws: GTDError.missingFields([.why, .what, .context, .timeEstimate])) {
            try await model.send(.fileInbox(captured, .action(ActionDraft(
                title: "", status: .next))))
        }
        #expect(try vault.filesOutsideTheTrash() == bytesBefore,
                "a card refused for its fields writes nothing at all")
        #expect(model.snapshot.inbox.contains { $0.id == captured }, "the card is still the card")

        // Filling in three of the four is still a refusal, and it names only what is left.
        await #expect(throws: GTDError.missingFields([.timeEstimate])) {
            try await model.send(.fileInbox(captured, .action(ActionDraft(
                title: "", status: .next, contexts: ["calls"],
                why: "The window does not close and it is getting cold.",
                what: "Call them and ask."))))
        }

        // ── 3. The filled card now meets the cap instead (I4/A3/D14) ─────────────────────────
        // The sample vault counts 14 toward the cap; one filing takes it to 15 exactly.
        #expect(Rules.countsTowardCap(model.snapshot, today: Fixtures.today) == 14)
        let filler = try #require(model.snapshot.actions.first {
            $0.status == .someday && !$0.why.isEmpty && !$0.what.isEmpty
                && !$0.contexts.isEmpty && $0.timeEstimate != nil
        })
        try await model.send(.setStatus(filler.id, .next, waiting: nil))
        #expect(Rules.isAtCap(model.snapshot, today: Fixtures.today))

        let complete = ActionDraft(
            title: "", status: .next, contexts: ["calls"], timeEstimate: 10,
            why: "The window does not close and it is getting cold.",
            what: "Call them and ask.")
        let bytesAtCap = try vault.filesOutsideTheTrash()
        await #expect(throws: GTDError.nextCapReached(cap: 15)) {
            try await model.send(.fileInbox(captured, .action(complete)))
        }
        #expect(try vault.filesOutsideTheTrash() == bytesAtCap,
                "a *complete* card refused by the cap writes nothing either")

        // ── 4. Demote one — the cap sheet's only other exit is Cancel (D14) ──────────────────
        // R-3 never blocks a demotion: that is how an over-cap vault stays repairable.
        let demoted = try #require(model.snapshot.actions.first {
            $0.status == .next && $0.id != filler.id
        })
        try await model.send(.setStatus(demoted.id, .someday, waiting: nil))
        #expect(!Rules.isAtCap(model.snapshot, today: Fixtures.today))

        // ── 5. …and the same card goes through (R-4) ─────────────────────────────────────────
        try await model.send(.fileInbox(captured, .action(complete)))

        // The file is named after the *capture text*, cut at a word boundary to ≤ 60 characters.
        let title = try #require(CaptureText.title(of: dictation))
        #expect(title.count <= CaptureText.titleLimit)
        #expect(dictation.hasPrefix(title), "the title is the head of what was dictated")
        let filedPath = "Actions/\(title).md"
        let filed = try #require(try vault.text(filedPath))
        #expect(try vault.text(captured.path) == nil, "the capture file left `Inbox/` (it moved)")

        #expect(filed.contains("status: next"))
        #expect(filed.contains("contexts: [calls]"))
        #expect(filed.contains("timeEstimate: 10"))
        #expect(filed.contains("created: 2026-09-19T12:05:00+02:00"),
                "the capture's own `created` survives the move (C3)")
        // R-4 — nothing dictated is lost: the full text is the note's first paragraph, above
        // `# Why?`, because the title could not hold it.
        #expect(filed.contains(dictation), "the whole dictation is kept in the body")
        let leadRange = try #require(filed.range(of: dictation))
        let whyRange = try #require(filed.range(of: "# Why?"))
        #expect(leadRange.upperBound <= whyRange.lowerBound,
                "the full capture text is the *preamble*, above `# Why?`")
        #expect(model.undoLabel == "Filed to Next")

        // ── 6. A cold re-scan of those bytes says the same thing ─────────────────────────────
        let rescanned = try vault.rescan()
        let action = try #require(rescanned.action(NoteID(path: filedPath)))
        #expect(action.status == .next)
        #expect(action.title == title)
        #expect(action.preamble == dictation)
        #expect(action.why == "The window does not close and it is getting cold.")
        #expect(Rules.countsTowardCap(rescanned, today: Fixtures.today) == 15)
        #expect(rescanned.issues.isEmpty, "the journey left no unreadable file behind")
    }

    // MARK: (b) Capture → list → complete → undo → Make action into Someday

    /// The list branch (I4b/§5a, L3/L4): a capture becomes a list item, is ticked off into
    /// `Done/`, comes back with `⌘Z`, and is then promoted into **Someday** — where the only
    /// required field is `What?`, so a promotion that Next would refuse goes straight through.
    @Test func aCaptureBecomesAListItemAndIsMadeIntoASomedayAction() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        // ── 1. Step 1 → `Knowledge / List` → the `Watch` navbar slot (I4b) ───────────────────
        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(
            text: "the Villeneuve documentary Marie mentioned",
            at: Fixtures.date(Fixtures.today, 21, 10))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { $0.inbox.contains { $0.id == captured } }

        try await model.send(.fileInbox(captured, .list(
            name: "Watch", notes: "She said the first twenty minutes are the whole point.")))

        let itemPath = "Lists/Watch/the Villeneuve documentary Marie mentioned.md"
        let itemText = try #require(try vault.text(itemPath))
        #expect(try vault.text(captured.path) == nil)
        #expect(itemText.contains("She said the first twenty minutes are the whole point."))
        #expect(!itemText.contains("status:"), "a list item is not a commitment (L1)")
        #expect(model.undoLabel == "Added to Watch")

        // ── 2. Tick it off: the note *moves* into `Done/` and stays a log (L3) ───────────────
        let itemID = NoteID(path: itemPath)
        try await model.send(.completeListItem(itemID))
        let donePath = "Lists/Watch/Done/the Villeneuve documentary Marie mentioned.md"
        #expect(try vault.text(itemPath) == nil)
        #expect(try vault.text(donePath) == itemText, "byte for byte, it is the same note")
        #expect(model.undoLabel == "Done")

        // ── 3. Undo brings it back to the open half of the list (N6) ─────────────────────────
        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.text(donePath) == nil)
        #expect(try vault.text(itemPath) == itemText)
        #expect(model.snapshot.listItem(itemID)?.isFinished == false)

        // ── 4. `Make action` into Someday (L4, R-3) ──────────────────────────────────────────
        // The card opens on the item, so its title is the item's own (L4); Next would be refused
        // here — no Why?, no context, no time estimate. Someday asks for `What?` and nothing
        // else, so the same card files without any of that.
        let itemTitle = try #require(model.snapshot.listItem(itemID)?.title)
        await #expect(throws: GTDError.missingFields([.why, .context, .timeEstimate])) {
            try await model.send(.promoteListItem(itemID, ActionDraft(
                title: itemTitle, status: .next, what: "Watch it on Sunday.")))
        }
        #expect(try vault.text(itemPath) == itemText, "the refused promotion left the item alone")

        try await model.send(.promoteListItem(itemID, ActionDraft(
            title: itemTitle, status: .someday, what: "Watch it on Sunday.")))

        let actionPath = "Actions/the Villeneuve documentary Marie mentioned.md"
        let actionText = try #require(try vault.text(actionPath))
        #expect(try vault.text(itemPath) == nil, "the note moved out of the list, it was not copied")
        #expect(actionText.contains("status: someday"))
        #expect(actionText.contains("# What?\nWatch it on Sunday."))
        // L4 — the item's own notes are kept, above the headings.
        #expect(actionText.contains("She said the first twenty minutes are the whole point."))
        #expect(model.undoLabel == "Filed to Someday")

        let rescanned = try vault.rescan()
        #expect(rescanned.action(NoteID(path: actionPath))?.status == .someday)
        #expect(rescanned.listItem(itemID) == nil)
        #expect(rescanned.issues.isEmpty)
    }

    // MARK: (c) Capture → Knowledge, into an active project's folder

    /// I4b/D36 — the Knowledge card's targets are the `Knowledge/**` tree **and** the folder of
    /// an active project. The note is written through `Reduction.filedNotes`, so what lands on
    /// disk is what the reducer decided, in the project's own folder.
    @Test func aCaptureBecomesAKnowledgeNoteInsideAnActiveProjectsFolder() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.projects.isEmpty }

        let daad = try #require(model.snapshot.projects.first { $0.title == "DAAD" })
        #expect(daad.status == .active, "only an *active* project is offered as a target (I4b)")

        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let dictation = "DAAD deadline is the 31st, the portal closes at 23:59 CET"
        let captured = try writer.capture(text: dictation, at: Fixtures.date(Fixtures.today, 10, 15))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { $0.inbox.contains { $0.id == captured } }

        try await model.send(.fileInbox(captured, .knowledge(
            .project(daad.id), notes: "Confirmed on the DAAD site, not in the info mail.")))

        // R-4 — the note is named after the capture text, sanitised into a legal file name (the
        // colon of `23:59` cannot be one), and it lands **inside the project's own folder**.
        let title = try #require(CaptureText.title(of: dictation))
        #expect(title == "DAAD deadline is the 31st, the portal closes at 23 59 CET")
        let notePath = "Projects/Applications/DAAD/\(title).md"
        let note = try #require(try vault.text(notePath))
        #expect(try vault.text(captured.path) == nil, "the capture file moved into the project")
        #expect(note.contains("Confirmed on the DAAD site, not in the info mail."))
        #expect(!note.contains("status:"), "a Knowledge note is not an action (I4b)")
        #expect(note.contains("created: 2026-09-19T10:15:00+02:00"),
                "the capture's timestamp travels with the file")
        // The colon was the only thing the title could not keep, so the full text is kept too.
        #expect(note.contains(dictation), "nothing dictated is lost (R-4)")

        // It is a *reference file* of the project, not one of its actions (P6).
        let rescanned = try vault.rescan()
        let scannedDaad = try #require(rescanned.projects.first { $0.title == "DAAD" })
        #expect(scannedDaad.referenceFiles.contains(notePath))
        #expect(rescanned.action(NoteID(path: notePath)) == nil)
        #expect(rescanned.issues.isEmpty, "a note in a project folder is not a vault issue")

        // And the Knowledge tree still works as the other half of the same card.
        let second = try writer.capture(text: "Zotero exports BibTeX from the web library",
                                        at: Fixtures.date(Fixtures.today, 10, 20))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { $0.inbox.contains { $0.id == second } }
        try await model.send(.fileInbox(second, .knowledge(.folder("Studium"), notes: "")))
        #expect(try vault.text(
            "Knowledge/Studium/Zotero exports BibTeX from the web library.md") != nil)
    }

    // MARK: (d) Trash → undo restores byte for byte

    /// I4c — Trash is a **move**, never a status and never a hard delete. The card's note goes to
    /// `GTD/Trash/`, and one `⌘Z` puts the bytes back exactly where they were (R-9's small card).
    @Test func trashingACardMovesItsNoteAndUndoRestoresItByteForByte() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(text: "that newsletter thing, probably nothing",
                                          at: Fixtures.date(Fixtures.today, 7, 40))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { $0.inbox.contains { $0.id == captured } }

        let capturedText = try #require(try vault.text(captured.path))
        let before = try vault.filesOutsideTheTrash()

        try await model.send(.fileInbox(captured, .trash))
        #expect(try vault.text(captured.path) == nil)
        #expect(model.undoLabel == "Moved to Trash")
        // Nothing is hard-deleted: the note is in the trash, under its own name, unchanged.
        let inTrash = try #require(try vault.text("GTD/Trash/2026-09-19 074000.md"))
        #expect(inTrash == capturedText, "the trashed note is not rewritten on its way out")
        #expect(!model.snapshot.inbox.contains { $0.id == captured })

        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.filesOutsideTheTrash() == before,
                "undo restores the vault the app shows, byte for byte")
        #expect(try vault.text(captured.path) == capturedText)
        #expect(model.snapshot.inbox.contains { $0.id == captured }, "the card is back in the queue")

        // An *action* is trashed the same way (I4c): no `status: trash` is ever written.
        let action = try #require(model.snapshot.actions.first { $0.status == .next })
        let actionText = try #require(try vault.text(action.id.path))
        try await model.send(.trashAction(action.id))
        #expect(try vault.text(action.id.path) == nil)
        #expect(try vault.text("GTD/Trash/\(action.title).md") == actionText)
        #expect(!(try vault.files().values.joined().contains("status: trash\ncontexts")),
                "trashing never writes a legacy `status: trash` line")

        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.text(action.id.path) == actionText)
    }

    // MARK: (e) The project chip creates the project, and its area is its folder

    /// R-8 + R-6/R-7 in one journey: the card's `+ project` chip names a project that does not
    /// exist, so **one** command creates it area-less in `Projects/no_area/`, links the action and
    /// files the card. Giving it an area later moves the folder and rewrites the link; one undo
    /// brings every byte back.
    @Test func theProjectChipCreatesAnAreaLessProjectThatLaterMovesIntoItsArea() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(text: "get the Bafög follow-up application in",
                                          at: Fixtures.date(Fixtures.today, 11, 45))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { $0.inbox.contains { $0.id == captured } }

        // ── 1. `Create project "Bafög"` on the chip — one command, not two (R-8) ─────────────
        try await model.send(.fileInbox(captured, .action(ActionDraft(
            title: "", status: .someday, newProjectTitle: "Bafög",
            what: "Download the form and fill in the parts I know."))))

        let projectID = NoteID(path: "Projects/no_area/Bafög/Bafög.md")
        let projectNote = try #require(try vault.text(projectID.path))
        #expect(projectNote.contains("kind: project"))
        #expect(projectNote.contains("status: active"))
        #expect(!projectNote.contains("area:"),
                "created by name only, so there is no area and no `area:` line (R-6)")

        let actionPath = "Actions/get the Bafög follow-up application in.md"
        let actionText = try #require(try vault.text(actionPath))
        #expect(actionText.contains("project: \"[[Projects/no_area/Bafög/Bafög]]\""),
                "the same command linked the action to the project it just created")
        #expect(try vault.text(captured.path) == nil)
        // The project is never born without its first action: both are in one commit, so one
        // undo takes both away again.
        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.text(projectID.path) == nil, "the project went with the filing")
        #expect(try vault.text(actionPath) == nil)
        #expect(model.snapshot.inbox.contains { $0.id == captured }, "and the card is back (R-9)")

        // ── 2. File it again, then give the project an area (R-7) ────────────────────────────
        try await model.send(.fileInbox(captured, .action(ActionDraft(
            title: "", status: .someday, newProjectTitle: "Bafög",
            what: "Download the form and fill in the parts I know."))))
        let beforeTheMove = try vault.filesOutsideTheTrash()

        let area = try #require(model.snapshot.areas.first { $0.title == "Karriereplanung" })
        var project = try #require(model.snapshot.project(projectID))
        project.area = area.id
        try await model.send(.updateProject(project))

        let movedID = NoteID(path: "Projects/Karriereplanung/Bafög/Bafög.md")
        #expect(try vault.text(projectID.path) == nil)
        #expect(try await vault.store.folderContents("Projects/no_area/Bafög") == nil,
                "the folder moved; it was not copied")
        #expect(try #require(try vault.text(movedID.path))
            .contains("area: \"[[Projects/Karriereplanung/Karriereplanung]]\""))
        // The action's wikilink is rewritten in the **same** transaction as the folder move.
        #expect(try #require(try vault.text(actionPath))
            .contains("project: \"[[Projects/Karriereplanung/Bafög/Bafög]]\""))
        // An open project detail follows the note rather than concluding it was deleted.
        #expect(model.consumeRenames().resolve(projectID) == movedID)

        // ── 3. One journal entry carries the whole tree back (N6) ────────────────────────────
        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.filesOutsideTheTrash() == beforeTheMove, "byte for byte")

        let rescanned = try vault.rescan()
        #expect(rescanned.project(projectID)?.area == nil)
        #expect(rescanned.action(NoteID(path: actionPath))?.project == projectID)
        #expect(rescanned.issues.isEmpty)
    }

    // MARK: (f) A legacy `status: backlog` note survives a whole session

    /// R-1 — the codec *reads* `backlog`/`maybe` as `.someday` and the encoder patches only the
    /// lines whose decoded value changed, so a pre-rework note keeps its own word for as long as
    /// its status does not really change. A whole processing session runs over it and the file is
    /// byte-identical afterwards; the word changes on the first command that moves the note.
    @Test func aLegacyBacklogNoteIsReadAsSomedayAndIsNotRewrittenUntilItReallyChanges() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        let root = try #require(vault.root)

        // A note as a 2026-09-20 vault spells it — including an unknown key nobody must touch.
        let legacyPath = "Actions/Sort the cellar.md"
        let legacy = """
            ---
            status: backlog
            contexts: [home]
            timeEstimate: 90
            priority: someday-maybe
            created: 2026-05-02T14:00:00+02:00
            ---
            # Why?
            The bikes do not fit any more.

            # What?
            - [ ] Throw the paint tins out

            """
        try PlainFileSystem(root: root).writeText(legacy, to: legacyPath)

        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        let legacyID = NoteID(path: legacyPath)
        #expect(model.snapshot.action(legacyID)?.status == .someday,
                "`backlog` is the pre-rework spelling of the one 'not now' tier (A3/R-1)")
        // It is not a commitment, so it holds no cap slot and it does not rescue a project.
        #expect(!Rules.visibleActions(model.snapshot, today: Fixtures.today)
            .contains { $0.id == legacyID && $0.status == .next })

        // ── A whole session runs over it, and it is not touched ──────────────────────────────
        let writer = InboxWriter(fileSystem: PlainFileSystem(root: root), calendar: Fixtures.calendar)
        let captured = try writer.capture(text: "hang the bikes on the wall",
                                          at: Fixtures.date(Fixtures.today, 12, 0))
        await vault.store.simulateChangeForTesting()
        _ = await settle(model) { $0.inbox.contains { $0.id == captured } }

        try await model.send(.fileInbox(captured, .action(ActionDraft(
            title: "", status: .someday, what: "Buy two hooks."))))
        try await model.send(.trashAction(NoteID(path: "Actions/Learn Portuguese.md")))
        await model.undo()
        try await model.send(.completeListItem(NoteID(path: "Lists/Watch/Arrival.md")))

        #expect(try vault.text(legacyPath) == legacy,
                "a session that never touched this note left every byte of it alone (R-1)")

        // ── The word changes only when the status really changes ─────────────────────────────
        // Someday → Someday is not a change, so even *sending* it writes nothing.
        try await model.send(.setStatus(legacyID, .someday, waiting: nil))
        #expect(try vault.text(legacyPath) == legacy,
                "re-stating the status it already has does not rewrite the line")

        try await model.send(.setStatus(legacyID, .next, waiting: nil))
        let moved = try #require(try vault.text(legacyPath))
        #expect(moved.contains("status: next"))
        #expect(!moved.contains("backlog"))
        #expect(moved.contains("priority: someday-maybe"),
                "the unknown key the app knows nothing about is still there (N2)")
        #expect(moved.contains("- [ ] Throw the paint tins out"))

        let rescanned = try vault.rescan()
        #expect(rescanned.action(legacyID)?.status == .next)
        #expect(rescanned.issues.isEmpty)
    }

    // MARK: - Helpers

    /// Same poll as `EndToEndJourneyTests`: a store change reaches `AppModel` over three hops, so
    /// wait for the value rather than for a fixed number of turns.
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
