import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// The other half of the round-trip rule: whatever the app writes must read back unchanged.
///
/// `RoundTripTests` proves the codec does not *damage* a file it leaves alone. These tests prove
/// it does not *lose* a value it writes — the failure mode that would silently drop a user's
/// edit on the next scan.
struct FidelityTests {

    private let zone = vaultTimeZone
    private let id = NoteID(path: "Actions/Fidelity.md")

    private func reread(_ action: Action) throws -> Action {
        try NoteCodec.decodeAction(
            id: action.id, text: NoteCodec.encode(action, timeZone: zone), timeZone: zone)
    }

    /// Values chosen to break naive YAML quoting.
    static let awkwardStrings = [
        "plain",
        "with: a colon",
        "trailing colon:",
        "#starts with a hash",
        "- starts with a dash",
        "  leading and trailing spaces  ",
        "quotes \" and ' and \\ backslash",
        "[brackets] {braces} , comma",
        "true",
        "no",
        "null",
        "42",
        "3.14",
        "2026-09-19",
        "07:00",
        "Jürgen Müller — Frühstück 🍞 日本語",
        "a # b",
        "@at and `backtick` and *star*",
        "|pipe >gt &amp *alias !bang %percent",
        "",
    ]

    @Test(arguments: awkwardStrings)
    func waitingForSurvivesEncoding(_ value: String) throws {
        var action = Action(id: id, title: "Fidelity", status: .waiting)
        action.waitingFor = value
        action.followUpDate = Day(year: 2026, month: 9, day: 30)
        let back = try reread(action)
        #expect(back.waitingFor == (value.isEmpty ? nil : value))
        #expect(back.followUpDate == action.followUpDate)
    }

    @Test(arguments: awkwardStrings)
    func reviewReasonSurvivesEncoding(_ value: String) throws {
        var action = Action(id: id, title: "Fidelity", status: .next)
        action.reviewReason = value
        #expect(try reread(action).reviewReason == (value.isEmpty ? nil : value))
    }

    @Test(arguments: awkwardStrings)
    func inboxTextSurvivesEncoding(_ value: String) throws {
        let item = InboxItem(
            id: NoteID(path: "Inbox/x.md"), body: value, created: Date(timeIntervalSince1970: 1_790_000_000))
        let encoded = NoteCodec.encode(item, timeZone: zone)
        let back = try NoteCodec.decodeInboxItem(id: item.id, text: encoded, timeZone: zone)
        #expect(back.body == value)
        #expect(back.created == item.created)
    }

    @Test(arguments: awkwardStrings)
    func contextValuesSurviveEncoding(_ value: String) throws {
        guard !value.isEmpty, !value.contains("\n") else { return }
        var action = Action(id: id, title: "Fidelity", status: .next)
        action.contexts = ["mac", value]
        #expect(try reread(action).contexts == ["mac", value])
    }

    @Test(arguments: awkwardStrings)
    func bodyTextSurvivesEncoding(_ value: String) throws {
        var action = Action(id: id, title: "Fidelity", status: .next)
        action.why = value
        action.what = "- [ ] \(value)"
        let back = try reread(action)
        #expect(back.why == value)
        #expect(back.checkboxes.first?.text == value.trimmingCharacters(in: .whitespaces))
    }

    @Test func allActionFieldsSurviveEncoding() throws {
        var action = Action(id: id, title: "Fidelity", status: .inProgress)
        action.contexts = ["mac", "deep-work"]
        action.timeEstimate = 90
        action.project = NoteID(path: "Projects/A B/A B.md")
        action.due = Day(year: 2027, month: 12, day: 31)
        action.waitingFor = "Prof. Weber"
        action.followUpDate = Day(year: 2026, month: 2, day: 3)
        action.created = YAMLScalar.parseTimestamp("2026-09-07T09:30:00+02:00", defaultTimeZone: zone)
        action.completedDate = YAMLScalar.parseTimestamp("2026-09-08T23:59:59+02:00", defaultTimeZone: zone)
        action.reviewReason = "Because: reasons"
        action.why = "Line one\n\nLine three"
        action.what = "- [x] Done\n- [ ] Open\n\nSome prose after."

        let back = try reread(action)
        #expect(back.status == action.status)
        #expect(back.contexts == action.contexts)
        #expect(back.timeEstimate == action.timeEstimate)
        #expect(back.project == action.project)
        #expect(back.due == action.due)
        #expect(back.waitingFor == action.waitingFor)
        #expect(back.followUpDate == action.followUpDate)
        #expect(back.created == action.created)
        #expect(back.completedDate == action.completedDate)
        #expect(back.reviewReason == action.reviewReason)
        #expect(back.why == action.why)
        #expect(back.what == action.what)
    }

    @Test func allProjectFieldsSurviveEncoding() throws {
        var project = Project(id: NoteID(path: "Projects/P/P.md"), title: "P", status: .someday)
        project.area = NoteID(path: "Projects/Applications/Applications.md")
        project.outcome = "An outcome: with a colon"
        project.why = "Multi\nline\nwhy"
        project.steps = [
            ProjectStep(text: "First step", done: true),
            ProjectStep(text: "Promoted step", promotedTo: NoteID(path: "Actions/Promoted step.md")),
            ProjectStep(text: "Step with → an arrow but no link"),
        ]
        project.log = [
            LogEntry(day: Day(year: 2026, month: 9, day: 8), text: "Did a thing"),
            LogEntry(day: Day(year: 2026, month: 9, day: 9), text: "Did: another — thing"),
        ]
        let back = try NoteCodec.decodeProject(id: project.id, text: NoteCodec.encode(project))
        #expect(back.status == project.status)
        #expect(back.area == project.area)
        #expect(back.outcome == project.outcome)
        #expect(back.why == project.why)
        #expect(back.steps == project.steps)
        #expect(back.log == project.log)
    }

