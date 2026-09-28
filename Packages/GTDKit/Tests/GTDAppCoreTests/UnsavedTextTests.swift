import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDAppCore

/// #56 — the crash journal: what an entry restores into, and when the journal writes.
@MainActor
struct UnsavedTextTests {

    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(_ kind: UnsavedText.Kind = .action, path: String, title: String? = nil,
                       text: String? = "typed") -> UnsavedText {
        UnsavedText(kind: kind, path: path, title: title, text: text, savedAt: when)
    }

    // MARK: Restore

    /// Only the unsaved fields change; the rest of the action stays as the vault has it.
    @Test func anActionGetsItsTypedBodyAndKeepsTheRest() throws {
        let action = try #require(Fixtures.sampleSnapshot.actions.first)
        let command = entry(path: action.id.path, text: "# Why?\nnew").restoreCommand(in: Fixtures.sampleSnapshot)
        guard case let .updateAction(restored)? = command else {
            Issue.record("expected updateAction, got \(String(describing: command))"); return
        }
        #expect(restored.body == "# Why?\nnew")
        #expect(restored.title == action.title)
        #expect(restored.status == action.status)
        #expect(restored.contexts == action.contexts)
    }

    @Test func anUnsavedTitleIsRestoredToo() throws {
        let action = try #require(Fixtures.sampleSnapshot.actions.first)
        let command = entry(path: action.id.path, title: "Renamed", text: nil)
            .restoreCommand(in: Fixtures.sampleSnapshot)
        guard case let .updateAction(restored)? = command else { Issue.record("no command"); return }
        #expect(restored.title == "Renamed")
        #expect(restored.body == action.body)
    }

    @Test func aListItemGetsItsNotes() throws {
        let item = try #require(Fixtures.sampleSnapshot.listItems.first)
        let command = entry(.listItem, path: item.id.path, text: "typed notes")
            .restoreCommand(in: Fixtures.sampleSnapshot)
        #expect(command == .updateListItem(item.id, title: item.title, notes: "typed notes"))
    }

    /// Renamed, completed or trashed since: nothing to write into, only copying is left.
    @Test func aNoteThatIsGoneHasNoRestore() {
        #expect(entry(path: "Actions/Gone.md").restoreCommand(in: Fixtures.sampleSnapshot) == nil)
        #expect(entry(.listItem, path: "Lists/Read/Gone.md").restoreCommand(in: Fixtures.sampleSnapshot) == nil)
    }

    @Test func copyTextPutsTheTitleFirst() {
        #expect(entry(path: "Actions/A.md", title: "T", text: "body").copyText == "T\n\nbody")
        #expect(entry(path: "Actions/A.md").copyText == "typed")
        #expect(entry(path: "Actions/A.md").displayTitle == "A")
    }

    // MARK: Journal

    @Test func whatTheLastRunLeftIsRecoveredAndKept() {
        let left = entry(path: "Actions/A.md")
        let store = InMemoryUnsavedTextStore([left])
        let journal = UnsavedTextJournal(store: store)
        #expect(journal.recovered == [left])

        let live = entry(path: "Actions/B.md")
        journal.update(live: [live])
        journal.writeNow()
        #expect(store.entries == [left, live], "recovered entries stay until the person decides")

        journal.resolve(left)
        #expect(journal.recovered.isEmpty)
        #expect(store.entries == [live])
    }

    @Test func liveTextIsWrittenAfterAPauseNotPerKeystroke() async throws {
        let store = InMemoryUnsavedTextStore()
        let journal = UnsavedTextJournal(store: store, delay: .milliseconds(30))
        for index in 0..<5 { journal.update(live: [entry(path: "Actions/A.md", text: "t\(index)")]) }
        #expect(store.saves == 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.saves == 1)
        #expect(store.entries.first?.text == "t4")
    }

    /// A clean quit: the flush saved everything, so the journal ends empty.
    @Test func nothingLiveLeavesNothingBehind() {
        let store = InMemoryUnsavedTextStore()
        let journal = UnsavedTextJournal(store: store)
        journal.update(live: [entry(path: "Actions/A.md")])
        journal.writeNow()
        journal.update(live: [])
        journal.writeNow()
        #expect(store.entries.isEmpty)
    }

    @Test func anUnreadableJournalIsReportedNotSilentlyEmptied() {
        struct Broken: UnsavedTextStore {
            struct Failure: Error {}
            func load() throws -> [UnsavedText] { throw Failure() }
            func save(_ entries: [UnsavedText]) throws { throw Failure() }
        }
        let journal = UnsavedTextJournal(store: Broken())
        #expect(journal.recovered.isEmpty)
        #expect(journal.failure != nil)
        journal.clearFailure()
        journal.update(live: [entry(path: "Actions/A.md")])
        journal.writeNow()
        #expect(journal.failure != nil, "a failed write reaches the shell's alert")
    }
}
