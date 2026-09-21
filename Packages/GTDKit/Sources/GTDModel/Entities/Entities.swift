import Foundation

// MARK: - Inbox

/// One capture, one file in `Inbox/` (C3).
public struct InboxItem: Identifiable, Sendable, Equatable {
    public let id: NoteID
    public var text: String
    public var created: Date
    /// Non-nil ⇒ deferred to the weekly review (I5); such items leave the processing queue.
    public var reviewReason: String?
    public var passthrough: NotePassthrough

    public init(
        id: NoteID,
        text: String,
        created: Date,
        reviewReason: String? = nil,
        passthrough: NotePassthrough = .empty
    ) {
        self.id = id
        self.text = text
        self.created = created
        self.reviewReason = reviewReason
        self.passthrough = passthrough
    }
}

// MARK: - Action

/// One markdown note in `Actions/` (A1). Body is `# Why?` + `# What?`.
public struct Action: Identifiable, Sendable, Equatable {
    public let id: NoteID
    /// Filename stem. Renaming an action is a file move, performed by `GTDServices`.
    public var title: String
    public var status: ActionStatus
    public var contexts: [String]
    /// Minutes. Empty when undecided — never `0` (§1 "no lying defaults").
    public var timeEstimate: Int?
    public var project: NoteID?
    public var deferDate: Day?
    public var due: Day?
    public var waitingFor: String?
    public var followUpDate: Day?
    public var created: Date?
    public var completedDate: Date?
    public var reviewReason: String?
    /// File modification date. Read-only for everything except `GTDVault`, which fills it in
    /// from the file system; drives the staleness signals (STYLEGUIDE §2.2).
    public var modified: Date?
    public var why: String
    public var what: String
    public var passthrough: NotePassthrough

    public init(
        id: NoteID,
        title: String,
        status: ActionStatus,
        contexts: [String] = [],
        timeEstimate: Int? = nil,
        project: NoteID? = nil,
        deferDate: Day? = nil,
        due: Day? = nil,
        waitingFor: String? = nil,
        followUpDate: Day? = nil,
        created: Date? = nil,
        completedDate: Date? = nil,
        reviewReason: String? = nil,
        modified: Date? = nil,
        why: String = "",
        what: String = "",
        passthrough: NotePassthrough = .empty
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.contexts = contexts
        self.timeEstimate = timeEstimate
        self.project = project
        self.deferDate = deferDate
        self.due = due
        self.waitingFor = waitingFor
        self.followUpDate = followUpDate
        self.created = created
        self.completedDate = completedDate
        self.reviewReason = reviewReason
        self.modified = modified
        self.why = why
        self.what = what
        self.passthrough = passthrough
    }

    /// Checkboxes parsed out of `what` (A2).
    public var checkboxes: [Checkbox] { Checkbox.scan(what) }

    public var timeBucket: TimeBucket? { TimeBucket(minutes: timeEstimate) }

    /// The `waiting` pair, present only when both halves are set (W1).
    public var waiting: WaitingInfo? {
        guard let waitingFor, let followUpDate, !waitingFor.isEmpty else { return nil }
        return WaitingInfo(who: waitingFor, followUp: followUpDate)
    }
}

// MARK: - Areas and projects

/// An ongoing area of responsibility — a folder under `Projects/` with `kind: area` (P1).
public struct Area: Identifiable, Sendable, Equatable {
    public let id: NoteID
    public var title: String
    public var passthrough: NotePassthrough

    public init(id: NoteID, title: String, passthrough: NotePassthrough = .empty) {
        self.id = id
        self.title = title
        self.passthrough = passthrough
    }
}

/// A checklist line in a project note's `# Steps` section (P4).
public struct ProjectStep: Sendable, Equatable {
    public var text: String
    public var done: Bool
    /// Set once the step has been promoted into a real action note (`→ [[Action title]]`).
    public var promotedTo: NoteID?

    public init(text: String, done: Bool = false, promotedTo: NoteID? = nil) {
        self.text = text
        self.done = done
        self.promotedTo = promotedTo
    }
}

/// One `- 2026-09-18 Did X` line in a project note's `# Log` section (P6).
public struct LogEntry: Sendable, Equatable {
    public var day: Day
    public var text: String

    public init(day: Day, text: String) {
        self.day = day
        self.text = text
    }
}

