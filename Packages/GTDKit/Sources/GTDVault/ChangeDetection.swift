import Foundation

/// Time, injected. Tests drive `DebounceState` directly and never sleep; the few tests that do
/// exercise `ChangeDebouncer` end to end shorten the intervals instead of faking the clock.
public protocol VaultClock: Sendable {
    func now() -> Date
    func sleep(seconds: TimeInterval) async throws
}

public struct SystemVaultClock: VaultClock {
    public init() {}
    public func now() -> Date { Date() }

    public func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// The debounce *decision*, as a pure value.
///
/// A vault sync delivers dozens of file events in a burst; re-indexing on each one would make the
/// app stutter and could publish a snapshot of a half-arrived sync. So a burst is coalesced:
/// fire `interval` after the last signal, but never later than `maxDelay` after the first, so a
/// continuous trickle of events still produces snapshots.
public struct DebounceState: Sendable, Equatable {
    /// Quiet period after the last change. Default: 300 ms.
    public var interval: TimeInterval
    /// Ceiling on coalescing, so a continuous stream still updates the UI.
    public var maxDelay: TimeInterval

    public private(set) var firstSignal: Date?
    public private(set) var lastSignal: Date?

    public init(interval: TimeInterval = 0.3, maxDelay: TimeInterval = 2.0) {
        self.interval = interval
        self.maxDelay = maxDelay
    }

    public static let `default` = DebounceState()

    public var isPending: Bool { firstSignal != nil }

    public mutating func signal(at now: Date) {
        if firstSignal == nil { firstSignal = now }
        lastSignal = now
    }

    /// When the pending burst should be handled, or `nil` when nothing is pending.
    public var deadline: Date? {
        guard let firstSignal, let lastSignal else { return nil }
        return min(lastSignal.addingTimeInterval(interval),
                   firstSignal.addingTimeInterval(maxDelay))
    }

    public func shouldFire(at now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// Seconds to wait before checking again; `nil` when nothing is pending.
    public func wait(from now: Date) -> TimeInterval? {
        deadline.map { max(0, $0.timeIntervalSince(now)) }
    }

    public mutating func reset() {
        firstSignal = nil
        lastSignal = nil
    }
}

/// Drives `DebounceState` with a clock and runs `action` once per burst.
///
/// Serial by construction: the action never runs concurrently with itself, and signals that
/// arrive while it runs start the next burst rather than being dropped.
public actor ChangeDebouncer {
    private var state: DebounceState
    private let clock: any VaultClock
    private let action: @Sendable () async -> Void
    private var worker: Task<Void, Never>?
    /// Bumped on every cancel, so a worker that is on its way out cannot clear a newer one.
    private var generation = 0

    public init(
        state: DebounceState = .default,
        clock: any VaultClock = SystemVaultClock(),
        action: @escaping @Sendable () async -> Void
    ) {
        self.state = state
        self.clock = clock
        self.action = action
    }

    public func signal() {
        state.signal(at: clock.now())
        guard worker == nil else { return }
        let mine = generation
        worker = Task { [weak self] in await self?.drain(generation: mine) }
    }

    public func cancel() {
        worker?.cancel()
        worker = nil
        generation += 1
        state.reset()
    }

    /// For tests: waits until the pending burst (if any) has been handled.
    public func drainForTesting() async {
        let pending = worker
        await pending?.value
    }

    private func drain(generation mine: Int) async {
        while !Task.isCancelled {
            guard let wait = state.wait(from: clock.now()) else { break }
            if wait > 0 {
                do { try await clock.sleep(seconds: wait) } catch { break }
            }
            guard !Task.isCancelled else { break }
            guard state.shouldFire(at: clock.now()) else { continue }
            state.reset()
            await action()
        }
        if generation == mine { worker = nil }
    }
}
