import Testing
import Foundation
import GTDModel

/// #85 — a half-processed inbox card closed without filing keeps what it had in its inbox note:
/// `InboxBody` (the body as the card reads and writes it), `saveInboxProgress` (the command) and
/// the action filing that later takes those sections over without writing them twice.
struct InboxProgressTests {
    private let env = TestVault.env()

    // MARK: - InboxBody

    @Test func aBodyWithoutTheHeadingsIsAllLead() {
        let body = "the long capture text\nsecond line"
        #expect(InboxBody.read(body) == InboxBody(lead: body))
        #expect(InboxBody.read("") == InboxBody())
    }

    /// The empty Obsidian template is not a card's progress: nothing is split out of it.
    @Test func theEmptyTemplateSkeletonIsNotSplit() {
        let skeleton = "# Why?\n-\n\n# What?\n- [ ] "
        #expect(InboxBody.read(skeleton) == InboxBody(lead: skeleton))
    }

    @Test func headingsSplitIntoLeadWhyAndWhat() {
        let body = "capture text\n\n# Why?\nbecause\n\n# What?\n- [ ] call"
        #expect(InboxBody.read(body) == InboxBody(lead: "capture text", why: "because", what: "- [ ] call"))
    }

    /// A section that holds only template bullets reads as empty, so the card does not count an
    /// empty `- [ ]` as an answer to `What?`.
    @Test func aSkeletonSectionReadsAsEmpty() {
        let body = "# Why?\nbecause\n\n# What?\n- [ ] "
        #expect(InboxBody.read(body) == InboxBody(why: "because"))
    }

    @Test func writingIntoAHeadinglessBodyAppendsTheSections() {
        let written = InboxBody(lead: "capture text", why: "because", what: "call").written(over: "capture text")
        #expect(written == "capture text\n\n# Why?\nbecause\n\n# What?\ncall")
        #expect(InboxBody.read(written) == InboxBody(lead: "capture text", why: "because", what: "call"))
    }

    @Test func writingChangesOnlyThePiecesThatDiffer() {
        let stored = "capture text  \n\n# Why?\nbecause\n\n# Ideas\nkeep me\n\n# What?\n- [ ] "
        var card = InboxBody.read(stored)
        #expect(card.written(over: stored) == stored, "nothing changed, nothing rewritten")

        card.what = "call"
        let written = card.written(over: stored)
        #expect(written == "capture text  \n\n# Why?\nbecause\n\n# Ideas\nkeep me\n\n# What?\ncall")
    }

    @Test func clearingTheLeadKeepsTheSections() {
        let stored = "capture\n\n# Why?\nbecause"
        let written = InboxBody(lead: "", why: "because").written(over: stored)
        #expect(written == "# Why?\nbecause")
    }

    // MARK: - saveInboxProgress

    @Test func savingProgressKeepsEverythingAndLeavesTheNoteInTheInbox() throws {
        let item = TestVault.inboxItem("call the Hausverwaltung")
        let project = TestVault.project("Flat")
        let snapshot = TestVault.snapshot(inbox: [item], projects: [project])
        let progress = InboxProgress(
            body: "# Why?\nbecause\n\n# What?\ncall",
            contexts: ["calls"],
            timeEstimate: 10,
            project: project.id,
            deferDate: Day(year: 2026, month: 10, day: 6),
            due: Day(year: 2026, month: 10, day: 9))

        let result = try Reducer.reduce(snapshot, .saveInboxProgress(item.id, progress), env: env)

        let saved = try #require(result.snapshot.inboxItem(item.id))
        #expect(saved.progress == progress)
        #expect(Rules.inboxQueue(result.snapshot).map(\.id) == [item.id], "still waiting to be processed")
        #expect(result.snapshot.actions.isEmpty)
        #expect(Rules.isUndoable(.saveInboxProgress(item.id, progress)))
    }

    @Test func aZeroEstimateIsNeverStored() throws {
        let item = TestVault.inboxItem("x")
        let result = try Reducer.reduce(
            TestVault.snapshot(inbox: [item]),
            .saveInboxProgress(item.id, InboxProgress(body: "", timeEstimate: 0)), env: env)
        #expect(result.snapshot.inboxItem(item.id)?.timeEstimate == nil)
    }

    @Test func savingProgressOfAMissingNoteIsRefused() {
        let item = TestVault.inboxItem("x")
        #expect(throws: GTDError.notFound(item.id)) {
            try Reducer.reduce(
                TestVault.snapshot(inbox: []), .saveInboxProgress(item.id, InboxProgress(body: "")),
                env: env)
        }
    }

    // MARK: - Filing a card that was closed half-way

    private func draft(why: String, what: String) -> ActionDraft {
        ActionDraft(
            title: "x", status: .next, contexts: ["calls"], timeEstimate: 10, why: why, what: what)
    }

    /// The sections become the action's own — never a second `# Why?` in the preamble.
    @Test func filingTakesTheSectionsOverInsteadOfDuplicatingThem() throws {
        let item = TestVault.inboxNote(
            "call the Hausverwaltung", body: "the long text\n\n# Why?\nbecause\n\n# What?\ncall")
        let result = try Reducer.reduce(
            TestVault.snapshot(inbox: [item]),
            .fileInbox(item.id, .action(draft(why: "because", what: "call"))), env: env)

        let action = try #require(result.snapshot.action(TestVault.actionID("call the Hausverwaltung")))
        #expect(action.preamble == "the long text")
        #expect(action.why == "because")
        #expect(action.what == "call")
        #expect(action.body.components(separatedBy: "# Why?").count == 2, "one Why? heading")
    }

    /// Written content is never lost: a field the draft leaves empty takes the note's.
    @Test func anEmptyDraftFieldTakesTheStoredSection() throws {
        let item = TestVault.inboxNote("x", body: "# Why?\nbecause\n\n# What?\ncall")
        let result = try Reducer.reduce(
            TestVault.snapshot(inbox: [item]),
            .fileInbox(item.id, .action(ActionDraft(title: "x", status: .someday, why: "", what: ""))),
            env: env)
        let action = try #require(result.snapshot.action(TestVault.actionID("x")))
        #expect(action.why == "because")
        #expect(action.what == "call")
    }

    @Test func aSectionOfTheUsersOwnComesAlong() throws {
        let item = TestVault.inboxNote("x", body: "# Why?\nbecause\n\n# Ideas\nkeep me\n\n# What?\nold")
        let result = try Reducer.reduce(
            TestVault.snapshot(inbox: [item]),
            .fileInbox(item.id, .action(draft(why: "because", what: "call"))), env: env)
        let action = try #require(result.snapshot.action(TestVault.actionID("x")))
        #expect(action.body == "# Why?\nbecause\n\n# Ideas\nkeep me\n\n# What?\ncall")
    }

    /// The pre-#85 path is unchanged: a headingless body is the preamble.
    @Test func aHeadinglessBodyIsStillThePreamble() throws {
        let item = TestVault.inboxNote("x", body: "the long text")
        let result = try Reducer.reduce(
            TestVault.snapshot(inbox: [item]),
            .fileInbox(item.id, .action(draft(why: "because", what: "call"))), env: env)
        let action = try #require(result.snapshot.action(TestVault.actionID("x")))
        #expect(action.body == "the long text\n\n# Why?\nbecause\n\n# What?\ncall")
    }
}
