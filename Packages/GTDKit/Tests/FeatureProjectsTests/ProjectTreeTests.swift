import Testing
import Foundation
import GTDModel
@testable import FeatureProjects

/// #67 — the projects overview's folder tree, built from paths alone.
struct ProjectTreeTests {
    private typealias Tree = ProjectTree<NoteID>

    private func tree(_ paths: [String], layout: VaultLayout = .default) -> Tree {
        Tree(rows: paths.map { NoteID(path: $0) }, layout: layout, id: { $0 }, title: \.title)
    }

    /// The layout the user described: nested areas, top folders without an area note, a project
    /// directly in a top folder, area-less projects in `no_area/` and directly under `Projects/`.
    private let vault = [
        "Projects/Orga/Wohnungssuche/Besichtigungen/Besichtigungen.md",
        "Projects/Growth/Coding/BrainTrain/BrainTrain.md",
        "Projects/Orga/GTD/GTD.md",
        "Projects/no_area/Zahnarzt/Zahnarzt.md",
        "Projects/Karriere/Applications/DAAD/DAAD.md",
        "Projects/Growth/Coding/apps/apps.md",
        "Projects/Karriere/Applications/Erasmus/Erasmus.md",
        "Projects/Solo/Solo.md",
        "Projects/Orga/Wohnungssuche/Umzug/Umzug.md",
    ]

    private func titles(_ lines: [Tree.Line]) -> [String] {
        lines.map { line in
            switch line {
            case let .folder(_, name, depth, open):
                String(repeating: "  ", count: depth) + (open ? "v " : "> ") + name
            case let .project(_, id, depth):
                String(repeating: "  ", count: depth) + id.title
            }
        }
    }

    @Test func areaLessProjectsSitFlatOnTopAlphabetically() {
        let built = tree(vault)
        #expect(built.top.map(\.title) == ["Solo", "Zahnarzt"])
    }

    @Test func foldersMirrorTheVaultAndSortAlphabeticallyFoldersFirst() {
        #expect(titles(tree(vault).lines(collapsed: [], id: { $0 })) == [
            "Solo",
            "Zahnarzt",
            "v Growth",
            "  v Coding",
            "    apps",
            "    BrainTrain",
            "v Karriere",
            "  v Applications",
            "    DAAD",
            "    Erasmus",
            "v Orga",
            "  v Wohnungssuche",
            "    Besichtigungen",
            "    Umzug",
            "  GTD",          // directly in the top folder — after its sub-folders
        ])
    }

    @Test func nodeIDsAreVaultFolderPaths() {
        let built = tree(vault)
        #expect(built.nodes.map(\.id) == ["Projects/Growth", "Projects/Karriere", "Projects/Orga"])
        #expect(built.nodes[0].children.map(\.id) == ["Projects/Growth/Coding"])
    }

    @Test func collapsedFolderHidesItsWholeSubtree() {
        let lines = tree(vault).lines(collapsed: ["Projects/Orga", "Projects/Growth/Coding"], id: { $0 })
        #expect(titles(lines) == [
            "Solo", "Zahnarzt",
            "v Growth", "  > Coding",
            "v Karriere", "  v Applications", "    DAAD", "    Erasmus",
            "> Orga",
        ])
    }

    @Test func foldersWithoutProjectsDoNotExist() {
        // The status filter runs before the tree is built, so a folder whose projects are all
        // filtered out simply never becomes a node.
        let built = tree(["Projects/Orga/GTD/GTD.md", "Projects/no_area/X/X.md"])
        #expect(built.nodes.map(\.name) == ["Orga"])
        #expect(tree([]).isEmpty)
    }

    @Test func noAreaIsMatchedCaseInsensitivelyAndCustomRootsWork() {
        let layout = VaultLayout(projects: "Work/Projects")
        let built = tree(["Work/Projects/No_Area/A/A.md", "Work/Projects/Area/B/B.md"], layout: layout)
        #expect(built.top.map(\.title) == ["A"])
        #expect(built.nodes.map(\.id) == ["Work/Projects/Area"])
    }

    @Test func sortingIsCaseInsensitiveAndNumeric() {
        #expect(ProjectTreePath.precedes("apps", "BrainTrain"))
        #expect(ProjectTreePath.precedes("Step 2", "Step 10"))
        #expect(!ProjectTreePath.precedes("b", "A"))
    }

    @Test func parentFolders() {
        let root = ["Projects"]
        #expect(ProjectTreePath.parentFolders(
            of: NoteID(path: "Projects/Growth/Coding/BrainTrain/BrainTrain.md"), projectsRoot: root)
            == ["Growth", "Coding"])
        #expect(ProjectTreePath.parentFolders(of: NoteID(path: "Projects/Solo/Solo.md"), projectsRoot: root) == [])
        #expect(ProjectTreePath.parentFolders(of: NoteID(path: "Elsewhere/A/B/B.md"), projectsRoot: root) == [])
    }

    @Test func collapsedStateRoundTripsThroughItsStorageString() {
        let collapsed: Set<String> = ["Projects/Orga", "Projects/Growth/Coding"]
        #expect(ProjectTreePath.decode(ProjectTreePath.encode(collapsed)) == collapsed)
        #expect(ProjectTreePath.decode("") == [])
        #expect(ProjectTreePath.toggling("Projects/Orga", in: collapsed) == ["Projects/Growth/Coding"])
        #expect(ProjectTreePath.toggling("Projects/X", in: []) == ["Projects/X"])
    }
}
