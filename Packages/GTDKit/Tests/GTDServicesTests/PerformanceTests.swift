import Foundation
import GTDAppCore
import GTDFixtures
import GTDMarkdown
import GTDModel
import GTDServices
import GTDVault
import Testing

/// T41 deliverable 5 — the performance floor, measured on Linux through the **real** stack.
///
/// What a benchmark can and cannot say here: cold launch, typing latency and scroll smoothness
/// need a device and live in `docs/MANUAL_TEST.md`. What *is* measurable without one is the work
/// underneath them, and that is what this suite pins:
///
/// * a cold scan of a generated vault (REQUIREMENTS' 1 000 notes, more via `GTD_BENCH_NOTES`),
/// * an incremental refresh after a single file changed,
/// * one command end to end through `VaultBackend` → `SnapshotDiff` → `FileVaultStore`,
/// * the derived queries every view calls on every snapshot (`Rules`),
/// * raw codec throughput.
///
/// **The assertions are structural, not wall-clock.** A container's clock is not a phone's, so
/// timing an assertion would only produce a flaky test. Instead each test asserts the *shape* of
/// the work — "the refresh read one file, not 1 000", "the command wrote one file, not 1 000",
/// "doubling the projects does not square the work" — and prints the milliseconds for the record.
/// The numbers of the run that shipped are in `agent_task/41-qa-hardening.md`'s Result;
/// `scripts/benchmark.sh` re-runs them.
@Suite(.enabled(if: NoteCodecParser.codecIsImplemented), .serialized)
struct PerformanceTests {

    // MARK: - Cold scan and incremental refresh

