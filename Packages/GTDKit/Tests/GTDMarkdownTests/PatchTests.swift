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
        action.status = .backlog
        action.why = "y"
        let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
        #expect(encoded == "---\r\nstatus: backlog\r\ncontexts: [mac]\r\n---\r\n# Why?\r\ny\r\n")
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
        action.what = "Just prose."          // matches what decode would have read
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

    // MARK: - Routines

    @Test func changingARoutineTimeLeavesTheStepsAlone() throws {
        let path = "GTD/Routines/Morning.md"
        let text = try #require(SampleVault.files[path])
        var routine = try NoteCodec.decodeRoutine(id: NoteID(path: path), text: text)
        routine.time = DayTime(hour: 6, minute: 45)
        #expect(NoteCodec.encode(routine)
            == text.replacingOccurrences(of: "time: \"07:00\"", with: "time: \"06:45\""))
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
