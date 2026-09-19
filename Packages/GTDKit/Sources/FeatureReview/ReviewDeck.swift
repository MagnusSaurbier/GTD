import Foundation
import GTDModel
import DesignSystem

/// The three phases of the deck (§10.2): Next, then Backlog and Maybe, then the projects that
/// are not active. Declaration order is the order the wizard walks them in.
public enum DeckPhase: String, Sendable, CaseIterable, Codable, Hashable {
    case next
    case backlogMaybe
    case projects

    public var title: String {
        switch self {
        case .next: ReviewCopy.deckNextTitle
        case .backlogMaybe: ReviewCopy.deckBacklogMaybeTitle
        case .projects: ReviewCopy.deckProjectsTitle
        }
    }

    public var page: ReviewPage {
        switch self {
        case .next: .deckNext
        case .backlogMaybe: .deckBacklogMaybe
        case .projects: .deckProjects
        }
    }
}

/// What the user can do with a deck card. Keys are fixed by STYLEGUIDE §3.10:
/// `K` keep · `D` demote · `P` promote · `T` trash. `activate`/`drop` are the project-shaped
/// versions of promote/trash and reuse their keys — a card never offers both.
public enum DeckChoice: String, Sendable, CaseIterable, Codable, Hashable, Identifiable {
    case keep
    case demote
    case promote
    case trash
    case activate
    case drop

    public var id: String { rawValue }

    public var key: String {
        switch self {
        case .keep: "K"
        case .demote: "D"
        case .promote, .activate: "P"
        case .trash, .drop: "T"
        }
    }

    public var title: String {
        switch self {
        case .keep: ReviewCopy.keep
        case .demote: Copy.demote
        case .promote: Copy.promote
        case .trash: Copy.trash
        case .activate: ReviewCopy.activateChoice
        case .drop: ReviewCopy.dropChoice
        }
    }

    public var symbol: String {
        switch self {
        case .keep: ReviewSymbols.keep
        case .demote: ReviewSymbols.demote
        case .promote, .activate: ReviewSymbols.promote
        case .trash: ReviewSymbols.trash
        case .drop: ReviewSymbols.maybe
        }
    }

    /// `keep` writes nothing, so it can never fail and never counts as a change.
    public var changesAnything: Bool { self != .keep }
}

/// One card in the deck: an action in the Next/Backlog/Maybe phases, a project in the last one.
public struct DeckCard: Sendable, Equatable, Identifiable {
    public enum Subject: Sendable, Equatable {
        case action(Action)
        case project(Project)
    }

    public var subject: Subject
    public var choices: [DeckChoice]

    public var id: NoteID {
        switch subject {
        case let .action(action): action.id
        case let .project(project): project.id
        }
    }

    public var title: String {
        switch subject {
        case let .action(action): action.title
        case let .project(project): project.title
        }
    }

    public var action: Action? {
        if case let .action(action) = subject { return action }
        return nil
    }

    public var project: Project? {
        if case let .project(project) = subject { return project }
        return nil
    }

    public init(subject: Subject, choices: [DeckChoice]) {
        self.subject = subject
        self.choices = choices
    }
}

/// The deck's pure half: which cards a phase shows, in which order, and which command a choice
/// turns into. Every decision here is a function of the snapshot, so resuming mid-deck after a
/// relaunch rebuilds exactly the same list (minus the cards already decided).
public enum ReviewDeck {

    /// Cards for `phase`, in the order the wizard deals them.
    ///
    /// - `.next` reuses `Rules.nextList` so the deck order matches the Next view the user knows
    ///   (`in-progress` first, then nearest `due`, then oldest capture).
    /// - `.backlogMaybe` deals Backlog before Maybe — the promotion candidates first — each
    ///   oldest capture first, so the things that have sat longest get decided first.
    /// - `.projects` deals on-hold before someday, by title.
    public static func cards(for phase: DeckPhase, in s: VaultSnapshot, today: Day) -> [DeckCard] {
        switch phase {
        case .next:
            return Rules.nextList(s, today: today)
                .map { DeckCard(subject: .action($0), choices: [.keep, .demote]) }
        case .backlogMaybe:
            let byStatus: [ActionStatus] = [.backlog, .maybe]
            return byStatus.flatMap { status in
                s.actions
                    .filter { $0.status == status }
                    .sorted(by: oldestFirst)
                    .map { DeckCard(subject: .action($0), choices: [.promote, .keep, .trash]) }
            }
        case .projects:
            let byStatus: [ProjectStatus] = [.onHold, .someday]
            return byStatus.flatMap { status in
                s.projects
                    .filter { $0.status == status }
                    .sorted { ($0.title, $0.id.path) < ($1.title, $1.id.path) }
                    .map { DeckCard(subject: .project($0), choices: choices(for: status)) }
            }
        }
    }

    /// An on-hold project can be dropped a step further (to Someday); one that is already there
    /// has nowhere left to drop to — the app never deletes, and "drop" must not quietly mean
    /// "done" (§1 "no lying UI"). So the choice is hidden rather than shown disabled.
    static func choices(for status: ProjectStatus) -> [DeckChoice] {
        switch status {
        case .onHold: [.activate, .keep, .drop]
        case .someday: [.activate, .keep]
        case .active, .done: [.keep]
        }
    }

    /// The command a choice turns into, or `nil` for `keep` (which writes nothing).
    /// Trashing an action sets `status: trash`; the file itself is never hard-deleted (§2, N-rule).
    public static func command(for choice: DeckChoice, card: DeckCard) -> GTDCommand? {
        switch (choice, card.subject) {
        case (.keep, _):
            return nil
        case let (.demote, .action(action)):
            return .setStatus(action.id, .backlog, waiting: nil)
        case let (.promote, .action(action)):
            return .setStatus(action.id, .next, waiting: nil)
        case let (.trash, .action(action)):
            return .setStatus(action.id, .trash, waiting: nil)
        case let (.activate, .project(project)):
            return projectStatus(project, .active)
        case let (.drop, .project(project)):
            return projectStatus(project, .someday)
        default:
            return nil      // a choice a card does not offer
        }
    }

    private static func projectStatus(_ project: Project, _ status: ProjectStatus) -> GTDCommand? {
        guard project.status != status else { return nil }
        var updated = project
        updated.status = status
        return .updateProject(updated)
    }

    /// Oldest capture first; a note without `created` sorts last rather than pretending to be new.
    static func oldestFirst(_ lhs: Action, _ rhs: Action) -> Bool {
        let l = lhs.created ?? .distantFuture
        let r = rhs.created ?? .distantFuture
        if l != r { return l < r }
        return lhs.id.path < rhs.id.path
    }
}
