import Testing
import Foundation
import GTDAppCore
@testable import GTDServices

/// #94 — the dialog drafts' file in Application Support.
struct FileInputDraftStoreTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("drafts-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("input-drafts.json")
    }

    @Test func roundTripsAndRemovesTheFileWhenEmpty() throws {
        let store = FileInputDraftStore(file: tempFile())
        #expect(try store.load().isEmpty, "no file yet is no drafts")

        let drafts = ["newProject": InputDraft(json: "{\"title\":\"Thesis\"}", savedAt: Date(timeIntervalSince1970: 1_790_000_000))]
        try store.save(drafts)
        #expect(try store.load() == drafts)

        try store.save([:])
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
    }

    @Test func aDamagedFileThrowsInsteadOfReadingAsEmpty() throws {
        let store = FileInputDraftStore(file: tempFile())
        try FileManager.default.createDirectory(
            at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.file)
        #expect(throws: (any Error).self) { try store.load() }
    }
}
