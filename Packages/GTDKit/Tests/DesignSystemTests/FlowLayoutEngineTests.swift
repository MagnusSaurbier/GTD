import Testing
import Foundation
@testable import DesignSystem

/// STYLEGUIDE §3.1 — chips "wrap lines, `chipGap` both ways". Exercises the pure algorithm
/// behind the SwiftUI `FlowLayout`, which cannot itself run outside a SwiftUI host.
struct FlowLayoutEngineTests {
    @Test func itemsThatFitStayOnOneRow() {
        let sizes = [CGSize(width: 40, height: 20), CGSize(width: 40, height: 20), CGSize(width: 40, height: 20)]
        let result = FlowLayoutEngine.layout(sizes: sizes, maxWidth: 200, spacing: 8)
        #expect(result.placements.map(\.row) == [0, 0, 0])
        // 40 + 8 + 40 + 8 + 40 = 136
        #expect(result.size.width == 136)
        #expect(result.size.height == 20)
    }

    @Test func anItemThatDoesNotFitWrapsToTheNextRow() {
        let sizes = [CGSize(width: 100, height: 20), CGSize(width: 100, height: 20), CGSize(width: 100, height: 20)]
        // 100 + 8 + 100 = 208 fits in 220; a third 100 does not (208 + 8 + 100 = 316 > 220).
        let result = FlowLayoutEngine.layout(sizes: sizes, maxWidth: 220, spacing: 8)
        #expect(result.placements.map(\.row) == [0, 0, 1])
        #expect(result.placements[2].position == CGPoint(x: 0, y: 28)) // 20 + spacing(8)
    }

    @Test func aSingleItemWiderThanMaxWidthStillPlacesAlone() {
        let sizes = [CGSize(width: 500, height: 20)]
        let result = FlowLayoutEngine.layout(sizes: sizes, maxWidth: 200, spacing: 8)
        #expect(result.placements.count == 1)
        #expect(result.placements[0].row == 0)
    }

    @Test func rowHeightIsTheTallestItemAndShorterItemsAreCentered() {
        let sizes = [CGSize(width: 40, height: 20), CGSize(width: 40, height: 34)]
        let result = FlowLayoutEngine.layout(sizes: sizes, maxWidth: 200, spacing: 8)
        #expect(result.placements.map(\.row) == [0, 0])
        #expect(result.size.height == 34)
        // The 20pt-tall chip is vertically centered within the 34pt row: (34 - 20) / 2 = 7.
        #expect(result.placements[0].position.y == 7)
        #expect(result.placements[1].position.y == 0)
    }

    @Test func infiniteWidthNeverWraps() {
        let sizes = (0..<10).map { _ in CGSize(width: 100, height: 20) }
        let result = FlowLayoutEngine.layout(sizes: sizes, maxWidth: .infinity, spacing: 8)
        #expect(result.placements.allSatisfy { $0.row == 0 })
    }

    @Test func emptyInputProducesNoPlacementsAndZeroSize() {
        let result = FlowLayoutEngine.layout(sizes: [], maxWidth: 200, spacing: 8)
        #expect(result.placements.isEmpty)
        #expect(result.size == .zero)
    }

    @Test func widthIsCappedAtMaxWidthEvenWhenARowIsNarrower() {
        let sizes = [CGSize(width: 40, height: 20)]
        let result = FlowLayoutEngine.layout(sizes: sizes, maxWidth: 200, spacing: 8)
        #expect(result.size.width == 40)
    }
}