    @Test func allRoutineFieldsSurviveEncoding() throws {
        let routine = Routine(
            id: NoteID(path: "GTD/Routines/R.md"), title: "R",
            time: DayTime(hour: 0, minute: 5),
            day: .sunday,
            steps: [
                RoutineStep(id: RoutineStep.slug("Frühstück"), title: "Frühstück",
                            substeps: ["Brainsmoothie", "Brötchen"]),
                RoutineStep(id: RoutineStep.slug("Get things done"), title: "Get things done"),
            ])
        let back = try NoteCodec.decodeRoutine(id: routine.id, text: NoteCodec.encode(routine))
        #expect(back.time == routine.time)
        #expect(back.day == routine.day)
        #expect(back.steps == routine.steps)
    }

    @Test func routineLogEntriesSurviveEncoding() throws {
        let day = Day(year: 2026, month: 9, day: 19)
        let id = NoteID(path: "GTD/RoutineLog/2026-09-19--Mac mini.md")
        let entries = (0..<5).map { index in
            RoutineLogEntry(
                day: day, routine: "Morning: früh", step: "step-\(index)",
                result: index.isMultiple(of: 2) ? .done : .skipped,
                at: Date(timeIntervalSince1970: 1_790_000_000 + Double(index) * 60),
                device: "Mac mini")
        }
        let text = NoteCodec.encodeRoutineLog(entries, timeZone: zone)
        let back = try NoteCodec.decodeRoutineLog(id: id, text: text, timeZone: zone)
        #expect(back == entries)
    }

    @Test func weeklyReviewFieldsSurviveEncoding() throws {
        let review = WeeklyReview(
            year: 2026, week: 5,
            wantedToAchieve: "A: one",
            achieved: "B\n\nstill B",
            behaviorToChange: "C",
            whatToStop: "D",
            howIGrew: "E",
            howToGrowFurther: "F",
            whatToTry: "G",
            goalForNextWeek: "H",
            systemFixNotes: ["First note", "Second — note"],
            savedAt: YAMLScalar.parseTimestamp("2026-02-01T12:00:00+02:00", defaultTimeZone: zone))
        let text = NoteCodec.encode(review, timeZone: zone)
        let back = try NoteCodec.decodeWeeklyReview(id: review.noteID(), text: text, timeZone: zone)
        #expect(back.year == review.year)
        #expect(back.week == review.week)
        #expect(back.wantedToAchieve == review.wantedToAchieve)
        #expect(back.achieved == review.achieved)
        #expect(back.goalForNextWeek == review.goalForNextWeek)
        #expect(back.systemFixNotes == review.systemFixNotes)
        #expect(back.savedAt == review.savedAt)
    }

    @Test func configFieldsSurviveEncoding() throws {
        var config = GTDConfig.default
        config.contexts = ["mac", "no", "true", "deep-work"]
        config.onTheGoContexts = ["no"]
        config.nextCap = 7
        config.layout.inbox = "Eingang"
        let text = NoteCodec.encode(config)
        let back = try NoteCodec.decodeConfig(id: NoteID(path: config.layout.configFile), text: text)
        #expect(back.contexts == config.contexts)
        #expect(back.onTheGoContexts == config.onTheGoContexts)
        #expect(back.nextCap == config.nextCap)
        #expect(back.layout == config.layout)
    }

    // MARK: - Editing a real vault file

    /// Every sample-vault action, edited in every field the app can edit, still reads back
    /// exactly as edited — and the file stays parseable.
    @Test func editingEverySampleActionIsLossless() throws {
        for (path, text) in SampleVault.files where NoteID(path: path).isInside("Actions") {
            let noteID = NoteID(path: path)
            var action = try NoteCodec.decodeAction(id: noteID, text: text, timeZone: zone)
            action.status = .waiting
            action.contexts = ["calls", "campus"]
            action.timeEstimate = 45
            action.project = NoteID(path: "Projects/Wohnungssuche/Wohnungssuche.md")
            action.due = Day(year: 2026, month: 11, day: 5)
            action.waitingFor = "Someone: with a colon"
            action.followUpDate = Day(year: 2026, month: 11, day: 8)
            action.reviewReason = "changed"
            action.why = "New why."
            action.what = "- [x] New what"

            let back = try NoteCodec.decodeAction(
                id: noteID, text: NoteCodec.encode(action, timeZone: zone), timeZone: zone)
            #expect(back.status == .waiting, "\(path)")
            #expect(back.contexts == ["calls", "campus"], "\(path)")
            #expect(back.timeEstimate == 45, "\(path)")
            #expect(back.project == action.project, "\(path)")
            #expect(back.due == action.due, "\(path)")
            #expect(back.waitingFor == action.waitingFor, "\(path)")
            #expect(back.followUpDate == action.followUpDate, "\(path)")
            #expect(back.reviewReason == "changed", "\(path)")
            #expect(back.why == "New why.", "\(path)")
            #expect(back.what == "- [x] New what", "\(path)")
            #expect(back.created == action.created, "\(path)")
            #expect(back.completedDate == action.completedDate, "\(path)")
        }
    }
}
