import Testing
import GTDAppCore
import GTDModel

/// The merge the conflict sheet opens with (N3, ARCHITECTURE §6 2026-09-25): one side's change
/// is kept, both sides' identical change is kept once, and where the two disagree the vault's
/// (newer) side wins and is counted.
@Suite struct ThreeWayMergeTests {

    private let base = "---\nstatus: next\n---\n# Why?\nThe fee is wrong.\n# What?\nCall them.\n"

    @Test func aChangeOnOneSideIsTaken() {
        let mine = base.replacingOccurrences(of: "Call them.", with: "Call them on Monday.")
        let merged = ThreeWayMerge.merge(base: base, mine: mine, theirs: base)
        #expect(merged == ThreeWayMerge.Result(text: mine, conflicts: 0))
        let other = ThreeWayMerge.merge(base: base, mine: base, theirs: mine)
        #expect(other == ThreeWayMerge.Result(text: mine, conflicts: 0))
    }

    @Test func changesToDifferentLinesAreBothKept() {
        let mine = base.replacingOccurrences(of: "Call them.", with: "Call them on Monday.")
        let theirs = base.replacingOccurrences(of: "status: next", with: "status: someday")
        let merged = ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.conflicts == 0)
        #expect(merged.text == "---\nstatus: someday\n---\n# Why?\nThe fee is wrong.\n# What?\nCall them on Monday.\n")
    }

    @Test func theSameChangeOnBothSidesAppearsOnce() {
        let both = base.replacingOccurrences(of: "status: next", with: "status: someday")
        let merged = ThreeWayMerge.merge(base: base, mine: both, theirs: both)
        #expect(merged == ThreeWayMerge.Result(text: both, conflicts: 0))
    }

    @Test func whereBothChangedTheSameLineTheVaultWinsAndItIsCounted() {
        let mine = base.replacingOccurrences(of: "Call them.", with: "Call them on Monday.")
        let theirs = base.replacingOccurrences(of: "Call them.", with: "Write to them instead.")
        let merged = ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.conflicts == 1)
        #expect(merged.text == theirs)
    }

    @Test func linesAddedOnBothSidesAtDifferentPlacesAreBothKept() {
        let mine = base + "# Notes\nAsk for the reference number.\n"
        let theirs = base.replacingOccurrences(of: "# Why?\n", with: "# Why?\nSeen on the statement.\n")
        let merged = ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.conflicts == 0)
        #expect(merged.text.contains("Seen on the statement."))
        #expect(merged.text.hasSuffix("# Notes\nAsk for the reference number.\n"))
    }

    @Test func aLineRemovedOnOneSideStaysRemoved() {
        let mine = base.replacingOccurrences(of: "# What?\nCall them.\n", with: "")
        let theirs = base.replacingOccurrences(of: "status: next", with: "status: someday")
        let merged = ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged == ThreeWayMerge.Result(
            text: "---\nstatus: someday\n---\n# Why?\nThe fee is wrong.\n", conflicts: 0))
    }

    @Test func anEmptyBaseMergesTwoNewTextsAsOneConflict() {
        let merged = ThreeWayMerge.merge(base: "", mine: "a\n", theirs: "b\n")
        #expect(merged.conflicts == 1)
        #expect(merged.text == "b\n")
    }
}

/// `WriteConflict.suggestion`: which path and which text the sheet proposes.
@Suite struct WriteConflictSuggestionTests {

    private let base = "---\nstatus: next\n---\n# Why?\nThe fee is wrong.\n"
    private var edited: String { base.replacingOccurrences(of: "is wrong", with: "is wrong, twice") }

