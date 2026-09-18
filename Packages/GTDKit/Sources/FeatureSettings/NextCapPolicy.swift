import Foundation

/// The Next-cap stepper's warning threshold (A3, A4). `GTDConfig.default.nextCap` (15) is the
/// recommended ceiling for a focused Next list; raising it is legal (the reducer only rejects
/// `<= 0`, see `Reducer.updateConfig`) but the UI should say so.
public enum NextCapPolicy {
    public static let recommended = 15
    public static let minimum = 1

    /// True once the cap is raised past the recommendation — the stepper shows a quiet warning,
    /// never blocks it (STYLEGUIDE #2: nothing shouts unless it matters).
    public static func showsRaisedWarning(_ cap: Int) -> Bool { cap > recommended }
}