/// A finite project with an outcome (P1, P2).
public struct Project: Identifiable, Sendable, Equatable {
    public let id: NoteID
    public var title: String
    public var area: NoteID?
    public var status: ProjectStatus
    public var outcome: String
    public var why: String
    public var steps: [ProjectStep]
    public var log: [LogEntry]
    /// Other files in the project folder, vault-relative (P6). Filled by `GTDVault`.
    public var referenceFiles: [String]
    public var passthrough: NotePassthrough

    public init(
        id: NoteID,
        title: String,
        area: NoteID? = nil,
        status: ProjectStatus = .active,
        outcome: String = "",
        why: String = "",
        steps: [ProjectStep] = [],
        log: [LogEntry] = [],
        referenceFiles: [String] = [],
        passthrough: NotePassthrough = .empty
    ) {
        self.id = id
        self.title = title
        self.area = area
        self.status = status
        self.outcome = outcome
        self.why = why
        self.steps = steps
        self.log = log
        self.referenceFiles = referenceFiles
        self.passthrough = passthrough
    }

    /// Steps that are neither done nor already promoted — what `WhatsNextSheet` offers (P5).
    public var openSteps: [ProjectStep] { steps.filter { !$0.done && $0.promotedTo == nil } }
}

// MARK: - Routines

/// One top-level checkbox of a routine template; nested items are sub-steps (R1).
public struct RoutineStep: Identifiable, Sendable, Equatable {
    /// Slug of the step text — stable across template edits (T24 relies on this).
    public let id: String
    public var title: String
    public var substeps: [String]

    public init(id: String, title: String, substeps: [String] = []) {
        self.id = id
        self.title = title
        self.substeps = substeps
    }

    /// Lowercased, non-alphanumerics collapsed to `-`. Used as the step id in the routine log.
    public static func slug(_ text: String) -> String {
        var out = ""
        var pendingSeparator = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !out.isEmpty { out.append("-") }
                pendingSeparator = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return out.isEmpty ? "step" : String(out.prefix(60))
    }
}

/// A routine template note in `GTD/Routines/` (R1).
public struct Routine: Identifiable, Sendable, Equatable {
    public let id: NoteID
    public var title: String
    public var time: DayTime?
    public var steps: [RoutineStep]
    public var passthrough: NotePassthrough

    public init(
        id: NoteID,
        title: String,
        time: DayTime? = nil,
        steps: [RoutineStep] = [],
        passthrough: NotePassthrough = .empty
    ) {
        self.id = id
        self.title = title
        self.time = time
        self.steps = steps
        self.passthrough = passthrough
    }
}

/// One logged step, one entry in a `GTD/RoutineLog/<day>--<device>.md` file (R5, N3).
public struct RoutineLogEntry: Sendable, Equatable {
    public var day: Day
    /// Routine title (the log is human-readable in Obsidian).
    public var routine: String
    /// `RoutineStep.id`.
    public var step: String
    public var result: RoutineStepResult
    public var at: Date
    public var device: String

    public init(
        day: Day,
        routine: String,
        step: String,
        result: RoutineStepResult,
        at: Date,
        device: String
    ) {
        self.day = day
        self.routine = routine
        self.step = step
        self.result = result
        self.at = at
        self.device = device
    }
}

// MARK: - Config

/// Settings synced through `GTD/Config.md` (A4, A3).
public struct GTDConfig: Sendable, Equatable {
    public var contexts: [String]
    public var onTheGoContexts: [String]
    public var nextCap: Int
    public var layout: VaultLayout
    public var passthrough: NotePassthrough

    public init(
        contexts: [String],
        onTheGoContexts: [String],
        nextCap: Int,
        layout: VaultLayout = .default,
        passthrough: NotePassthrough = .empty
    ) {
        self.contexts = contexts
        self.onTheGoContexts = onTheGoContexts
        self.nextCap = nextCap
        self.layout = layout
        self.passthrough = passthrough
    }

    /// A4 — there is **no `reading` context**: all reading goes to the Read list (§5a).
    /// Only the *default* changed; a vault whose `Config.md` still lists `reading` keeps it,
    /// because the config is read from the file and the list is the user's.
    public static let `default` = GTDConfig(
        contexts: ["mac", "phone", "home", "campus", "errands", "calls", "deep-work"],
        onTheGoContexts: ["phone", "errands", "calls"],
        nextCap: 15,
        layout: .default)
}

