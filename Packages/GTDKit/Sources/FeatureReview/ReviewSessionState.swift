import Foundation
import GTDModel

/// The eight questions of §10.4, in the order the requirements list them. Modelled as a case
/// each (rather than key paths, which are not `Sendable`) so the reflection screen renders them
/// in one loop and the wording lives in `ReviewCopy`.
public enum ReviewQuestion: String, Sendable, CaseIterable, Codable, Hashable, Identifiable {
    case wantedToAchieve
    case achieved
    case behaviorToChange
    case whatToStop
    case howIGrew
    case howToGrowFurther
    case whatToTry
    case goalForNextWeek

    public var id: String { rawValue }

    public var prompt: String {
        switch self {
        case .wantedToAchieve: ReviewCopy.questionWantedToAchieve
        case .achieved: ReviewCopy.questionAchieved
        case .behaviorToChange: ReviewCopy.questionBehaviorToChange
        case .whatToStop: ReviewCopy.questionWhatToStop
        case .howIGrew: ReviewCopy.questionHowIGrew
        case .howToGrowFurther: ReviewCopy.questionHowToGrowFurther
        case .whatToTry: ReviewCopy.questionWhatToTry
        case .goalForNextWeek: ReviewCopy.questionGoalForNextWeek
        }
    }

    /// The one question that is shown next to last week's answer (§10.4).
    public var showsLastWeeksGoal: Bool { self == .wantedToAchieve }
}

/// The eight answers of §10.4, separated from `WeeklyReview` so the wizard state stays `Codable`
/// and carries no `NotePassthrough`.
public struct WeeklyReviewAnswers: Codable, Equatable, Sendable {
    public var wantedToAchieve = ""
    public var achieved = ""
    public var behaviorToChange = ""
    public var whatToStop = ""
    public var howIGrew = ""
    public var howToGrowFurther = ""
    public var whatToTry = ""
    public var goalForNextWeek = ""

    public init() {}

    public subscript(question: ReviewQuestion) -> String {
        get {
            switch question {
            case .wantedToAchieve: wantedToAchieve
            case .achieved: achieved
            case .behaviorToChange: behaviorToChange
            case .whatToStop: whatToStop
            case .howIGrew: howIGrew
            case .howToGrowFurther: howToGrowFurther
            case .whatToTry: whatToTry
            case .goalForNextWeek: goalForNextWeek
            }
        }
        set {
            switch question {
            case .wantedToAchieve: wantedToAchieve = newValue
            case .achieved: achieved = newValue
            case .behaviorToChange: behaviorToChange = newValue
            case .whatToStop: whatToStop = newValue
            case .howIGrew: howIGrew = newValue
            case .howToGrowFurther: howToGrowFurther = newValue
            case .whatToTry: whatToTry = newValue
            case .goalForNextWeek: goalForNextWeek = newValue
            }
        }
    }

