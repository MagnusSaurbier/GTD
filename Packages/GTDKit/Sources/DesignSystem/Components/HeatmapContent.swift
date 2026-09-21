import Foundation

/// One heatmap cell's state (STYLEGUIDE §3.10). `.noData` predates the routine or the log file
/// for that day is missing — never conflated with a deliberate skip.
///
/// Platform-free on purpose: `RoutineHeatmap` draws it, and the words VoiceOver reads for a whole
/// row are built here, where they can be unit-tested on Linux (ARCHITECTURE §5).
public enum HeatmapCellState: Sendable, Equatable {
    case done, skipped, noData
}

/// What VoiceOver says about one heatmap row.
///
/// The grid is the only place in the app where a week of results is carried by position and fill
/// alone, so it is also the only place that has to spell the week out to satisfy "colour is never
/// the only carrier" (STYLEGUIDE §1.6, §8).
public enum HeatmapSpeech {
    /// `done Mon, Tue; skipped Wed; nothing logged Thu, Fri` — the three groups in that order,
    /// empty groups omitted. Days with no entry are named as such rather than read as skips.
    public static func week(_ cells: [HeatmapCellState], columnLabels: [String]) -> String {
        func days(_ state: HeatmapCellState) -> [String] {
            cells.enumerated().compactMap { index, cell in
                guard cell == state else { return nil }
                return index < columnLabels.count ? columnLabels[index] : "day \(index + 1)"
            }
        }
        let groups: [(String, [String])] = [
            ("done", days(.done)),
            ("skipped", days(.skipped)),
            ("nothing logged", days(.noData)),
        ]
        let spoken = groups
            .filter { !$0.1.isEmpty }
            .map { "\($0.0) \($0.1.joined(separator: ", "))" }
        return spoken.isEmpty ? "no days" : spoken.joined(separator: "; ")
    }
}
