import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
import DesignSystem
@testable import FeatureNext

/// #87 — the In progress board: three columns, context and project filters, card moves.
@MainActor
struct InProgressBoardModelTests {

    private func makeModel(snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        let backend = InMemoryBackend(
            snapshot: snapshot,
            deviceID: "test",
            env: { Fixtures.reducerEnv(deviceID: "test") })
        return AppModel(backend: backend, snapshot: snapshot, today: { Fixtures.today })
    }

    @Test func theBoardHasItsThreeColumnsInOrder() {
        let board = InProgressBoardModel(model: makeModel())
        #expect(board.columns.map(\.status) == [.inProgress, .agent, .review])
        #expect(board.columns.map(\.title) == ["In progress", "Agent", "Review"])
        #expect(board.columns.map(\.destination) == [.inProgress, .agent, .review])
        #expect(board.columns.map(\.actions.count) == [2, 1, 1])
        #expect(!board.isEmpty)
        #expect(!board.isFiltered)
        #expect(board.projectFilterTitle == "All projects")
    }

    @Test func contextFilterNarrowsEveryColumnAndKeepsThemAll() {
        let board = InProgressBoardModel(model: makeModel())
        board.toggleContext("errands")
        #expect(board.isFiltered)
        #expect(board.columns.count == 3)
        #expect(board.columns.map(\.actions.count) == [1, 0, 0])
        board.toggleContext("errands")
        #expect(!board.isFiltered)
    }

    @Test func projectFilterNarrowsAndNamesTheProject() {
        let board = InProgressBoardModel(model: makeModel())
        #expect(Set(board.availableProjects.map(\.id))
            == [Fixtures.daadProject.id, Fixtures.thesisProject.id])
        board.setProject(Fixtures.daadProject.id)
        #expect(board.projectFilterTitle == Fixtures.daadProject.title)
        #expect(board.columns.flatMap(\.actions).allSatisfy { $0.project == Fixtures.daadProject.id })
        #expect(board.columns.map(\.actions.count) == [1, 0, 1])
        board.clearFilters()
        #expect(board.project == nil)
        #expect(board.contexts.isEmpty)
    }

    /// A chosen project stays offered after its last card left the board — otherwise the
    /// person could not see (or lift) the filter that hides everything.
    @Test func aChosenProjectStaysOfferedWhenNoCardNamesItAnyMore() {
        let board = InProgressBoardModel(model: makeModel())
        board.setProject(Fixtures.flatProject.id)
        #expect(board.isEmpty)
        #expect(board.emptyStateTitle == Copy.emptyNextFilteredTitle)
        #expect(board.emptyStateBody == Copy.emptyBoardFilteredBody)
        #expect(board.availableProjects.map(\.id).contains(Fixtures.flatProject.id))
    }

    @Test func anEmptyVaultShowsTheEmptyBoard() {
        let board = InProgressBoardModel(model: makeModel(snapshot: .empty))
        #expect(board.isEmpty)
        #expect(board.emptyStateTitle == Copy.emptyBoardTitle)
        #expect(board.availableProjects.isEmpty)
    }

    @Test func aCardMovesToTheOtherTwoColumns() throws {
        let board = InProgressBoardModel(model: makeModel())
        let card = try #require(board.columns[1].actions.first)
        #expect(board.moveTargets(for: card) == [.inProgress, .review])
        #expect(InProgressBoardModel.destination(for: .review) == .review)
        #expect(InProgressBoardModel.destination(for: .next) == nil)
    }

    /// Moving a card changes its status — the board follows the snapshot.
    @Test func aStatusChangeMovesTheCard() async throws {
        let model = makeModel()
        let board = InProgressBoardModel(model: model)
        let card = try #require(board.columns[1].actions.first)
        try await model.send(.setStatus(card.id, .review, waiting: nil))
        #expect(board.columns.map(\.actions.count) == [2, 0, 2])
        #expect(board.columns[2].actions.contains { $0.id == card.id })
    }
}
