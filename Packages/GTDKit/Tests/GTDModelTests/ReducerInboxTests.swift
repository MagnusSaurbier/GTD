import Testing
import Foundation
import GTDModel
import GTDFixtures

/// I1, I4, I5 — every way a capture can leave the inbox, and every way it can be refused.
///
/// The rulings this suite pins: **R-3** (required fields per tier), **C3/R-4** (an inbox note's
/// title is its file name, renaming it is a move, and nothing dictated is lost) and **R-8** (the
/// project chip, including the project it creates).
struct ReducerInboxTests {
    private let env = TestVault.env()
    private let capture = TestVault.inboxItem("call the Hausverwaltung", created: 0)

    private func vault(
        inbox: [InboxItem]? = nil,
        actions: [Action] = [],
        projects: [Project] = [],
        areas: [Area] = [],
        lists: [GTDList] = [GTDList(name: "Read")]
    ) -> VaultSnapshot {
        TestVault.snapshot(
            inbox: inbox ?? [capture], actions: actions, areas: areas, projects: projects,
            lists: lists)
    }

    /// A card that carries everything Next asks for (R-3).
    private func complete(_ status: ActionStatus = .next, waiting: WaitingInfo? = nil) -> ActionDraft {
        ActionDraft(
            title: "ignored — the note keeps the inbox note's file name",
            status: status,
            contexts: ["calls"],
            timeEstimate: 10,
            waiting: waiting,
            why: "The handle has been broken for two weeks.",
            what: "Ask about the window handle.")
    }

    // MARK: - I4: the four decisions

    @Test func filingToAnActionMovesTheCaptureIntoItsNewNote() throws {
        let result = try Reducer.reduce(vault(), .fileInbox(capture.id, .action(complete())), env: env)

        #expect(result.snapshot.inbox.isEmpty)
        // C3 — the note keeps the inbox note's file name, not the draft's title.
        let action = try #require(result.snapshot.action(TestVault.actionID("call the Hausverwaltung")))
        #expect(action.status == .next)
        #expect(action.contexts == ["calls"])
        #expect(action.timeEstimate == 10)
        #expect(action.preamble.isEmpty, "the title held the whole capture")
        // The capture's timestamp is the action's `created` — nothing pretends to be new (C3).
        #expect(action.created == capture.created)
        #expect(action.modified == env.now)
        // The capture file *becomes* the action note (R-4): it is moved, never trashed.
        #expect(result.extraOps == [.move(from: capture.id.path, to: action.id.path)])
        #expect(result.renames.resolve(capture.id) == action.id)
    }

