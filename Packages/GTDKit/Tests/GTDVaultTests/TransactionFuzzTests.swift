import Foundation
import GTDModel
import Testing
@testable import GTDVault

/// Data safety under randomised op sequences (T41).
///
/// `VaultTransactionTests` pins each rule with a hand-written case. This suite throws ~1 500
/// random op sequences at `VaultTransaction` — with and without an injected write/move failure —
/// and checks the three invariants the user's vault depends on (ARCHITECTURE §7, CLAUDE.md rule 2):
///
/// 1. **All or nothing.** A commit that throws anything but `rollbackFailed` leaves every file
///    outside `GTD/Trash/` exactly as it was.
/// 2. **The inverse really is the inverse.** `commit(commit(ops))` restores the vault byte for
///    byte (again ignoring the trash, which only ever grows).
/// 3. **Nothing is ever hard-deleted.** Every byte that existed before the commit is still
///    somewhere in the vault afterwards — unless a `.put` deliberately overwrote the file it
///    was living in. A successful commit is additionally compared against a plain simulation
///    of the same ops, so the transaction cannot quietly do something else.
///
/// A failure prints the seed, and `Fuzz(seed:)` regenerates exactly that sequence.
@Suite("Transaction fuzzing: rollback, inverses and never hard-deleting")
struct TransactionFuzzTests {

