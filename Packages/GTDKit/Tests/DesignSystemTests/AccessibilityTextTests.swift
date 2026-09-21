import Testing
import Foundation
@testable import DesignSystem

/// STYLEGUIDE §8 — the words VoiceOver reads for the two components that would otherwise carry
/// their meaning by colour and position alone (T41 deliverable 6).
///
/// The views themselves cannot be compiled here (no SwiftUI on Linux), so the *wording* lives
/// outside the platform guard and is pinned here instead.
struct AccessibilityTextTests {

    // MARK: - Routine heatmap (§3.10, R5)

    private let week = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    @Test func aHeatmapRowSpellsOutTheWholeWeek() {
        let cells: [HeatmapCellState] =
            [.done, .done, .skipped, .noData, .done, .noData, .noData]
        #expect(HeatmapSpeech.week(cells, columnLabels: week)
            == "done Mon, Tue, Fri; skipped Wed; nothing logged Thu, Sat, Sun")
    }

    /// A day with no entry is never read as a skip — the two mean different things (R5).
    @Test func missingDaysAreNamedAsMissingNotAsSkipped() {
        let value = HeatmapSpeech.week([.noData, .skipped], columnLabels: week)
        #expect(value.contains("nothing logged Mon"))
        #expect(value.contains("skipped Tue"))
    }

    @Test func groupsThatAreEmptyAreLeftOut() {
        #expect(HeatmapSpeech.week([.done, .done], columnLabels: week) == "done Mon, Tue")
        #expect(HeatmapSpeech.week([], columnLabels: week) == "no days")
    }

    /// The heatmap is 7 columns by contract, but a caller that passes fewer labels than cells
    /// must still produce speech rather than crash.
    @Test func moreCellsThanColumnLabelsStillReads() {
        #expect(HeatmapSpeech.week([.done, .done], columnLabels: ["Mon"]) == "done Mon, day 2")
    }

    // MARK: - Row metadata (§3.3)

    @Test func theMetaLineUsesMiddleDotsAndVoiceOverUsesCommas() {
        let parts = ["DAAD", "mac", "phone", "≤30 min"]
        #expect(Copy.metaLine(parts) == "DAAD · mac · phone · ≤30 min")
        #expect(Copy.spoken(parts) == "DAAD, mac, phone, ≤30 min")
    }

    /// §1 "no lying defaults": a value that is not there is left out of both forms, never
    /// spoken as "no project".
    @Test func absentValuesAreOmittedFromSpokenText() {
        #expect(Copy.spoken(["Call the bank", "", "calls"]) == "Call the bank, calls")
        #expect(Copy.metaLine([]) == "")
        #expect(Copy.spoken([]) == "")
    }
}
