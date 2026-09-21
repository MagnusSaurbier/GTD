import Foundation
import GTDFixtures
import GTDModel
import Testing
@testable import GTDVault

/// §5a — what the scanner makes of `Lists/`: the folder is the list, `Done/` is its log, and
/// anything else under `Lists/` is reported rather than guessed at.
@Suite("Lists: classification and indexing")
struct ListsIndexTests {

    private let classifier = VaultClassifier()

    // MARK: - Classification

    @Test(arguments: [
        "Lists/Read/Sapiens.md",
        "Lists/Watch/Arrival.md",
        "Lists/Read/Done/Why we sleep.md",
    ])
    func aNoteInsideAListIsAListItem(path: String) {
        #expect(classifier.kind(of: path) == .listItem)
    }

    @Test(arguments: [
        "Lists/Stray.md",                       // in no list at all
        "Lists/Read/Notes/Deeper.md",           // nested deeper than a list holds
        "Lists/Read/Done/Deeper/Deeper.md",     // deeper than the Done log
        "Lists/Done/Reserved.md",               // `Done` directly under Lists/ is not a list
    ])
    func aNoteUnderListsThatIsInNoListIsReported(path: String) {
        #expect(classifier.kind(of: path) == .listMisplaced)
        #expect(!classifier.misplacedListReason(of: path).isEmpty)
    }

    /// Anything that is not markdown is left completely alone — a cover image, a PDF.
    @Test func aNonMarkdownFileInAListIsLeftAlone() {
        #expect(classifier.kind(of: "Lists/Read/cover.png") == .other)
    }

    @Test(arguments: [
        ("Lists/Read", "Read"),
        ("Lists/Wish list", "Wish list"),
    ])
    func aDirectSubfolderOfListsIsAList(folder: String, name: String) {
        #expect(classifier.listFolderName(of: folder) == name)
    }

    @Test(arguments: [
        "Lists",                 // the root is not a list
        "Lists/Read/Done",       // reserved (L3)
        "Lists/Done",            // reserved, whatever it holds
        "Lists/Read/Notes",      // too deep
        "Knowledge/Studium",     // not a list at all
    ])
    func theseFoldersAreNotLists(folder: String) {
        #expect(classifier.listFolderName(of: folder) == nil)
    }

    /// The lists root is overridable like every other folder (§3).
    @Test func aRenamedListsRootIsHonoured() {
        let german = VaultClassifier(layout: VaultLayout(lists: "Listen"))
        #expect(german.kind(of: "Listen/Lesen/Sapiens.md") == .listItem)
        #expect(german.listFolderName(of: "Listen/Lesen") == "Lesen")
        #expect(german.kind(of: "Lists/Read/Sapiens.md") == .other)
    }

    // MARK: - Indexing

    private func index() throws -> VaultSnapshot {
        let fs = InMemoryFileSystem(files: [
            "Lists/Read/Sapiens.md": "---\ncreated: 2026-09-01T09:30:00+02:00\n---\nMarie's copy",
            "Lists/Read/Why we sleep.md": "no frontmatter at all",
            "Lists/Read/Done/Thinking Fast and Slow.md": "---\n---\n",
            "Lists/Watch/Arrival.md": "---\n---\n",
            "Lists/Read/Notes/Deeper.md": "---\n---\n",
            "Lists/Stray.md": "---\n---\n",
            "Actions/Fix the bike light.md": "---\nstatus: next\n---\n",
        ])
        try fs.createFolder("Lists/Wish")          // an empty folder is a list too (L2)
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: fs)
        return index.snapshot(today: Day(year: 2026, month: 9, day: 19))
    }

    @Test func everyDirectSubfolderOfListsIsAList() throws {
        #expect(try index().lists.map(\.name) == ["Read", "Watch", "Wish"])
    }

    /// L2 — a list the user has just created has no items, and it is a list all the same.
    @Test func anEmptyFolderIsAList() throws {
        let snapshot = try index()
        #expect(snapshot.list(named: "Wish") != nil)
        #expect(snapshot.listItems.allSatisfy { $0.list != "Wish" })
    }

    @Test func itemsCarryTheirListAndWhetherTheyAreFinished() throws {
        let snapshot = try index()
        #expect(snapshot.listItems.map(\.id.path) == [
            "Lists/Read/Done/Thinking Fast and Slow.md",
            "Lists/Read/Sapiens.md",
            "Lists/Read/Why we sleep.md",
            "Lists/Watch/Arrival.md",
        ])
        #expect(snapshot.listItem(NoteID(path: "Lists/Read/Sapiens.md"))?.list == "Read")
        #expect(snapshot.listItem(NoteID(path: "Lists/Read/Sapiens.md"))?.isFinished == false)
        #expect(snapshot.listItem(
            NoteID(path: "Lists/Read/Done/Thinking Fast and Slow.md"))?.isFinished == true)
    }

    /// `Done/` is a log, not a list: it never shows up as one (L3, D38).
    @Test func theDoneFolderIsNotAList() throws {
        #expect(try index().lists.map(\.name).contains("Done") == false)
    }

    /// Nested deeper, or in no list: ignored and surfaced, never moved and never guessed at.
    @Test func misplacedNotesBecomeIssuesAndNoItems() throws {
        let snapshot = try index()
        let issuePaths = snapshot.issues.map(\.path)
        #expect(issuePaths.contains("Lists/Read/Notes/Deeper.md"))
        #expect(issuePaths.contains("Lists/Stray.md"))
        #expect(snapshot.listItems.allSatisfy { !$0.id.path.contains("Notes/") })
        #expect(snapshot.lists.map(\.name).contains("Notes") == false)
    }

    /// The sample vault's lists, end to end through the real codec — from the **files alone**.
    /// Every list folder holds at least one note, so a fresh clone carries all three (git does
    /// not track empty directories); nothing here creates a folder to help it along.
    @Test func theSampleVaultCarriesItsThreeLists() throws {
        guard NoteCodecParser.codecIsImplemented else { return }
        let fs = InMemoryFileSystem(files: SampleVault.files)
        var index = VaultIndex()
        try index.refresh(using: fs)
        let snapshot = index.snapshot(today: Day(year: 2026, month: 9, day: 19))
        #expect(snapshot.lists.map(\.name) == ["Read", "Watch", "Wish"])
        #expect(snapshot.listItems.count == 7)
        #expect(snapshot.listItems.count { $0.isFinished } == 1)
        #expect(snapshot.issues.isEmpty)
    }

    /// The same, from the **committed tree on disk** rather than the rendered dictionary — which
    /// is what a fresh clone actually has. Git does not track empty directories, so a list whose
    /// folder held no file would silently disappear here and nowhere else.
    @Test func everyListOfTheCommittedSampleVaultSurvivesACopyOfItsFiles() throws {
        guard NoteCodecParser.codecIsImplemented else { return }
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var index = VaultIndex()
        try index.refresh(using: PlainFileSystem(root: root))
        let snapshot = index.snapshot(today: Fixtures.today)

        #expect(snapshot.lists == Fixtures.lists)
        #expect(snapshot.listItems.map(\.id) == Fixtures.listItems.map(\.id).sorted())
        #expect(Rules.listRows(snapshot).allSatisfy { $0.openCount + $0.finishedCount > 0 },
                "a list folder with no file in it cannot survive a clone")
        #expect(snapshot.issues.isEmpty)
    }
}
