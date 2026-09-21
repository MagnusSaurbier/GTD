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
            year: 2026, week: 38, page: .deckSomeday,
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

    /// T12 — a state written by the **pre-rework** build (before `feature/inbox-rework`'s deck
    /// merged Backlog and Maybe into one Someday phase) carried `page: "deckBacklogMaybe"`, which
    /// no longer exists on `ReviewPage`. Reconstructed from `git show 8fa4105:…ReviewSessionState.swift`
    /// — that build's fields are otherwise identical to today's, so this is a literal, faithful
    /// stored state, not an invented shape. It must not crash, and since the rename is
    /// unambiguous (the merged phase sat in the same position the new `deckSomeday` does), the
    /// review resumes exactly there rather than restarting the whole wizard — the sweep progress
    /// (`handledDeferred`) survives untouched.
    @Test func aPreReworkStoredStateMigratesTheRemovedDeckPhase() throws {
        let json = """
        {
          "year": 2026, "week": 37, "page": "deckBacklogMaybe",
          "review": {
            "wantedToAchieve": "", "achieved": "", "behaviorToChange": "", "whatToStop": "",
            "howIGrew": "", "howToGrowFurther": "", "whatToTry": "", "goalForNextWeek": ""
          },
          "systemsCheck": { "trust": "", "workload": "", "routines": "" },
          "systemFixNotes": [], "startedAt": 0,
          "handledDeferred": ["Inbox/2026-09-10 090000.md"],
          "handledWaiting": [], "handledStalled": [],
          "handledDeckCards": ["Actions/Already decided.md"],
          "inboxAtStart": 3,
          "changes": {
            "deferredHandled": 1, "waitingHandled": 0, "demoted": 0, "promoted": 0,
            "trashed": 0, "kept": 0, "projectsTouched": 0
          },
          "isSaved": false
        }
        """
        let state = try JSONDecoder().decode(ReviewSessionState.self, from: Data(json.utf8))
        #expect(state.page == .deckSomeday)                 // unambiguous rename, same position
        #expect(state.stage == .deck)
        // Never lost: the sweep's own progress from before the rework.
        #expect(state.handledDeferred == ["Inbox/2026-09-10 090000.md"])
        #expect(state.handledDeckCards == ["Actions/Already decided.md"])
        #expect(state.changes.deferredHandled == 1)
        #expect(state.year == 2026)
        #expect(state.week == 37)
    }

    /// Any other page value this build has never had (a hypothetical future removal, or a
    /// corrupted field) restarts the deck stage rather than crashing or discarding the whole
    /// state — the sweep progress still survives.
    @Test func anUnrecognisedPageRestartsTheDeckStageWithoutLosingSweepProgress() throws {
        let json = """
        {"year":2026,"week":37,"page":"deckSomethingThatNeverExisted","startedAt":0,
         "handledWaiting":["Actions/Chase this.md"]}
        """
        let state = try JSONDecoder().decode(ReviewSessionState.self, from: Data(json.utf8))
        #expect(state.page == .deckNext)
        #expect(state.handledWaiting == ["Actions/Chase this.md"])
    }

    /// The store's own `load()` never crashes or throws on a pre-rework file either — it is
    /// resumed, exactly as `aPreReworkStoredStateMigratesTheRemovedDeckPhase` decodes it.
    @Test func theFileStoreResumesAPreReworkStateInsteadOfDiscardingIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(FileReviewStateStore.defaultFileName)
        try Data("""
        {"year":2026,"week":37,"page":"deckBacklogMaybe","startedAt":0}
        """.utf8).write(to: url)

        let loaded = try #require(FileReviewStateStore(directory: directory).load())
        #expect(loaded.page == .deckSomeday)
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
