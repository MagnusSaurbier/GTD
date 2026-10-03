import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// "Changing one field changes only that key's line in the output" (T10 acceptance).
struct PatchTests {

    /// A note with unknown keys, comments, odd spacing and unknown sections around everything
    /// the model knows about — so a sloppy encoder cannot pass by accident.
    static let messyAction = """
    ---
    # user's own comment
    tags: [work, uni]
    status: next
    priority: high
    contexts: [mac, deep-work]

    timeEstimate: 30
    project: "[[Projects/Applications/DAAD/DAAD]]"
    due: 2026-09-24
    created: 2026-09-07T09:30:00+02:00
    Ressources: ""
    ---
    # Why?
    The letter is the part the committee actually reads.

    # Notes
    Keep this.

    # What?
    - [ ] Draft the opening paragraph
    - [ ] Rework the research-fit section

    # Attachments
    ![[scan.pdf]]

    """

    private static let id = NoteID(path: "Actions/Write DAAD motivation letter.md")

    private func decoded() throws -> Action {
        try NoteCodec.decodeAction(id: PatchTests.id, text: PatchTests.messyAction, timeZone: vaultTimeZone)
    }

    /// Number of lines that differ between the original and the re-encoded note.
    private func changedLines(_ mutate: (inout Action) -> Void) throws -> [String] {
        var action = try decoded()
        mutate(&action)
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        let before = RawText.split(PatchTests.messyAction)
        let after = RawText.split(encoded)
        var changed: [String] = []
        for index in 0..<max(before.count, after.count) {
            let lhs = index < before.count ? before[index] : nil
            let rhs = index < after.count ? after[index] : nil
            if lhs != rhs { changed.append(rhs?.content ?? "<removed: \(lhs?.content ?? "")>") }
        }
        return changed
    }

    @Test func noChangeMeansNoBytesChange() throws {
        #expect(try changedLines { _ in } == [])
    }

    @Test func changingStatusRewritesOnlyTheStatusLine() throws {
        #expect(try changedLines { $0.status = .done } == ["status: done"])
    }

    @Test func changingTimeEstimateRewritesOnlyThatLine() throws {
        #expect(try changedLines { $0.timeEstimate = 60 } == ["timeEstimate: 60"])
    }

    @Test func changingContextsRewritesOnlyThatLine() throws {
        #expect(try changedLines { $0.contexts = ["phone"] } == ["contexts: [phone]"])
    }

