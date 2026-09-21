import Foundation
import GTDModel
import Testing
@testable import GTDVault

/// R-6 — `Projects/no_area/` is a **folder, not an area**: the classifier never yields an `Area`
/// for it, a project inside it has no area, and a project a pre-rework vault left directly under
/// `Projects/` keeps working exactly as it did.
@Suite("no_area: a folder, never an area (R-6)")
struct NoAreaIndexTests {

    private let classifier = VaultClassifier()

    // MARK: - Classification

    /// The one note under `Projects/` that is never read as an area or as a project. It is only
    /// reported — never moved, never rewritten.
    @Test(arguments: [
        "Projects/no_area/no_area.md",
        "Projects/NO_AREA/no_area.md",      // the file system is case-insensitive
        "Projects/no_area/No_Area.md",
    ])
    func theNoAreaNoteIsNeitherAnAreaNorAProject(path: String) {
        #expect(classifier.kind(of: path) == .noAreaNote)
        #expect(!classifier.noAreaNoteReason().isEmpty)
    }

    /// A project *inside* `no_area/` is an ordinary project note, and so is one in an area.
    @Test(arguments: [
        "Projects/no_area/Wohnungssuche/Wohnungssuche.md",
        "Projects/Applications/DAAD/DAAD.md",
        "Projects/Altbau/Altbau.md",                            // legacy, directly under Projects/
    ])
    func everyOtherProjectNoteIsStillAProjectNote(path: String) {
        #expect(classifier.kind(of: path) == .projectNote)
    }

    /// Anything else in `Projects/no_area/` is a reference file, exactly as anywhere else.
    @Test func otherFilesInTheNoAreaFolderAreReferenceFiles() {
        #expect(classifier.kind(of: "Projects/no_area/Wohnungssuche/Exposé.pdf") == .reference)
        #expect(classifier.kind(of: "Projects/no_area/Readme.md") == .reference)
    }

    @Test func onlyTheNoAreaFolderItselfIsTheNoAreaFolder() {
        #expect(classifier.isNoAreaFolder(of: "Projects/no_area"))
        #expect(classifier.isNoAreaFolder(of: "Projects/NO_AREA"))
        #expect(!classifier.isNoAreaFolder(of: "Projects"))
        #expect(!classifier.isNoAreaFolder(of: "Projects/no_area/Wohnungssuche"))
        #expect(!classifier.isNoAreaFolder(of: "Lists/no_area"))
    }

    /// The projects root is overridable, and `no_area` follows it (§3).
    @Test func theNoAreaFolderFollowsACustomProjectsRoot() {
        var layout = VaultLayout.default
        layout.projects = "20 Projekte"
        let custom = VaultClassifier(layout: layout)
        #expect(custom.kind(of: "20 Projekte/no_area/no_area.md") == .noAreaNote)
        #expect(custom.kind(of: "20 Projekte/no_area/Umzug/Umzug.md") == .projectNote)
        #expect(custom.kind(of: "Projects/no_area/no_area.md") == .other)
    }

    // MARK: - Indexing

    private func snapshot(_ files: [String: String]) throws -> VaultSnapshot {
        var index = VaultIndex(parser: StubNoteParser())
        try index.refresh(using: InMemoryFileSystem(files: files))
        return index.snapshot(today: MiniVault.today)
    }

    /// The acceptance criteria of R-6, on one indexed tree: `no_area` yields no area, a project
    /// inside it has `area == nil`, and a legacy top-level project is still indexed with no area.
    @Test func noAreaYieldsNoAreaAndItsProjectsHaveNone() throws {
        let snapshot = try snapshot([
            "Projects/Applications/Applications.md": "---\nkind: area\n---\n",
            "Projects/Applications/DAAD/DAAD.md":
                "---\nkind: project\nstatus: active\narea: Projects/Applications/Applications.md\n---\n",
            "Projects/no_area/Wohnungssuche/Wohnungssuche.md":
                "---\nkind: project\nstatus: active\n---\n",
            "Projects/Altbau/Altbau.md": "---\nkind: project\nstatus: active\n---\n",
        ])

        #expect(snapshot.areas.map(\.title) == ["Applications"], "no_area is never an area")
        #expect(snapshot.projects.map(\.title) == ["Altbau", "DAAD", "Wohnungssuche"])
        #expect(snapshot.project(NoteID(path: "Projects/no_area/Wohnungssuche/Wohnungssuche.md"))?
            .area == nil)
        // A project the user has not moved out of the `Projects/` root keeps working, with no
        // area and without anything moving it (R-6).
        #expect(snapshot.project(NoteID(path: "Projects/Altbau/Altbau.md"))?.area == nil)
        #expect(snapshot.issues.isEmpty)
    }

    /// A `no_area/no_area.md` that somebody wrote by hand — even one saying `kind: area` — is
    /// never an area. It becomes a `VaultIssue`, and the file is left exactly where it is.
    @Test func aHandWrittenNoAreaNoteIsReportedAndLeftAlone() throws {
        let files = [
            "Projects/no_area/no_area.md": "---\nkind: area\n---\n# no_area",
            "Projects/no_area/Wohnungssuche/Wohnungssuche.md":
                "---\nkind: project\nstatus: active\n---\n",
        ]
        let snapshot = try snapshot(files)

        #expect(snapshot.areas.isEmpty)
        #expect(snapshot.projects.map(\.title) == ["Wohnungssuche"])
        let issue = try #require(snapshot.issues.first { $0.path == "Projects/no_area/no_area.md" })
        #expect(issue.message.contains("no_area"))
        // Nothing the index does can move or rewrite it: the index only reads.
        #expect(snapshot.issues.count == 1)
    }

    /// A project in `no_area/` whose frontmatter still names an area contradicts its folder.
    /// The value is left exactly as the file spells it — the user is told instead.
    @Test func anAreaKeyInsideNoAreaIsReportedNotRewritten() throws {
        let snapshot = try snapshot([
            "Projects/Applications/Applications.md": "---\nkind: area\n---\n",
            "Projects/no_area/Umzug/Umzug.md":
                "---\nkind: project\nstatus: active\narea: Projects/Applications/Applications.md\n---\n",
        ])

        let issue = try #require(snapshot.issues.first {
            $0.path == "Projects/no_area/Umzug/Umzug.md"
        })
        #expect(issue.message.contains("area"))
        #expect(snapshot.project(NoteID(path: "Projects/no_area/Umzug/Umzug.md"))?.area
                == NoteID(path: "Projects/Applications/Applications.md"),
                "the note is read as it is written; nothing is silently corrected")
    }

    /// Reference files of a project in `no_area/` are found exactly as anywhere else (P6).
    @Test func referenceFilesOfAnAreaLessProjectAreStillFound() throws {
        let snapshot = try snapshot([
            "Projects/no_area/Wohnungssuche/Wohnungssuche.md":
                "---\nkind: project\nstatus: active\n---\n",
            "Projects/no_area/Wohnungssuche/Exposé.pdf": "%PDF",
        ])
        #expect(snapshot.projects.first?.referenceFiles
                == ["Projects/no_area/Wohnungssuche/Exposé.pdf"])
    }
}
