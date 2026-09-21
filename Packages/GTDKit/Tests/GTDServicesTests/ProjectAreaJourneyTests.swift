import Testing
import Foundation
import GTDModel
import GTDAppCore
import GTDFixtures
import GTDServices
import GTDVault

/// R-6/R-7 end to end, through the **real** stack — `AppModel` → `VaultBackend` →
/// `FileVaultStore` → `PlainFileSystem` over a temp copy of the sample vault. The assertions are
/// about the **files**: an area-less project is a folder in `Projects/no_area/`, changing its area
/// moves that folder with everything inside it, and one undo brings the whole thing back byte for
/// byte. Never the real vault (CLAUDE.md rule 1).
@MainActor
@Suite("A project's area is its folder (R-6, R-7)")
struct ProjectAreaJourneyTests {

    /// Create a project by name only → it lands in `Projects/no_area/` → an action links to it →
    /// assigning an area moves the folder, the reference file inside travels, the action's
    /// `project:` line is rewritten on disk, the renames name every note that moved → undo
    /// restores every byte.
    @Test func anAreaLessProjectIsCreatedInNoAreaAndMovesWhenItGetsAnArea() async throws {
        let vault = try TestVault.onDisk(deviceID: "mac-1")
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.actions.isEmpty }

        // ── 1. Name only — everything else can be filled in later (P2, I4a) ───────────────────
        try await model.send(.createProject(ProjectDraft(title: "Wohnung streichen")))
        let noAreaID = NoteID(path: "Projects/no_area/Wohnung streichen/Wohnung streichen.md")
        let projectNote = try #require(try vault.text(noAreaID.path))
        #expect(projectNote.contains("kind: project"))
        #expect(projectNote.contains("status: active"))
        #expect(!projectNote.contains("area:"), "no area means no `area:` line (no lying defaults)")
        #expect(model.snapshot.project(noAreaID)?.area == nil)

