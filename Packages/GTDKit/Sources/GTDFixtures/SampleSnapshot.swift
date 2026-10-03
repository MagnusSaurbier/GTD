import Foundation
import GTDModel

/// Deterministic sample data for previews, feature tests and the app's `-useFixtures` mode.
///
/// Everything is anchored on `Fixtures.today` (2026-09-19, a Saturday) so signals, ages and
/// heat maps look the same on every machine and in every screenshot. Never read the real vault.
public enum Fixtures {

    /// The day every fixture date is relative to.
    public static let today = Day(year: 2026, month: 9, day: 19)

    /// Europe/Berlin in September — the user's time zone. Fixed so timestamps round-trip.
    public static let timeZoneOffsetSeconds = 7200

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: timeZoneOffsetSeconds) ?? .gmt
        return calendar
    }

    /// A fixed instant on a fixture day.
    public static func date(_ day: Day, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: timeZoneOffsetSeconds)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// `today` shifted by whole days.
    public static func day(_ offset: Int) -> Day { today.adding(days: offset) }

    public static func reducerEnv(deviceID: String = "fixtures") -> ReducerEnv {
        ReducerEnv(now: date(today, 10, 0), today: today, deviceID: deviceID, calendar: calendar)
    }

    // MARK: - Identity helpers

    private static let layout = VaultLayout.default

    private static func actionID(_ title: String) -> NoteID { layout.actionPath(title: title) }
    private static func areaID(_ title: String) -> NoteID { layout.areaPath(title: title) }
    private static func projectID(_ title: String, area: String?) -> NoteID {
        layout.projectPath(title: title, inArea: area.map(areaID))
    }

    // MARK: - Areas and projects

    public static let applicationsArea = Area(id: areaID("Applications"), title: "Applications")
    public static let careerArea = Area(id: areaID("Karriereplanung"), title: "Karriereplanung")

    public static let daadProject = Project(
        id: projectID("DAAD", area: "Applications"),
        title: "DAAD",
        area: applicationsArea.id,
        status: .active,
        outcome: "DAAD scholarship application submitted and confirmed.",
        why: "Funds the semester abroad without a side job.",
        steps: [
            ProjectStep(text: "Collect transcripts", done: true,
                        promotedTo: actionID("Collect DAAD transcripts")),
            ProjectStep(text: "Write motivation letter", done: false,
                        promotedTo: actionID("Write DAAD motivation letter")),
            ProjectStep(text: "Ask Prof. Weber for a reference"),
            ProjectStep(text: "Submit the online form"),
            ProjectStep(text: "Check the DAAD budget table", done: false,
                        promotedTo: actionID("Check the DAAD budget table")),
        ],
        log: [
            LogEntry(day: day(-11), text: "Collect DAAD transcripts"),
            LogEntry(day: day(-4), text: "Shortlisted three target universities"),
        ])

    public static let erasmusProject = Project(
        id: projectID("Erasmus", area: "Applications"),
        title: "Erasmus",
        area: applicationsArea.id,
        status: .active,
        outcome: "Erasmus place for the summer term accepted.",
        why: "Second option if DAAD falls through.",
        steps: [
            ProjectStep(text: "Compare partner universities", done: false,
                        promotedTo: actionID("Compare Erasmus partner universities")),
            ProjectStep(text: "Check language requirements"),
        ],
        log: [])

    public static let thesisProject = Project(
        id: projectID("Masterarbeit", area: "Karriereplanung"),
        title: "Masterarbeit",
        area: careerArea.id,
        status: .active,
        outcome: "Thesis topic agreed and registered with the examination office.",
        why: "Everything after graduation depends on starting this on time.",
        steps: [
            ProjectStep(text: "Read three candidate papers", done: false,
                        promotedTo: actionID("Read candidate thesis papers")),
            ProjectStep(text: "Draft a one-page exposé"),
            ProjectStep(text: "Book a slot with the chair"),
            ProjectStep(text: "Draft the thesis LaTeX template", done: false,
                        promotedTo: actionID("Draft the thesis LaTeX template")),
        ],
        log: [LogEntry(day: day(-6), text: "Mailed the chair about open topics")])

    /// On hold — its actions must not sit in Next (P3).
    public static let sideJobProject = Project(
        id: projectID("Nebenjob", area: "Karriereplanung"),
        title: "Nebenjob",
        area: careerArea.id,
        status: .onHold,
        outcome: "A 10 h/week working-student job that fits the thesis schedule.",
        why: "Only if the scholarship does not come through.",
        steps: [
            ProjectStep(text: "Update the CV"),
            ProjectStep(text: "Ask around in the chair's Slack"),
        ],
        log: [])

    /// Active with zero open actions ⇒ stalled (P4), and the vault's one project **without an
    /// area**, so it lives in `Projects/no_area/` (P1, R-6) and writes no `area:` line.
    public static let flatProject = Project(
        id: projectID("Wohnungssuche", area: nil),
        title: "Wohnungssuche",
        status: .active,
        outcome: "Signed contract for a room from April.",
        why: "The sublet ends in March.",
        steps: [
            ProjectStep(text: "Write a tenant profile"),
            ProjectStep(text: "Set up search alerts"),
        ],
        log: [])

    public static let areas: [Area] = [applicationsArea, careerArea]
    public static let projects: [Project] = [
        daadProject, erasmusProject, thesisProject, sideJobProject, flatProject,
    ]

    // MARK: - Actions

    /// 14 of these count toward the cap (`in-progress` + `next`), i.e. the sample vault sits at
    /// **cap − 1** with `nextCap == 15`: one more filing succeeds, the next one hits the cap.
    public static let actions: [Action] = [
        // in-progress (2) — pinned on top of Next
        action("Write DAAD motivation letter", .inProgress,
               contexts: ["mac", "deep-work"], estimate: 60, project: daadProject.id,
               due: day(5), created: -12, modified: -1,
               why: "The letter is the part the committee actually reads.",
               what: "- [ ] Draft the opening paragraph\n- [ ] Rework the research-fit section"),
        action("Fix the bike light", .inProgress,
               contexts: ["errands"], estimate: 30, created: -3, modified: -1,
               why: "Riding home in the dark without a light is how people get hurt.",
               what: "Buy a rear light at the shop on Türkenstraße and fit it."),

        // next (12)
        action("Read candidate thesis papers", .next,
               contexts: ["deep-work"], estimate: 90, project: thesisProject.id,
               created: -9, modified: -2,
               why: "Cannot pick a topic without knowing what is already written.",
               what: "Read the three PDFs in Knowledge/Thesis and take one page of notes each."),
        action("Compare Erasmus partner universities", .next,
               contexts: ["mac"], estimate: 60, project: erasmusProject.id,
               created: -8, modified: -8,
               why: "Deadline is in three weeks and the list is long.",
               what: "Build a short table: language, courses, housing, deadline."),
        action("Call the Studierendenwerk about the deposit", .next,
               contexts: ["calls", "phone"], estimate: 10, created: -21, modified: -20,
               why: "They still hold 500 € from the old room.",
               what: "Call 089/38196-0 and ask for the payout date."),
        action("Order the new passport photo", .next,
               contexts: ["errands"], estimate: 30, created: -5, modified: -5,
               why: "The DAAD form needs a biometric photo.",
               what: "Photo booth in the U-Bahn station, biometric setting."),
        action("Answer Lena about the WG viewing", .next,
               contexts: ["phone"], estimate: 10, due: day(1), created: -2, modified: -2,
               why: "She holds the slot only until tomorrow.",
               what: "Reply on WhatsApp with Thursday 18:00."),
        action("Cancel the gym membership", .next,
               contexts: ["mac"], estimate: 10, created: -40, modified: -35,
               why: "Paying 32 € a month for a place I have not entered since June.",
               what: "Send the cancellation form by email before the 30th."),
        action("Book the dentist appointment", .next,
               contexts: ["calls"], estimate: 10, created: -16, modified: -16,
               why: "Check-up is nine months overdue.",
               what: "Call the practice at Leopoldstraße."),
        action("Prepare the lab presentation", .next,
               contexts: ["mac", "deep-work"], estimate: 90, created: -6, modified: -3,
               why: "Fifteen minutes in front of the whole chair.",
               what: "- [ ] Outline five slides\n- [ ] Rehearse once out loud"),
        action("Reply to the DAAD info mail", .next,
               contexts: ["mac"], estimate: 10, project: daadProject.id,
               due: day(-2), created: -7, modified: -5,
               why: "They asked for a confirmation and the date has passed.",
               what: "Confirm attendance for the info session."),
        action("Buy a birthday present for Jonas", .next,
               contexts: ["errands"], created: -4, modified: -4,
               why: "His birthday is next weekend.",
               what: "Something for the kitchen — he moved in August."),
        action("Sort the Knowledge folder for the thesis", .next,
               contexts: ["mac"], estimate: 30, created: -30, modified: -18,
               why: "Papers are spread over three folders.",
               what: "Move everything thesis-related into Knowledge/Thesis."),
        action("Return the library books", .next,
               contexts: ["campus", "errands"], estimate: 30, due: day(2),
               created: -10, modified: -10,
               why: "Two of them are due on Monday.",
               what: "Drop them at the TUM Stammgelände library desk."),

        // someday (8) — two of them deferred into the future
        action("Set up the new bank account", .someday,
               contexts: ["mac"], estimate: 60, created: -25, modified: -25,
               why: "The old account charges 5 € a month.",
               what: "Open the DKB account online."),
        action("Write the tenant profile", .someday,
               contexts: ["mac"], estimate: 30, project: flatProject.id,
               deferDate: day(9), created: -13, modified: -13,
               why: "Landlords ask for it before a viewing.",
               what: "One page: who I am, what I earn, references."),
        action("Plan the semester timetable", .someday,
               contexts: ["mac"], estimate: 60, deferDate: day(20), created: -18, modified: -18,
               why: "Registration opens in October.",
               what: "Check overlaps between the two seminars."),
        action("Deep-clean the kitchen", .someday,
               contexts: ["home"], estimate: 90, created: -34, modified: -34,
               why: "The sublet hand-over will be checked.",
               what: "Oven, fridge, the cupboard behind the door."),
        action("Digitise the old notes", .someday,
               contexts: ["home", "deep-work"], created: -60, modified: -45,
               why: "Two boxes of paper I will never carry to the next flat.",
               what: "Scan and shred, folder by folder."),

        action("Learn Portuguese", .someday,
               contexts: ["home"], created: -90, modified: -70,
               why: "Would make the Lisbon option far more attractive.",
               what: "Try the first ten Duolingo lessons and see if it sticks."),
        action("Start a bouldering course", .someday,
               contexts: ["errands"], created: -50, modified: -50,
               why: "Sport that is not running.",
               what: "Look at the course plan of the Boulderwelt."),
        action("Build a small weather station", .someday,
               contexts: ["home", "deep-work"], created: -120, modified: -100,
               why: "A reason to finally use the ESP32 in the drawer.",
               what: "Sensor, case, a tiny dashboard."),

        // waiting (3) — one follow-up overdue (chase), one due in a day, one far out
        action("Reference letter from Prof. Weber", .waiting,
               project: daadProject.id, waiting: WaitingInfo(who: "Prof. Weber", followUp: day(-9)),
               created: -28, modified: -28,
               why: "The application cannot be submitted without it.",
               what: "Asked by mail on the 22nd; nothing since."),
        action("Deposit refund from the old landlord", .waiting,
               waiting: WaitingInfo(who: "Herr Kramer", followUp: day(1)),
               created: -15, modified: -15,
               why: "500 € that belong to me.",
               what: "He promised the transfer 'next week'."),
        action("Enrolment certificate from the office", .waiting,
               waiting: WaitingInfo(who: "Studierendensekretariat", followUp: day(6)),
               created: -6, modified: -6,
               why: "Needed for the scholarship form.",
               what: "Requested through the portal."),

        // agent (1) and review (1) — the In progress board's other two columns (#87). Neither
        // holds a cap slot, so the vault still sits at cap − 1.
        action("Draft the thesis LaTeX template", .agent,
               contexts: ["mac"], estimate: 30, project: thesisProject.id,
               created: -4, modified: -1,
               why: "Setting up the template is not where the thinking happens.",
               what: "Chair's title page, biblatex, one chapter skeleton."),
        action("Check the DAAD budget table", .review,
               contexts: ["mac"], estimate: 10, project: daadProject.id,
               created: -3, modified: 0,
               why: "The agent built it; the choice is mine.",
               what: "Read the table and mark the two favourites."),

        // done (2) — one old enough to be an archive candidate (A5)
        action("Collect DAAD transcripts", .done,
               contexts: ["campus"], estimate: 60, project: daadProject.id,
               created: -45, modified: -40, completed: -40,
               why: "Part of the DAAD paperwork.",
               what: "Picked up both certified copies."),
        action("Renew the bike insurance", .done,
               contexts: ["mac"], estimate: 10, created: -5, modified: -1, completed: -1,
               why: "Cover expires at the end of the month.",
               what: "Renewed online."),

        // legacy `status: trash` (1) — a note a pre-rework vault left behind. Trash is not a
        // status any more (I4c); R-1 decodes this one into the hidden legacy state, keeps it out
        // of every list, and `archiveCompleted` moves it to `GTD/Trash/` instead of `Archive/`.
        action("Look into that podcast app", .legacyTrashed,
               created: -33, modified: -30, completed: -30,
               why: "",
               what: "Not a real commitment."),
    ]

    // MARK: - Lists (§5a)

    /// The three initial lists of L1. Every one of them holds at least one item, because git
    /// cannot track an empty directory: a list whose folder held no file would simply be missing
    /// from a fresh clone of `Resources/SampleVault`. "An empty folder is still a list" (L2) is
    /// proved where it can be — against a temp directory, in `GTDVaultTests/ListsIndexTests` and
    /// `GTDServicesTests/ListJourneyTests`.
    public static let lists: [GTDList] = [
        GTDList(name: "Read"), GTDList(name: "Watch"), GTDList(name: "Wish"),
    ]

    /// Seven items — six open across the three lists, one finished in `Lists/Read/Done/` (L3).
    /// `Fixtures.config` leaves `favouriteLists` unset, so the sample vault also exercises R-5's
    /// derived default (the first four lists alphabetically: Read, Watch, Wish).
    public static let listItems: [ListItem] = [
        listItem("Read", "Thinking Fast and Slow", created: -22,
                 notes: "Kahneman. Marie said the second half is the interesting one."),
        listItem("Read", "The DAAD funding guidelines PDF", created: -12),
        listItem("Read", "Why we sleep", created: -3, notes: ""),
        listItem("Read", "Designing Data-Intensive Applications", created: -40,
                 finished: true, notes: "Done in August. Chapter 5 was worth the whole book."),
        listItem("Watch", "Arrival", created: -19),
        listItem("Watch", "The lecture recording on distributed systems", created: -6,
                 notes: "Second half of the term, the one about consensus."),
        listItem("Wish", "A second monitor arm", created: -8,
                 notes: "The clamp kind, not the one with the base."),
    ]

    // MARK: - Inbox

    public static let inbox: [InboxItem] = [
        inboxItem("2026-09-19 081204", "call the Hausverwaltung about the broken window handle"),
        inboxItem("2026-09-18 221501", "idea: a script that renames the scanned pdfs by their date"),
        inboxItem("2026-09-18 094410", "ask Marie whether she still needs the monitor"),
        inboxItem("2026-09-17 173355",
                  "Steuererklärung — find out whether the semester ticket is deductible"),
        inboxItem("2026-09-12 200900",
                  "the whole Erasmus vs DAAD decision — I keep pushing this around",
                  reviewReason: "It is a decision, not an action, and it needs an hour of thinking."),
        inboxItem("2026-09-08 071233", "buy new running shoes before the knee gets worse"),
    ]

    // MARK: - Routines

    public static let morningRoutine = routine(
        "Morning", time: DayTime(hour: 7, minute: 0),
        steps: [
            ("Wake up", []),
            ("Record dreams", []),
            ("Drink TPS/Water", ["Creatine if morning sport"]),
            ("5 min workout", []),
            ("Cold shower", []),
            ("Frühstück", ["Brainsmoothie", "Brötchen"]),
            ("Sonnencreme", []),
            ("Get things done", []),
        ])

    public static let bedtimeRoutine = routine(
        "Bedtime", time: DayTime(hour: 22, minute: 0),
        steps: [
            ("Work done by 22:00", []),
            ("Brush teeth", []),
            ("Reflect on day", [
                "Main plot", "Look at dayplan", "3 achievements", "3 gratitude",
                "1 will-do-better",
            ]),
            ("Read 30 min", []),
            ("Sleep by 23:30", []),
        ])

    public static let routines: [Routine] = [morningRoutine, bedtimeRoutine]

    /// Ten days of log, ending yesterday. Deterministic pattern so the audit heatmap always
    /// shows the same picture: every third day the cold shower is skipped, reading is skipped
    /// on weekends, and two days have no bedtime log at all.
    public static let routineLog: [RoutineLogEntry] = {
        var entries: [RoutineLogEntry] = []
        for offset in stride(from: -10, through: -1, by: 1) {
            let logDay = day(offset)
            for (index, step) in morningRoutine.steps.enumerated() {
                let skipped = step.id == "cold-shower" && offset % 3 == 0
                entries.append(RoutineLogEntry(
                    day: logDay,
                    routine: morningRoutine.title,
                    step: step.id,
                    result: skipped ? .skipped : .done,
                    at: date(logDay, 7, 5 + index * 2),
                    device: "iPhone"))
            }
            guard offset != -4, offset != -9 else { continue }
            for (index, step) in bedtimeRoutine.steps.enumerated() {
                let skipped = step.id == "read-30-min" && logDay.isoWeekday >= 6
                entries.append(RoutineLogEntry(
                    day: logDay,
                    routine: bedtimeRoutine.title,
                    step: step.id,
                    result: skipped ? .skipped : .done,
                    at: date(logDay, 22, 10 + index * 3),
                    device: "iPhone"))
            }
        }
        return entries
    }()

    // MARK: - Knowledge and review

    public static let knowledgeFolders: [String] = [
        "Finanzen", "Studium", "Studium/Thesis", "Technik", "Wohnen",
    ]

    public static let lastReview = WeeklyReview(
        year: 2026,
        week: 37,
        wantedToAchieve: "Get the DAAD paperwork to the point where only the letter is missing.",
        achieved: "Transcripts done, universities shortlisted. The letter did not start.",
        behaviorToChange: "Stop opening the inbox without processing it.",
        whatToStop: "Checking the flat portals five times a day.",
        howIGrew: "Asked the chair directly instead of waiting for office hours.",
        howToGrowFurther: "Do the uncomfortable mail first thing in the morning.",
        whatToTry: "Write the motivation letter in one 90-minute block, no research.",
        goalForNextWeek: "Motivation letter drafted end to end, however rough.",
        systemFixNotes: ["Decisions need their own place — they are not actions."],
        savedAt: date(day(-5), 11, 30))

    // MARK: - The snapshot

    /// The config **as it comes back from a vault**: `GTDConfig.default` plus the text of
    /// `GTD/Config.md` in its passthrough.
    ///
    /// Every entity `GTDMarkdown` decodes carries its own file text in the passthrough slot
    /// `"source"` (`NoteCodec.sourceSlot`) — that is what makes the round-trip rule (N2) hold.
    /// A fixture built in code carries nothing, so `scan(sample vault) != sampleSnapshot` for any
    /// entity compared as a whole value. `config` is the one the scan test compares that way
    /// (`GTDVaultTests.SampleVaultScanTests.scanOfTheSampleVaultEqualsTheSampleSnapshot`), so it
    /// carries its source here. The text is the very one `SampleVault` renders into the committed
    /// vault, so nothing can drift; `GTDFixtures` still does not depend on `GTDMarkdown`.
    public static let config: GTDConfig = {
        var config = GTDConfig.default
        config.passthrough["source"] = SampleVault.renderConfig(.default)
        return config
    }()

    /// The whole sample vault. `SampleVault` renders exactly this to markdown files.
    public static let sampleSnapshot = VaultSnapshot(
        inbox: inbox,
        actions: actions,
        areas: areas,
        projects: projects,
        lists: lists,
        listItems: listItems,
        routines: routines,
        routineLog: routineLog,
        knowledgeFolders: knowledgeFolders,
        config: config,
        lastReview: lastReview,
        issues: [])

    // MARK: - Builders

    private static func action(
        _ title: String,
        _ status: ActionStatus,
        contexts: [String] = [],
        estimate: Int? = nil,
        project: NoteID? = nil,
        deferDate: Day? = nil,
        due: Day? = nil,
        waiting: WaitingInfo? = nil,
        created: Int,
        modified: Int,
        completed: Int? = nil,
        why: String = "",
        what: String = ""
    ) -> Action {
        Action(
            id: actionID(title),
            title: title,
            status: status,
            contexts: contexts,
            timeEstimate: estimate,
            project: project,
            deferDate: deferDate,
            due: due,
            waitingFor: waiting?.who,
            followUpDate: waiting?.followUp,
            created: date(day(created), 9, 30),
            completedDate: completed.map { date(day($0), 17, 45) },
            modified: date(day(modified), 12, 0),
            why: why,
            what: what)
    }

    private static func listItem(
        _ list: String,
        _ title: String,
        created: Int,
        finished: Bool = false,
        notes: String = ""
    ) -> ListItem {
        ListItem(
            id: layout.listItemPath(list: list, title: title, finished: finished),
            list: list,
            title: title,
            isFinished: finished,
            created: date(day(created), 9, 30),
            notes: notes)
    }

    /// A capture written the way `InboxWriter` writes one (C3): named after its text, with the
    /// full text as the body only when the name could not carry it. `capturedAt` is
    /// `yyyy-MM-dd HHmmss`, the moment of the capture.
    private static func inboxItem(
        _ capturedAt: String,
        _ text: String,
        reviewReason: String? = nil
    ) -> InboxItem {
        let parts = capturedAt.split(separator: " ")
        let captureDay = Day(iso: String(parts[0])) ?? today
        let digits = Array(parts[1])
        let hour = Int(String(digits[0...1])) ?? 0
        let minute = Int(String(digits[2...3])) ?? 0
        let second = Int(String(digits[4...5])) ?? 0
        let note = CaptureText.note(for: text) ?? (title: text, body: "")
        return InboxItem(
            id: layout.inboxPath(title: note.title),
            body: note.body,
            created: date(captureDay, hour, minute, second),
            reviewReason: reviewReason)
    }

    private static func routine(
        _ title: String,
        time: DayTime,
        steps: [(String, [String])]
    ) -> Routine {
        Routine(
            id: NoteID(path: "\(layout.routines)/\(title).md"),
            title: title,
            time: time,
            steps: steps.map { RoutineStep(id: RoutineStep.slug($0.0), title: $0.0, substeps: $0.1) })
    }
}
