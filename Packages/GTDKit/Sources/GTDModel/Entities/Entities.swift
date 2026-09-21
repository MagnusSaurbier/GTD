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
    /// R-4 — the body text **above** `# Why?`: the full capture text of a note whose title could
    /// not hold it, and anything a hand-written note carries before the first heading. Empty for
    /// a note whose body starts with a heading.
    public var preamble: String
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
        preamble: String = "",
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
        self.preamble = preamble
        self.why = why
        self.what = what
        self.passthrough = passthrough
    }

    /// Checkboxes parsed out of `what` (A2).
    public var checkboxes: [Checkbox] { Checkbox.scan(what) }

    public var timeBucket: TimeBucket? { TimeBucket(minutes: timeEstimate) }

    /// The waiting information, present as soon as the **follow-up date** is (W1, D39). `who` is
    /// optional: a wait on a process has nobody to name.
    public var waiting: WaitingInfo? {
        guard let followUpDate else { return nil }
        return WaitingInfo(
            who: waitingFor.flatMap { $0.isEmpty ? nil : $0 }, followUp: followUpDate)
    }
}

// MARK: - Lists (§5a)

/// One list — a **direct subfolder** of `VaultLayout.lists` (L2). The folder is the only marker:
/// there is no list note and no `status`, so the name *is* the identity.
///
/// `Done/` inside a list is reserved (it holds the finished items, L3) and is never a list.
public struct GTDList: Identifiable, Sendable, Equatable, Hashable {
    /// Folder name directly under `Lists/`, e.g. `Read`. Also the display name.
    public let name: String

    public var id: String { name }

    public init(name: String) {
        self.name = name
    }

    /// Two lists are the same list when their names differ only in case — macOS and iOS file
    /// systems are case-insensitive, so `Read` and `read` cannot both exist (L2).
    public static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() == rhs.lowercased()
    }
}

/// One item of a list — one note in `Lists/<name>/` (L1, D17).
///
/// A list item is **not a commitment**: no Why?/What?, no context, no time estimate, no `status`,
/// no cap and no staleness. Its title is the file name, its body is free notes, and the only
/// frontmatter it carries is the optional `created` timestamp.
public struct ListItem: Identifiable, Sendable, Equatable {
    public let id: NoteID
    /// The list it lives in — the folder name, not a path.
    public var list: String
    /// File name stem. Changing it renames the file (`updateListItem`).
    public var title: String
    /// True for an item in `Lists/<name>/Done/` — read / watched / bought (L3).
    public var isFinished: Bool
    public var created: Date?
    /// The note's body (I4b: the optional notes panel writes here).
    public var notes: String
    public var passthrough: NotePassthrough

    public init(
        id: NoteID,
        list: String,
        title: String,
        isFinished: Bool = false,
        created: Date? = nil,
        notes: String = "",
        passthrough: NotePassthrough = .empty
    ) {
        self.id = id
        self.list = list
        self.title = title
        self.isFinished = isFinished
        self.created = created
        self.notes = notes
        self.passthrough = passthrough
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
    /// The lists shown in the inbox navbar, in the user's order (I4b, L2, R-5).
    ///
    /// **`nil` means "the user has never chosen"** — `Rules.favouriteLists` then derives the
    /// first four lists alphabetically. That default is never written to `GTD/Config.md`: the
    /// key appears in the file only once the user has picked favourites (`setFavouriteLists`),
    /// so a vault that has not been to the settings screen keeps its config untouched.
    public var favouriteLists: [String]?
    public var layout: VaultLayout
    public var passthrough: NotePassthrough

    public init(
        contexts: [String],
        onTheGoContexts: [String],
        nextCap: Int,
        favouriteLists: [String]? = nil,
        layout: VaultLayout = .default,
        passthrough: NotePassthrough = .empty
    ) {
        self.contexts = contexts
        self.onTheGoContexts = onTheGoContexts
        self.nextCap = nextCap
        self.favouriteLists = favouriteLists
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
    /// Every direct subfolder of `Lists/` (L2) — including the empty ones, which are lists too.
    public var lists: [GTDList]
    /// Every note in `Lists/<name>/` and `Lists/<name>/Done/` (L1, L3). Kept flat, next to the
    /// other entity collections, so one file is one entity for the snapshot diff.
    public var listItems: [ListItem]
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
        lists: [GTDList] = [],
        listItems: [ListItem] = [],
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
        self.lists = lists
        self.listItems = listItems
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
    public func listItem(_ id: NoteID) -> ListItem? { listItems.first { $0.id == id } }

    /// The list called `name`, compared case-insensitively — a case-insensitive file system
    /// cannot hold `Read` and `read` side by side, so neither can a lookup pretend it could (L2).
    public func list(named name: String) -> GTDList? {
        lists.first { GTDList.sameName($0.name, name) }
    }
}