    @Test func coldScanOfAGeneratedVaultOnDisk() async throws {
        let size = Bench.size
        let files = GeneratedVault.files(actions: size.actions, projects: size.projects,
                                         areas: size.areas, inbox: size.inbox)
        let root = try GeneratedVault.write(files)
        defer { try? FileManager.default.removeItem(at: root) }

        let counting = CountingFileSystem(PlainFileSystem(root: root))
        let store = FileVaultStore(fileSystem: counting, watcher: NullVaultWatcher(),
                                   today: { Fixtures.today })

        Bench.header("cold scan — \(files.count) files on disk (PlainFileSystem)")
        let snapshot = try await Bench.measureAsync("cold scan") { try await store.scan() }
        Bench.report("reads", counting.reads)

        #expect(snapshot.actions.count == size.actions)
        #expect(snapshot.projects.count == size.projects)
        #expect(snapshot.inbox.count == size.inbox)
        #expect(snapshot.issues.isEmpty,
                Comment(rawValue: "generated vault must scan clean: \(snapshot.issues.prefix(3))"))
        // Every note is read exactly once. A second read per file would mean the scan decodes
        // twice (the `kind:` peek must stay a substring search, not a re-read).
        #expect(counting.reads == snapshot.actions.count + snapshot.projects.count
            + snapshot.areas.count + snapshot.inbox.count + size.otherNotes)

        // A refresh with nothing changed must decode nothing at all.
        counting.resetCounts()
        _ = try await Bench.measureAsync("refresh, nothing changed") { try await store.scan() }
        #expect(counting.reads == 0, "an unchanged vault must not be re-parsed")

        // One file changed ⇒ exactly one decode.
        let victim = try #require(snapshot.actions.first).id.path
        try counting.writeText(GeneratedVault.actionNote(index: 0, projects: size.projects,
                                                         marker: "touched"), to: victim)
        counting.resetCounts()
        let after = try await Bench.measureAsync("refresh, one file changed") { try await store.scan() }
        Bench.report("reads", counting.reads)
        #expect(counting.reads == 1, "an incremental refresh must re-read only what changed")
        #expect(after.actions.count == size.actions)
    }

    // MARK: - One command through the whole stack

    @Test func oneCommandWritesOneFileOnALargeVault() async throws {
        let size = Bench.size
        let files = GeneratedVault.files(actions: size.actions, projects: size.projects,
                                         areas: size.areas, inbox: size.inbox)
        let counting = CountingFileSystem(InMemoryFileSystem(files: files))
        let store = FileVaultStore(fileSystem: counting, watcher: NullVaultWatcher(),
                                   today: { Fixtures.today })
        let stateDirectory = TestVault.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: stateDirectory) }
        let backend = VaultBackend(
            store: store, deviceID: "bench", journal: UndoJournal(directory: stateDirectory),
            stateDirectory: stateDirectory,
            env: { Fixtures.reducerEnv(deviceID: "bench") })

        Bench.header("one command — \(files.count)-file vault (InMemoryFileSystem)")
        try await Bench.measureAsync("activate + first scan") { try await store.activate() }

        let snapshot = await store.currentSnapshot
        let target = try #require(snapshot.actions.first { $0.status == .backlog })

        counting.resetCounts()
        _ = try await Bench.measureAsync("setStatus(.maybe)") {
            try await backend.perform(.setStatus(target.id, .maybe, waiting: nil))
        }
        Bench.report("writes", counting.writes)
        Bench.report("reads (the re-index that follows)", counting.reads)

        // The whole point of `SnapshotDiff`: one changed entity is one changed file, whatever the
        // size of the vault. If this ever reads as `size.actions` the diff has started
        // re-serialising notes instead of patching the text it kept.
        #expect(counting.writes == 1)
        // Three constant reads, none of them proportional to the vault: the transaction reads the
        // file it is about to overwrite (that text *is* the inverse op), the undo journal hashes
        // it, and the re-index decodes it again afterwards.
        #expect(counting.reads <= 4)

        counting.resetCounts()
        try await Bench.measureAsync("undo") { try await backend.undo() }
        #expect(counting.writes == 1)
    }

    // MARK: - Derived queries (every view, every snapshot)

    @Test func derivedQueriesOnALargeSnapshot() async throws {
        let size = Bench.size
        let files = GeneratedVault.files(actions: size.actions, projects: size.projects,
                                         areas: size.areas, inbox: size.inbox)
        let store = FileVaultStore(fileSystem: InMemoryFileSystem(files: files),
                                   watcher: NullVaultWatcher(), today: { Fixtures.today })
        let snapshot = try await store.scan()
        let today = Fixtures.today

        Bench.header("derived queries — \(snapshot.actions.count) actions, \(snapshot.projects.count) projects")
        _ = Bench.measure("Rules.sidebarCounts") { Rules.sidebarCounts(snapshot, today: today) }
        _ = Bench.measure("Rules.nextList") { Rules.nextList(snapshot, today: today) }
        _ = Bench.measure("Rules.waitingList") { Rules.waitingList(snapshot, today: today) }
        _ = Bench.measure("Rules.deferredList") { Rules.deferredList(snapshot, today: today) }
        let rows = Bench.measure("Rules.projectRows") { Rules.projectRows(snapshot, today: today) }
        _ = Bench.measure("Rules.stalledProjects") { Rules.stalledProjects(snapshot, today: today) }
        _ = Bench.measure("Rules.timeline(±90 d)") {
            Rules.timeline(snapshot, from: today.adding(days: -90), to: today.adding(days: 90))
        }
        #expect(rows.count == snapshot.projects.count)

        // `projectRows` used to call `visibleActions` once per project — O(projects × actions).
        // Doubling the projects must not quadruple the work; the ratio below is ~2 when the query
        // is linear and ~4 when it is not. The bound is deliberately slack (3.0) because a
        // container's clock is noisy — it catches the pathology, not a regression of 20 %.
        let small = try await Self.snapshot(projects: 40, actions: size.actions)
        let large = try await Self.snapshot(projects: 80, actions: size.actions)
        let smallTime = Bench.best(of: 5) { _ = Rules.projectRows(small, today: today) }
        let largeTime = Bench.best(of: 5) { _ = Rules.projectRows(large, today: today) }
        Bench.report("projectRows, 40 projects", Bench.ms(smallTime))
        Bench.report("projectRows, 80 projects", Bench.ms(largeTime))
        #expect(largeTime < smallTime * 3.0 + 0.002,
                Comment(rawValue: "projectRows looks superlinear in the project count: "
                    + "\(Bench.ms(smallTime)) ms → \(Bench.ms(largeTime)) ms"))
    }

    // MARK: - Codec throughput

    @Test func codecThroughput() throws {
        let count = Bench.size.actions
        let texts = (0..<count).map {
            GeneratedVault.actionNote(index: $0, projects: Bench.size.projects)
        }
        let ids = (0..<count).map { NoteID(path: "Actions/Generated \($0).md") }

        Bench.header("codec — \(count) action notes")
        var decoded: [Action] = []
        try Bench.measure("decode") {
            decoded = try zip(ids, texts).map { try NoteCodec.decodeAction(id: $0, text: $1) }
        }
        var encoded: [String] = []
        Bench.measure("encode (unchanged, patching path)") {
            encoded = decoded.map { NoteCodec.encode($0) }
        }
        var edited = decoded
        for index in edited.indices { edited[index].status = .maybe }
        Bench.measure("encode (one field changed)") {
            _ = edited.map { NoteCodec.encode($0) }
        }
        // N2: encoding an untouched note reproduces its file byte for byte. That is also what
        // makes the diff cheap — an unchanged note costs a string compare, not a write.
        #expect(encoded == texts)
    }

    // MARK: - Helpers

    private static func snapshot(projects: Int, actions: Int) async throws -> VaultSnapshot {
        let files = GeneratedVault.files(actions: actions, projects: projects, areas: 4, inbox: 0)
        let store = FileVaultStore(fileSystem: InMemoryFileSystem(files: files),
                                   watcher: NullVaultWatcher(), today: { Fixtures.today })
        return try await store.scan()
    }
}

