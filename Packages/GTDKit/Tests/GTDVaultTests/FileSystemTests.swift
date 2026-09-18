import Foundation
import GTDModel
import Testing
@testable import GTDVault

/// A throw-away directory that is removed when the test ends. Never the real vault.
final class TempVault {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("GTDVaultTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ text: String, to path: String) throws {
        let target = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(path).path)
    }
}

@Suite("PlainFileSystem on a real temp directory")
struct PlainFileSystemTests {

    @Test func listsFilesAndFoldersRecursivelySkippingDotFiles() throws {
        let vault = try TempVault()
        try vault.write("a", to: "Actions/A.md")
        try vault.write("b", to: "Projects/Applications/DAAD/DAAD.md")
        try vault.write("junk", to: ".obsidian/workspace.json")
        try vault.write("junk", to: "Actions/.DS_Store")
        let fs = PlainFileSystem(root: vault.url)

        #expect(try fs.listFiles().map(\.path) == ["Actions/A.md", "Projects/Applications/DAAD/DAAD.md"])
        let folders = try fs.listFolders()
        #expect(folders.contains("Projects/Applications/DAAD"))
        #expect(!folders.contains(".obsidian"))
    }

    @Test func writeIsAtomicAndCreatesIntermediateFolders() throws {
        let vault = try TempVault()
        let fs = PlainFileSystem(root: vault.url)
        try fs.writeText("hello", to: "GTD/Reviews/2026/KW 38.md")
        #expect(vault.read("GTD/Reviews/2026/KW 38.md") == "hello")
        // No stray temp file left behind by the atomic write.
        #expect(try fs.listFiles().map(\.path) == ["GTD/Reviews/2026/KW 38.md"])
    }

    @Test func writeOverwritesAndFingerprintChanges() throws {
        let vault = try TempVault()
        let fs = PlainFileSystem(root: vault.url)
        try fs.writeText("one", to: "Actions/A.md")
        let first = try #require(try fs.info("Actions/A.md"))
        try fs.writeText("two longer text", to: "Actions/A.md")
        let second = try #require(try fs.info("Actions/A.md"))
        #expect(first.fingerprint != second.fingerprint)
        #expect(try fs.readText("Actions/A.md") == "two longer text")
    }

    @Test func moveNeverOverwrites() throws {
        let vault = try TempVault()
        let fs = PlainFileSystem(root: vault.url)
        try fs.writeText("one", to: "Actions/A.md")
        try fs.writeText("two", to: "Actions/B.md")
        #expect(throws: VaultError.destinationExists(path: "Actions/B.md")) {
            try fs.move("Actions/A.md", to: "Actions/B.md")
        }
        #expect(vault.read("Actions/A.md") == "one")
        #expect(vault.read("Actions/B.md") == "two")
    }

    @Test func moveCreatesTheDestinationFolder() throws {
        let vault = try TempVault()
        let fs = PlainFileSystem(root: vault.url)
        try fs.writeText("done", to: "Actions/A.md")
        try fs.move("Actions/A.md", to: "Archive/2026/09/A.md")
        #expect(!vault.exists("Actions/A.md"))
        #expect(vault.read("Archive/2026/09/A.md") == "done")
    }

    @Test func readingAMissingFileReturnsNil() throws {
        let vault = try TempVault()
        let fs = PlainFileSystem(root: vault.url)
        #expect(try fs.readText("Actions/Nope.md") == nil)
        #expect(try fs.info("Actions/Nope.md") == nil)
    }

    @Test func pathsThatEscapeTheVaultAreRefused() throws {
        let vault = try TempVault()
        let fs = PlainFileSystem(root: vault.url)
        #expect(throws: VaultError.self) { try fs.writeText("x", to: "../escaped.md") }
        #expect(throws: VaultError.self) { try fs.readText("Actions/../../etc/passwd") }
    }

    @Test func evictediCloudItemIsListedAsNotDownloadedAndRefusesToRead() throws {
        let vault = try TempVault()
        // iCloud replaces `Foo.md` with the hidden placeholder `.Foo.md.icloud`.
        try vault.write("", to: "Actions/.Evicted.md.icloud")
        let fs = PlainFileSystem(root: vault.url)

        let files = try fs.listFiles()
        #expect(files.map(\.path) == ["Actions/Evicted.md"])
        #expect(files[0].isDownloaded == false)
        #expect(throws: VaultError.notDownloaded(path: "Actions/Evicted.md")) {
            try fs.readText("Actions/Evicted.md")
        }
    }

    @Test func aMissingRootIsAnError() throws {
        let fs = PlainFileSystem(root: URL(fileURLWithPath: "/definitely/not/here"))
        #expect(throws: VaultError.self) { try fs.listFiles() }
    }

    @Test func thereIsNoDeleteOnTheProtocol() throws {
        // The compile-time guarantee behind "the app never hard-deletes a vault file":
        // `VaultFileSystem` exposes no removal at all, so `GTD/Trash/` is the only way out.
        let vault = try TempVault()
        let fs: any VaultFileSystem = PlainFileSystem(root: vault.url)
        try fs.writeText("x", to: "Actions/A.md")
        try fs.move("Actions/A.md", to: "GTD/Trash/A.md")
        #expect(vault.read("GTD/Trash/A.md") == "x")
    }
}

@Suite("InMemoryFileSystem behaves like the real one")
struct InMemoryFileSystemTests {

    @Test func storesReadsAndMoves() throws {
        let fs = InMemoryFileSystem(files: ["Actions/A.md": "one"])
        #expect(try fs.readText("Actions/A.md") == "one")
        try fs.move("Actions/A.md", to: "GTD/Trash/A.md")
        #expect(fs.exists("Actions/A.md") == false)
        #expect(try fs.readText("GTD/Trash/A.md") == "one")
    }

    @Test func refusesToOverwriteOnMove() throws {
        let fs = InMemoryFileSystem(files: ["A.md": "one", "B.md": "two"])
        #expect(throws: VaultError.destinationExists(path: "B.md")) { try fs.move("A.md", to: "B.md") }
    }

    @Test func injectedFailuresAndEviction() throws {
        let fs = InMemoryFileSystem(files: ["A.md": "one", "B.md": "two"])
        fs.failWrites(matching: ["A.md"])
        #expect(throws: VaultError.self) { try fs.writeText("x", to: "A.md") }
        #expect(try fs.readText("A.md") == "one")

        fs.evict("B.md")
        #expect(throws: VaultError.notDownloaded(path: "B.md")) { try fs.readText("B.md") }
        #expect(try fs.listFiles().first { $0.path == "B.md" }?.isDownloaded == false)
    }

    @Test func derivesFoldersFromPaths() throws {
        let fs = InMemoryFileSystem(files: ["Knowledge/Studium/Thesis/S.md": "x"])
        #expect(try fs.listFolders() == ["Knowledge", "Knowledge/Studium", "Knowledge/Studium/Thesis"])
    }

    @Test func everyWriteAdvancesTheFingerprint() throws {
        let fs = InMemoryFileSystem(files: ["A.md": "one"])
        let first = try #require(try fs.info("A.md"))
        try fs.writeText("one", to: "A.md")     // same content, new mtime
        let second = try #require(try fs.info("A.md"))
        #expect(first.fingerprint != second.fingerprint)
    }
}
