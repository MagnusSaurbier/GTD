import Foundation
import Testing
@testable import GTDVault

@Suite("Debounce decision (pure — no sleeping)")
struct DebounceStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func nothingPendingMeansNoDeadline() {
        let state = DebounceState()
        #expect(state.deadline == nil)
        #expect(state.wait(from: t0) == nil)
        #expect(!state.shouldFire(at: t0))
        #expect(!state.isPending)
    }

    @Test func firesOneIntervalAfterTheLastSignal() {
        var state = DebounceState(interval: 0.3, maxDelay: 2)
        state.signal(at: t0)
        #expect(state.deadline == t0.addingTimeInterval(0.3))
        #expect(!state.shouldFire(at: t0.addingTimeInterval(0.29)))
        #expect(state.shouldFire(at: t0.addingTimeInterval(0.3)))
    }

    @Test func aBurstIsCoalescedIntoOneFire() {
        var state = DebounceState(interval: 0.3, maxDelay: 2)
        for tick in stride(from: 0.0, through: 0.5, by: 0.1) {
            state.signal(at: t0.addingTimeInterval(tick))
        }
        // 200 sync events later, still one deadline: 0.3 s after the last of them.
        #expect(state.deadline == t0.addingTimeInterval(0.8))
    }

    @Test func maxDelayStopsAContinuousTrickleFromStarvingTheUI() {
        var state = DebounceState(interval: 0.3, maxDelay: 2)
        for tick in stride(from: 0.0, through: 5.0, by: 0.1) {
            state.signal(at: t0.addingTimeInterval(tick))
        }
        #expect(state.deadline == t0.addingTimeInterval(2))
        #expect(state.shouldFire(at: t0.addingTimeInterval(2)))
    }

    @Test func resetClearsThePendingBurst() {
        var state = DebounceState()
        state.signal(at: t0)
        state.reset()
        #expect(state.deadline == nil)
        #expect(!state.isPending)
    }

    @Test func waitIsNeverNegative() {
        var state = DebounceState(interval: 0.3)
        state.signal(at: t0)
        #expect(state.wait(from: t0.addingTimeInterval(10)) == 0)
    }

    @Test func theDefaultIs300msAsTheBriefRequires() {
        #expect(DebounceState.default.interval == 0.3)
    }
}

/// Counts how often the debounced action ran.
private actor Counter {
    var value = 0
    func increment() { value += 1 }
}

@Suite("ChangeDebouncer end to end (short real intervals)")
struct ChangeDebouncerTests {

    @Test func aBurstOfSignalsRunsTheActionOnce() async {
        let counter = Counter()
        let debouncer = ChangeDebouncer(state: DebounceState(interval: 0.02, maxDelay: 0.2)) {
            await counter.increment()
        }
        for _ in 0..<20 { await debouncer.signal() }
        await debouncer.drainForTesting()
        #expect(await counter.value == 1)
    }

    @Test func signalsAfterARunStartTheNextBurst() async {
        let counter = Counter()
        let debouncer = ChangeDebouncer(state: DebounceState(interval: 0.01, maxDelay: 0.1)) {
            await counter.increment()
        }
        await debouncer.signal()
        await debouncer.drainForTesting()
        await debouncer.signal()
        await debouncer.drainForTesting()
        #expect(await counter.value == 2)
    }

    @Test func cancelStopsAPendingBurst() async {
        let counter = Counter()
        let debouncer = ChangeDebouncer(state: DebounceState(interval: 5, maxDelay: 10)) {
            await counter.increment()
        }
        await debouncer.signal()
        await debouncer.cancel()
        #expect(await counter.value == 0)
    }
}

@Suite("PollingVaultWatcher — the Linux and safety-net mechanism")
struct PollingVaultWatcherTests {

    @Test func reportsAChangeOnlyWhenTheListingDiffers() throws {
        let fs = InMemoryFileSystem(files: ["Actions/A.md": "one"])
        let watcher = PollingVaultWatcher(fileSystem: fs, interval: 60)
        watcher.start(onChange: {})
        defer { watcher.stop() }

        #expect(watcher.pollDidChange() == false)
        fs.writeIgnoringFailures("two", to: "Actions/A.md")
        #expect(watcher.pollDidChange() == true)
        #expect(watcher.pollDidChange() == false)
    }

    @Test func noticesAddedAndRemovedFiles() throws {
        let fs = InMemoryFileSystem(files: ["Actions/A.md": "one"])
        let watcher = PollingVaultWatcher(fileSystem: fs, interval: 60)
        watcher.start(onChange: {})
        defer { watcher.stop() }

        fs.writeIgnoringFailures("new", to: "Actions/B.md")
        #expect(watcher.pollDidChange() == true)
        try fs.move("Actions/B.md", to: "GTD/Trash/B.md")
        #expect(watcher.pollDidChange() == true)
    }

    @Test func aNullWatcherNeverFires() {
        let watcher = NullVaultWatcher()
        watcher.start(onChange: { Issue.record("should never fire") })
        watcher.stop()
    }
}
