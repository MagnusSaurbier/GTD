import Foundation

/// The four stages of the weekly review (§10). Rail order is the declaration order.
public enum ReviewStage: String, Sendable, CaseIterable, Codable, Hashable {
    case sweep
    case deck
    case systemsCheck
    case reflection

    public var title: String {
        switch self {
        case .sweep: ReviewCopy.stageSweep
        case .deck: ReviewCopy.stageDeck
        case .systemsCheck: ReviewCopy.stageSystemsCheck
        case .reflection: ReviewCopy.stageReflection
        }
    }

    /// The pages this stage is made of, in order.
    public var pages: [ReviewPage] { ReviewPage.allCases.filter { $0.stage == self } }

    /// Where `advance()` lands when it enters this stage.
    public var firstPage: ReviewPage { pages.first ?? .sweepInbox }
}

/// One screen of the wizard. The wizard is a flat, ordered list of pages; the four stages of
/// §10 are a grouping over it (the rail). Keeping navigation one-dimensional is what makes
/// "resume exactly where I stopped" a single stored value.
///
/// `summary` is the post-save screen (§10 "Summary screen: what changed this review"); it
/// belongs to no stage, so the rail shows all four stages complete while it is up.
public enum ReviewPage: String, Sendable, CaseIterable, Codable, Hashable {
    case sweepInbox
    case sweepDeferred
    case sweepWaiting
    case sweepStalled
    case deckNext
    case deckBacklogMaybe
    case deckProjects
    case systemsCheck
    case reflection
    case summary

    public var stage: ReviewStage? {
        switch self {
        case .sweepInbox, .sweepDeferred, .sweepWaiting, .sweepStalled: .sweep
        case .deckNext, .deckBacklogMaybe, .deckProjects: .deck
        case .systemsCheck: .systemsCheck
        case .reflection: .reflection
        case .summary: nil
        }
    }

    /// The deck phase this page shows, if it is a deck page.
    public var deckPhase: DeckPhase? {
        switch self {
        case .deckNext: .next
        case .deckBacklogMaybe: .backlogMaybe
        case .deckProjects: .projects
        default: nil
        }
    }

    /// Sub-step title in the rail (§3.10). Stage-sized pages repeat their stage title.
    public var title: String {
        switch self {
        case .sweepInbox: ReviewCopy.stepInbox
        case .sweepDeferred: ReviewCopy.stepDeferred
        case .sweepWaiting: ReviewCopy.stepWaiting
        case .sweepStalled: ReviewCopy.stepStalled
        case .deckNext: ReviewCopy.stepDeckNext
        case .deckBacklogMaybe: ReviewCopy.stepDeckBacklogMaybe
        case .deckProjects: ReviewCopy.stepDeckProjects
        case .systemsCheck: ReviewCopy.stageSystemsCheck
        case .reflection: ReviewCopy.stageReflection
        case .summary: ReviewCopy.stageSummary
        }
    }

    /// Position in the flat order; `summary` is last.
    public var index: Int { ReviewPage.allCases.firstIndex(of: self) ?? 0 }

    /// The page after this one, or `nil` at the end.
    public var next: ReviewPage? {
        let i = index + 1
        return ReviewPage.allCases.indices.contains(i) ? ReviewPage.allCases[i] : nil
    }

    /// The page before this one, or `nil` at the start. `summary` has no way back — the review
    /// is already written to the vault by the time it shows.
    public var previous: ReviewPage? {
        guard self != .summary else { return nil }
        let i = index - 1
        return ReviewPage.allCases.indices.contains(i) ? ReviewPage.allCases[i] : nil
    }

    /// The last page before saving; its primary button is `Save and finish`, not `Continue`.
    public static let lastBeforeSave: ReviewPage = .reflection
}

/// One rail entry (STYLEGUIDE §3.10), platform-free so the mapping is unit-tested rather than
/// written inside a view.
public struct ReviewRailItem: Sendable, Equatable, Identifiable {
    public var id: String { stage.rawValue }
    public var stage: ReviewStage
    public var title: String
    public var subSteps: [String]
    public var isComplete: Bool
    public var isCurrent: Bool

    public init(stage: ReviewStage, title: String, subSteps: [String], isComplete: Bool, isCurrent: Bool) {
        self.stage = stage
        self.title = title
        self.subSteps = subSteps
        self.isComplete = isComplete
        self.isCurrent = isCurrent
    }

    /// The rail for a wizard sitting on `page`: everything before the current stage is done, and
    /// once the summary shows, all four stages are done.
    public static func rail(for page: ReviewPage) -> [ReviewRailItem] {
        ReviewStage.allCases.map { stage in
            let isCurrent = page.stage == stage
            let isComplete: Bool
            if let current = page.stage {
                isComplete = stage.firstPage.index < current.firstPage.index
            } else {
                isComplete = true            // summary: the whole review is behind us
            }
            return ReviewRailItem(
                stage: stage,
                title: stage.title,
                subSteps: stage.pages.count > 1 ? stage.pages.map(\.title) : [],
                isComplete: isComplete,
                isCurrent: isCurrent)
        }
    }
}
