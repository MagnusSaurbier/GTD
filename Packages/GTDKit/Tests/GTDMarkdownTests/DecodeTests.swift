import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// What the decoders read out of a file, and what they refuse to guess about.
struct DecodeTests {

    private let actionID = NoteID(path: "Actions/Write DAAD motivation letter.md")

    // MARK: - Action fields

    @Test func decodesEveryActionField() throws {
        let text = """
        ---
        status: waiting
        contexts: [mac, deep-work]
        timeEstimate: 30
        project: "[[Projects/Applications/DAAD/DAAD]]"
        defer: 2026-09-20
        due: 2026-09-24
        waitingFor: "Prof. Weber"
        followUpDate: 2026-09-30
        created: 2026-09-07T09:30:00+02:00
        completedDate: 2026-09-08T10:00:00+02:00
        reviewReason: "Needs thinking"
        ---
        # Why?
        Because.

        # What?
        - [ ] One
        - [x] Two
        """
        let action = try NoteCodec.decodeAction(id: actionID, text: text, timeZone: vaultTimeZone)
        #expect(action.title == "Write DAAD motivation letter")
        #expect(action.status == .waiting)
        #expect(action.contexts == ["mac", "deep-work"])
        #expect(action.timeEstimate == 30)
        #expect(action.project == NoteID(path: "Projects/Applications/DAAD/DAAD.md"))
        #expect(action.deferDate == Day(year: 2026, month: 9, day: 20))
        #expect(action.due == Day(year: 2026, month: 9, day: 24))
        #expect(action.waitingFor == "Prof. Weber")
        #expect(action.followUpDate == Day(year: 2026, month: 9, day: 30))
        #expect(action.reviewReason == "Needs thinking")
        #expect(action.why == "Because.")
        #expect(action.what == "- [ ] One\n- [x] Two")
        #expect(action.checkboxes == [Checkbox(text: "One"), Checkbox(text: "Two", done: true)])
        #expect(action.waiting == WaitingInfo(who: "Prof. Weber", followUp: Day(year: 2026, month: 9, day: 30)))
        #expect(action.modified == nil)      // filled in by GTDVault, never by the codec
    }

    @Test func headingMatchingIsCaseAndPunctuationInsensitive() throws {
        let text = "---\nstatus: next\n---\n# why\nBecause.\n\n# WHAT ?\nDo it.\n"
        let action = try NoteCodec.decodeAction(id: actionID, text: text)
        #expect(action.why == "Because.")
        #expect(action.what == "Do it.")
    }

    @Test func aNoteWithoutKnownHeadingsIsAllWhat() throws {
        let text = "---\nstatus: next\n---\nCall the office about the certificate.\n"
        let action = try NoteCodec.decodeAction(id: actionID, text: text)
        #expect(action.why == "")
        #expect(action.what == "Call the office about the certificate.")
    }

    // MARK: - Tolerance and refusals

