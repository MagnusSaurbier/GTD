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

    /// T15 defect 9 — the inbox card's **value** chips (`DateValueChip`, `+ project`) are lower
    /// case per STYLEGUIDE §3.1/§3.5 (`+ defer` / `+ due` / `+ project`), unlike
    /// `unsetChipTitle`'s title-case `Area`/`Project` single-value chips in the Mac editor — the
    /// two were conflated and every value chip read `+ Defer` / `+ Due` / `+ Project` on screen.
    @Test func anUnsetValueChipTitleIsLowercasedNeverCarriesAPlusAndMatchesRegardlessOfInputCasing() {
        #expect(Copy.unsetValueChipTitle("Defer") == "defer")
        #expect(Copy.unsetValueChipTitle("+ Due") == "due")
        #expect(Copy.unsetValueChipTitle("+ + Project") == "project")
        #expect(Copy.unsetValueChipTitle("defer") == Copy.unsetValueChipTitle("Defer"))
        #expect(Copy.unsetValueChipTitle("") == "")
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
        #expect(Copy.lists == "Lists")
        #expect(Copy.list == "List")
    }

    /// T06 — R-3's validation flow (STYLEGUIDE §3.6): "every missing field or chip group shows a
    /// leading asterisk … until it is filled". VoiceOver must say the word, not just draw a glyph.
    @Test func requiredFieldLabelSpellsOutTheWord() {
        #expect(Copy.requiredFieldLabel(Copy.why) == "Why?, required")
        #expect(Copy.requiredFieldLabel("Context") == "Context, required")
    }

    /// STYLEGUIDE §6.3 canonical strings, word for word.
    @Test func canonicalStringsMatchTheStyleguideTable() {
        #expect(Copy.createProject("Renew passport") == "Create project \"Renew passport\"")
        #expect(Copy.alreadyUsedBy("Trash") == "Already used by Trash")
        #expect(Copy.addedTo("Read") == "Added to Read")
        #expect(Copy.notesPlaceholder == "Notes (optional)")
        #expect(Copy.setWaiting == "Set waiting")
    }

    /// §6.3's `Nothing in <list>` empty state, and Someday's own (`Nothing in Someday` is listed
    /// separately in the table, so it is its own constant rather than `emptyListTitle(someday)`).
    @Test func emptyStatesNameTheirScreen() {
        #expect(Copy.emptySomedayTitle == "Nothing in Someday")
        #expect(Copy.emptyListTitle("Read") == "Nothing in Read")
        #expect(Copy.emptyListTitle("Watch") == "Nothing in Watch")
    }

    /// §3.10 — the Someday deck header's stale count. Break-proof: a naive implementation that
    /// always used the plural ("1 untouched > 30 days" vs "1 untouched...") would fail this.
    @Test func untouchedOver30DaysIsPluralisedCorrectly() {
        #expect(Copy.untouchedOver30Days(1) == "1 untouched > 30 days")
        #expect(Copy.untouchedOver30Days(0) == "0 untouched > 30 days")
        #expect(Copy.untouchedOver30Days(7) == "7 untouched > 30 days")
        #expect(Copy.untouchedOver30Days(1) != Copy.untouchedOver30Days(2))
    }

    /// No Backlog/Maybe wording anywhere in the fixed vocabulary or canonical strings (§6.2:
    /// "Never: … Backlog, Maybe …").
    @Test func noLegacyTierWordingRemains() {
        let mirror = [
            Copy.inbox, Copy.next, Copy.someday, Copy.waiting, Copy.project, Copy.projects,
            Copy.area, Copy.knowledge, Copy.trash, Copy.lists, Copy.list, Copy.actionKind,
            Copy.knowledgeOrList,
        ]
        for word in mirror {
            #expect(!word.lowercased().contains("backlog"))
            #expect(!word.lowercased().contains("maybe"))
        }
    }
}