    @Test func renamedElsewhereAndEditedHereSuggestsTheNewTitleWithTheEdit() {
        let conflict = WriteConflict(
            label: "Edit", basePath: "Actions/Call the bank.md", base: base,
            path: "Actions/Call the bank.md", mine: edited,
            theirsPath: "Actions/Call the bank about the fee.md", theirs: base)
        #expect(conflict.theirsRenamed && !conflict.mineRenamed)
        #expect(conflict.suggestion == MergeSuggestion(
            path: "Actions/Call the bank about the fee.md", text: edited, conflicts: 0))
    }

    @Test func renamedHereAndEditedElsewhereSuggestsMyTitleWithTheirEdit() {
        let conflict = WriteConflict(
            label: "Edit", basePath: "Actions/Call the bank.md", base: base,
            path: "Actions/Call the bank today.md", mine: base,
            theirsPath: "Actions/Call the bank.md", theirs: edited)
        #expect(conflict.mineRenamed && !conflict.theirsRenamed)
        #expect(conflict.suggestion == MergeSuggestion(
            path: "Actions/Call the bank today.md", text: edited, conflicts: 0))
    }

    @Test func renamedOnBothSidesTakesTheVaultsTitle() {
        let conflict = WriteConflict(
            label: "Edit", basePath: "Actions/A.md", base: base,
            path: "Actions/B.md", mine: base, theirsPath: "Actions/C.md", theirs: base)
        #expect(conflict.suggestion.path == "Actions/C.md")
    }

    @Test func trashedHereAndEditedElsewhereSuggestsTheirs() {
        let conflict = WriteConflict(
            label: "Moved to Trash", basePath: "Actions/A.md", base: base,
            path: "Actions/A.md", mine: nil, theirsPath: "Actions/A.md", theirs: edited)
        #expect(conflict.suggestion == MergeSuggestion(path: "Actions/A.md", text: edited, conflicts: 0))
    }

    @Test func goneFromTheVaultSuggestsMine() {
        let conflict = WriteConflict(
            label: "Edit", basePath: "Actions/A.md", base: base,
            path: "Actions/A.md", mine: edited, theirsPath: nil, theirs: nil)
        #expect(conflict.suggestion == MergeSuggestion(path: "Actions/A.md", text: edited, conflicts: 0))
    }

    @Test func aRefusalWithAConflictBecomesTheModelsConflictNotItsAlert() async throws {
        let backend = FailingBackend()
        let model = await AppModel(backend: backend)
        let conflict = WriteConflict(
            label: "Edit", basePath: "Actions/A.md", base: base,
            path: "Actions/A.md", mine: edited, theirsPath: "Actions/A.md", theirs: base)
        backend.emit(WriteFailure(label: "Edit", reason: ConflictError.unsupported, conflict: conflict))
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await model.conflict == conflict)
        #expect(await model.writeFailure == nil)

        // Done on a backend that cannot write keeps the sheet open and reports why.
        #expect(await model.resolveConflict(path: "Actions/A.md", text: edited) == false)
        #expect(await model.conflict == conflict)
        #expect(await model.lastError as? ConflictError == .unsupported)

        await model.discardConflict()
        #expect(await model.conflict == nil)
    }
}

/// A backend whose only job is to emit a refusal on demand.
private final class FailingBackend: GTDBackend, @unchecked Sendable {
    private let inner = InMemoryBackend(snapshot: .empty)
    private var continuation: AsyncStream<WriteFailure>.Continuation?
    private let stream: AsyncStream<WriteFailure>

    init() {
        var c: AsyncStream<WriteFailure>.Continuation?
        stream = AsyncStream { c = $0 }
        continuation = c
    }

    func emit(_ failure: WriteFailure) { continuation?.yield(failure) }

    func snapshots() -> AsyncStream<SnapshotUpdate> { inner.snapshots() }
    func currentUpdate() async -> SnapshotUpdate { await inner.currentUpdate() }
    func writeFailures() -> AsyncStream<WriteFailure> { stream }
    func perform(_ command: GTDCommand) async throws -> [AppPrompt] { try await inner.perform(command) }
    func undo() async throws { try await inner.undo() }
    func undoLabel() async -> String? { await inner.undoLabel() }
}
