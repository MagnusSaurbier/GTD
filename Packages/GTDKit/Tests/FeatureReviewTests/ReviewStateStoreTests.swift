import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureReview

/// Device-local persistence of the wizard state (ARCHITECTURE §3 — never in the vault).
struct ReviewStateStoreTests {

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtd-review-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theStateRoundTripsThroughJSON() throws {
        var state = ReviewSessionState(
            year: 2026, week: 38, page: .deckBacklogMaybe,
            startedAt: Date(timeIntervalSince1970: 1_758_240_000))
        state.review.goalForNextWeek = "Letter submitted."
        state.systemsCheck.routines = "Bedtime is drifting."
        state.systemFixNotes = ["Decisions need their own place"]
        state.handledDeckCards = ["Actions/A.md", "Actions/B.md"]
        state.changes.demoted = 2
        state.inboxAtStart = 7

        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(ReviewSessionState.self, from: data) == state)
    }

    @Test func theFileStoreWritesReadsAndClears() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileReviewStateStore(directory: directory)

        #expect(store.load() == nil)

        var state = ReviewSessionState(
            year: 2026, week: 38, page: .systemsCheck, startedAt: Date(timeIntervalSince1970: 0))
        state.systemsCheck.trust = "Nothing slipped."
        store.save(state)

        // A fresh store over the same directory sees it — this is the relaunch case.
        #expect(FileReviewStateStore(directory: directory).load() == state)

        store.clear()
        #expect(store.load() == nil)
        store.clear()                                    // idempotent
    }

    /// A corrupt file means "no session in progress", never a half-restored wizard.
    @Test func aCorruptFileIsTreatedAsNoSession() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(FileReviewStateStore.defaultFileName)
        try Data("{ not json".utf8).write(to: url)

        #expect(FileReviewStateStore(directory: directory).load() == nil)
    }

    /// A state written before a field existed still decodes — the wizard must not lose a review
    /// because the app gained a counter.
    @Test func anOlderRecordDecodesWithDefaults() throws {
        let json = """
        {"year":2026,"week":38,"startedAt":0}
        """
        let state = try JSONDecoder().decode(ReviewSessionState.self, from: Data(json.utf8))
        #expect(state.page == .sweepInbox)
        #expect(state.systemFixNotes.isEmpty)
        #expect(state.changes == ReviewChanges())
        #expect(!state.isSaved)
    }

    @Test func theStageInitialiserLandsOnThatStagesFirstPage() {
        let state = ReviewSessionState(
            year: 2026, week: 38, stage: .deck, startedAt: Date(timeIntervalSince1970: 0))
        #expect(state.page == .deckNext)
        #expect(state.stage == .deck)
        #expect(state.isFor(year: 2026, week: 38))
        #expect(!state.isFor(year: 2026, week: 37))
    }

    @Test func changesCountEveryDeckChoice() {
        var changes = ReviewChanges()
        for choice in DeckChoice.allCases { changes.record(choice) }
        #expect(changes.kept == 1)
        #expect(changes.demoted == 1)
        #expect(changes.promoted == 1)
        #expect(changes.trashed == 1)
        #expect(changes.projectsTouched == 2)            // activate + drop
    }
}