        // ── 2. An action links to it, and a reference file lands in its folder (P6) ───────────
        try await model.send(.createAction(ActionDraft(
            title: "Farbe aussuchen",
            status: .someday,
            project: noAreaID,
            what: "Drei Weißtöne vergleichen.")))
        let actionPath = "Actions/Farbe aussuchen.md"
        #expect(try #require(try vault.text(actionPath))
            .contains("project: \"[[Projects/no_area/Wohnung streichen/Wohnung streichen]]\""))

        let referencePath = "Projects/no_area/Wohnung streichen/Farbkarte.md"
        try vault.fileSystem.writeText("RAL 9010, RAL 9016", to: referencePath)
        await vault.store.simulateChangeForTesting()
        await settle(model) { $0.project(noAreaID)?.referenceFiles.isEmpty == false }

        let beforeTheMove = try vault.filesOutsideTheTrash()

        // ── 3. Assigning an area moves the folder — one command, one commit (R-7) ─────────────
        let area = try #require(model.snapshot.areas.first { $0.title == "Karriereplanung" })
        var project = try #require(model.snapshot.project(noAreaID))
        project.area = area.id
        try await model.send(.updateProject(project))

        let movedID = NoteID(path: "Projects/Karriereplanung/Wohnung streichen/Wohnung streichen.md")
        #expect(try vault.text(noAreaID.path) == nil, "the old folder is empty")
        #expect(try await vault.store.folderContents("Projects/no_area/Wohnung streichen") == nil)
        #expect(try vault.text("Projects/Karriereplanung/Wohnung streichen/Farbkarte.md")
                == "RAL 9010, RAL 9016", "everything inside the folder travelled with it")
        let movedNote = try #require(try vault.text(movedID.path))
        #expect(movedNote.contains("area: \"[[Projects/Karriereplanung/Karriereplanung]]\""))
        // The action's wikilink was rewritten in the same commit as the folder move.
        #expect(try #require(try vault.text(actionPath))
            .contains("project: \"[[Projects/Karriereplanung/Wohnung streichen/Wohnung streichen]]\""))

        // R-7 — an open detail view follows the note instead of concluding it was deleted, and so
        // does an open reference note.
        let renames = model.consumeRenames()
        #expect(renames.resolve(noAreaID) == movedID)
        #expect(renames.resolve(NoteID(path: referencePath))
                == NoteID(path: "Projects/Karriereplanung/Wohnung streichen/Farbkarte.md"))

        // ── 4. One journal entry: undo puts every byte back (N6) ─────────────────────────────
        await model.undo()
        #expect(model.lastError == nil)
        #expect(try vault.filesOutsideTheTrash() == beforeTheMove)
        #expect(try await vault.store.folderContents("Projects/Karriereplanung/Wohnung streichen")
                == nil)

        // ── 5. …and a cold re-scan of the bytes agrees ───────────────────────────────────────
        let rescanned = try vault.rescan()
        #expect(rescanned.project(noAreaID)?.area == nil)
        #expect(rescanned.action(NoteID(path: actionPath))?.project == noAreaID)
        #expect(rescanned.issues.isEmpty, "the journey left no unreadable file behind")
    }

    /// The other direction: taking the area away moves the folder into `Projects/no_area/`, and
    /// the `area:` line goes with it.
    @Test func takingTheAreaAwayMovesTheProjectIntoNoArea() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.projects.isEmpty }

        let id = NoteID(path: "Projects/Applications/Erasmus/Erasmus.md")
        var project = try #require(model.snapshot.project(id))
        #expect(project.area != nil)
        project.area = nil
        try await model.send(.updateProject(project))

        let movedID = NoteID(path: "Projects/no_area/Erasmus/Erasmus.md")
        #expect(try vault.text(id.path) == nil)
        let note = try #require(try vault.text(movedID.path))
        #expect(!note.contains("area:"), "the stale `area:` line is gone with the folder")
        #expect(note.contains("kind: project"), "the rest of the note is untouched")

        let linked = try #require(try vault.text("Actions/Compare Erasmus partner universities.md"))
        #expect(linked.contains("project: \"[[Projects/no_area/Erasmus/Erasmus]]\""))
        // A promoted step points at an action, which did not move (R-7).
        #expect(note.contains("→ [[Actions/Compare Erasmus partner universities]]"))

        let rescanned = try vault.rescan()
        #expect(rescanned.project(movedID)?.area == nil)
        #expect(rescanned.issues.isEmpty)
    }

    /// Never overwrite: an area that already holds a project of that name refuses the move, and
    /// the tree is left exactly as it was.
    @Test func movingOntoATakenFolderIsRefusedAndChangesNothing() async throws {
        let vault = try TestVault.onDisk()
        defer { vault.cleanUp() }
        try await vault.backend.start()
        let model = AppModel(backend: vault.backend, today: { Fixtures.today })
        defer { model.stop() }
        await settle(model) { !$0.projects.isEmpty }

        // `Projects/Applications/DAAD` is already there; this one is area-less.
        try await model.send(.createProject(ProjectDraft(title: "DAAD")))
        let id = NoteID(path: "Projects/no_area/DAAD/DAAD.md")
        let before = try vault.files()

        let area = try #require(model.snapshot.areas.first { $0.title == "Applications" })
        var project = try #require(model.snapshot.project(id))
        project.area = area.id
        await #expect(throws: GTDError.titleCollision("DAAD")) {
            try await model.send(.updateProject(project))
        }
        #expect(try vault.files() == before, "a refused move writes nothing and moves nothing")
        #expect(try vault.text("Projects/Applications/DAAD/DAAD.md") != nil)
    }

    // MARK: - Helpers

    /// Same poll as `ListJourneyTests`: a store change reaches `AppModel` over three hops.
    @discardableResult
    private func settle(
        _ model: AppModel, until condition: @MainActor (VaultSnapshot) -> Bool
    ) async -> Bool {
        for _ in 0..<2_000 {
            if condition(model.snapshot) { return true }
            await Task.yield()
        }
        return condition(model.snapshot)
    }
}