// MARK: - Bench

/// Timing and printing. Deliberately tiny — no dependency, no statistics beyond "best of n",
/// which is the only number that means anything on a shared machine.
enum Bench {
    struct Size {
        var actions: Int
        var projects: Int
        var areas: Int
        var inbox: Int
        /// Routine templates, routine logs, the config note and one review — see `GeneratedVault`.
        var otherNotes: Int { GeneratedVault.otherNoteCount }
    }

    /// 1 000 notes is REQUIREMENTS' own figure (brief deliverable 5). `GTD_BENCH_NOTES` scales it
    /// for `scripts/benchmark.sh`.
    static let size: Size = {
        let actions = ProcessInfo.processInfo.environment["GTD_BENCH_NOTES"].flatMap(Int.init) ?? 1_000
        return Size(actions: actions, projects: max(8, actions / 25), areas: 6,
                    inbox: max(4, actions / 50))
    }()

    static func header(_ title: String) {
        print("\n[bench] \(title)")
    }

    static func report(_ label: String, _ value: Any) {
        print("[bench]   \(label): \(value)")
    }

    static func ms(_ seconds: Double) -> String {
        String(format: "%.2f", seconds * 1000)
    }

    @discardableResult
    static func measure<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try body()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        report(label, "\(ms(elapsed)) ms")
        return value
    }

    @discardableResult
    static func measureAsync<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try await body()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        report(label, "\(ms(elapsed)) ms")
        return value
    }

    /// Fastest of `n` runs, in seconds. The fastest run is the one least disturbed by whatever
    /// else the machine was doing.
    static func best(of n: Int, _ body: () -> Void) -> Double {
        var best = Double.infinity
        for _ in 0..<n {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
        }
        return best
    }
}

// MARK: - A generated vault

