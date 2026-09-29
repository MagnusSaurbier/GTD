import Foundation
import GTDModel
import Testing
@testable import GTDVault

/// #60 — "Create new vault" from onboarding. Every test works in its own temp directory; none
/// touches the real vault (CLAUDE.md rule 1).
@Suite("VaultCreator — a new, empty vault (#60)")
struct VaultCreatorTests {

    private func makeLocation() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultCreatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Every file below `root`, relative, sorted — directories excluded.
    private func files(below root: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        var result: [String] = []
        while let path = enumerator?.nextObject() as? String {
            var isDirectory: ObjCBool = false
            let full = root.appendingPathComponent(path).path
            if FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                result.append(path)
            }
        }
        return result.sorted()
    }

    @Test func createsTheFolderAndTheWholeLayoutAndNothingElse() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }

        let root = try VaultCreator.create(named: "My GTD", in: location)

        #expect(root.lastPathComponent == "My GTD")
        for folder in VaultLayout.default.requiredFolders {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent(folder).path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue, "\(folder) is a folder")
        }
        #expect(files(below: root).isEmpty, "no sample notes, no config — folders only")
    }

    /// "Only what the app needs to open it without vault issues": the store opens the new vault
    /// with an empty snapshot and no issues.
    @Test func theNewVaultOpensEmptyAndWithoutIssues() async throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }
        let root = try VaultCreator.create(named: "Fresh", in: location)

        let store = FileVaultStore(root: root)
        let snapshot = try await store.scan()
        await store.close()

        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.actions.isEmpty)
        #expect(snapshot.projects.isEmpty)
        #expect(snapshot.inbox.isEmpty)
    }

    @Test func refusesAFolderThatAlreadyHasContentAndLeavesItUntouched() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }
        let existing = location.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let note = existing.appendingPathComponent("note.md")
        try Data("keep me".utf8).write(to: note)

        #expect(throws: VaultCreator.Refusal.notEmpty("Vault")) {
            try VaultCreator.create(named: "Vault", in: location)
        }
        #expect(files(below: existing) == ["note.md"], "nothing was added")
        #expect(try String(contentsOf: note, encoding: .utf8) == "keep me")
    }

    /// A hidden file is content too — only Finder's `.DS_Store` is not.
    @Test func aHiddenFileCountsAsContent() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }
        let existing = location.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: existing.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)

        #expect(throws: VaultCreator.Refusal.notEmpty("Vault")) {
            try VaultCreator.create(named: "Vault", in: location)
        }
        #expect(!FileManager.default.fileExists(atPath: existing.appendingPathComponent("Actions").path))
    }

    @Test func anExistingEmptyFolderIsUsed() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }
        let existing = location.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data().write(to: existing.appendingPathComponent(".DS_Store"))

        let root = try VaultCreator.create(named: "Vault", in: location)
        #expect(root.standardizedFileURL == existing.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: existing.appendingPathComponent("Actions").path))
    }

    @Test func refusesAFileOfThatName() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }
        let file = location.appendingPathComponent("Vault")
        try Data("x".utf8).write(to: file)

        #expect(throws: VaultCreator.Refusal.notAFolder("Vault")) {
            try VaultCreator.create(named: "Vault", in: location)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "x")
    }

    @Test func refusesAMissingLocation() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }
        let missing = location.appendingPathComponent("gone", isDirectory: true)

        #expect(throws: VaultCreator.Refusal.locationMissing(missing.path)) {
            try VaultCreator.create(named: "Vault", in: missing)
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func namesAreTrimmedSanitisedAndNeverEmptyOrHidden() throws {
        #expect(try VaultCreator.folderName(for: "  GTD  ") == "GTD")
        #expect(try VaultCreator.folderName(for: "Work: 2026") == "Work 2026")
        #expect(throws: VaultCreator.Refusal.emptyName) { try VaultCreator.folderName(for: "   ") }
        #expect(throws: VaultCreator.Refusal.hiddenName(".vault")) {
            try VaultCreator.folderName(for: ".vault")
        }
        #expect(VaultCreator.Refusal.notEmpty("X").errorDescription?.contains("not empty") == true)
    }

    @Test func withAccessBracketsTheBody() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location) }
        let bookmark = VaultBookmark(
            store: PathBookmarkStore(), fileURL: location.appendingPathComponent("bookmark.data"))
        let root = try bookmark.withAccess(to: location) {
            let root = try VaultCreator.create(named: "Inside", in: location)
            try bookmark.save(url: root)
            return root
        }
        #expect(try bookmark.resolve().standardizedFileURL.path == root.standardizedFileURL.path)
    }
}
