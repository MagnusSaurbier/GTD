import Foundation
import GTDModel

/// Small hand-built snapshots for the rule tables. `GTDFixtures.sampleSnapshot` is the realistic
/// vault (used where a rule needs a whole system); `TestVault` is used where a rule needs exactly
/// two actions and nothing else, so a failure names the rule and not the fixture.
///
/// Everything is anchored on a fixed day and a UTC calendar, so the tables behave the same in
/// every time zone.
enum TestVault {
    static let today = Day(year: 2026, month: 9, day: 19)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// 2026-09-19 10:00 UTC — `Day(now, calendar: calendar) == today`.
    static let now = today.date(at: DayTime(hour: 10, minute: 0), in: calendar) ?? Date(timeIntervalSince1970: 0)

    static func env(deviceID: String = "test") -> ReducerEnv {
        ReducerEnv(now: now, today: today, deviceID: deviceID, calendar: calendar)
    }

    static func day(_ offset: Int) -> Day { today.adding(days: offset) }

    /// A fixed instant on a day relative to `today`.
    static func date(_ offset: Int, hour: Int = 9) -> Date {
        day(offset).date(at: DayTime(hour: hour, minute: 0), in: calendar) ?? now
    }

    static let layout = VaultLayout.default

    static func actionID(_ title: String) -> NoteID { layout.actionPath(title: title) }

    static func action(
        _ title: String,
        _ status: ActionStatus = .backlog,
        contexts: [String] = [],
        timeEstimate: Int? = nil,
        project: NoteID? = nil,
        deferDate: Day? = nil,
        due: Day? = nil,
        waiting: WaitingInfo? = nil,
        created: Int = -1,
        modified: Int = -1,
        completed: Int? = nil,
        why: String = "",
        what: String = ""
    ) -> Action {
        Action(
            id: actionID(title),
            title: title,
            status: status,
            contexts: contexts,
            timeEstimate: timeEstimate,
            project: project,
            deferDate: deferDate,
            due: due,
            waitingFor: waiting?.who,
            followUpDate: waiting?.followUp,
            created: date(created),
            completedDate: completed.map { date($0, hour: 17) },
            modified: date(modified, hour: 12),
            why: why,
            what: what)
    }

    static func project(
        _ title: String,
        status: ProjectStatus = .active,
        area: NoteID? = nil,
        steps: [ProjectStep] = [],
        log: [LogEntry] = []
    ) -> Project {
        Project(
            id: layout.projectPath(title: title, inArea: area),
            title: title,
            area: area,
            status: status,
            steps: steps,
            log: log)
    }

    static func inboxItem(_ stamp: String, _ text: String, created: Int = 0, reviewReason: String? = nil) -> InboxItem {
        InboxItem(
            id: layout.inboxPath(stamp: stamp),
            text: text,
            created: date(created, hour: 8),
            reviewReason: reviewReason)
    }

    static func routine(_ title: String, steps: [String]) -> Routine {
        Routine(
            id: NoteID(path: "\(layout.routines)/\(title).md"),
            title: title,
            time: DayTime(hour: 7, minute: 0),
            steps: steps.map { RoutineStep(id: RoutineStep.slug($0), title: $0) })
    }

    static func snapshot(
        inbox: [InboxItem] = [],
        actions: [Action] = [],
        areas: [Area] = [],
        projects: [Project] = [],
        routines: [Routine] = [],
        routineLog: [RoutineLogEntry] = [],
        config: GTDConfig = .default
    ) -> VaultSnapshot {
        VaultSnapshot(
            inbox: inbox,
            actions: actions,
            areas: areas,
            projects: projects,
            routines: routines,
            routineLog: routineLog,
            config: config)
    }

    /// A snapshot holding exactly `count` actions that occupy a Next slot (A3).
    static func nextOccupied(_ count: Int, cap: Int = 15) -> VaultSnapshot {
        var config = GTDConfig.default
        config.nextCap = cap
        return snapshot(
            actions: (0..<count).map { action("Next \($0)", .next) },
            config: config)
    }

    /// `reduce`, but returning `nil` instead of throwing — for the error tables.
    static func error(_ s: VaultSnapshot, _ c: GTDCommand, env: ReducerEnv = TestVault.env()) -> GTDError? {
        do {
            _ = try Reducer.reduce(s, c, env: env)
            return nil
        } catch {
            return error
        }
    }
}
