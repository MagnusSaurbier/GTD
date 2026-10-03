import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDAppCore

/// #94 — the store behind every dialog's kept text: what is kept, what clears it, when it
/// reaches the file.
@MainActor
struct InputDraftsTests {

    private struct Fields: Codable, Equatable {
        var title: String
        var day: Day?
    }

    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func aKeptValueComesBackUntilItIsCleared() {
        let drafts = InputDrafts(now: { self.when })
        let value = Fields(title: "Thesis", day: Day(year: 2026, month: 10, day: 9))
        drafts.keep(value, for: "newProject")
        #expect(drafts.value(Fields.self, for: "newProject") == value)
        #expect(drafts.hasDraft(for: "newProject"))
        #expect(drafts.value(Fields.self, for: "other") == nil)

        drafts.clear("newProject")
        #expect(drafts.value(Fields.self, for: "newProject") == nil)
    }

    @Test func keepingNilClears() {
        let drafts = InputDrafts()
        drafts.keep("typed", for: "k")
        drafts.keep(String?.none, for: "k")
        #expect(!drafts.hasDraft(for: "k"))
    }

    /// A value that no longer decodes (an older app wrote another shape) is not dropped.
    @Test func aDraftOfAnotherShapeIsLeftAlone() {
        let drafts = InputDrafts()
        drafts.keep("just text", for: "k")
        #expect(drafts.value(Fields.self, for: "k") == nil)
        #expect(drafts.value(String.self, for: "k") == "just text")
    }

    @Test func itIsWrittenAfterTypingPausesAndAtOnceOnWriteNow() async {
        let store = InMemoryInputDraftStore()
        let drafts = InputDrafts(store: store, delay: .seconds(60), now: { self.when })
        drafts.keep("typed", for: "k")
        #expect(store.saves == 0, "not on every keystroke")

        drafts.writeNow()
        #expect(store.saves == 1)
        #expect(store.drafts["k"] == InputDraft(json: "\"typed\"", savedAt: when))

        drafts.writeNow()
        #expect(store.saves == 1, "nothing new, nothing written")

        let quick = InputDraftsTests.Probe()
        let fast = InputDrafts(store: quick.store, delay: .milliseconds(1))
        fast.keep("typed", for: "k")
        for _ in 0..<500 where quick.store.saves == 0 { try? await Task.sleep(nanoseconds: 1_000_000) }
        #expect(quick.store.saves == 1)
    }

    /// What an earlier run kept (the app was quit, or crashed) is there on the next launch.
    @Test func aNewRunReadsWhatTheLastOneKept() {
        let store = InMemoryInputDraftStore()
        let first = InputDrafts(store: store)
        first.keep(WaitingSheetDraft(who: "Marie"), for: InputDraftKey.waiting(NoteID(path: "Inbox/a.md")))
        first.writeNow()

        let second = InputDrafts(store: store)
        #expect(second.value(WaitingSheetDraft.self, for: InputDraftKey.waiting(NoteID(path: "Inbox/a.md")))?.who
                == "Marie")
    }

    @Test func anUnreadableStoreIsReportedNotSilentlyEmptied() {
        let drafts = InputDrafts(store: FailingStore())
        #expect(drafts.failure != nil)
        drafts.keep("typed", for: "k")
        #expect(drafts.value(String.self, for: "k") == "typed", "memory still works")
        drafts.clearFailure()
        #expect(drafts.failure == nil)
    }

    /// The shell's flush before quitting writes the drafts at once.
    @Test func flushingHeldEditsWritesTheDrafts() async {
        let store = InMemoryInputDraftStore()
        let model = AppModel(backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot), snapshot: Fixtures.sampleSnapshot)
        model.inputDrafts = InputDrafts(store: store, delay: .seconds(60))
        model.inputDrafts.keep("typed", for: InputDraftKey.newProject)
        await model.flushHeldEdits()
        #expect(store.drafts[InputDraftKey.newProject] != nil)
    }

    @Test func theFollowUpSheetsDraftIsEmptyWithoutAWhoOrADate() {
        #expect(WaitingSheetDraft().isEmpty)
        #expect(WaitingSheetDraft(who: "  ").isEmpty)
        #expect(!WaitingSheetDraft(who: "Marie").isEmpty)
        #expect(!WaitingSheetDraft(followUp: Fixtures.today).isEmpty)
    }

    @Test func keysNameTheDialogAndTheNote() {
        let note = NoteID(path: "Inbox/a.md")
        #expect(InputDraftKey.waiting(note) != InputDraftKey.deferReason(note))
        #expect(InputDraftKey.makeActionOverStep(project: note, text: "x")
                != InputDraftKey.makeActionOverStep(project: note, text: "y"))
        #expect(InputDraftKey.settingsRenameList("Read") != InputDraftKey.settingsRenameContext("Read"))
    }

    private final class Probe {
        let store = InMemoryInputDraftStore()
    }

    private struct FailingStore: InputDraftStore {
        struct Broken: Error {}
        func load() throws -> [String: InputDraft] { throw Broken() }
        func save(_ drafts: [String: InputDraft]) throws { throw Broken() }
    }
}
