import Testing
import Foundation
import GTDAppCore
@testable import GTDServices

/// #56 — the crash journal's file in Application Support.
struct FileUnsavedTextStoreTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("unsaved-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("unsaved-text.json")
    }

    @Test func roundTripsAndRemovesTheFileWhenEmpty() throws {
        let store = FileUnsavedTextStore(file: tempFile())
        #expect(try store.load().isEmpty, "no file yet is an empty journal")

        let entry = UnsavedText(kind: .listItem, path: "Lists/Read/Dune.md", title: "Dune",
                                text: "notes\nwith lines", savedAt: Date(timeIntervalSince1970: 1_790_000_000))
        try store.save([entry])
        #expect(try store.load() == [entry])

        try store.save([])
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
    }

    @Test func aDamagedFileThrowsInsteadOfReadingAsEmpty() throws {
        let store = FileUnsavedTextStore(file: tempFile())
        try FileManager.default.createDirectory(
            at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.file)
        #expect(throws: (any Error).self) { try store.load() }
    }
}