    public var isEmpty: Bool {
        ReviewQuestion.allCases.allSatisfy {
            self[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// The three §10.3 systems-check prompts.
public enum SystemsCheckPrompt: String, Sendable, CaseIterable, Codable, Hashable, Identifiable {
    case trust
    case workload
    case routines

    public var id: String { rawValue }

    public var prompt: String {
        switch self {
        case .trust: ReviewCopy.promptTrust
        case .workload: ReviewCopy.promptWorkload
        case .routines: ReviewCopy.promptRoutines
        }
    }
}

/// The answers to those three prompts. Stored separately from the eight questions because they
/// end up in the review note's `systemFixNotes`, not among the answers.
public struct SystemsCheckAnswers: Codable, Equatable, Sendable {
    public var trust = ""
    public var workload = ""
    public var routines = ""

    public init() {}

    public subscript(prompt: SystemsCheckPrompt) -> String {
        get {
            switch prompt {
            case .trust: trust
            case .workload: workload
            case .routines: routines
            }
        }
        set {
            switch prompt {
            case .trust: trust = newValue
            case .workload: workload = newValue
            case .routines: routines = newValue
            }
        }
    }

    /// One note per answered prompt, each keeping its question (an answer alone is unreadable
    /// a year later). Unanswered prompts write nothing — an empty field is not a finding.
    public var notes: [String] {
        SystemsCheckPrompt.allCases.compactMap { prompt in
            let answer = self[prompt].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return nil }
            return ReviewCopy.systemsCheckNote(prompt: prompt.prompt, answer: answer)
        }
    }
}

/// What this review changed, for the summary screen (§10 "Summary screen"). Part of the
/// persisted state so the numbers survive a relaunch mid-review.
public struct ReviewChanges: Codable, Equatable, Sendable {
    public var deferredHandled = 0
    public var waitingHandled = 0
    public var demoted = 0
    public var promoted = 0
    public var trashed = 0
    public var kept = 0
    public var projectsTouched = 0

    public init() {}

    public mutating func record(_ choice: DeckChoice) {
        switch choice {
        case .keep: kept += 1
        case .demote: demoted += 1
        case .promote: promoted += 1
        case .trash: trashed += 1
        case .activate, .drop: projectsTouched += 1
        }
    }
}

/// Resumable wizard state, persisted device-locally in Application Support (never in the vault,
/// ARCHITECTURE §3) and keyed by ISO week.
///
/// Everything that must survive "quit the app half-way through the review" is here: which page
/// the user was on, which items of each sweep step and which deck cards already have a decision,
/// the free text typed so far, and the running change counters.
public struct ReviewSessionState: Codable, Equatable, Sendable {
    public var year: Int
    public var week: Int
    public var page: ReviewPage
    public var review: WeeklyReviewAnswers
    public var systemsCheck: SystemsCheckAnswers
    /// One note per deferred-to-review item the sweep handled (I5).
    public var systemFixNotes: [String]
    public var startedAt: Date
    /// `NoteID.path`s that already have a decision, per step — the basis of "resume where I was".
    public var handledDeferred: [String]
    public var handledWaiting: [String]
    public var handledStalled: [String]
    public var handledDeckCards: [String]
    /// Size of the inbox queue when the review started, so the summary can report how many
    /// items the review itself processed.
    public var inboxAtStart: Int
    public var changes: ReviewChanges
    /// Set once `saveWeeklyReview` succeeded; the wizard then only has the summary left.
    public var isSaved: Bool

    public init(
        year: Int,
        week: Int,
        stage: ReviewStage = .sweep,
        review: WeeklyReviewAnswers = WeeklyReviewAnswers(),
        systemFixNotes: [String] = [],
        startedAt: Date
    ) {
        self.init(
            year: year, week: week, page: stage.firstPage, review: review,
            systemFixNotes: systemFixNotes, startedAt: startedAt)
    }

    public init(
        year: Int,
        week: Int,
        page: ReviewPage,
        review: WeeklyReviewAnswers = WeeklyReviewAnswers(),
        systemsCheck: SystemsCheckAnswers = SystemsCheckAnswers(),
        systemFixNotes: [String] = [],
        startedAt: Date,
        handledDeferred: [String] = [],
        handledWaiting: [String] = [],
        handledStalled: [String] = [],
        handledDeckCards: [String] = [],
        inboxAtStart: Int = 0,
        changes: ReviewChanges = ReviewChanges(),
        isSaved: Bool = false
    ) {
        self.year = year
        self.week = week
        self.page = page
        self.review = review
        self.systemsCheck = systemsCheck
        self.systemFixNotes = systemFixNotes
        self.startedAt = startedAt
        self.handledDeferred = handledDeferred
        self.handledWaiting = handledWaiting
        self.handledStalled = handledStalled
        self.handledDeckCards = handledDeckCards
        self.inboxAtStart = inboxAtStart
        self.changes = changes
        self.isSaved = isSaved
    }

    /// The stage the rail highlights. `nil` on the summary screen, which belongs to no stage.
    public var stage: ReviewStage? { page.stage }

    public func isFor(year: Int, week: Int) -> Bool { self.year == year && self.week == week }

    /// A state written by an older build may carry a `page` this build no longer has — the
    /// pre-rework deck had one merged "not now" phase, `deckBacklogMaybe`, where this build has
    /// `deckSomeday` (T12). That one rename is unambiguous (same position, same phase), so it is
    /// migrated rather than discarded: `migratedPage(fromRaw:)` maps it, and maps anything else
    /// unrecognised to the start of the deck stage — never a crash, and the sweep's own progress
    /// (`handledDeferred`/`handledWaiting`/`handledStalled`, all unaffected by the rename) is
    /// never lost over a `page` value alone.
    ///
    /// Everything else is additive with a default, so a state written before a field existed
    /// still decodes.
    private enum CodingKeys: String, CodingKey {
        case year, week, page, review, systemsCheck, systemFixNotes, startedAt
        case handledDeferred, handledWaiting, handledStalled, handledDeckCards
        case inboxAtStart, changes, isSaved
    }

    /// Maps a stored `page` raw value to a `ReviewPage` this build has, tolerating the one
    /// pre-rework case the migration guide calls out (T12) plus any other value a future build
    /// might no longer recognise.
    ///
    /// - A value this build still has decodes straight through.
    /// - `deckBacklogMaybe` (the pre-rework merged Next↔Backlog/Maybe deck phase) is an
    ///   unambiguous rename to `deckSomeday` — same position in the same three-phase deck, so the
    ///   review resumes exactly where it was rather than restarting.
    /// - Anything else unrecognised restarts at the top of the deck stage (`deckNext`) instead of
    ///   discarding the whole state: only the deck's own phases changed shape in this rework, so
    ///   the sweep the user already finished is never re-asked, and re-dealing the deck from its
    ///   first phase can never lose a note (`ReviewDeck.cards` is a pure function of the vault).
    static func migratedPage(fromRaw raw: String) -> ReviewPage {
        if let page = ReviewPage(rawValue: raw) { return page }
        if raw == "deckBacklogMaybe" { return .deckSomeday }
        return .deckNext
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = try c.decode(Int.self, forKey: .year)
        week = try c.decode(Int.self, forKey: .week)
        if let rawPage = try c.decodeIfPresent(String.self, forKey: .page) {
            page = ReviewSessionState.migratedPage(fromRaw: rawPage)
        } else {
            page = .sweepInbox
        }
        review = try c.decodeIfPresent(WeeklyReviewAnswers.self, forKey: .review) ?? WeeklyReviewAnswers()
        systemsCheck = try c.decodeIfPresent(SystemsCheckAnswers.self, forKey: .systemsCheck) ?? SystemsCheckAnswers()
        systemFixNotes = try c.decodeIfPresent([String].self, forKey: .systemFixNotes) ?? []
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        handledDeferred = try c.decodeIfPresent([String].self, forKey: .handledDeferred) ?? []
        handledWaiting = try c.decodeIfPresent([String].self, forKey: .handledWaiting) ?? []
        handledStalled = try c.decodeIfPresent([String].self, forKey: .handledStalled) ?? []
        handledDeckCards = try c.decodeIfPresent([String].self, forKey: .handledDeckCards) ?? []
        inboxAtStart = try c.decodeIfPresent(Int.self, forKey: .inboxAtStart) ?? 0
        changes = try c.decodeIfPresent(ReviewChanges.self, forKey: .changes) ?? ReviewChanges()
        isSaved = try c.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
    }
}