    @Test func randomOpSequencesEitherApplyCompletelyOrNotAtAll() throws {
        var rollbackFailures = 0
        var refusals = 0
        for seed in UInt64(1)...600 {
            var fuzz = Fuzz(seed: seed)
            let start = Self.startingVault(seed: seed)
            let fs = InMemoryFileSystem(files: start)
            let tx = VaultTransaction(fileSystem: fs, layout: .default)
            let ops = fuzz.ops()
            fuzz.injectFailure(into: fs)

            var inverse: [VaultFileOp]?
            do {
                inverse = try tx.commit(ops)
            } catch let error as VaultError {
                if case .rollbackFailed = error {
                    // Allowed — but only as the loud error: the user is told, never silently.
                    rollbackFailures += 1
                } else {
                    refusals += 1
                    #expect(Self.outsideTrash(fs) == start,
                            "seed \(seed) — a refused commit (\(error)) still changed the vault")
                    Self.expectNothingLost(start: start, now: fs, overwritten: [], seed: seed)
                }
                continue
            }

            // The commit went through, so the straightforward simulation of `ops` is what the
            // vault must look like — op for op, with nothing extra and nothing missing.
            let simulated = try #require(Self.simulate(ops, from: start),
                                         "seed \(seed) — commit succeeded but the simulation says it could not")
            #expect(Self.outsideTrash(fs) == simulated.live,
                    "seed \(seed) — \(ops) did not leave the vault the ops describe")
            Self.expectNothingLost(start: start, now: fs, overwritten: simulated.overwritten, seed: seed)

            // Undo restores the vault byte for byte. The injected failure is disarmed first:
            // it models the *commit* failing, not the undo.
            fs.failWrites(matching: [])
            fs.failMoves(to: [])
            _ = try tx.commit(try #require(inverse))
            #expect(Self.outsideTrash(fs) == start,
                    "seed \(seed) — undoing \(ops) did not restore the vault")
        }
        // The generator has to actually reach both paths, or this suite proves nothing.
        #expect(refusals > 20, "the fuzz never produced a refused commit (\(refusals))")
        #expect(rollbackFailures < 120, "rollback fails suspiciously often (\(rollbackFailures)/600)")
    }

    /// `.delete` of two different files that share a name must not let one overwrite the other
    /// in `GTD/Trash/` — the trash is the only copy left.
    @Test func repeatedTrashingOfTheSameNameKeepsEveryVersion() throws {
        let fs = InMemoryFileSystem(files: [:])
        let tx = VaultTransaction(fileSystem: fs, layout: .default)
        var expected: Set<String> = []
        for round in 1...12 {
            let text = "version \(round)"
            expected.insert(text)
            fs.writeIgnoringFailures(text, to: "Actions/Same name.md")
            _ = try tx.commit([.delete(path: "Actions/Same name.md")])
        }
        let trashed = Set(fs.snapshotOfFiles
            .filter { $0.key.hasPrefix("GTD/Trash/") }
            .map(\.value))
        #expect(trashed == expected, "a trashed file overwrote an earlier one")
        #expect(!fs.exists("Actions/Same name.md"))
    }

    /// The same, one commit at a time, through the whole pipe: a put that re-creates a trashed
    /// name and is then trashed again keeps both copies.
    @Test func trashingCollidesFreelyButNeverOverwrites() throws {
        let fs = InMemoryFileSystem(files: ["Inbox/2026-09-19 090000.md": "first"])
        let tx = VaultTransaction(fileSystem: fs, layout: .default)
        _ = try tx.commit([.delete(path: "Inbox/2026-09-19 090000.md"),
                           .put(path: "Inbox/2026-09-19 090000.md", text: "second")])
        _ = try tx.commit([.delete(path: "Inbox/2026-09-19 090000.md")])
        let contents = Set(fs.snapshotOfFiles.values)
        #expect(contents == ["first", "second"])
    }

    // MARK: - Invariants

    private static func outsideTrash(_ fs: InMemoryFileSystem) -> [String: String] {
        fs.snapshotOfFiles.filter { !$0.key.hasPrefix("GTD/Trash/") }
    }

    /// Invariant 3: every byte that was in the vault is still in the vault — unless a `.put`
    /// deliberately overwrote the file where that byte was living at the time.
    private static func expectNothingLost(
        start: [String: String], now fs: InMemoryFileSystem,
        overwritten: Set<String>, seed: UInt64
    ) {
        let present = Set(fs.snapshotOfFiles.values)
        for text in start.values where !overwritten.contains(text) {
            #expect(present.contains(text), "seed \(seed) — \(text) was hard-deleted")
        }
    }

    /// What the ops plainly say should happen, with no transaction machinery involved: the
    /// reference `VaultTransaction` is compared against. `nil` when an op could not apply
    /// (the commit must then have thrown).
    private static func simulate(
        _ ops: [VaultFileOp], from start: [String: String]
    ) -> (live: [String: String], overwritten: Set<String>)? {
        var live = start
        var overwritten: Set<String> = []
        for op in ops {
            switch op {
            case let .put(path, text):
                if let previous = live[VaultPath.normalize(path)] { overwritten.insert(previous) }
                live[VaultPath.normalize(path)] = text
            case let .move(from, to):
                let source = VaultPath.normalize(from), destination = VaultPath.normalize(to)
                if source == destination { continue }
                guard let text = live[source], live[destination] == nil else { return nil }
                live[source] = nil
                live[destination] = text
            case let .delete(path):
                live[VaultPath.normalize(path)] = nil     // into the trash, which we do not model
            }
        }
        return (live, overwritten)
    }

    // MARK: - The generator

    private static let paths = [
        "Actions/Call the bank.md",
        "Actions/Renew the ticket.md",
        "Actions/Same name.md",
        "Projects/Applications/DAAD/DAAD.md",
        "Projects/Applications/DAAD/Same name.md",
        "Knowledge/Uni/Same name.md",
        "Inbox/2026-09-19 090000.md",
        "GTD/Config.md",
        "Archive/2026/08/Old thing.md",
    ]

    private static func startingVault(seed: UInt64) -> [String: String] {
        var fuzz = Fuzz(seed: seed &+ 7_777)
        var files: [String: String] = [:]
        for path in paths where fuzz.bool(70) {
            files[path] = "the only copy of \(path) (seed \(seed))"
        }
        // Never generate an empty vault: there would be nothing to lose.
        if files.isEmpty { files[paths[0]] = "the only copy of \(paths[0]) (seed \(seed))" }
        return files
    }

    struct Fuzz {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x5EED }

        /// SplitMix64 — deterministic and identical on every platform.
        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ upperBound: Int) -> Int { Int(next() % UInt64(upperBound)) }
        mutating func bool(_ percent: Int = 50) -> Bool { int(100) < percent }
        mutating func pick<T>(_ options: [T]) -> T { options[int(options.count)] }

        mutating func ops() -> [VaultFileOp] {
            (0...int(5)).map { _ in
                switch int(3) {
                case 0:
                    return .put(path: pick(TransactionFuzzTests.paths), text: "written by the fuzz")
                case 1:
                    return .move(from: pick(TransactionFuzzTests.paths),
                                 to: pick(TransactionFuzzTests.paths))
                default:
                    return .delete(path: pick(TransactionFuzzTests.paths))
                }
            }
        }

        /// Half the sequences run against a file system that fails one write or one move —
        /// the only way to reach the rollback path deterministically.
        mutating func injectFailure(into fs: InMemoryFileSystem) {
            switch int(4) {
            case 0: fs.failWrites(matching: [pick(TransactionFuzzTests.paths)])
            case 1: fs.failMoves(to: [pick(TransactionFuzzTests.paths)])
            default: break
            }
        }
    }
}
