import Testing
import Foundation
@testable import DesignSystem

/// STYLEGUIDE §3.6 — axis lock, per-direction thresholds, rotation cap, and the fly-out offset.
/// Foundation-only, so it runs on Linux without a compiled SwiftUI gesture.
struct CardDragGeometryTests {
    private let geometry = CardDragGeometry(cardSize: CGSize(width: 360, height: 600))

    @Test func noDirectionBeforeTheAxisLocks() {
        // 8pt is under `DragThresholds.axisLock` (12pt) on both axes.
        #expect(geometry.direction(for: CGSize(width: 8, height: 4)) == nil)
        #expect(geometry.releaseDirection(for: CGSize(width: 8, height: 4)) == nil)
    }

    @Test func axisLocksToTheDominantDimension() {
        #expect(geometry.direction(for: CGSize(width: 200, height: 10)) == .right)
        #expect(geometry.direction(for: CGSize(width: -200, height: 10)) == .left)
        #expect(geometry.direction(for: CGSize(width: 10, height: -200)) == .up)
        #expect(geometry.direction(for: CGSize(width: 10, height: 200)) == .down)
        // Equal travel on both axes resolves to horizontal.
        #expect(geometry.direction(for: CGSize(width: 50, height: 50)) == .right)
    }

    @Test func horizontalThresholdIsThirtyFivePercentOfWidth() {
        // 34% of 360 = 122.4pt — just under threshold.
        #expect(geometry.releaseDirection(for: CGSize(width: 122, height: 0)) == nil)
        // 35% of 360 = 126pt — exactly at threshold.
        #expect(geometry.releaseDirection(for: CGSize(width: 126, height: 0)) == .right)
        #expect(geometry.releaseDirection(for: CGSize(width: -200, height: 0)) == .left)
    }

    @Test func upNeedsOnlyTwentyFivePercentOfHeightButTrashNeedsForty() {
        // 25% of 600 = 150pt is enough for an upward release.
        #expect(geometry.releaseDirection(for: CGSize(width: 0, height: -150)) == .up)
        #expect(geometry.releaseDirection(for: CGSize(width: 0, height: -100)) == nil)
        // Trash needs 40% of 600 = 240pt; 25% (150pt) is not enough.
        #expect(geometry.releaseDirection(for: CGSize(width: 0, height: 160)) == nil)
        #expect(geometry.releaseDirection(for: CGSize(width: 0, height: 240)) == .down)
    }

    @Test func rotationIsSignedAndCappedAtTheStyleguideMaximum() {
        #expect(geometry.rotation(for: .zero) == 0)
        let atThreshold = geometry.rotation(for: CGSize(width: 126, height: 0))
        #expect(atThreshold == DragThresholds.maxRotationDegrees)
        let beyond = geometry.rotation(for: CGSize(width: 300, height: 0))
        #expect(beyond == DragThresholds.maxRotationDegrees)
        let negative = geometry.rotation(for: CGSize(width: -126, height: 0))
        #expect(negative == -DragThresholds.maxRotationDegrees)
        // A pure vertical drag never rotates the card.
        #expect(geometry.rotation(for: CGSize(width: 0, height: -400)) == 0)
    }

    @Test func exitOffsetSendsTheCardWellPastEachEdge() {
        #expect(geometry.exitOffset(for: .right).width > geometry.cardSize.width)
        #expect(geometry.exitOffset(for: .left).width < -geometry.cardSize.width)
        #expect(geometry.exitOffset(for: .up).height < -geometry.cardSize.height)
        #expect(geometry.exitOffset(for: .down).height > geometry.cardSize.height)
        // Horizontal exits keep dy at 0 and vice versa, so the fly-out stays axis-aligned.
        #expect(geometry.exitOffset(for: .right).height == 0)
        #expect(geometry.exitOffset(for: .up).width == 0)
    }

    @Test func progressReachesOneExactlyAtTheThreshold() {
        #expect(geometry.progress(for: CGSize(width: 63, height: 0)) == 0.5)
        #expect(geometry.progress(for: CGSize(width: 126, height: 0)) == 1)
        #expect(geometry.hasCrossedThreshold(for: CGSize(width: 126, height: 0)))
        #expect(!geometry.hasCrossedThreshold(for: CGSize(width: 63, height: 0)))
    }

    @Test func degenerateCardSizeNeverCrashesOrFiles() {
        let empty = CardDragGeometry(cardSize: .zero)
        #expect(empty.releaseDirection(for: CGSize(width: 200, height: 0)) == nil)
        #expect(empty.rotation(for: CGSize(width: 200, height: 0)) == 0)
    }
}
