import Testing
import Foundation
import GTDModel
@testable import FeatureProjects

/// Pure index maths for the step checklist's drag + `⌥↑↓` reorder (P6). No SwiftUI, no `AppModel`.
struct StepReorderTests {
    private func steps(_ texts: String...) -> [ProjectStep] {
        texts.map { ProjectStep(text: $0) }
    }

    private func texts(_ steps: [ProjectStep]) -> [String] {
        steps.map(\.text)
    }

    // MARK: - move(from:to:)

    @Test func moveInteriorForward() {
        let result = StepReorder.move(steps("a", "b", "c", "d"), from: 0, to: 2)
        #expect(texts(result) == ["b", "c", "a", "d"])
    }

    @Test func moveInteriorBackward() {
        let result = StepReorder.move(steps("a", "b", "c", "d"), from: 3, to: 1)
        #expect(texts(result) == ["a", "d", "b", "c"])
    }

    @Test func moveToSameIndexIsANoOp() {
        let original = steps("a", "b", "c")
        #expect(StepReorder.move(original, from: 1, to: 1) == original)
    }

    @Test func moveClampsAnOutOfRangeDestination() {
        let result = StepReorder.move(steps("a", "b", "c"), from: 0, to: 99)
        #expect(texts(result) == ["b", "c", "a"])

        let resultNegative = StepReorder.move(steps("a", "b", "c"), from: 2, to: -5)
        #expect(texts(resultNegative) == ["c", "a", "b"])
    }

    @Test func moveWithAnOutOfRangeSourceIsANoOp() {
        let original = steps("a", "b")
        #expect(StepReorder.move(original, from: 5, to: 0) == original)
        #expect(StepReorder.move(original, from: -1, to: 0) == original)
    }

    @Test func moveOnASingleStepListIsANoOp() {
        let original = steps("only")
        #expect(StepReorder.move(original, from: 0, to: 0) == original)
    }

    // MARK: - moveUp / moveDown (⌥↑↓)

    @Test func moveUpSwapsWithThePreviousStep() {
        let result = StepReorder.moveUp(steps("a", "b", "c"), at: 1)
        #expect(result.map(texts) == ["b", "a", "c"])
    }

    @Test func moveUpAtTheTopBoundaryIsNil() {
        #expect(StepReorder.moveUp(steps("a", "b"), at: 0) == nil)
    }

    @Test func moveUpWithAnOutOfRangeIndexIsNil() {
        #expect(StepReorder.moveUp(steps("a", "b"), at: 5) == nil)
        #expect(StepReorder.moveUp(steps("a", "b"), at: -1) == nil)
    }

    @Test func moveDownSwapsWithTheNextStep() {
        let result = StepReorder.moveDown(steps("a", "b", "c"), at: 1)
        #expect(result.map(texts) == ["a", "c", "b"])
    }

    @Test func moveDownAtTheBottomBoundaryIsNil() {
        let last = steps("a", "b").count - 1
        #expect(StepReorder.moveDown(steps("a", "b"), at: last) == nil)
    }

    @Test func moveDownWithAnOutOfRangeIndexIsNil() {
        #expect(StepReorder.moveDown(steps("a", "b"), at: 5) == nil)
    }

    @Test func repeatedMoveUpWalksAStepToTheFront() {
        var current = steps("a", "b", "c", "d")
        var index = 3
        while index > 0, let moved = StepReorder.moveUp(current, at: index) {
            current = moved
            index -= 1
        }
        #expect(texts(current) == ["d", "a", "b", "c"])
    }

    // MARK: - move(fromOffsets:toOffset:) — drag reorder via `List.onMove`

    @Test func dragMoveMatchesArrayMoveSemantics() {
        // Moving the first item to the end: SwiftUI reports `toOffset` as the array's `count`
        // (post-removal insertion index), matching `Array.move(fromOffsets:toOffset:)` exactly.
        let result = StepReorder.move(steps("a", "b", "c"), fromOffsets: [0], toOffset: 3)
        #expect(texts(result) == ["b", "c", "a"])
    }

    @Test func dragMoveToTheFront() {
        let result = StepReorder.move(steps("a", "b", "c"), fromOffsets: [2], toOffset: 0)
        #expect(texts(result) == ["c", "a", "b"])
    }

    @Test func dragMoveIsEquivalentToSingleStepMoveUpDown() {
        let start = steps("a", "b", "c", "d")
        // `moveUp(at: 2)` == dragging index 2 to index 1.
        #expect(StepReorder.moveUp(start, at: 2).map(texts) == texts(StepReorder.move(start, fromOffsets: [2], toOffset: 1)))
    }
}
