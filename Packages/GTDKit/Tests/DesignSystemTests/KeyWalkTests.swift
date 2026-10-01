import Testing
@testable import DesignSystem

/// The pure keyboard walk every walked screen shares (#65, #77): rows of stops, `Tab`/`⇧Tab`
/// wrapping inside a row, `⌘↩` on to the next non-empty row, a shrinking row pulling it back.
struct KeyWalkTests {

    @Test func theWalkStartsOnTheFirstNonEmptyRow() {
        #expect(KeyWalk.first(in: [0, 3, 1]) == KeyWalk(row: 1, index: 0))
        #expect(KeyWalk.first(in: [0, 0]) == nil)
        #expect(KeyWalk.first(in: []) == nil)
    }

    @Test func tabAndShiftTabWrapInsideTheRow() {
        let rows = [4]
        #expect(KeyWalk().moved(by: 1, in: rows) == KeyWalk(index: 1))
        #expect(KeyWalk().moved(by: -1, in: rows) == KeyWalk(index: 3), "⇧Tab from the first wraps")
        #expect(KeyWalk(index: 3).moved(by: 1, in: rows) == KeyWalk(index: 0))
    }

    @Test func commandReturnSkipsEmptyRowsAndStopsOnTheLast() {
        let rows = [2, 0, 3, 1]
        var walk = KeyWalk(row: 0, index: 1)
        #expect(walk.hasNextRow(in: rows))
        walk = walk.advanced(in: rows)
        #expect(walk == KeyWalk(row: 2, index: 0), "the empty row is skipped, the index resets")
        walk = walk.advanced(in: rows)
        #expect(walk == KeyWalk(row: 3, index: 0))
        #expect(!walk.hasNextRow(in: rows))
        #expect(walk.advanced(in: rows) == walk, "the last row keeps the highlight")
    }

    @Test func aShrunkRowPullsTheHighlightBack() {
        #expect(KeyWalk(row: 0, index: 7).clamped(in: [3]) == KeyWalk(row: 0, index: 2))
        #expect(KeyWalk(row: 1, index: 2).clamped(in: [2, 0, 1]) == KeyWalk(row: 2, index: 0),
                "an emptied row hands over to the next one")
        #expect(KeyWalk(row: 2, index: 0).clamped(in: [2, 1, 0]) == KeyWalk(row: 1, index: 0),
                "… or, at the end, to the one before")
        #expect(KeyWalk(row: 5).clamped(in: [1, 1]) == KeyWalk(row: 1, index: 0))
        #expect(KeyWalk().clamped(in: [0]) == nil)
    }

    @Test func aScreenFindsItsStopAndAClickFindsItsPosition() {
        let rows = [["a"], [], ["b", "c"]]
        #expect(KeyWalk(row: 2, index: 1).stop(in: rows) == "c")
        #expect(KeyWalk(row: 1).stop(in: rows) == "b", "clamped first")
        #expect(KeyWalk.position(of: "c", in: rows) == KeyWalk(row: 2, index: 1))
        #expect(KeyWalk.position(of: "z", in: rows) == nil)
        #expect(KeyWalk(row: 2, index: 1).highlight(inRow: 2) == 1)
        #expect(KeyWalk(row: 2, index: 1).highlight(inRow: 0) == nil)
    }

    @Test func theLegendNamesTheWalkingKeys() {
        #expect(KeyWalkLegend.string(press: Copy.walkChoose, hasNextRow: true, back: Copy.cancel)
            == "Tab ⇧Tab Move · ↩ Choose · ⌘↩ Next row · Esc Cancel")
        #expect(KeyWalkLegend.string(press: Copy.walkChoose, hasNextRow: false, back: nil)
            == "Tab ⇧Tab Move · ↩ Choose")
    }
}
