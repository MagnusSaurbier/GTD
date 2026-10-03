import Foundation
import GTDModel
import Testing
@testable import GTDVault

/// #89 — an inbox note without `created` (a capture Shortcut that writes only the text, a note
/// typed in Obsidian) is dated by the file's **birth** time, not its modification time: editing
/// the capture in Obsidian must not move it to the top of the Inbox.
struct CaptureDateTests {
    private let born = Date(timeIntervalSince1970: 1_790_000_000)
    private let edited = Date(timeIntervalSince1970: 1_790_086_400)

    // MARK: VaultFileInfo.captureDate

    @Test func theBirthTimeDatesAFileThatWasEditedLater() {
        let info = VaultFileInfo(path: "Inbox/x.md", size: 1, modified: edited, created: born)
        #expect(info.captureDate == born)
    }

    @Test func theModificationTimeStandsInWhereThereIsNoBirthTime() {
        let info = VaultFileInfo(path: "Inbox/x.md", size: 1, modified: edited, created: nil)
        #expect(info.captureDate == edited)
    }

    /// A copy or a restore makes a new file (fresh birth time) that keeps an old modification
    /// time; the content is at least as old as its last change.
    @Test func anOlderModificationTimeThanBirthTimeWins() {
        let info = VaultFileInfo(path: "Inbox/x.md", size: 1, modified: born, created: edited)
        #expect(info.captureDate == born)
    }

    @Test func theBirthTimeIsNotPartOfTheFingerprint() {
        let a = VaultFileInfo(path: "Inbox/x.md", size: 1, modified: edited, created: born)
        let b = VaultFileInfo(path: "Inbox/x.md", size: 1, modified: edited, created: nil)
        #expect(a.fingerprint == b.fingerprint)
    }

    // MARK: The index

    @Test func anInboxNoteWithoutCreatedIsDatedByItsBirthTime() throws {
        let fs = InMemoryFileSystem(files: ["Inbox/buy running shoes.md": "buy running shoes\n"])
        fs.setDates(of: "Inbox/buy running shoes.md", created: born, modified: edited)

        let item = try #require(try Self.inbox(fs).first)
        #expect(item.created == born)
    }

    @Test func withoutABirthTimeTheIndexFallsBackToTheModificationTime() throws {
        let fs = InMemoryFileSystem(files: ["Inbox/buy running shoes.md": "buy running shoes\n"])
        fs.setDates(of: "Inbox/buy running shoes.md", created: nil, modified: edited)

        let item = try #require(try Self.inbox(fs).first)
        #expect(item.created == edited)
    }

    /// Fifty captures from a Shortcut that wrote nothing but their text sort by when each was
    /// made — the frozen-`created` ties that started #89 cannot happen without the line.
    @Test func capturesWithoutCreatedSortByBirthTimeNotByEdits() throws {
        var files: [String: String] = [:]
        for n in 0..<50 { files["Inbox/capture \(n).md"] = "capture \(n)\n" }
        let fs = InMemoryFileSystem(files: files)
        for n in 0..<50 {
            // Born in order, all touched at the same later moment (a sync, a bulk edit).
            fs.setDates(of: "Inbox/capture \(n).md",
                        created: born.addingTimeInterval(Double(n) * 60), modified: edited)
        }

        let created = try Self.inbox(fs).sorted { $0.id.path < $1.id.path }.map(\.created)
        #expect(Set(created).count == 50, "no ties")
    }

    @Test func anExplicitCreatedStillWins() throws {
        let fs = InMemoryFileSystem(files: [
            "Inbox/old.md": "---\ncreated: 2026-01-02T03:04:05+00:00\n---\nold\n",
        ])
        fs.setDates(of: "Inbox/old.md", created: born, modified: edited)

        let item = try #require(try Self.inbox(fs).first)
        #expect(item.created == Date(timeIntervalSince1970: 1_767_323_045))
    }

    /// `PlainFileSystem` reads the birth time where the platform has one. Setting it needs a file
    /// system that stores it (APFS does); where it does not stick, the fallback is what counts.
    @Test func plainFileSystemReportsTheBirthTime() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("CaptureDateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fs = PlainFileSystem(root: root)
        try fs.writeText("buy running shoes\n", to: "Inbox/buy running shoes.md")
        let url = root.appendingPathComponent("Inbox/buy running shoes.md")
        try? FileManager.default.setAttributes(
            [.creationDate: born, .modificationDate: edited], ofItemAtPath: url.path)

        let info = try #require(try fs.info("Inbox/buy running shoes.md"))
        let listed = try #require(try fs.listFiles().first { $0.path == info.path })
        #expect(listed.created == info.created)
        let item = try #require(try Self.inbox(fs).first)
        if let birth = info.created, abs(birth.timeIntervalSince(born)) < 1 {
            #expect(abs(item.created.timeIntervalSince(born)) < 1)
        } else {
            #expect(item.created == info.captureDate)
        }
#if os(macOS)
        #expect(info.created.map { abs($0.timeIntervalSince(born)) < 1 } == true,
                "APFS keeps a birth time and lets it be set")
#endif
    }

    private static func inbox(_ fs: any VaultFileSystem) throws -> [InboxItem] {
        var index = VaultIndex()
        try index.refresh(using: fs)
        return index.snapshot(today: Day(year: 2026, month: 9, day: 19)).inbox
    }
}
