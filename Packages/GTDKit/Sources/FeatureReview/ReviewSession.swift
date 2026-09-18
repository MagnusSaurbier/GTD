import Foundation
import Observation
import GTDModel
import GTDAppCore

/// The four stages of the weekly review (§10). Rail order is the declaration order.
public enum ReviewStage: String, Sendable, CaseIterable, Codable, Hashable {
    case sweep
    case deck
    case systemsCheck
    case reflection
}

/// Resumable wizard state, persisted device-locally in Application Support, keyed by ISO week.
/// Plain and unit-testable — **no SwiftUI**. Owned by T27.
public struct ReviewSessionState: Codable, Equatable, Sendable {
    public var year: Int
    public var week: Int
    public var stage: ReviewStage
    public var review: WeeklyReviewAnswers
    /// One note per deferred-to-review item the sweep handled (I5).
    public var systemFixNotes: [String]
    public var startedAt: Date

    public init(
        year: Int,
        week: Int,
        stage: ReviewStage = .sweep,
        review: WeeklyReviewAnswers = WeeklyReviewAnswers(),
        systemFixNotes: [String] = [],
        startedAt: Date
    ) {
        self.year = year
        self.week = week
        self.stage = stage
        self.review = review
        self.systemFixNotes = systemFixNotes
        self.startedAt = startedAt
    }
}

/// The eight answers, separated from `WeeklyReview` so the wizard state stays `Codable`.
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
}

@MainActor
@Observable
public final class ReviewSession {
    public private(set) var state: ReviewSessionState

    private let model: AppModel

    public init(model: AppModel, state: ReviewSessionState? = nil) {
        self.model = model
        let today = model.today()
        let iso = today.isoWeek
        self.state = state ?? ReviewSessionState(year: iso.year, week: iso.week, startedAt: Date())
    }

    /// Items the sweep must handle, each with its reason (§10.1.2).
    public var deferredInbox: [InboxItem] { Rules.reviewDeferredInbox(model.snapshot) }
    public var stalledProjects: [Project] { Rules.stalledProjects(model.snapshot, today: model.today()) }
    public var chase: [Action] { Rules.chaseItems(model.snapshot, today: model.today()) }

    /// The deck step cannot be left while Next is over the cap (§10.2).
    public var canLeaveDeck: Bool {
        Rules.countsTowardCap(model.snapshot) <= model.snapshot.config.nextCap
    }

    public func advance() {
        guard let index = ReviewStage.allCases.firstIndex(of: state.stage),
              index + 1 < ReviewStage.allCases.count
        else { return }
        state.stage = ReviewStage.allCases[index + 1]
    }

    public func back() {
        guard let index = ReviewStage.allCases.firstIndex(of: state.stage), index > 0 else { return }
        state.stage = ReviewStage.allCases[index - 1]
    }

    /// Saves `GTD/Reviews/<yyyy>/KW <ww>.md` (§10.4).
    public func save() async throws {
        let answers = state.review
        let review = WeeklyReview(
            year: state.year,
            week: state.week,
            wantedToAchieve: answers.wantedToAchieve,
            achieved: answers.achieved,
            behaviorToChange: answers.behaviorToChange,
            whatToStop: answers.whatToStop,
            howIGrew: answers.howIGrew,
            howToGrowFurther: answers.howToGrowFurther,
            whatToTry: answers.whatToTry,
            goalForNextWeek: answers.goalForNextWeek,
            systemFixNotes: state.systemFixNotes)
        try await model.send(.saveWeeklyReview(review))
    }
}