/// A synthetic vault of any size, shaped like the real one: actions spread over the statuses,
/// contexts, defer/due/waiting dates and projects; projects spread over the four project
/// statuses, some of them stalled; areas; inbox captures; two routines with a fortnight of logs.
///
/// Every note carries an unknown frontmatter key and an unknown body section, so the round-trip
/// rule (N2) is exercised by the throughput numbers rather than bypassed by them.
enum GeneratedVault {
    /// `GTD/Config.md`, two routine templates, 14 routine logs, one review note.
    static let otherNoteCount = 1 + 2 + 14 + 1

    static func files(actions: Int, projects: Int, areas: Int, inbox: Int) -> [String: String] {
        var files: [String: String] = [:]

        for index in 0..<areas {
            let name = areaName(index)
            files["Projects/\(name)/\(name).md"] = """
                ---
                kind: area
                obsidianPlugin: keep-me
                ---
                # Why?
                Area \(index) exists to keep the generated vault shaped like the real one.
                """
        }
        for index in 0..<projects {
            let (folder, name) = projectPath(index, areas: areas)
            files["\(folder)/\(name).md"] = projectNote(index: index, areas: areas)
        }
        for index in 0..<actions {
            files["Actions/Generated \(index).md"] = actionNote(index: index, projects: projects)
        }
        for index in 0..<inbox {
            let stamp = String(format: "2026-09-%02d %02d%02d%02d", 1 + index % 28,
                               index % 24, index % 60, (index * 7) % 60)
            files["Inbox/\(stamp).md"] = """
                ---
                created: 2026-09-\(String(format: "%02d", 1 + index % 28))T0\(index % 9):15:00+02:00
                ---
                Captured thought number \(index) that still needs clarifying.
                """
        }

        files["GTD/Config.md"] = """
            ---
            contexts: [mac, phone, home, campus, errands, calls, reading, deep-work]
            onTheGoContexts: [phone, errands, calls, reading]
            nextCap: 15
            ---
            """
        for (name, time) in [("Morning", "07:00"), ("Bedtime", "22:30")] {
            files["GTD/Routines/\(name).md"] = """
                ---
                time: "\(time)"
                ---
                - [ ] First step of \(name)
                    - sub step
                - [ ] Second step of \(name)
                - [ ] Third step of \(name)
                """
        }
        for day in 0..<14 {
            let date = String(format: "2026-09-%02d", 5 + day)
            files["GTD/RoutineLog/\(date)--bench.md"] = """
                ---
                entries:
                  - routine: Morning
                    step: first-step-of-morning
                    result: done
                    at: \(date)T07:05:00+02:00
                  - routine: Morning
                    step: second-step-of-morning
                    result: skipped
                    at: \(date)T07:08:00+02:00
                ---
                """
        }
        files["GTD/Reviews/2026/KW 37.md"] = """
            ---
            week: 37
            year: 2026
            ---
            # Wanted to achieve
            A generated week.
            """
        return files
    }

    /// One action note. `marker` changes the body so the file's fingerprint moves.
    static func actionNote(index: Int, projects: Int, marker: String = "") -> String {
        let statuses = ["next", "backlog", "backlog", "maybe", "waiting", "in-progress", "done"]
        let status = statuses[index % statuses.count]
        let contexts = [["mac"], ["phone", "calls"], ["home"], ["campus", "deep-work"],
                        ["errands"], ["reading"], []][index % 7]
        var frontmatter = """
            status: \(status)
            contexts: [\(contexts.joined(separator: ", "))]
            """
        if index % 3 != 0 { frontmatter += "\ntimeEstimate: \([10, 30, 60, 90][index % 4])" }
        if projects > 0, index % 4 == 0 {
            let (folder, name) = projectPath(index % projects, areas: 6)
            frontmatter += "\nproject: \"[[\(folder)/\(name)]]\""
        }
        if index % 11 == 0 { frontmatter += "\ndefer: 2026-10-\(String(format: "%02d", 1 + index % 28))" }
        if index % 9 == 0 { frontmatter += "\ndue: 2026-09-\(String(format: "%02d", 1 + index % 28))" }
        if status == "waiting" {
            frontmatter += "\nwaitingFor: Someone \(index)"
            frontmatter += "\nfollowUpDate: 2026-09-\(String(format: "%02d", 1 + index % 28))"
        }
        if status == "done" { frontmatter += "\ncompletedDate: 2026-09-12T18:00:00+02:00" }
        return """
            ---
            \(frontmatter)
            created: 2026-0\(1 + index % 8)-\(String(format: "%02d", 1 + index % 28))T09:30:00+02:00
            legacyField: kept verbatim
            ---
            # Why?
            Because action \(index) has a reason, written out at the length a real note runs to
            so the parser sees realistic input rather than one short line.\(marker)

            # What?
            - [ ] Do the thing for action \(index)
            \(index % 5 == 0 ? "- [ ] And the second half of it\n" : "")
            # Notes
            An unknown section the codec must carry through untouched (N2).
            """
    }