    @Test func legacyStatusIsRefusedWithPathAndReason() throws {
        let text = "---\nstatus: to-do\n---\n"
        #expect {
            _ = try NoteCodec.decodeAction(id: actionID, text: text)
        } throws: { error in
            guard case let NoteCodecError.unreadable(path, reason) = error else { return false }
            return path == actionID.path && reason.contains("to-do") && reason.contains("next")
        }
    }

    @Test func missingStatusIsRefused() throws {
        #expect {
            _ = try NoteCodec.decodeAction(id: actionID, text: "---\ncontexts: [mac]\n---\n")
        } throws: { error in
            guard case let NoteCodecError.unreadable(_, reason) = error else { return false }
            return reason.contains("status")
        }
    }

    @Test func brokenYamlIsRefusedRatherThanCrashing() throws {
        let text = "---\nstatus: next\ncontexts: [mac\n---\n"
        #expect(throws: NoteCodecError.self) {
            _ = try NoteCodec.decodeAction(id: actionID, text: text)
        }
    }

    @Test func aVaultIssueCarriesThePathAndTheReason() throws {
        let error = NoteCodecError.unreadable(path: "Actions/X.md", reason: "Missing `status`")
        #expect(error.vaultIssue == VaultIssue(path: "Actions/X.md", message: "Missing `status`"))
    }

    @Test func legacyTimeEstimateZeroReadsAsUndecided() throws {
        let action = try NoteCodec.decodeAction(
            id: actionID, text: "---\nstatus: next\ntimeEstimate: 0\n---\n")
        #expect(action.timeEstimate == nil)
        #expect(action.timeBucket == nil)
    }

    @Test func emptyAndMissingKeysAreUndecidedNotDefaults() throws {
        let text = "---\nstatus: next\ntimeEstimate:\nproject: \"\"\ncontexts: []\ndue:\n---\n"
        let action = try NoteCodec.decodeAction(id: actionID, text: text)
        #expect(action.timeEstimate == nil)
        #expect(action.project == nil)
        #expect(action.contexts == [])
        #expect(action.due == nil)
        #expect(action.created == nil)
    }

    @Test func contextsAcceptBlockSequencesAndBareScalars() throws {
        let block = try NoteCodec.decodeAction(
            id: actionID, text: "---\nstatus: next\ncontexts:\n  - mac\n  - Bike\n---\n")
        #expect(block.contexts == ["mac", "Bike"])
        let scalar = try NoteCodec.decodeAction(
            id: actionID, text: "---\nstatus: next\ncontexts: phone\n---\n")
        #expect(scalar.contexts == ["phone"])
    }

    @Test func unknownContextsAreReportedNotRefused() throws {
        let action = try NoteCodec.decodeAction(
            id: actionID, text: "---\nstatus: next\ncontexts: [mac, Bike, 10min]\n---\n")
        #expect(action.contexts == ["mac", "Bike", "10min"])
        #expect(NoteCodec.unknownContexts(in: action, known: GTDConfig.default.contexts)
            == ["Bike", "10min"])
        #expect(NoteCodec.unknownContexts(in: action, known: ["MAC", "bike", "10min"]) == [])
    }

    // MARK: - Dates

    @Test(arguments: [
        ("2026-09-13T23:20:17.632+02:00", 2026, 9, 13, 23, 20, 17),
        ("2026-09-13T23:20:17+02:00", 2026, 9, 13, 23, 20, 17),
        ("2026-09-13T23:20+02:00", 2026, 9, 13, 23, 20, 0),
        ("2026-09-13 23:20:17+02:00", 2026, 9, 13, 23, 20, 17),
        ("2026-09-13T23:20:17+0200", 2026, 9, 13, 23, 20, 17),
        ("2026-09-13T23:20:17", 2026, 9, 13, 23, 20, 17),
        ("2026-09-13", 2026, 9, 13, 0, 0, 0),
    ])
    func parsesTheTimestampShapesTheVaultContains(
        _ testCase: (text: String, y: Int, mo: Int, d: Int, h: Int, mi: Int, s: Int)
    ) throws {
        let date = try #require(
            YAMLScalar.parseTimestamp(testCase.text, defaultTimeZone: vaultTimeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = vaultTimeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(c.year == testCase.y && c.month == testCase.mo && c.day == testCase.d)
        #expect(c.hour == testCase.h && c.minute == testCase.mi && c.second == testCase.s)
    }

    @Test func zuluTimestampsAreRead() throws {
        let date = try #require(YAMLScalar.parseTimestamp("2026-09-14T08:00:00Z", defaultTimeZone: vaultTimeZone))
        #expect(YAMLScalar.timestamp(date, timeZone: vaultTimeZone) == "2026-09-14T10:00:00+02:00")
    }

    @Test(arguments: ["", "not a date", "2026-13", "2026-09-13T25", "2026-09-13Tx", "13.09.2026"])
    func rejectsNonTimestamps(_ text: String) {
        #expect(YAMLScalar.parseTimestamp(text, defaultTimeZone: vaultTimeZone) == nil)
    }

    @Test func negativeOffsetsRoundTrip() throws {
        let zone = TimeZone(secondsFromGMT: -5 * 3600 - 30 * 60)!
        let date = try #require(YAMLScalar.parseTimestamp("2026-09-13T23:20:17-05:30", defaultTimeZone: .gmt))
        #expect(YAMLScalar.timestamp(date, timeZone: zone) == "2026-09-13T23:20:17-05:30")
    }

    // MARK: - Wikilinks

    @Test func parsesWikilinkShapes() {
        #expect(Wikilink.parse("[[Projects/A/A]]")?.noteID == NoteID(path: "Projects/A/A.md"))
        #expect(Wikilink.parse("[[Projects/A/A|Alias]]")?.alias == "Alias")
        #expect(Wikilink.parse("[[Projects/A/A#Heading]]")?.heading == "Heading")
        #expect(Wikilink.parse("[[Projects/A/A.md]]")?.noteID == NoteID(path: "Projects/A/A.md"))
        #expect(Wikilink.parse("[[DAAD]]")?.isBare == true)
        #expect(Wikilink.parse("[[Projects/A/A]]")?.isBare == false)
        #expect(Wikilink.parse("- [ ] Step → [[Actions/Step]]")?.noteID == NoteID(path: "Actions/Step.md"))
        #expect(Wikilink.parse("no link here") == nil)
        #expect(Wikilink.parse("[[]]") == nil)
    }

    @Test func rendersWikilinksWithoutTheExtension() {
        #expect(Wikilink.render(NoteID(path: "Projects/A/A.md")) == "[[Projects/A/A]]")
        #expect(Wikilink.render(NoteID(path: "Projects/A/A.md"), alias: "A") == "[[Projects/A/A|A]]")
        #expect(Wikilink.frontmatterValue(NoteID(path: "Projects/A/A.md")) == "\"[[Projects/A/A]]\"")
    }

    @Test func aPlainPathInFrontmatterIsAcceptedToo() throws {
        let action = try NoteCodec.decodeAction(
            id: actionID, text: "---\nstatus: next\nproject: Projects/A/A\n---\n")
        #expect(action.project == NoteID(path: "Projects/A/A.md"))
    }

    // MARK: - Checkboxes

    @Test func parsesCheckboxVariants() {
        #expect(CheckboxList.parseLine("- [ ] a")?.done == false)
        #expect(CheckboxList.parseLine("- [x] a")?.done == true)
        #expect(CheckboxList.parseLine("- [X] a")?.done == true)
        #expect(CheckboxList.parseLine("* [ ] a")?.marker == "*")
        #expect(CheckboxList.parseLine("\t- [ ] a")?.indent == "\t")
        #expect(CheckboxList.parseLine("    - [ ]   spaced  ")?.text == "spaced")
        // Not checkboxes:
        #expect(CheckboxList.parseLine("-[ ] a") == nil)
        #expect(CheckboxList.parseLine("+ [ ] a") == nil)       // matches GTDModel.Checkbox.scan
        #expect(CheckboxList.parseLine("- [-] a") == nil)       // a custom Obsidian state
        #expect(CheckboxList.parseLine("- plain bullet") == nil)
        #expect(CheckboxList.parseLine("# [ ] heading") == nil)
    }

    @Test func nestingComesFromVisualIndent() {
        let lines = RawText.split("- [ ] a\n\t- [ ] b\n        - [ ] c\n  - [ ] d\n- [ ] e\n")
        #expect(CheckboxList.parse(lines).map(\.depth) == [0, 1, 2, 1, 0])
    }

    @Test func readsThePromotionSuffix() {
        let item = CheckboxList.parseLine("- [x] Collect transcripts → [[Actions/Collect DAAD transcripts]]")
        #expect(item?.text == "Collect transcripts")
        #expect(item?.promotedTo == NoteID(path: "Actions/Collect DAAD transcripts.md"))
        #expect(CheckboxList.parseLine("- [ ] Step -> [[Actions/Step]]")?.promotedTo
            == NoteID(path: "Actions/Step.md"))
        // An arrow that is not followed by a link is part of the text.
        #expect(CheckboxList.parseLine("- [ ] A → B")?.text == "A → B")
    }

    // MARK: - Routine log

    @Test func decodesARoutineLogFile() throws {
        let path = "GTD/RoutineLog/2026-09-10--iPhone.md"
        let text = try #require(SampleVault.files[path])
        let entries = try NoteCodec.decodeRoutineLog(
            id: NoteID(path: path), text: text, timeZone: vaultTimeZone)
        #expect(entries.count == 8)
        #expect(entries[0].day == Day(year: 2026, month: 9, day: 10))
        #expect(entries[0].device == "iPhone")
        #expect(entries[0].routine == "Morning")
        #expect(entries[0].step == "wake-up")
        #expect(entries.contains { $0.result == .skipped })
    }

    @Test func refusesABadRoutineLogFileName() {
        #expect(throws: NoteCodecError.self) {
            _ = try NoteCodec.decodeRoutineLog(id: NoteID(path: "GTD/RoutineLog/nonsense.md"), text: "---\n---\n")
        }
    }

    @Test func refusesAnUnknownRoutineStepResult() {
        let text = "---\nentries:\n  - routine: \"M\"\n    step: \"s\"\n    result: maybe\n    at: 2026-09-10T07:05:00+02:00\n---\n"
        #expect(throws: NoteCodecError.self) {
            _ = try NoteCodec.decodeRoutineLog(id: NoteID(path: "GTD/RoutineLog/2026-09-10--iPhone.md"), text: text)
        }
    }

    @Test func anEmptyRoutineLogIsNotAnError() throws {
        for text in ["---\n---\n", NoteCodec.encodeRoutineLog([])] {
            let entries = try NoteCodec.decodeRoutineLog(
                id: NoteID(path: "GTD/RoutineLog/2026-09-10--iPhone.md"), text: text)
            #expect(entries.isEmpty, "\(text) is a legitimately empty log")
        }
    }

    /// T41: a damaged `entries:` used to decode as "no entries", and `encodeRoutineLog`
    /// regenerates the file — so the next step logged that day would have overwritten the
    /// user's history with an empty log. It must be refused, and become a `VaultIssue`.
    @Test func aDamagedEntriesKeyIsRefusedRatherThanReadAsAnEmptyLog() {
        for value in ["nonsense", "\"[]\"", "\n  routine: M\n  step: s"] {
            #expect(throws: NoteCodecError.self, "entries: \(value)") {
                _ = try NoteCodec.decodeRoutineLog(
                    id: NoteID(path: "GTD/RoutineLog/2026-09-10--iPhone.md"),
                    text: "---\nentries: \(value)\n---\n")
            }
        }
    }

    // MARK: - Config, area, review

    @Test func configFallsBackToTheAppDefaults() throws {
        let config = try NoteCodec.decodeConfig(id: NoteID(path: "GTD/Config.md"), text: "---\n---\n")
        #expect(config.contexts == GTDConfig.default.contexts)
        #expect(config.onTheGoContexts == GTDConfig.default.onTheGoContexts)
        #expect(config.nextCap == 15)
        #expect(config.layout == .default)
    }

    @Test func configCanOverrideTheLayout() throws {
        let text = "---\nnextCap: 20\nlayout:\n  inbox: Eingang\n  actions: Aktionen\n---\n"
        let config = try NoteCodec.decodeConfig(id: NoteID(path: "GTD/Config.md"), text: text)
        #expect(config.layout.inbox == "Eingang")
        #expect(config.layout.actions == "Aktionen")
        #expect(config.layout.projects == VaultLayout.default.projects)
        #expect(NoteCodec.encode(config) == text)
    }

    @Test func areaTitleComesFromTheHeadingThenTheFileName() throws {
        let withHeading = try NoteCodec.decodeArea(
            id: NoteID(path: "Projects/Applications/Applications.md"), text: "---\nkind: area\n---\n# Bewerbungen\n")
        #expect(withHeading.title == "Bewerbungen")
        let withoutHeading = try NoteCodec.decodeArea(
            id: NoteID(path: "Projects/Applications/Applications.md"), text: "---\nkind: area\n---\n")
        #expect(withoutHeading.title == "Applications")
    }

    @Test func reviewNumbersFallBackToThePath() throws {
        let review = try NoteCodec.decodeWeeklyReview(
            id: NoteID(path: "GTD/Reviews/2026/KW 37.md"), text: "---\nkind: review\n---\n")
        #expect(review.year == 2026)
        #expect(review.week == 37)
    }

    @Test func noteKindDispatches() {
        #expect(NoteCodec.noteKind(text: "---\nkind: project\n---\n") == "project")
        #expect(NoteCodec.noteKind(text: "---\nkind: area\n---\n") == "area")
        #expect(NoteCodec.noteKind(text: "no frontmatter") == nil)
    }

    // MARK: - The whole sample vault decodes

    @Test func everySampleVaultFileDecodesWithoutAnIssue() throws {
        for (path, text) in SampleVault.files {
            #expect(throws: Never.self, "\(path)") {
                _ = try RoundTrip.encodeDecoded(path: path, text: text)
            }
        }
    }
}
