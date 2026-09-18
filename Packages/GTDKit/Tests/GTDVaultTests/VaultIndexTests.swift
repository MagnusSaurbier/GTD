import Foundation
import GTDModel
import Testing
@testable import GTDVault

/// A small hand-written vault in the `StubNoteParser` format — enough to exercise every rule
/// the index applies, without waiting for T10's codec.
enum MiniVault {
    static let today = Day(year: 2026, month: 9, day: 19)

    static func files() -> [String: String] {
        [
            "Inbox/2026-09-18 094410.md":
                "---\ncreated: 2026-09-18T09:44:10+02:00\n---\nbuy running shoes",
            "Inbox/2026-09-17 173355.md":
                "---\ncreated: 2026-09-17T17:33:55+02:00\nreviewReason: needs a think\n---\nmove out?",
            "Actions/Fix the bike light.md":
                "---\nstatus: next\ncontexts: [home, errands]\n---\n- [ ] buy a bulb",
            "Actions/Old thing.md": "---\nstatus: backlog\n---\n",
            "Archive/2026/08/Done long ago.md": "---\nstatus: done\n---\n",
            "GTD/Trash/Thrown away.md": "---\nstatus: trash\n---\n",
            "Projects/Applications/Applications.md": "---\nkind: area\n---\n",
            "Projects/Applications/DAAD/DAAD.md":
                "---\nkind: project\nstatus: active\narea: Projects/Applications/Applications.md\n---\nscholarship",
            "Projects/Applications/DAAD/Transcript.pdf": "%PDF",
            "Projects/Applications/DAAD/Scratch.md": "notes that are not the project note",
            "GTD/Routines/Morning.md": "---\ntime: \"07:00\"\n---\n- [ ] wake up",
            "GTD/RoutineLog/2026-09-18--iPhone.md":
                "---\nentries:\n---\nMorning|wake-up|done|2026-09-18",
            "GTD/RoutineLog/2026-08-01--iPhone.md":
                "---\nentries:\n---\nMorning|wake-up|done|2026-08-01",
            "GTD/Reviews/2026/KW 36.md": "---\nkind: review\nyear: 2026\nweek: 36\n---\nolder",
            "GTD/Reviews/2026/KW 37.md": "---\nkind: review\nyear: 2026\nweek: 37\n---\nnewer",
            "GTD/Config.md": "---\ncontexts: [mac, phone]\nnextCap: 9\n---\n# Config",
            "Knowledge/Studium/Thesis/Sources.md": "a knowledge note",
        ]
    }

    static func index(
        parser: StubNoteParser = StubNoteParser()
    ) throws -> (VaultIndex, InMemoryFileSystem) {
        let fs = InMemoryFileSystem(files: files())
        try fs.createFolder("Knowledge/Finanzen")      // an empty folder still counts (I4)
        var index = VaultIndex(parser: parser)
        try index.refresh(using: fs)
        return (index, fs)
    }
}

@Suite("VaultIndex: scanning, incremental refresh and snapshot assembly")
struct VaultIndexTests {

    @Test func scanSortsEveryCollectionIntoTheSnapshot() throws {
        let (index, _) = try MiniVault.index()
        let snapshot = index.snapshot(today: MiniVault.today)

        #expect(snapshot.inbox.map(\.id.title) == ["2026-09-17 173355", "2026-09-18 094410"])
        #expect(snapshot.actions.map(\.title) == ["Fix the bike light", "Old thing"])
        #expect(snapshot.areas.map(\.title) == ["Applications"])
        #expect(snapshot.projects.map(\.title) == ["DAAD"])
        #expect(snapshot.routines.map(\.title) == ["Morning"])
        #expect(snapshot.config.nextCap == 9)
        #expect(snapshot.issues.isEmpty)
    }