    static func projectNote(index: Int, areas: Int) -> String {
        let statuses = ["active", "active", "active", "on-hold", "someday", "done"]
        let (_, name) = projectPath(index, areas: areas)
        return """
            ---
            kind: project
            status: \(statuses[index % statuses.count])
            someoneElsesKey: 42
            ---
            # Outcome
            \(name) is done when the generated outcome is reached.

            # Why?
            Because the vault needs projects to be shaped like the real one.

            # Steps
            - [x] A finished step
            - [ ] An open step
            - [ ] Another open step

            # Log
            - 2026-09-10 Started
            """
    }

    static func areaName(_ index: Int) -> String { "Area \(index)" }

    /// Half the projects sit inside an area, half directly under `Projects/` (both are legal).
    static func projectPath(_ index: Int, areas: Int) -> (folder: String, name: String) {
        let name = "Project \(index)"
        guard areas > 0, index % 2 == 0 else { return ("Projects/\(name)", name) }
        return ("Projects/\(areaName(index % areas))/\(name)", name)
    }

    /// Writes the generated files into a fresh temp directory and returns its root.
    static func write(_ files: [String: String]) throws -> URL {
        let root = TestVault.temporaryDirectory()
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }
}

// MARK: - CountingFileSystem

/// Forwards to another file system and counts what passes through. The structural assertions of
/// this suite are all about these counts: a refresh that reads 1 000 files, or a command that
/// writes 1 000, is the pathology, whatever the clock says.
final class CountingFileSystem: VaultFileSystem, @unchecked Sendable {
    private let base: any VaultFileSystem
    private let lock = NSLock()
    private var readCount = 0
    private var writeCount = 0
    private var listCount = 0

    init(_ base: any VaultFileSystem) { self.base = base }

    var reads: Int { lock.withLock { readCount } }
    var writes: Int { lock.withLock { writeCount } }
    var lists: Int { lock.withLock { listCount } }

    func resetCounts() {
        lock.withLock {
            readCount = 0
            writeCount = 0
            listCount = 0
        }
    }

    var root: URL { base.root }

    func listFiles() throws -> [VaultFileInfo] {
        lock.withLock { listCount += 1 }
        return try base.listFiles()
    }

    func listFolders() throws -> [String] { try base.listFolders() }

    func listEntries() throws -> VaultListing {
        lock.withLock { listCount += 1 }
        return try base.listEntries()
    }

    func info(_ path: String) throws -> VaultFileInfo? { try base.info(path) }
    func exists(_ path: String) -> Bool { base.exists(path) }

    func readText(_ path: String) throws -> String? {
        lock.withLock { readCount += 1 }
        return try base.readText(path)
    }

    func writeText(_ text: String, to path: String) throws {
        lock.withLock { writeCount += 1 }
        try base.writeText(text, to: path)
    }

    func move(_ from: String, to path: String) throws { try base.move(from, to: path) }
    func createFolder(_ path: String) throws { try base.createFolder(path) }
    func requestDownload(_ path: String) throws { try base.requestDownload(path) }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
