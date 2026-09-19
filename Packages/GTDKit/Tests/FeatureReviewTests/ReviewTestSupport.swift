import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
@testable import FeatureReview

/// Shared fixtures for the weekly-review suite. Everything is anchored on `Fixtures.today`
/// (2026-09-19, a Saturday in ISO week 38) with `Fixtures.calendar`, so nothing here depends on
/// the machine's clock or time zone.
@MainActor
enum ReviewTest {
    static var today: Day { Fixtures.today }
    static var week: ISOWeekTuple { ISOWeekTuple(Fixtures.today.isoWeek) }

    static func model(_ snapshot: VaultSnapshot = Fixtures.sampleSnapshot) -> AppModel {
        AppModel(
            backend: InMemoryBackend(snapshot: snapshot, deviceID: "test", env: { Fixtures.reducerEnv() }),
            snapshot: snapshot,
            today: { Fixtures.today })
    }

    @discardableResult
    static func session(
        _ snapshot: VaultSnapshot = Fixtures.sampleSnapshot,
        store: InMemoryReviewStateStore = InMemoryReviewStateStore(),
        model: AppModel? = nil
    ) -> ReviewSession {
        ReviewSession(
            model: model ?? ReviewTest.model(snapshot),
            store: store,
            now: { Fixtures.date(Fixtures.today, 9, 0) },
            calendar: Fixtures.calendar)
    }

    /// A snapshot whose processing queue is empty, so the sweep's inbox gate is open. The one
    /// item deferred to the review is deliberately kept.
    static var inboxZero: VaultSnapshot {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.inbox = snapshot.inbox.filter { $0.reviewReason != nil }
        return snapshot
    }

    /// A snapshot over the Next cap — only reachable by hand-editing files, and exactly what the
    /// deck's gate exists for.
    static func overCap(by extra: Int) -> VaultSnapshot {
        var snapshot = inboxZero
        for index in 0..<extra {
            snapshot.actions.append(Action(
                id: NoteID(path: "Actions/Over cap \(index).md"),
                title: "Over cap \(index)",
                status: .next,
                created: Fixtures.date(Fixtures.day(-3), 9, 0),
                modified: Fixtures.date(Fixtures.day(-3), 9, 0),
                what: "Something"))
        }
        return snapshot
    }

    /// Advances the wizard until it reaches `page` or a gate refuses to let it move.
    static func walk(_ session: ReviewSession, to page: ReviewPage) {
        for _ in 0..<ReviewPage.allCases.count where session.page != page {
            let before = session.page
            session.advance()
            if session.page == before { return }
        }
    }

    static func state(
        page: ReviewPage = .sweepInbox,
        year: Int? = nil,
        week: Int? = nil
    ) -> ReviewSessionState {
        let iso = Fixtures.today.isoWeek
        return ReviewSessionState(
            year: year ?? iso.year,
            week: week ?? iso.week,
            page: page,
            startedAt: Fixtures.date(Fixtures.today, 9, 0))
    }
}

/// `Day.isoWeek` returns a tuple, which cannot be stored; this is the storable form the tests use.
struct ISOWeekTuple: Equatable {
    let year: Int
    let week: Int
    init(_ tuple: (year: Int, week: Int)) {
        year = tuple.year
        week = tuple.week
    }
}
