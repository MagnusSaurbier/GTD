import Foundation
import Observation
import GTDModel
import GTDAppCore
import DesignSystem

/// One inbox-processing session: LIFO queue, one card at a time, no skipping (I1).
/// Plain and unit-testable — **no SwiftUI**. Owned by T20.
@MainActor
@Observable
public final class InboxSession {
    public private(set) var queue: [InboxItem]
    public private(set) var processed: Int
    /// The card being worked on, or `nil` when the session is finished (inbox zero).
    public var current: InboxItem? { queue.first }

    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
        self.queue = Rules.inboxQueue(model.snapshot)
        self.processed = 0
    }

    /// `3 of 14 left` (STYLEGUIDE §6.3).
    public var counter: String {
        Copy.counter(remaining: queue.count, total: queue.count + processed)
    }

    /// New captures that arrived mid-session go on top (LIFO, I7).
    public func refresh() {
        let seen = Set(queue.map(\.id))
        let fresh = Rules.inboxQueue(model.snapshot).filter { !seen.contains($0.id) }
        queue = fresh + queue.filter { item in
            model.snapshot.inbox.contains { $0.id == item.id && $0.reviewReason == nil }
        }
    }

    /// Files the current card. Rethrows `GTDError` so the UI can present the cap or waiting sheet.
    public func file(_ decision: InboxDecision) async throws {
        guard let item = current else { return }
        try await model.send(.fileInbox(item.id, decision))
        queue.removeFirst()
        processed += 1
    }

    public func deferToReview(reason: String) async throws {
        guard let item = current else { return }
        try await model.send(.deferInboxToReview(item.id, reason: reason))
        queue.removeFirst()
        processed += 1
    }

    /// Undo the last card; it comes back at the head of the queue (I6).
    public func undo() async {
        await model.undo()
        refresh()
        processed = max(processed - 1, 0)
    }
}
