import Foundation
import GTDFixtures
import GTDModel
import Testing
@testable import GTDVault

/// The real integration: `PlainFileSystem` + `VaultIndex` + `GTDMarkdown.NoteCodec` against a
/// throw-away copy of the sample vault on disk.
///
/// **Gated on T10.** Until the codec is implemented every decode throws
/// `NoteCodecError.notImplemented`, so these tests would only prove that the scanner reports 55
/// issues. They enable themselves automatically as soon as `NoteCodec` decodes — no edit needed.
/// The store's own behaviour is covered without the codec in `VaultIndexTests`,
/// `FileVaultStoreTests` and `VaultTransactionTests`.
@Suite(.enabled(if: NoteCodecParser.codecIsImplemented))
struct SampleVaultScanTests {

    private func vault() throws -> URL { try SampleVault.copyToTemporaryDirectory() }

    private func store(_ root: URL) -> FileVaultStore {
        FileVaultStore(
            fileSystem: PlainFileSystem(root: root),
            watcher: NullVaultWatcher(),
            today: { Fixtures.today })
    }

    @Test func scanOfTheSampleVaultEqualsTheSampleSnapshot() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanned = try await store(root).scan()
        let expected = Fixtures.sampleSnapshot

        #expect(scanned.issues.isEmpty, "unexpected issues: \(scanned.issues)")

        #expect(scanned.inbox.map(\.id).sorted() == expected.inbox.map(\.id).sorted())
        #expect(Set(scanned.inbox.map(\.text)) == Set(expected.inbox.map(\.text)))
        #expect(scanned.inbox.compactMap(\.reviewReason).count
            == expected.inbox.compactMap(\.reviewReason).count)

        #expect(scanned.actions.map(\.id).sorted() == expected.actions.map(\.id).sorted())
        for expectedAction in expected.actions {
            let scannedAction = try #require(scanned.action(expectedAction.id))
            #expect(scannedAction.status == expectedAction.status)
            #expect(scannedAction.contexts == expectedAction.contexts)
            #expect(scannedAction.timeEstimate == expectedAction.timeEstimate)
            #expect(scannedAction.project == expectedAction.project)
            #expect(scannedAction.deferDate == expectedAction.deferDate)
            #expect(scannedAction.due == expectedAction.due)
            #expect(scannedAction.waitingFor == expectedAction.waitingFor)
            // The one field the fixtures cannot carry: it comes from the file system.
            #expect(scannedAction.modified != nil)
        }

        #expect(scanned.areas.map(\.id).sorted() == expected.areas.map(\.id).sorted())
        #expect(scanned.projects.map(\.id).sorted() == expected.projects.map(\.id).sorted())
        for expectedProject in expected.projects {
            let scannedProject = try #require(scanned.project(expectedProject.id))
            #expect(scannedProject.status == expectedProject.status)
            #expect(scannedProject.area == expectedProject.area)
            #expect(scannedProject.steps.count == expectedProject.steps.count)
        }

        #expect(scanned.routines.map(\.id).sorted() == expected.routines.map(\.id).sorted())
        #expect(scanned.routineLog.count == expected.routineLog.count)
        #expect(scanned.knowledgeFolders == expected.knowledgeFolders)
        #expect(scanned.config == expected.config)
        #expect(scanned.lastReview?.year == expected.lastReview?.year)
        #expect(scanned.lastReview?.week == expected.lastReview?.week)
    }

    @Test func anExternalEditIsPickedUpOnTheNextScan() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        let before = try await store.scan()

        // Obsidian on another device rewrites a note.
        let id = try #require(before.actions.first { $0.status == .next }?.id)
        let text = try #require(try await store.read(path: id.path))
        try text.replacingOccurrences(of: "status: next", with: "status: backlog")
            .write(to: root.appendingPathComponent(id.path), atomically: true, encoding: .utf8)

        let after = try await store.scan()
        #expect(after.action(id)?.status == .backlog)
    }

    @Test func commitAndItsInverseRestoreTheVaultByteForByte() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        let snapshot = try await store.scan()
        let before = try SampleVault.read(tree: root)

        let action = try #require(snapshot.actions.first { $0.status == .next })
        let inboxItem = try #require(snapshot.inbox.first)
        let text = try #require(try await store.read(path: action.id.path))

        let inverse = try await store.commit([
            .put(path: action.id.path, text: text + "\nAn edit.\n"),
            .move(from: action.id.path, to: "Actions/Renamed by the test.md"),
            .delete(path: inboxItem.id.path),
        ])
        _ = try await store.commit(inverse)

        var after = try SampleVault.read(tree: root)
        // Emptied trash folders are the only difference the round trip may leave behind.
        after = after.filter { !$0.key.hasPrefix(VaultLayout.default.trash + "/") }
        #expect(after == before)
    }

    @Test func aFileTheCodecCannotReadBecomesAnIssueAndTheRestStillScans() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        try "---\nstatus: [this is not a status\ncontexts\n---\n"
            .write(to: root.appendingPathComponent("Actions/Broken.md"),
                   atomically: true, encoding: .utf8)

        let snapshot = try await store(root).scan()
        #expect(snapshot.issues.map(\.path) == ["Actions/Broken.md"])
        #expect(snapshot.actions.count == Fixtures.sampleSnapshot.actions.count)
    }

    @Test func aConflictCopyInARealVaultIsReported() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Actions/Fix the bike light.md")
        let copy = root.appendingPathComponent("Actions/Fix the bike light 2.md")
        try FileManager.default.copyItem(at: original, to: copy)

        let snapshot = try await store(root).scan()
        #expect(snapshot.issues.contains {
            $0.path == "Actions/Fix the bike light 2.md" && $0.message.contains("conflict copy")
        })
        #expect(FileManager.default.fileExists(atPath: copy.path))   // never resolved for the user
    }

    @Test func aThousandNotesScanWithinTheBudget() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let template = try String(
            contentsOf: root.appendingPathComponent("Actions/Fix the bike light.md"),
            encoding: .utf8)
        for index in 0..<1000 {
            try template.write(
                to: root.appendingPathComponent("Actions/Generated \(index).md"),
                atomically: true, encoding: .utf8)
        }

        let store = store(root)
        let start = Date()
        let snapshot = try await store.scan()
        let seconds = Date().timeIntervalSince(start)
        #expect(snapshot.actions.count >= 1000)
        #expect(seconds < 5.0, "scan of 1 000+ notes took \(seconds)s")
    }
}

