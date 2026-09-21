import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDAppCore

/// The rule both shells navigate by: follow a rename, drop a deletion (`NavigationRemap`).
///
/// The bug these pin: a note's id is its file name (A1), so after a rename the old id is as
/// absent from the snapshot as a deleted note's. Pruning against the snapshot alone popped the
/// iPhone's pushed detail — and cleared the Mac's detail column — while the person was editing
/// the title. Break `RenameMap`'s lookup or the order of the two steps and these fail.
@Suite struct NavigationRemapTests {

    private let old = NoteID(path: "Actions/Call the bank.md")
    private let new = NoteID(path: "Actions/Call the bank about the loan.md")
    private let other = NoteID(path: "Actions/Fix the bike light.md")

    private func exists(_ ids: NoteID...) -> (NoteID) -> Bool {
        let set = Set(ids)
        return { set.contains($0) }
    }

    // MARK: - Path (iPhone)

    @Test func aRenameKeepsThePathEntryUnderTheNewID() {
        let path = NavigationRemap.path(
            [old], renames: RenameMap(from: old, to: new), exists: exists(new))
        #expect(path == [new], "the renamed note is still open, under its new id")
    }

    @Test func aDeletedNoteIsStillPruned() {
        let path = NavigationRemap.path(
            [other, old], renames: .empty, exists: exists(other))
        #expect(path == [other])
    }

    @Test func aRenameOfANoteThatIsNotOnThePathChangesNothing() {
        let path = NavigationRemap.path(
            [other], renames: RenameMap(from: old, to: new), exists: exists(other, new))
        #expect(path == [other])
    }

    /// A rename whose new id is *also* missing is a note that is really gone (renamed into the
    /// archive, say): remapping must not resurrect it.
    @Test func aRenameIntoNothingPrunes() {
        let path = NavigationRemap.path(
            [old], renames: RenameMap(from: old, to: new), exists: exists(other))
        #expect(path.isEmpty)
    }

    /// Two renames of the same note before the shell looked: the map composes, the path follows
    /// all the way. This is what `AppModel` accumulates between two `consumeRenames()` calls.
    @Test func chainedRenamesLandOnTheLastID() {
        let middle = NoteID(path: "Actions/Call the bank tomorrow.md")
        let renames = RenameMap(from: old, to: middle).merging(RenameMap(from: middle, to: new))
        #expect(NavigationRemap.path([old], renames: renames, exists: exists(new)) == [new])
    }

    @Test func aRemapThatWouldDuplicateTheRowBelowCollapses() {
        let path = NavigationRemap.path(
            [new, old], renames: RenameMap(from: old, to: new), exists: exists(new))
        #expect(path == [new], "one screen, not two identical ones")
    }

    @Test func anEmptyMapAgainstTheRealSnapshotKeepsWhatExists() {
        let snapshot = Fixtures.sampleSnapshot
        let existing = snapshot.actions[0].id
        let ghost = NoteID(path: "Actions/Never existed.md")
        #expect(NavigationRemap.path([existing, ghost], renames: .empty, in: snapshot) == [existing])
    }

    // MARK: - Selection (Mac)

    @Test func selectionFollowsARenameAndDropsADeletion() {
        let renames = RenameMap(from: old, to: new)
        #expect(NavigationRemap.selection(old, renames: renames, exists: exists(new)) == new)
        #expect(NavigationRemap.selection(other, renames: renames, exists: exists(new)) == nil)
        #expect(NavigationRemap.selection(nil, renames: renames, exists: exists(new)) == nil)
    }

    // MARK: - The map itself

    @Test func theMapAnswersOnlyForWhatItWasToldAbout() {
        var map = RenameMap.empty
        #expect(map.isEmpty)
        #expect(map.resolve(old) == old)

        map.record(old, as: new)
        #expect(map.resolve(old) == new)
        #expect(map.resolve(other) == other)
        #expect(map.pairs.map(\.old) == [old])

        map.record(other, as: other)
        #expect(map.pairs.count == 1, "a note renamed to itself is not a rename")
    }

    /// The plumbing, end to end: the reducer's rename reaches `AppModel` **with** the snapshot
    /// that contains it, and the shell takes it exactly once.
    @MainActor
    @Test func aRenameCommandPublishesItsRenameToTheModel() async throws {
        let backend = InMemoryBackend(snapshot: Fixtures.sampleSnapshot)
        let model = AppModel(backend: backend, snapshot: Fixtures.sampleSnapshot)
        let before = try #require(model.snapshot.actions.first)

        var renamed = before
        renamed.title = "A title nothing else has"
        try await model.send(.updateAction(renamed))

        let after = model.snapshot.config.layout.actionPath(title: renamed.title)
        #expect(model.snapshot.action(before.id) == nil, "the old id really is gone")
        #expect(model.snapshot.action(after) != nil)

        let renames = model.consumeRenames()
        #expect(renames.resolve(before.id) == after)
        #expect(NavigationRemap.path([before.id], renames: renames, in: model.snapshot) == [after])
        #expect(model.consumeRenames().isEmpty, "taken once, not twice")
    }

    /// Any other command leaves the map empty — nothing to follow, so the shell prunes as before.
    @MainActor
    @Test func aCommandThatRenamesNothingPublishesNoRenames() async throws {
        let backend = InMemoryBackend(snapshot: Fixtures.sampleSnapshot)
        let model = AppModel(backend: backend, snapshot: Fixtures.sampleSnapshot)
        let target = try #require(model.snapshot.actions.first { $0.status != .done })

        try await model.send(.complete(target.id))
        #expect(model.consumeRenames().isEmpty)
    }

    @Test func mergingComposesRatherThanOverwrites() {
        let middle = NoteID(path: "Actions/Call the bank tomorrow.md")
        let merged = RenameMap(from: old, to: middle).merging(RenameMap(from: middle, to: new))
        #expect(merged.resolve(old) == new)
        #expect(RenameMap(from: old, to: new).merging(.empty).resolve(old) == new)
        #expect(RenameMap.empty.merging(RenameMap(from: old, to: new)).resolve(old) == new)
    }
}
