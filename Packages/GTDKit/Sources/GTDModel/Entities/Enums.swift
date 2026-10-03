import Foundation

/// Commitment tier and lifecycle of an action (A3). Raw values are what the frontmatter holds.
///
/// **Someday is the single "not now" tier** — the former `backlog` and `maybe` merged (A3, D1).
/// Legacy vaults still hold the old words; `init(tolerantRawValue:)` reads them (R-1).
///
/// `legacyTrashed` is **not a tier**: trashing a note moves it to `GTD/Trash/` (I4c, D41).
/// It exists only to read a `status: trash` line a pre-rework vault (or the user's own editing)
/// left in `Actions/`, so such a note is hidden rather than refused. It is deliberately **not**
/// in `allCases`, so no status picker ever offers it, and the reducer refuses a command that
/// would set it.
public enum ActionStatus: String, Sendable, CaseIterable, Codable, Hashable {
    case next
    case someday
    case inProgress = "in-progress"
    /// #87 — handed to an agent (an AI coding agent works on it). On the In progress board,
    /// never in Next, and it does **not** hold a cap slot: the person is not doing it.
    case agent
    /// #87 — the work waits for the person's input or review (an agent asked for it). On the
    /// In progress board, not in Next, and no cap slot until the person takes it back.
    case review
    case waiting
    case done
    case legacyTrashed = "trash"

    /// The statuses a user can choose (A3). `legacyTrashed` is read-only and stays out (R-1).
    public static var allCases: [ActionStatus] {
        [.next, .someday, .inProgress, .agent, .review, .waiting, .done]
    }

    /// #87 — the statuses of the In progress board, one column each, in column order.
    public static let boardStatuses: [ActionStatus] = [.inProgress, .agent, .review]

    /// True for the statuses the In progress board shows.
    public var isOnBoard: Bool { ActionStatus.boardStatuses.contains(self) }

    /// `next` and `in-progress` occupy a slot under the hard cap (ARCHITECTURE §6); `agent` and
    /// `review` do not (#87).
    /// A *hidden* (future-deferred) one does not — see `Rules.countsTowardCap(_:today:)` (R-2).
    public var countsTowardCap: Bool { self == .next || self == .inProgress }

    /// Done and legacy-trashed actions vanish from every list immediately (A5, R-1).
    public var isClosed: Bool { self == .done || self == .legacyTrashed }

    /// True for the states the user cannot pick (R-1).
    public var isUserSettable: Bool { self != .legacyTrashed }

    /// Tolerant read of a `status:` line (R-1). `backlog` and `maybe` are the pre-2026-09-21
    /// spellings of `someday`; nothing rewrites the file until the status really changes,
    /// because the encoder only patches lines whose *decoded* value differs.
    public init?(tolerantRawValue raw: String) {
        switch raw {
        case "backlog", "maybe": self = .someday
        default: self.init(rawValue: raw)
        }
    }

    /// The spellings a `status:` line may carry, for the codec's error message (R-1).
    public static let acceptedRawValues: [String] =
        ActionStatus.allCases.map(\.rawValue) + ["backlog", "maybe", ActionStatus.legacyTrashed.rawValue]
}

/// Project lifecycle (P3). Only `active` projects may put actions into Next.
public enum ProjectStatus: String, Sendable, CaseIterable, Codable, Hashable {
    case active
    case onHold = "on-hold"
    case someday
    case done
}

/// Time-estimate buckets shown as chips (I3). Chips write 10 / 30 / 60 / 90 minutes;
/// anything above 60 displays as "60+" (ARCHITECTURE §6).
public enum TimeBucket: Sendable, CaseIterable, Codable, Hashable {
    case upTo10
    case upTo30
    case upTo60
    case over60

    /// `nil` in ⇒ `nil` out: an undecided estimate has no bucket (no lying defaults).
    public init?(minutes: Int?) {
        guard let minutes, minutes > 0 else { return nil }
        switch minutes {
        case ...10: self = .upTo10
        case ...30: self = .upTo30
        case ...60: self = .upTo60
        default: self = .over60
        }
    }

    /// The value a chip writes to `timeEstimate`.
    public var minutes: Int {
        switch self {
        case .upTo10: 10
        case .upTo30: 30
        case .upTo60: 60
        case .over60: 90
        }
    }

    /// True when `minutes` of available time is enough for this bucket (Next-view filter, E1).
    public func fits(available: Int) -> Bool {
        switch self {
        case .upTo10: available >= 10
        case .upTo30: available >= 30
        case .upTo60: available >= 60
        case .over60: available > 60
        }
    }
}

/// How one routine step ended on one day (R5).
public enum RoutineStepResult: String, Sendable, CaseIterable, Codable, Hashable {
    case done
    case skipped
}
