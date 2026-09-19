import Testing
import Foundation
@testable import DesignSystem

/// Wording the 2026-09-19 walkthrough found wrong on screen (P4, P15, M9). The views cannot be
/// compiled on Linux, so the strings they draw are pinned here.
struct CopyWordingTests {

    /// P4 — the unset chip draws a `plus` symbol, so its title must not carry a second "+".
    @Test func anUnsetChipTitleNeverCarriesALiteralPlus() {
        #expect(Copy.unsetChipTitle("Defer") == "Defer")
        #expect(Copy.unsetChipTitle("+ Due") == "Due")
        #expect(Copy.unsetChipTitle("+ + project") == "Project")
    }

    /// P4 — "Defer" in the detail, "defer" on the card: one casing everywhere.
    @Test func anUnsetChipTitleIsCapitalisedTheSameEverywhere() {
        #expect(Copy.unsetChipTitle("defer") == Copy.unsetChipTitle("Defer"))
        #expect(Copy.unsetChipTitle("follow-up") == "Follow-up")
        #expect(Copy.unsetChipTitle("") == "")
    }

    /// M9 — "1 steps left".
    @Test func stepsLeftIsPluralised() {
        #expect(Copy.stepsLeft(0) == "0 steps left")
        #expect(Copy.stepsLeft(1) == "1 step left")
        #expect(Copy.stepsLeft(5) == "5 steps left")
        #expect(Copy.projectCounts(active: 2, remainingSteps: 1) == "2 active · 1 step left")
    }

    /// P15 — list screens are titled in the plural; the singular stays for one item / the field.
    @Test func listScreensUseThePlural() {
        #expect(Copy.projects == "Projects")
        #expect(Copy.routines == "Routines")
        #expect(Copy.project == "Project")
        #expect(Copy.routine == "Routine")
    }
}
