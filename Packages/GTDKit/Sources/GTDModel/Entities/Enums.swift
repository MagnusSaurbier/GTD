import Foundation

/// Commitment tier and lifecycle of an action (A3). Raw values are what the frontmatter holds.
public enum ActionStatus: String, Sendable, CaseIterable, Codable, Hashable {
    case next
    case backlog
    case maybe
    case inProgress = "in-progress"
    case waiting
    case done
    case trash

    /// `next` and `in-progress` occupy a slot under the hard cap (ARCHITECTURE §6).
    public var countsTowardCap: Bool { self == .next || self == .inProgress }

    /// Done and trashed actions vanish from every list immediately (A5).
    public var isClosed: Bool { self == .done || self == .trash }
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
