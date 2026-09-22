import Foundation
import GTDFixtures
import GTDModel
import Testing
@testable import GTDVault

/// The fast path behind a watcher hint: `VaultIndex.refresh(paths:using:)` re-reads only the
/// hinted files. The invariant it must never bend is *the snapshot is what the files say* — so
/// every case here ends in the same comparison: the incrementally updated index against a cold
/// index over the same files.
@Suite("Targeted re-index: only the hinted files, never a different snapshot")
struct TargetedRefreshTests {

    private func scanned(_ fs: InMemoryFileSystem) throws -> VaultIndex {
        var index = VaultIndex()
        try index.refresh(using: fs)
        return index
    }

    private func cold(_ fs: InMemoryFileSystem) throws -> VaultSnapshot {
        try scanned(fs).snapshot(today: Fixtures.today)
    }

    @Test func aNewInboxFileShowsUpFromItsPathAlone() throws {
        let fs = InMemoryFileSystem(files: SampleVault.files)
        var index = try scanned(fs)
        let before = index.snapshot(today: Fixtures.today).inbox.count

        fs.writeIgnoringFailures("from a script\n", to: "Inbox/From a script.md")
        let report = try #require(try index.refresh(
            paths: ["Inbox/From a script.md"], using: fs))

        #expect(report.added == 1)
        let snapshot = index.snapshot(today: Fixtures.today)
        #expect(snapshot.inbox.count == before + 1)
        #expect(snapshot.inbox.contains { $0.title == "From a script" && $0.body == "from a script" },
                "a plain file with no frontmatter is a capture, dated by the file")
        #expect(snapshot.issues == (try cold(InMemoryFileSystem(files: SampleVault.files))).issues)
        #expect(snapshot == (try cold(fs)))
    }

    @Test func aHintThatNeedsAWalkSaysSoAndChangesNothing() throws {
        let fs = InMemoryFileSystem(files: SampleVault.files)
        var index = try scanned(fs)
        let before = index.snapshot(today: Fixtures.today)

        // A file in a folder the index has never seen: the folder list (lists, Knowledge) can
        // only be rebuilt by a walk.
        fs.writeIgnoringFailures("milk\n", to: "Lists/Brand new list/milk.md")
        #expect(try index.refresh(paths: ["Lists/Brand new list/milk.md"], using: fs) == nil)
        // A folder.
        #expect(try index.refresh(paths: ["Actions"], using: fs) == nil)
        // A sync landing.
        let many = Set((0...VaultIndex.targetedLimit).map { "Inbox/\($0).md" })
        #expect(try index.refresh(paths: many, using: fs) == nil)

        #expect(index.snapshot(today: Fixtures.today) == before)
    }

    @Test func dotFilesAndPlaceholdersAreTreatedAsTheWalkTreatsThem() throws {
        let fs = InMemoryFileSystem(files: SampleVault.files)
        var index = try scanned(fs)
        fs.writeIgnoringFailures("temp", to: "Inbox/.dat.nosync1234.tmp")

        let report = try #require(try index.refresh(
            paths: ["Inbox/.dat.nosync1234.tmp", ".obsidian/workspace.json"], using: fs))
        #expect(!report.changed)
        #expect(index.snapshot(today: Fixtures.today) == (try cold(fs)))
    }

    /// Random external edits — write, create, move, move to the trash — each reported as a path
    /// hint. Whatever the hint path answers (or declines to answer), the snapshot must equal a
    /// cold scan's. A failure prints the seed.
    @Test func randomExternalEditsNeverDriftFromAColdScan() throws {
        for seed in UInt64(1)...40 {
            var random = SplitMix(seed: seed)
            let fs = InMemoryFileSystem(files: SampleVault.files)
            var index = try scanned(fs)

            for step in 0..<12 {
                let files = fs.snapshotOfFiles.keys.filter {
                    $0.hasSuffix(".md") && !$0.hasPrefix("GTD/Trash/")
                }.sorted()
                let victim = files[Int(random.next() % UInt64(files.count))]
                var touched: Set<String> = []

                switch random.next() % 4 {
                case 0:
                    let text = fs.snapshotOfFiles[victim] ?? ""
                    fs.writeIgnoringFailures(text + "\nedited \(step)\n", to: victim)
                    touched = [victim]
                case 1:
                    let path = "Inbox/2026-09-22 10\(10 + step)00 s\(seed).md"
                    fs.writeIgnoringFailures("capture \(seed)-\(step)\n", to: path)
                    touched = [path]
                case 2:
                    let destination = VaultPath.join(
                        VaultPath.folder(of: victim), "Moved \(seed)-\(step).md")
                    guard (try? fs.move(victim, to: destination)) != nil else { continue }
                    touched = [victim, destination]
                default:
                    let destination = "GTD/Trash/Gone \(seed)-\(step).md"
                    guard (try? fs.move(victim, to: destination)) != nil else { continue }
                    touched = [victim, destination]
                }

                if try index.refresh(paths: touched, using: fs) == nil {
                    try index.refresh(using: fs)
                }
                #expect(index.snapshot(today: Fixtures.today) == (try cold(fs)),
                        "seed \(seed), step \(step) — hinted \(touched.sorted())")
            }
        }
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
