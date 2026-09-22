import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// Entities the app just created carry an empty `NotePassthrough`, so the encoders render them
/// from `NoteTemplates`. The result must be the format ARCHITECTURE §3 describes — and it must
/// decode back into the same entity.
struct EncodeFromScratchTests {

    private let zone = vaultTimeZone

    @Test func aNewActionIsWrittenInSchemaOrder() throws {
        let action = Action(
            id: NoteID(path: "Actions/Call the office.md"),
            title: "Call the office",
            status: .next,
            contexts: ["phone", "campus"],
            timeEstimate: 10,
            project: NoteID(path: "Projects/Applications/DAAD/DAAD.md"),
            due: Day(year: 2026, month: 9, day: 24),
            created: YAMLScalar.parseTimestamp("2026-09-19T08:12:00+02:00", defaultTimeZone: zone),
            why: "They only answer before noon.",
            what: "- [ ] Ask for the certificate")
        #expect(NoteCodec.encode(action, timeZone: zone) == """
        ---
        status: next
        contexts: [phone, campus]
        timeEstimate: 10
        project: "[[Projects/Applications/DAAD/DAAD]]"
        due: 2026-09-24
        created: 2026-09-19T08:12:00+02:00
        ---
        # Why?
        They only answer before noon.

        # What?
        - [ ] Ask for the certificate

        """)
    }

    @Test func aNewActionWithNothingDecidedHasNoLyingDefaults() throws {
        let action = Action(id: NoteID(path: "Actions/X.md"), title: "X", status: .someday)
        let text = NoteCodec.encode(action, timeZone: zone)
        #expect(text == "---\nstatus: someday\n---\n# Why?\n\n# What?\n")
        #expect(!text.contains("timeEstimate"))
        #expect(!text.contains("contexts"))
        #expect(!text.contains("project"))
    }

    @Test func aNewInboxItem() throws {
        let created = try #require(YAMLScalar.parseTimestamp("2026-09-19T08:12:04+02:00", defaultTimeZone: zone))
        let item = InboxItem(
            id: NoteID(path: "Inbox/2026-09-19 081204.md"),
            body: "buy new running shoes",
            created: created)
        #expect(NoteCodec.encode(item, timeZone: zone)
            == "---\ncreated: 2026-09-19T08:12:04+02:00\n---\nbuy new running shoes\n")
    }

    @Test func aNewArea() throws {
        let area = Area(id: NoteID(path: "Projects/Wohnen/Wohnen.md"), title: "Wohnen")
        #expect(NoteCodec.encode(area) == "---\nkind: area\n---\n# Wohnen\n")
    }

    @Test func aNewProject() throws {
        let project = Project(
            id: NoteID(path: "Projects/Wohnungssuche/Wohnungssuche.md"),
            title: "Wohnungssuche",
            status: .active,
            outcome: "Signed contract for a room from April.",
            why: "The sublet ends in March.",
            steps: [ProjectStep(text: "Write a tenant profile"), ProjectStep(text: "Set up search alerts")],
            log: [])
        #expect(NoteCodec.encode(project) == """
        ---
        kind: project
        status: active
        ---
        # Outcome
        Signed contract for a room from April.

        # Why?
        The sublet ends in March.

        # Steps
        - [ ] Write a tenant profile
        - [ ] Set up search alerts

        # Log

        """)
    }

    @Test func aNewRoutine() throws {
        let routine = Routine(
            id: NoteID(path: "GTD/Routines/Bedtime.md"),
            title: "Bedtime",
            time: DayTime(hour: 22, minute: 30),
            steps: [
                RoutineStep(id: "tidy-desk", title: "Tidy desk"),
                RoutineStep(id: "dream-journal", title: "Dream journal", substeps: ["Three lines"]),
            ])
        #expect(NoteCodec.encode(routine) == """
        ---
        time: "22:30"
        ---
        - [ ] Tidy desk
        - [ ] Dream journal
            - [ ] Three lines

        """)
    }

    @Test func aNewRoutineLog() throws {
        let at = try #require(YAMLScalar.parseTimestamp("2026-09-19T07:05:00+02:00", defaultTimeZone: zone))
        let entries = [
            RoutineLogEntry(day: Day(year: 2026, month: 9, day: 19), routine: "Morning",
                            step: "wake-up", result: .done, at: at, device: "iPhone"),
            RoutineLogEntry(day: Day(year: 2026, month: 9, day: 19), routine: "Morning",
                            step: "cold-shower", result: .skipped, at: at.addingTimeInterval(120),
                            device: "iPhone"),
        ]
        #expect(NoteCodec.encodeRoutineLog(entries, timeZone: zone) == """
        ---
        entries:
          - routine: "Morning"
            step: "wake-up"
            result: done
            at: 2026-09-19T07:05:00+02:00
          - routine: "Morning"
            step: "cold-shower"
            result: skipped
            at: 2026-09-19T07:07:00+02:00
        ---

        """)
    }

    @Test func aNewWeeklyReview() throws {
        let review = WeeklyReview(
            year: 2026, week: 38,
            wantedToAchieve: "Finish the letter.",
            achieved: "Half of it.",
            systemFixNotes: ["Decisions need their own place."])
        let text = NoteCodec.encode(review, timeZone: zone)
        #expect(text.hasPrefix("---\nkind: review\nyear: 2026\nweek: 38\n---\n"))
        #expect(text.contains("# What did I want to achieve?\nFinish the letter.\n"))
        #expect(text.contains("# Goal for next week\n\n"))
        #expect(text.hasSuffix("# System fixes\n- Decisions need their own place.\n"))
        // …and it decodes back into the same review.
        let decoded = try NoteCodec.decodeWeeklyReview(
            id: review.noteID(), text: text, timeZone: zone)
        #expect(decoded.wantedToAchieve == review.wantedToAchieve)
        #expect(decoded.systemFixNotes == review.systemFixNotes)
        #expect(decoded.week == 38)
    }

    @Test func aNewConfig() throws {
        let text = NoteCodec.encode(GTDConfig.default)
        #expect(text == """
        ---
        contexts: [mac, phone, home, campus, errands, calls, deep-work]
        onTheGoContexts: [phone, errands, calls]
        nextCap: 15
        ---
        # Config
        Settings synced through the vault. Edited by the app.

        """)
    }

    // MARK: - Parity with the fixtures' own renderer

    /// `GTDFixtures.SampleVault` renders the sample vault with a hand-written writer that is
    /// deliberately independent of the codec. Encoding the same entities from scratch must give
    /// the same bytes — otherwise the committed sample vault and the app's writes have drifted.
    @Test func encodingTheFixtureSnapshotMatchesTheCommittedSampleVault() throws {
        let snapshot = Fixtures.sampleSnapshot
        let files = SampleVault.files

        for action in snapshot.actions {
            let expected = try #require(files[action.id.path], "\(action.id.path)")
            let encoded = NoteCodec.encode(action, timeZone: zone)
            if action.why.isEmpty || action.what.isEmpty {
                // The fixtures' renderer concatenates blindly and leaves a redundant blank line
                // under an empty section; the codec does not. Compare once the extra blank is
                // collapsed — everything else must still match byte for byte.
                #expect(encoded == expected.replacingOccurrences(of: "\n\n\n", with: "\n\n"),
                        "\(action.id.path) — \(firstDifference(expected, encoded))")
            } else {
                #expect(encoded == expected, "\(action.id.path) — \(firstDifference(expected, encoded))")
            }
        }
        for project in snapshot.projects {
            let expected = try #require(files[project.id.path], "\(project.id.path)")
            #expect(NoteCodec.encode(project) == expected,
                    "\(project.id.path) — \(firstDifference(expected, NoteCodec.encode(project)))")
        }
        for area in snapshot.areas {
            let expected = try #require(files[area.id.path], "\(area.id.path)")
            #expect(NoteCodec.encode(area) == expected, "\(area.id.path)")
        }
        for routine in snapshot.routines {
            let expected = try #require(files[routine.id.path], "\(routine.id.path)")
            #expect(NoteCodec.encode(routine) == expected,
                    "\(routine.id.path) — \(firstDifference(expected, NoteCodec.encode(routine)))")
        }
        for item in snapshot.inbox {
            let expected = try #require(files[item.id.path], "\(item.id.path)")
            #expect(NoteCodec.encode(item, timeZone: zone) == expected, "\(item.id.path)")
        }
        let configPath = snapshot.config.layout.configFile
        #expect(NoteCodec.encode(snapshot.config) == files[configPath])
        if let review = snapshot.lastReview {
            let expected = try #require(files[review.noteID().path])
            #expect(NoteCodec.encode(review, timeZone: zone) == expected,
                    "\(firstDifference(expected, NoteCodec.encode(review, timeZone: zone)))")
        }
    }
}
