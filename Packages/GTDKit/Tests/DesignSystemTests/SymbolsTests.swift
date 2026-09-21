import Testing
@testable import DesignSystem

/// STYLEGUIDE §7 — the icon map, and specifically `Symbols.list(named:)` (T06): the three named
/// lists get their own glyph, any custom list falls back to `list.bullet`.
struct SymbolsTests {

    @Test func namedListsGetTheirOwnGlyph() {
        #expect(Symbols.list(named: "Read") == Symbols.listRead)
        #expect(Symbols.list(named: "Watch") == Symbols.listWatch)
        #expect(Symbols.list(named: "Wish") == Symbols.listWish)
    }

    /// Case-insensitive, matching how `GTDList.sameName` compares list names (L2).
    @Test func matchingIsCaseInsensitive() {
        #expect(Symbols.list(named: "read") == Symbols.listRead)
        #expect(Symbols.list(named: "READ") == Symbols.listRead)
    }

    /// Break-proof: a lookup that only matched the three named lists and crashed or returned ""
    /// for anything else would fail this — the fallback must always be `list.bullet`.
    @Test func aCustomListFallsBackToListBullet() {
        #expect(Symbols.list(named: "Groceries") == Symbols.listBullet)
        #expect(Symbols.list(named: "") == Symbols.listBullet)
        #expect(Symbols.listBullet == "list.bullet")
    }

    @Test func makeActionSharesThePromoteStepGlyph() {
        // STYLEGUIDE §7 lists "Promote step / Make action" as one table entry.
        #expect(Symbols.makeAction == Symbols.promoteStep)
    }
}