    @Test func archiveAndTrashNeverReachTheSnapshot() throws {
        let (index, _) = try MiniVault.index()
        let snapshot = index.snapshot(today: MiniVault.today)
        #expect(!snapshot.actions.contains { $0.title == "Done long ago" })
        #expect(!snapshot.actions.contains { $0.title == "Thrown away" })
    }

    @Test func actionsCarryTheFileModificationDate() throws {
        let (index, fs) = try MiniVault.index()
        let snapshot = index.snapshot(today: MiniVault.today)
        let action = try #require(snapshot.actions.first { $0.title == "Fix the bike light" })
        let info = try #require(try fs.info("Actions/Fix the bike light.md"))
        #expect(action.modified == info.modified)
    }

    @Test func projectsCollectTheirFolderAsReferenceFiles() throws {
        let (index, _) = try MiniVault.index()
        let project = try #require(index.snapshot(today: MiniVault.today).projects.first)
        #expect(project.referenceFiles == [
            "Projects/Applications/DAAD/Scratch.md",
            "Projects/Applications/DAAD/Transcript.pdf",
        ])
    }

    @Test func knowledgeFoldersAreTheTreeWithoutThePrefix() throws {
        let (index, _) = try MiniVault.index()
        #expect(index.snapshot(today: MiniVault.today).knowledgeFolders
            == ["Finanzen", "Studium", "Studium/Thesis"])
    }

    @Test func theNewestReviewWins() throws {
        let (index, _) = try MiniVault.index()
        let review = try #require(index.snapshot(today: MiniVault.today).lastReview)
        #expect(review.year == 2026)
        #expect(review.week == 37)
    }

    @Test func routineLogIsTrimmedToTheLastFourteenDays() throws {
        let (index, _) = try MiniVault.index()
        let log = index.snapshot(today: MiniVault.today).routineLog
        #expect(log.count == 1)
        #expect(log.first?.day == Day(year: 2026, month: 9, day: 18))
    }

    @Test func aConfiglessVaultFallsBackToTheDefault() throws {
        var files = MiniVault.files()
        files["GTD/Config.md"] = nil
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: InMemoryFileSystem(files: files))
        #expect(index.snapshot(today: MiniVault.today).config == .default)
    }

    // MARK: Incremental behaviour

    @Test func anUnchangedVaultIsFullyReusedAndReportsNoChange() throws {
        var (index, fs) = try MiniVault.index()
        let report = try index.refresh(using: fs)
        #expect(report.reused == index.fileCount)
        #expect(report.added == 0 && report.updated == 0 && report.removed == 0)
        #expect(report.changed == false)
    }

    @Test func onlyTheChangedFileIsDecodedAgain() throws {
        var (index, fs) = try MiniVault.index()
        fs.writeIgnoringFailures("---\nstatus: done\n---\n", to: "Actions/Old thing.md")

        let report = try index.refresh(using: fs)
        #expect(report.updated == 1)
        #expect(report.added == 0 && report.removed == 0)
        #expect(report.changed)

        let action = try #require(index.snapshot(today: MiniVault.today)
            .actions.first { $0.title == "Old thing" })
        #expect(action.status == .done)
    }

    @Test func newAndRemovedFilesAreTracked() throws {
        var (index, fs) = try MiniVault.index()
        fs.writeIgnoringFailures("---\nstatus: next\n---\n", to: "Actions/Brand new.md")
        try fs.move("Actions/Old thing.md", to: "GTD/Trash/Old thing.md")

        let report = try index.refresh(using: fs)
        #expect(report.added == 2)      // the new action, plus its new path inside the trash
        #expect(report.removed == 1)    // the action's old path under Actions/
        let titles = index.snapshot(today: MiniVault.today).actions.map(\.title)
        #expect(titles == ["Brand new", "Fix the bike light"])
    }

    @Test func aNewEmptyFolderIsPickedUp() throws {
        var (index, fs) = try MiniVault.index()
        try fs.createFolder("Knowledge/Technik")
        let report = try index.refresh(using: fs)
        #expect(report.foldersChanged)
        #expect(index.snapshot(today: MiniVault.today).knowledgeFolders.contains("Technik"))
    }

    // MARK: Issues

    @Test func anUndecodableFileBecomesAnIssueAndTheRestStillScans() throws {
        let parser = StubNoteParser(failing: ["Actions/Old thing.md"])
        let (index, _) = try MiniVault.index(parser: parser)
        let snapshot = index.snapshot(today: MiniVault.today)

        #expect(snapshot.actions.map(\.title) == ["Fix the bike light"])
        #expect(snapshot.issues.map(\.path) == ["Actions/Old thing.md"])
        #expect(snapshot.issues[0].message.contains("stub failure"))
    }

    @Test func anEvictediCloudItemIsAnIssueAndItsDownloadIsRequested() throws {
        let fs = InMemoryFileSystem(files: MiniVault.files())
        fs.evict("Actions/Fix the bike light.md")
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: fs)
        let snapshot = index.snapshot(today: MiniVault.today)

        #expect(snapshot.actions.map(\.title) == ["Old thing"])
        let issue = try #require(snapshot.issues.first { $0.path == "Actions/Fix the bike light.md" })
        #expect(issue.message.lowercased().contains("icloud"))
        #expect(fs.requestedDownloads.contains("Actions/Fix the bike light.md"))
    }

    @Test func anArrivingDownloadIsPickedUpOnTheNextRefresh() throws {
        let fs = InMemoryFileSystem(files: MiniVault.files())
        fs.evict("Actions/Fix the bike light.md")
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: fs)
        #expect(index.snapshot(today: MiniVault.today).issues.count == 1)

        fs.writeIgnoringFailures("---\nstatus: next\n---\narrived", to: "Actions/Fix the bike light.md")
        try index.refresh(using: fs)
        let snapshot = index.snapshot(today: MiniVault.today)
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.actions.count == 2)
    }

    @Test func aConflictCopyIsReportedButStillIndexed() throws {
        var files = MiniVault.files()
        files["Actions/Fix the bike light 2.md"] = "---\nstatus: next\n---\nthe other device's copy"
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: InMemoryFileSystem(files: files))
        let snapshot = index.snapshot(today: MiniVault.today)

        // Reported (N3 §7.5) …
        let issue = try #require(snapshot.issues.first)
        #expect(issue.path == "Actions/Fix the bike light 2.md")
        #expect(issue.message.contains("conflict copy"))
        // … and still visible, so nothing the user wrote silently disappears.
        #expect(snapshot.actions.contains { $0.title == "Fix the bike light 2" })
    }

    @Test func areasAndProjectsAreToldApartByTheirKindKey() throws {
        var files = MiniVault.files()
        // Same shape, different `kind` — the only discriminator (ARCHITECTURE §3).
        files["Projects/Wohnungssuche/Wohnungssuche.md"] = "---\nkind: project\nstatus: active\n---\n"
        files["Projects/Karriere/Karriere.md"] = "---\nkind: area\n---\n"
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: InMemoryFileSystem(files: files))
        let snapshot = index.snapshot(today: MiniVault.today)

        #expect(snapshot.areas.map(\.title) == ["Applications", "Karriere"])
        #expect(snapshot.projects.map(\.title) == ["DAAD", "Wohnungssuche"])
    }

    @Test func aProjectNoteWithoutAKindKeyIsTreatedAsAProject() throws {
        var files = MiniVault.files()
        files["Projects/Nebenjob/Nebenjob.md"] = "---\nstatus: active\n---\n"
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: InMemoryFileSystem(files: files))
        #expect(index.snapshot(today: MiniVault.today).projects.map(\.title) == ["DAAD", "Nebenjob"])
    }

    @Test func scanningTwiceProducesTheSameSnapshot() throws {
        var (index, fs) = try MiniVault.index()
        let first = index.snapshot(today: MiniVault.today)
        try index.refresh(using: fs)
        #expect(index.snapshot(today: MiniVault.today) == first)
    }
}