    @Test func filingToKnowledgeMovesTheCaptureAndWritesTheNotesPanel() throws {
        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .knowledge(.folder("Studium/Thesis"), notes: "Marie has it.")),
            env: env)

        #expect(result.snapshot.inbox.isEmpty)
        #expect(result.snapshot.actions.isEmpty)
        let target = NoteID(path: "Knowledge/Studium/Thesis/call the Hausverwaltung.md")
        #expect(result.extraOps == [.move(from: capture.id.path, to: target.path)])
        // I4b — the note the capture became, with the notes panel as its body.
        #expect(result.filedNotes == [FiledNote(
            id: target, body: "Marie has it.", created: capture.created,
            source: capture.passthrough)])
        #expect(result.renames.resolve(capture.id) == target)
    }

    /// I4b/D36 — reference material for a project is filed through the Knowledge branch.
    @Test func knowledgeCanTargetAnActiveProjectsFolder() throws {
        let project = TestVault.project("Wohnungssuche")
        let result = try Reducer.reduce(
            vault(projects: [project]),
            .fileInbox(capture.id, .knowledge(.project(project.id), notes: "")),
            env: env)
        #expect(result.extraOps == [.move(
            from: capture.id.path,
            to: "Projects/no_area/Wohnungssuche/call the Hausverwaltung.md")])
    }

    @Test func knowledgeIntoAProjectThatIsNotActiveIsRefused() {
        let project = TestVault.project("Wohnungssuche", status: .onHold)
        #expect(TestVault.error(
            vault(projects: [project]),
            .fileInbox(capture.id, .knowledge(.project(project.id), notes: "")), env: env)
            == .invalid("Only active projects put actions into Next"))
        let ghost = TestVault.layout.projectPath(title: "Ghost", inArea: nil)
        #expect(TestVault.error(
            vault(), .fileInbox(capture.id, .knowledge(.project(ghost), notes: "")), env: env)
            == .notFound(ghost))
    }

    @Test func filingToAListMovesTheCaptureAndKeepsTheNotes() throws {
        let result = try Reducer.reduce(
            vault(), .fileInbox(capture.id, .list(name: "Read", notes: "Marie empfiehlt es.")),
            env: env)
        let item = try #require(result.snapshot.listItems.first)
        #expect(item.list == "Read")
        #expect(item.title == "call the Hausverwaltung")
        #expect(item.notes == "Marie empfiehlt es.")
        #expect(item.created == capture.created)
        #expect(result.extraOps == [.move(from: capture.id.path, to: item.id.path)])
    }

    @Test func filingToAnUnknownListIsRefused() {
        #expect(TestVault.error(vault(), .fileInbox(capture.id, .list(name: "Ghost", notes: "")), env: env)
                == .invalid("Unknown list: Ghost"))
    }

    @Test func trashingOnlyMovesTheFile() throws {
        let result = try Reducer.reduce(vault(), .fileInbox(capture.id, .trash), env: env)
        #expect(result.snapshot.inbox.isEmpty)
        #expect(result.snapshot.actions.isEmpty)
        // `.delete` means "move to GTD/Trash/" — the app never hard-deletes (ARCHITECTURE §3).
        #expect(result.extraOps == [.delete(path: capture.id.path)])
    }

    // MARK: - R-3: required fields, one row of the table each

    /// Next needs Why? + What? + a context + a time estimate, and the error names all of them,
    /// in a stable order.
    @Test func nextNeedsWhyWhatContextAndTime() {
        let bare = ActionDraft(title: "x", status: .next)
        #expect(TestVault.error(vault(), .fileInbox(capture.id, .action(bare)), env: env)
                == .missingFields([.why, .what, .context, .timeEstimate]))

        var partial = bare
        partial.why = "Because."
        partial.contexts = ["calls"]
        #expect(TestVault.error(vault(), .fileInbox(capture.id, .action(partial)), env: env)
                == .missingFields([.what, .timeEstimate]))
    }

    @Test func somedayNeedsWhatAndNothingElse() throws {
        #expect(TestVault.error(
            vault(), .fileInbox(capture.id, .action(ActionDraft(title: "x", status: .someday))), env: env)
            == .missingFields([.what]))

        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .action(ActionDraft(title: "x", status: .someday, what: "Anrufen"))),
            env: env)
        #expect(result.snapshot.actions.first?.status == .someday)
    }

    /// W1/D39 — the follow-up date is required; who is optional and writes no line when empty.
    @Test func waitingNeedsWhatAndAFollowUpDateButNotWho() throws {
        #expect(TestVault.error(
            vault(), .fileInbox(capture.id, .action(ActionDraft(title: "x", status: .waiting))), env: env)
            == .missingFields([.what, .followUpDate]))

        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .action(ActionDraft(
                title: "x", status: .waiting, waiting: WaitingInfo(followUp: TestVault.day(7)),
                what: "Warten auf Antwort"))),
            env: env)
        let action = try #require(result.snapshot.actions.first)
        #expect(action.status == .waiting)
        #expect(action.waitingFor == nil, "an empty who is no who at all (D39)")
        #expect(action.followUpDate == TestVault.day(7))
    }

    @Test func aBlankWhoIsTreatedAsNoWho() throws {
        let result = try Reducer.reduce(
            vault(),
            .fileInbox(capture.id, .action(ActionDraft(
                title: "x", status: .waiting,
                waiting: WaitingInfo(who: "   ", followUp: TestVault.day(7)),
                what: "Warten"))),
            env: env)
        #expect(result.snapshot.actions.first?.waitingFor == nil)
    }

    /// I4/D13 — the 2-minute rule asks for nothing at all, and the note is closed on the spot.
    @Test func doneFilingNeedsNothingAndCarriesACompletedDate() throws {
        let result = try Reducer.reduce(
            vault(), .fileInbox(capture.id, .action(ActionDraft(title: "x", status: .done))), env: env)
        let action = try #require(result.snapshot.actions.first)
        #expect(action.status == .done)
        #expect(action.completedDate == env.now)
    }

    @Test func listsKnowledgeAndTrashRequireNothing() throws {
        for decision: InboxDecision in [
            .list(name: "Read", notes: ""), .knowledge(.folder(""), notes: ""), .trash,
        ] {
            let result = try Reducer.reduce(vault(), .fileInbox(capture.id, decision), env: env)
            #expect(result.snapshot.inbox.isEmpty, "\(decision)")
        }
    }

    /// R-3 — a note **already** in its tier is never judged again: the vault stays repairable.
    @Test func aNoteAlreadyInNextWithGapsStaysEditable() throws {
        var gappy = TestVault.action("Old and gappy", .next)
        let snapshot = TestVault.snapshot(actions: [gappy])
        gappy.due = TestVault.day(3)
        let result = try Reducer.reduce(snapshot, .updateAction(gappy), env: env)
        #expect(result.snapshot.actions.first?.due == TestVault.day(3))
    }

    /// …but moving it *into* Next from somewhere else asks for everything (R-3).
    @Test func promotingASomedayNoteIntoNextAsksForTheFields() {
        let gappy = TestVault.action("Someday note", .someday, what: "Etwas tun")
        #expect(TestVault.error(
            TestVault.snapshot(actions: [gappy]), .setStatus(gappy.id, .next, waiting: nil), env: env)
            == .missingFields([.why, .context, .timeEstimate]))
    }

    @Test func promotingAListItemIntoNextAsksForTheFields() {
        let item = TestVault.listItem("Read", "Ein Buch")
        let snapshot = TestVault.snapshot(lists: [GTDList(name: "Read")], listItems: [item])
        #expect(TestVault.error(
            snapshot, .promoteListItem(item.id, ActionDraft(title: "Ein Buch", status: .next)), env: env)
            == .missingFields([.why, .what, .context, .timeEstimate]))
    }

    /// P4/P5 — the step line is the `What?`, so a one-tap promotion satisfies Someday; Next
    /// still asks for the rest (ARCHITECTURE §6, T04-1).
    @Test func promotingAStepTakesItsWhatFromTheStepLine() throws {
        let project = TestVault.project("Wohnungssuche", steps: [ProjectStep(text: "Makler anrufen")])
        let snapshot = TestVault.snapshot(projects: [project])
        let result = try Reducer.reduce(
            snapshot,
            .promoteStep(project: project.id, stepIndex: 0, ActionDraft(title: "", status: .someday)),
            env: env)
        #expect(result.snapshot.actions.first?.what == "Makler anrufen")

        #expect(TestVault.error(
            snapshot,
            .promoteStep(project: project.id, stepIndex: 0, ActionDraft(title: "", status: .next)),
            env: env)
            == .missingFields([.why, .context, .timeEstimate]))
    }

    // MARK: - C3/R-4: the file name is the title

    @Test func umlautsAreCountedAsCharactersNotBytes() throws {
        let text = "Prüfungsanmeldung für Mathe über das Portal erledigen bevor"  // exactly 59 characters
        let long = TestVault.inboxItem(text)
        #expect(text.count == 59)
        #expect(long.title == text, "59 characters fit, whatever they weigh in bytes")
        #expect(long.body.isEmpty)
        let result = try Reducer.reduce(
            vault(inbox: [long]), .fileInbox(long.id, .action(complete(.someday))), env: env)
        let action = try #require(result.snapshot.actions.first)
        #expect(action.title == text)
        #expect(action.preamble.isEmpty)
    }

    /// The trigger of the 2026-09-22 decision: a note made in Obsidian from the user's template
    /// has only the empty Why/What skeleton as its body. Its title is its file name — never the
    /// body's first line ("# Why? -").
    @Test func aSkeletonOnlyNoteIsTitledByItsFileName() {
        let note = TestVault.inboxNote("test task", body: "# Why?\n- \n\n# What?\n- [ ] ")
        #expect(note.title == "test task")
        #expect(note.id.path == "Inbox/test task.md")
    }

    /// …and filing it neither copies the skeleton into the action above its own `# Why?` /
    /// `# What?` nor into a Knowledge note's or list item's notes.
    @Test func aSkeletonBodyDoesNotLeakIntoTheFiledNote() throws {
        let note = TestVault.inboxNote("test task", body: "# Why?\n- \n\n# What?\n- [ ] \n")
        let snapshot = vault(inbox: [note])

        let asAction = try Reducer.reduce(snapshot, .fileInbox(note.id, .action(complete())), env: env)
        let action = try #require(asAction.snapshot.actions.first)
        #expect(action.title == "test task")
        #expect(action.id.path == "Actions/test task.md")
        #expect(action.preamble.isEmpty, "the skeleton is not content")
        #expect(action.why == complete().why)
        #expect(action.what == complete().what)

        let asKnowledge = try Reducer.reduce(
            snapshot, .fileInbox(note.id, .knowledge(.folder(""), notes: "")), env: env)
        #expect(asKnowledge.filedNotes.first?.body == "")
        let withNotes = try Reducer.reduce(
            snapshot, .fileInbox(note.id, .knowledge(.folder(""), notes: "Marie")), env: env)
        #expect(withNotes.filedNotes.first?.body == "Marie")

        let asListItem = try Reducer.reduce(
            snapshot, .fileInbox(note.id, .list(name: "Read", notes: "")), env: env)
        #expect(asListItem.snapshot.listItems.first?.notes == "")
    }

    /// A body the user actually wrote comes along, above the notes panel.
    @Test func aRealBodyIsCarriedAboveTheNotes() throws {
        let note = TestVault.inboxNote("Umzug", body: "# Why?\n- die Miete steigt\n")
        let result = try Reducer.reduce(
            vault(inbox: [note]), .fileInbox(note.id, .list(name: "Read", notes: "bis Oktober")),
            env: env)
        #expect(result.snapshot.listItems.first?.notes == "# Why?\n- die Miete steigt\n\nbis Oktober")
    }

    /// The name the user gave a note is kept whole — only a capture's name is cut to 60.
    @Test func aLongFileNameIsNotCutOnFiling() throws {
        let name = String(repeating: "Wohnung ", count: 10).trimmingCharacters(in: .whitespaces)
        let note = TestVault.inboxNote(name)
        let result = try Reducer.reduce(
            vault(inbox: [note]), .fileInbox(note.id, .action(complete(.someday))), env: env)
        #expect(result.snapshot.actions.first?.title == name)
    }

    @Test func aLongDictationIsCutAtAWordBoundaryAndKeptInTheBody() throws {
        let text = "Beim Studierendenwerk nachfragen, ob die Kaution für das Zimmer "
            + "schon überwiesen wurde"
        let long = TestVault.inboxItem(text)
        let result = try Reducer.reduce(
            vault(inbox: [long]), .fileInbox(long.id, .action(complete())), env: env)
        let action = try #require(result.snapshot.actions.first)

        #expect(action.title.count <= 60)
        #expect(!action.title.hasSuffix(" "))
        #expect(text.hasPrefix(action.title), "cut at a word boundary, never mid-word")
        #expect(action.title == "Beim Studierendenwerk nachfragen, ob die Kaution für das")
        // R-4 — nothing dictated is lost: the full text is the note's first paragraph.
        #expect(action.preamble == text)
    }

    @Test func aMultiLineCaptureIsTitledByItsFirstLineAndKeepsTheRest() throws {
        let text = "Mail an den Vermieter\nKaution\nNebenkosten"
        let multi = TestVault.inboxItem(text)
        let result = try Reducer.reduce(
            vault(inbox: [multi]), .fileInbox(multi.id, .action(complete())), env: env)
        let action = try #require(result.snapshot.actions.first)
        #expect(action.title == "Mail an den Vermieter")
        #expect(action.preamble == text)
    }

    /// The same rule for a Knowledge note and a list item: the full text above the notes.
    @Test func aCutCaptureKeepsItsFullTextAboveTheNotes() throws {
        let text = "Der Artikel über Wohnungsmärkte in München, den Marie in der Gruppe geteilt hat"
        let item = TestVault.inboxItem(text)
        let listResult = try Reducer.reduce(
            vault(inbox: [item]), .fileInbox(item.id, .list(name: "Read", notes: "Vor Montag")),
            env: env)
        #expect(listResult.snapshot.listItems.first?.notes == text + "\n\nVor Montag")

        let knowledgeResult = try Reducer.reduce(
            vault(inbox: [item]), .fileInbox(item.id, .knowledge(.folder(""), notes: "")), env: env)
        #expect(knowledgeResult.filedNotes.first?.body == text)
    }

    // MARK: - C3: renaming the card renames the file

    @Test func renamingMovesTheFileWithinTheInbox() throws {
        let result = try Reducer.reduce(
            vault(), .renameInboxItem(capture.id, title: "Mail the Hausverwaltung"), env: env)
        let target = NoteID(path: "Inbox/Mail the Hausverwaltung.md")
        let renamed = try #require(result.snapshot.inboxItem(target))
        #expect(renamed.title == "Mail the Hausverwaltung")
        #expect(renamed.created == capture.created)
        #expect(renamed.body == capture.body)
        #expect(renamed.passthrough == capture.passthrough)
        #expect(result.snapshot.inboxItem(capture.id) == nil)
        #expect(result.extraOps == [.move(from: capture.id.path, to: target.path)])
        #expect(result.renames.resolve(capture.id) == target)
    }

    /// A new name is sanitised and cut like a capture's; its lines are joined, nothing dropped.
    @Test func aRenamedTitleIsSanitisedLikeACapture() throws {
        let result = try Reducer.reduce(
            vault(), .renameInboxItem(capture.id, title: "  call: the\nHausverwaltung "), env: env)
        #expect(result.snapshot.inbox.map(\.title) == ["call the Hausverwaltung"])
        #expect(result.snapshot.inbox.first?.id == capture.id, "the same name is no rename")
        #expect(result.extraOps.isEmpty)
    }

    @Test func renamingToANameThatIsTakenIsACollision() {
        let other = TestVault.inboxItem("Mail the Hausverwaltung")
        let snapshot = vault(inbox: [capture, other])
        #expect(TestVault.error(
            snapshot, .renameInboxItem(capture.id, title: "Mail the Hausverwaltung"), env: env)
            == .titleCollision("Mail the Hausverwaltung"))
    }

    @Test func renamingToAnEmptyTitleIsRefused() {
        for blank in ["", "   ", "\n\t "] {
            #expect(TestVault.error(vault(), .renameInboxItem(capture.id, title: blank), env: env)
                    == .invalid("A title is required"))
        }
    }

    /// Filing after a rename files under the new name.
    @Test func aRenamedCardIsFiledUnderItsNewName() throws {
        let renamed = try Reducer.reduce(
            vault(), .renameInboxItem(capture.id, title: "Mail the Hausverwaltung"), env: env)
        let id = NoteID(path: "Inbox/Mail the Hausverwaltung.md")
        let filed = try Reducer.reduce(renamed.snapshot, .fileInbox(id, .action(complete())), env: env)
        #expect(filed.snapshot.actions.first?.id.path == "Actions/Mail the Hausverwaltung.md")
    }

    @Test func editingTheBodyKeepsTheNameAndEverythingElse() throws {
        let result = try Reducer.reduce(
            vault(), .editInboxBody(capture.id, "The handle on the left window."), env: env)
        let item = try #require(result.snapshot.inboxItem(capture.id))
        #expect(item.body == "The handle on the left window.")
        #expect(item.title == capture.title)
        #expect(item.created == capture.created)
        #expect(result.extraOps.isEmpty)
    }

    @Test func aTitleThatAlreadyExistsIsACollision() {
        let existing = TestVault.action("call the Hausverwaltung")
        #expect(TestVault.error(
            vault(actions: [existing]), .fileInbox(capture.id, .action(complete())), env: env)
            == .titleCollision("call the Hausverwaltung"))

        let item = TestVault.listItem("Read", "call the Hausverwaltung")
        let withItem = TestVault.snapshot(
            inbox: [capture], lists: [GTDList(name: "Read")], listItems: [item])
        #expect(TestVault.error(withItem, .fileInbox(capture.id, .list(name: "Read", notes: "")), env: env)
                == .titleCollision("call the Hausverwaltung"))
    }

    // MARK: - R-8: the project chip

    @Test func theProjectChipLinksAnExistingProject() throws {
        let project = TestVault.project("Wohnungssuche")
        var draft = complete()
        draft.project = project.id
        let result = try Reducer.reduce(
            vault(projects: [project]), .fileInbox(capture.id, .action(draft)), env: env)
        #expect(result.snapshot.actions.first?.project == project.id)
    }

    /// I4a/D35 — `Create project "<text>"`: name only, area-less, in the same command.
    @Test func theProjectChipCanCreateTheProjectItLinks() throws {
        var draft = complete()
        draft.newProjectTitle = "Wohnungssuche"
        let result = try Reducer.reduce(vault(), .fileInbox(capture.id, .action(draft)), env: env)

        let project = try #require(result.snapshot.projects.first)
        #expect(project.title == "Wohnungssuche")
        #expect(project.area == nil, "a project created from the chip has no area yet (P1)")
        #expect(project.status == .active, "so its first action may go to Next (P3)")
        #expect(project.id == TestVault.layout.projectPath(title: "Wohnungssuche", inArea: nil))
        #expect(result.snapshot.actions.first?.project == project.id)
        #expect(result.snapshot.actions.count == 1, "the card stays one action (D33)")
    }

    @Test func namingBothAnExistingAndANewProjectIsRefused() {
        let project = TestVault.project("Wohnungssuche")
        var draft = complete()
        draft.project = project.id
        draft.newProjectTitle = "Etwas anderes"
        #expect(TestVault.error(
            vault(projects: [project]), .fileInbox(capture.id, .action(draft)), env: env)
            == .invalid("An action names either an existing project or a new one, not both"))
    }

    @Test func aChipCreatingAProjectThatExistsIsACollision() {
        let project = TestVault.project("Wohnungssuche")
        var draft = complete()
        draft.newProjectTitle = "Wohnungssuche"
        #expect(TestVault.error(
            vault(projects: [project]), .fileInbox(capture.id, .action(draft)), env: env)
            == .titleCollision("Wohnungssuche"))
    }

    /// `createAction` and `promoteListItem` take the same chip — one place decides (R-8).
    @Test func theChipWorksOutsideTheInboxToo() throws {
        let result = try Reducer.reduce(
            vault(), .createAction(ActionDraft(
                title: "Termin machen", status: .someday, newProjectTitle: "Umzug",
                what: "Beim Amt anrufen")),
            env: env)
        let project = try #require(result.snapshot.projects.first)
        #expect(project.title == "Umzug")
        #expect(result.snapshot.actions.first?.project == project.id)
    }

    // MARK: - I4: refusals

    @Test func filingIsRefusedWhenNextIsFull() throws {
        var full = TestVault.nextOccupied(15)
        full.inbox = [capture]
        let error = TestVault.error(full, .fileInbox(capture.id, .action(complete())), env: env)
        #expect(error == .nextCapReached(cap: 15))
    }

    /// The fields come first: a card that is missing something hears about the field, not about
    /// the cap it has not reached yet.
    @Test func missingFieldsAreReportedBeforeTheCap() {
        var full = TestVault.nextOccupied(15)
        full.inbox = [capture]
        #expect(TestVault.error(
            full, .fileInbox(capture.id, .action(ActionDraft(title: "x", status: .next))), env: env)
            == .missingFields([.why, .what, .context, .timeEstimate]))
    }

    @Test func filingAnUnknownCaptureIsNotFound() {
        let ghost = TestVault.layout.inboxPath(title: "ghost")
        #expect(TestVault.error(vault(), .fileInbox(ghost, .trash), env: env) == .notFound(ghost))
        #expect(TestVault.error(vault(), .renameInboxItem(ghost, title: "x"), env: env) == .notFound(ghost))
        #expect(TestVault.error(vault(), .editInboxBody(ghost, "x"), env: env) == .notFound(ghost))
        #expect(TestVault.error(vault(), .deferInboxToReview(ghost, reason: "x"), env: env) == .notFound(ghost))
    }

    /// A refused command must leave the vault exactly as it was.
    @Test func arefusedFilingChangesNothing() {
        var full = TestVault.nextOccupied(15)
        full.inbox = [capture]
        let before = full
        _ = TestVault.error(full, .fileInbox(capture.id, .action(complete())), env: env)
        #expect(full == before)
    }

    // MARK: - I5: defer to review

    @Test func deferToReviewStoresTheReasonAndLeavesTheQueue() throws {
        let result = try Reducer.reduce(
            vault(), .deferInboxToReview(capture.id, reason: "  It is a decision, not an action.  "), env: env)
        let item = try #require(result.snapshot.inboxItem(capture.id))
        #expect(item.reviewReason == "It is a decision, not an action.")
        #expect(Rules.inboxQueue(result.snapshot).isEmpty)
        #expect(Rules.reviewDeferredInbox(result.snapshot).map(\.id) == [capture.id])
        #expect(result.extraOps.isEmpty)
    }

    @Test func deferToReviewNeedsAReason() {
        #expect(TestVault.error(vault(), .deferInboxToReview(capture.id, reason: "   "), env: env)
                == .invalid("Defer to review needs a reason"))
    }

    // MARK: - I1 against the realistic vault

    @Test func theSampleVaultProcessesLIFO() throws {
        let queue = Rules.inboxQueue(Fixtures.sampleSnapshot)
        #expect(queue.count == 5)                       // the sixth is deferred to review (I5)
        #expect(queue.first?.created == queue.map(\.created).max())
        let result = try Reducer.reduce(
            Fixtures.sampleSnapshot,
            .fileInbox(queue[0].id, .action(ActionDraft(
                title: "", status: .someday, what: "Anrufen"))),
            env: Fixtures.reducerEnv())
        #expect(Rules.inboxQueue(result.snapshot).map(\.id) == Array(queue.dropFirst()).map(\.id))
    }
}