/// Something in the vault the app will not silently fix: an unparsable file, a conflict copy,
/// an iCloud item that is not downloaded yet (N3 §7).
public struct VaultIssue: Sendable, Equatable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

// MARK: - Weekly review

/// The note saved as `GTD/Reviews/<yyyy>/KW <ww>.md` (§10.4).
///
/// The eight questions of REQUIREMENTS §10.4 are the eight `String` answers below;
/// `goalForNextWeek` is the eighth and is shown alongside next week's first question.
public struct WeeklyReview: Sendable, Equatable {
    public var year: Int
    /// ISO week number (the `KW`).
    public var week: Int
    public var wantedToAchieve: String
    public var achieved: String
    public var behaviorToChange: String
    public var whatToStop: String
    public var howIGrew: String
    public var howToGrowFurther: String
    public var whatToTry: String
    public var goalForNextWeek: String
    /// One note per "this didn't fit the process" item handled in the sweep (I5).
    public var systemFixNotes: [String]
    public var savedAt: Date?
    public var passthrough: NotePassthrough

    public init(
        year: Int,
        week: Int,
        wantedToAchieve: String = "",
        achieved: String = "",
        behaviorToChange: String = "",
        whatToStop: String = "",
        howIGrew: String = "",
        howToGrowFurther: String = "",
        whatToTry: String = "",
        goalForNextWeek: String = "",
        systemFixNotes: [String] = [],
        savedAt: Date? = nil,
        passthrough: NotePassthrough = .empty
    ) {
        self.year = year
        self.week = week
        self.wantedToAchieve = wantedToAchieve
        self.achieved = achieved
        self.behaviorToChange = behaviorToChange
        self.whatToStop = whatToStop
        self.howIGrew = howIGrew
        self.howToGrowFurther = howToGrowFurther
        self.whatToTry = whatToTry
        self.goalForNextWeek = goalForNextWeek
        self.systemFixNotes = systemFixNotes
        self.savedAt = savedAt
        self.passthrough = passthrough
    }

    public func noteID(layout: VaultLayout = .default) -> NoteID {
        layout.reviewPath(year: year, week: week)
    }
}

// MARK: - Snapshot

/// The whole vault as the app sees it, rebuilt from files. There is no database.
public struct VaultSnapshot: Sendable, Equatable {
    public var inbox: [InboxItem]
    /// Everything in `Actions/`; `Archive/` is excluded.
    public var actions: [Action]
    public var areas: [Area]
    public var projects: [Project]
    public var routines: [Routine]
    /// Last 14 days, merged across devices.
    public var routineLog: [RoutineLogEntry]
    /// Folder tree under `Knowledge/`, vault-relative paths without the `Knowledge/` prefix.
    public var knowledgeFolders: [String]
    public var config: GTDConfig
    /// The most recent `KW` note, shown alongside this week's questions (§10.4).
    public var lastReview: WeeklyReview?
    public var issues: [VaultIssue]

    public init(
        inbox: [InboxItem] = [],
        actions: [Action] = [],
        areas: [Area] = [],
        projects: [Project] = [],
        routines: [Routine] = [],
        routineLog: [RoutineLogEntry] = [],
        knowledgeFolders: [String] = [],
        config: GTDConfig = .default,
        lastReview: WeeklyReview? = nil,
        issues: [VaultIssue] = []
    ) {
        self.inbox = inbox
        self.actions = actions
        self.areas = areas
        self.projects = projects
        self.routines = routines
        self.routineLog = routineLog
        self.knowledgeFolders = knowledgeFolders
        self.config = config
        self.lastReview = lastReview
        self.issues = issues
    }

    /// An empty vault — what `AppModel` shows before the first scan arrives.
    public static let empty = VaultSnapshot()

    // MARK: Lookups

    public func action(_ id: NoteID) -> Action? { actions.first { $0.id == id } }
    public func project(_ id: NoteID) -> Project? { projects.first { $0.id == id } }
    public func area(_ id: NoteID) -> Area? { areas.first { $0.id == id } }
    public func routine(_ id: NoteID) -> Routine? { routines.first { $0.id == id } }
    public func inboxItem(_ id: NoteID) -> InboxItem? { inbox.first { $0.id == id } }
}