    @Test func clearingTheProjectRemovesOnlyThatLine() throws {
        var action = try decoded()
        action.project = nil
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        #expect(encoded == PatchTests.messyAction.replacingOccurrences(
            of: "project: \"[[Projects/Applications/DAAD/DAAD]]\"\n", with: ""))
    }

    @Test func addingAnAbsentKeyPutsItInSchemaOrder() throws {
        var action = try decoded()
        action.deferDate = Day(year: 2026, month: 10, day: 1)
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        let lines = RawText.split(encoded).map(\.content)
        let deferIndex = try #require(lines.firstIndex(of: "defer: 2026-10-01"))
        let projectIndex = try #require(lines.firstIndex { $0.hasPrefix("project:") })
        let dueIndex = try #require(lines.firstIndex { $0.hasPrefix("due:") })
        // REQUIREMENTS §5 order: … project, defer, due …
        #expect(projectIndex < deferIndex)
        #expect(deferIndex < dueIndex)
        // Nothing else moved.
        #expect(encoded.replacingOccurrences(of: "defer: 2026-10-01\n", with: "") == PatchTests.messyAction)
    }

    @Test func changingWhyLeavesEveryOtherSectionAlone() throws {
        let changed = try changedLines { $0.why = "A different reason." }
        #expect(changed == ["A different reason."])
    }

    @Test func togglingACheckboxChangesOnlyThatLine() throws {
        var action = try decoded()
        #expect(action.checkboxes.count == 2)
        action.what = action.what.replacingOccurrences(
            of: "- [ ] Draft the opening paragraph", with: "- [x] Draft the opening paragraph")
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        #expect(encoded == PatchTests.messyAction.replacingOccurrences(
            of: "- [ ] Draft the opening paragraph", with: "- [x] Draft the opening paragraph"))
    }

    @Test func unknownKeysAndSectionsAreNeverTouched() throws {
        var action = try decoded()
        action.status = .waiting
        action.waitingFor = "Prof. Weber"
        action.followUpDate = Day(year: 2026, month: 9, day: 30)
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        #expect(encoded.contains("# user's own comment"))
        #expect(encoded.contains("tags: [work, uni]"))
        #expect(encoded.contains("priority: high"))
        #expect(encoded.contains("Ressources: \"\""))
        #expect(encoded.contains("# Notes\nKeep this."))
        #expect(encoded.contains("# Attachments\n![[scan.pdf]]"))
        #expect(encoded.contains("waitingFor: \"Prof. Weber\""))
        #expect(encoded.contains("followUpDate: 2026-09-30"))
    }

    @Test func timeEstimateZeroIsNeverEmitted() throws {
        var action = try decoded()
        action.timeEstimate = 0
        #expect(!NoteCodec.encode(action, timeZone: vaultTimeZone).contains("timeEstimate: 0"))
        action.timeEstimate = nil
        #expect(!NoteCodec.encode(action, timeZone: vaultTimeZone).contains("timeEstimate:"))
    }

    @Test func crlfIsPreservedWhenAFieldChanges() throws {
        let text = "---\r\nstatus: next\r\ncontexts: [mac]\r\n---\r\n# Why?\r\nx\r\n"
        let id = NoteID(path: "Actions/A.md")
        var action = try NoteCodec.decodeAction(id: id, text: text, timeZone: vaultTimeZone)
        action.status = .someday
        action.why = "y"
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        #expect(encoded == "---\r\nstatus: someday\r\ncontexts: [mac]\r\n---\r\n# Why?\r\ny\r\n")
    }

    @Test func aMissingSectionIsInsertedInOrder() throws {
        let text = "---\nstatus: next\n---\n# Why?\nBecause.\n"
        let id = NoteID(path: "Actions/A.md")
        var action = try NoteCodec.decodeAction(id: id, text: text, timeZone: vaultTimeZone)
        action.what = "- [ ] Step"
        #expect(NoteCodec.encode(action, timeZone: vaultTimeZone)
            == "---\nstatus: next\n---\n# Why?\nBecause.\n\n# What?\n- [ ] Step\n")
    }

    @Test func frontmatterIsCreatedForANoteThatHasNone() throws {
        let text = "Just prose.\n"
        let id = NoteID(path: "Actions/A.md")
        // No `status` ⇒ unreadable; start from a fresh action instead.
        var action = Action(id: id, title: "A", status: .next)
        action.passthrough = NoteCodec.passthrough(text)
        action.body = "Just prose."          // matches what decode would have read
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        #expect(encoded == "---\nstatus: next\n---\nJust prose.\n")
    }

    // MARK: - Projects

    @Test func promotingAStepChangesOnlyThatStepLine() throws {
        let path = "Projects/Applications/DAAD/DAAD.md"
        let text = try #require(SampleVault.files[path])
        var project = try NoteCodec.decodeProject(id: NoteID(path: path), text: text)
        project.steps[2].promotedTo = NoteID(path: "Actions/Ask Prof. Weber for a reference.md")
        let encoded = NoteCodec.encode(project)
        #expect(encoded == text.replacingOccurrences(
            of: "- [ ] Ask Prof. Weber for a reference",
            with: "- [ ] Ask Prof. Weber for a reference → [[Actions/Ask Prof. Weber for a reference]]"))
    }

    @Test func appendingALogEntryChangesOnlyTheLogSection() throws {
        let path = "Projects/Applications/DAAD/DAAD.md"
        let text = try #require(SampleVault.files[path])
        var project = try NoteCodec.decodeProject(id: NoteID(path: path), text: text)
        project.log.append(LogEntry(day: Day(year: 2026, month: 9, day: 19), text: "Wrote the letter"))
        let encoded = NoteCodec.encode(project)
        #expect(encoded == text + "- 2026-09-19 Wrote the letter\n")
    }

    // MARK: - R-1: the legacy status words

    /// The heart of R-1: a file that says `status: backlog` decodes as `.someday`, so writing it
    /// back changes **nothing** — the user's note is not rewritten behind their back. Only a real
    /// status change touches the line, and then exactly that line.
    @Test func aLegacyBacklogFileKeepsItsWordUntilTheStatusReallyChanges() throws {
        let id = NoteID(path: "Actions/Alt.md")
        let text = "---\nstatus: backlog\ncontexts: [mac]\n---\n# Why?\nx\n\n# What?\ny\n"
        var action = try NoteCodec.decodeAction(id: id, text: text)
        #expect(action.status == .someday)
        #expect(NoteCodec.encode(action) == text)          // byte for byte: nothing changed

        // Editing another field still leaves the status line alone.
        action.contexts = ["home"]
        #expect(NoteCodec.encode(action)
            == text.replacingOccurrences(of: "contexts: [mac]", with: "contexts: [home]"))

        // Only a real tier change rewrites it — and it rewrites one line.
        var promoted = try NoteCodec.decodeAction(id: id, text: text)
        promoted.status = .next
        #expect(NoteCodec.encode(promoted)
            == text.replacingOccurrences(of: "status: backlog", with: "status: next"))
    }

    /// The same for the legacy `trash` state: repairing it writes the new word, once.
    @Test func aLegacyTrashFileIsRewrittenOnlyWhenItIsRepaired() throws {
        let id = NoteID(path: "Actions/Verworfen.md")
        let text = "---\nstatus: trash\n---\n# What?\nx\n"
        var action = try NoteCodec.decodeAction(id: id, text: text)
        #expect(NoteCodec.encode(action) == text)
        action.status = .someday
        #expect(NoteCodec.encode(action)
            == text.replacingOccurrences(of: "status: trash", with: "status: someday"))
    }

    // MARK: - #86: a legacy `defer:` is read as waiting

    static let legacyDeferred = "---\nstatus: next\ncontexts: [mac]\ndefer: 2026-10-10\n---\n# Why?\nx\n\n# What?\ny\n"

    /// A deferred note from before #86 reads as a who-less waiting item following up on the
    /// defer date, and writing it back unchanged changes nothing on disk.
    @Test func aLegacyDeferredFileReadsAsWaitingAndIsNotRewrittenByReading() throws {
        let id = NoteID(path: "Actions/Später.md")
        let action = try NoteCodec.decodeAction(id: id, text: PatchTests.legacyDeferred)
        #expect(action.status == .waiting)
        #expect(action.waitingFor == nil)
        #expect(action.followUpDate == Day(year: 2026, month: 10, day: 10))
        #expect(action.deferDate == nil)
        #expect(NoteCodec.encode(action) == PatchTests.legacyDeferred)     // byte for byte
    }

    /// Once the user changes the note, the lines the fold stood in for are written for real:
    /// `status: waiting`, `followUpDate:` in schema order, and no `defer:`.
    @Test func editingALegacyDeferredFileWritesItAsWaiting() throws {
        let id = NoteID(path: "Actions/Später.md")
        var action = try NoteCodec.decodeAction(id: id, text: PatchTests.legacyDeferred)
        action.contexts = ["home"]
        let encoded = NoteCodec.encode(action)
        #expect(encoded == "---\nstatus: waiting\ncontexts: [home]\nfollowUpDate: 2026-10-10\n---\n# Why?\nx\n\n# What?\ny\n")
        let reread = try NoteCodec.decodeAction(id: id, text: encoded)
        #expect(reread.status == .waiting)
        #expect(reread.followUpDate == Day(year: 2026, month: 10, day: 10))
    }

    /// Moving it to a tier drops the defer date; the status line says the tier.
    @Test func promotingALegacyDeferredFileDropsTheDeferLine() throws {
        let id = NoteID(path: "Actions/Später.md")
        var action = try NoteCodec.decodeAction(id: id, text: PatchTests.legacyDeferred)
        action.status = .someday
        action.followUpDate = nil
        let encoded = NoteCodec.encode(action)
        #expect(encoded == "---\nstatus: someday\ncontexts: [mac]\n---\n# Why?\nx\n\n# What?\ny\n")
    }

    /// Clearing the folded follow-up date is a change too, even though the patch against the
    /// folded note has no line to remove: the edit must not be lost on the next read.
    @Test func clearingTheFoldedFollowUpDateSurvivesTheWrite() throws {
        let id = NoteID(path: "Actions/Später.md")
        var action = try NoteCodec.decodeAction(id: id, text: PatchTests.legacyDeferred)
        action.followUpDate = nil
        let reread = try NoteCodec.decodeAction(id: id, text: NoteCodec.encode(action))
        #expect(reread.followUpDate == nil)
        #expect(reread.status == .waiting)
    }

    /// #86 (user decision) — a Someday note keeps its tier and its `defer:`: it reads as
    /// written, an edit changes only the edited line, and the defer date survives the round trip.
    @Test func aDeferredSomedayFileKeepsItsTierAndDate() throws {
        let id = NoteID(path: "Actions/Irgendwann.md")
        let text = "---\nstatus: someday\ncontexts: [mac]\ndefer: 2026-10-10\n---\n# What?\ny\n"
        var action = try NoteCodec.decodeAction(id: id, text: text)
        #expect(action.status == .someday)
        #expect(action.deferDate == Day(year: 2026, month: 10, day: 10))
        #expect(action.followUpDate == nil)
        #expect(NoteCodec.encode(action) == text)
        action.contexts = ["home"]
        let encoded = NoteCodec.encode(action)
        #expect(encoded == text.replacingOccurrences(of: "contexts: [mac]", with: "contexts: [home]"))
        let reread = try NoteCodec.decodeAction(id: id, text: encoded)
        #expect(reread.status == .someday)
        #expect(reread.deferDate == Day(year: 2026, month: 10, day: 10))
    }

    /// Closed notes keep their `defer:` as written: they are on no list, nothing is folded.
    @Test func aClosedNoteKeepsItsDeferDate() throws {
        let id = NoteID(path: "Actions/Erledigt.md")
        let text = "---\nstatus: done\ndefer: 2026-10-10\n---\n# What?\ny\n"
        let action = try NoteCodec.decodeAction(id: id, text: text)
        #expect(action.status == .done)
        #expect(action.deferDate == Day(year: 2026, month: 10, day: 10))
        #expect(NoteCodec.encode(action) == text)
    }

    // MARK: - Routines

    @Test func changingARoutineTimeLeavesTheStepsAlone() throws {
        let path = "GTD/Routines/Morning.md"
        let text = try #require(SampleVault.files[path])
        var routine = try NoteCodec.decodeRoutine(id: NoteID(path: path), text: text)
        routine.time = DayTime(hour: 6, minute: 45)
        #expect(NoteCodec.encode(routine)
            == text.replacingOccurrences(of: "time: \"07:00\"", with: "time: \"06:45\""))
    }

    @Test func settingARoutineDayAddsOneLineAfterTheTime() throws {
        let path = "GTD/Routines/Morning.md"
        let text = try #require(SampleVault.files[path])
        var routine = try NoteCodec.decodeRoutine(id: NoteID(path: path), text: text)
        routine.day = .sunday
        #expect(NoteCodec.encode(routine)
            == text.replacingOccurrences(of: "time: \"07:00\"\n", with: "time: \"07:00\"\nday: Sunday\n"))
    }

    @Test func changingARoutineTimeKeepsItsDay() throws {
        let path = "GTD/Routines/Weekly.md"
        let text = "---\ntime: 9:00\nday: Sunday\n---\n- [ ] Pick a topic\n"
        var routine = try NoteCodec.decodeRoutine(id: NoteID(path: path), text: text)
        routine.time = DayTime(hour: 10, minute: 30)
        #expect(NoteCodec.encode(routine)
            == "---\ntime: \"10:30\"\nday: Sunday\n---\n- [ ] Pick a topic\n")
    }

    @Test func clearingARoutineDayRemovesTheLine() throws {
        let path = "GTD/Routines/Weekly.md"
        let text = "---\ntime: 9:00\nday: Sunday\n---\n- [ ] Pick a topic\n"
        var routine = try NoteCodec.decodeRoutine(id: NoteID(path: path), text: text)
        routine.day = nil
        #expect(NoteCodec.encode(routine) == "---\ntime: 9:00\n---\n- [ ] Pick a topic\n")
    }

    // MARK: - Config

    @Test func changingTheCapRewritesOneLine() throws {
        let path = "GTD/Config.md"
        let text = try #require(SampleVault.files[path])
        var config = try NoteCodec.decodeConfig(id: NoteID(path: path), text: text)
        config.nextCap = 12
        #expect(NoteCodec.encode(config)
            == text.replacingOccurrences(of: "nextCap: 15", with: "nextCap: 12"))
    }
}