/// These run whether or not T10 has landed: they are about the scanner, not the codec.
@Suite("The sample vault on disk, without decoding")
struct SampleVaultFileSystemTests {

    @Test func everySampleFileIsClassifiedAndNothingIsLost() throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fs = PlainFileSystem(root: root)
        let classifier = VaultClassifier()

        let paths = try fs.listFiles().map(\.path)
        #expect(paths.count == 55, "the sample vault has 55 files; got \(paths.count)")
        #expect(paths.filter { classifier.kind(of: $0) == .other }.isEmpty,
                "unclassified: \(paths.filter { classifier.kind(of: $0) == .other })")
        #expect(paths.contains("GTD/Config.md"))
        #expect(VaultClassifier.conflictCopies(among: paths).isEmpty)
    }

    @Test func theKnowledgeFolderTreeMatchesTheFixtures() throws {
        let root = try SampleVault.copyToTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let classifier = VaultClassifier()
        let folders = try PlainFileSystem(root: root).listFolders()
            .compactMap(classifier.knowledgeFolder).sorted()
        #expect(folders == Fixtures.knowledgeFolders.sorted())
    }

    @Test func tryingToScanTheRealVaultIsImpossibleFromHere() {
        // The durable rule (CLAUDE.md 1): tests use fixtures or temp dirs. This is a reminder
        // in code — nothing in GTDVault knows the iCloud path, and nothing constructs one.
        #expect(VaultLayout.default.requiredFolders.allSatisfy { !$0.contains("iCloud") })
    }
}
