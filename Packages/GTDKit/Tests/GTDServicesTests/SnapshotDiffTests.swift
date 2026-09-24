import Foundation
import GTDFixtures
import GTDMarkdown
import GTDModel
@testable import GTDServices
import Testing

/// The diff on its own: no files, no reducer — just "these two snapshots differ, so write this".
@Suite("Snapshot diff")
struct SnapshotDiffTests {

    private let sample = Fixtures.sampleSnapshot

    @Test func anUnchangedSnapshotWritesNothing() throws {
        #expect(try SnapshotDiff.ops(from: sample, to: sample, extraOps: []).isEmpty)
    }

    @Test func aChangedEntityIsWrittenWithTheCodecsEncoding() throws {
        var next = sample
        let index = try #require(next.actions.firstIndex { $0.title == "Fix the bike light" })
        next.actions[index].status = .someday

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [])
        #expect(ops == [.put(
            path: next.actions[index].id.path,
            text: NoteCodec.encode(next.actions[index]))])
    }

    @Test func aNewEntityIsWritten() throws {
        var next = sample
        let area = Area(id: NoteID(path: "Projects/Gesundheit/Gesundheit.md"), title: "Gesundheit")
        next.areas.append(area)

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [])
        #expect(ops == [.put(path: area.id.path, text: NoteCodec.encode(area))])
    }

    /// T00-1 — `extraOps` owns every path it names; the diff stays out of it.
    @Test func aRemovedEntityNamedInExtraOpsIsLeftToExtraOps() throws {
        var next = sample
        let action = try #require(next.actions.first { $0.title == "Collect DAAD transcripts" })
        next.actions.removeAll { $0.id == action.id }
        let archive = VaultFileOp.move(
            from: action.id.path, to: "Archive/2026/08/Collect DAAD transcripts.md")

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [archive])
        #expect(ops == [archive])
    }

    /// T00-1 again, the other half: a note that left the snapshot with nobody saying where it
    /// went is trashed — `GTDVault` turns `.delete` into a move into `GTD/Trash/`.
    @Test func aRemovedEntityNobodyClaimedIsTrashed() throws {
        var next = sample
        let action = try #require(next.actions.first { $0.title == "Learn Portuguese" })
        next.actions.removeAll { $0.id == action.id }

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [])
        #expect(ops == [.delete(path: action.id.path)])
    }

    @Test func aPureRenameMovesTheFileAndWritesNothing() throws {
        var next = sample
        let index = try #require(next.actions.firstIndex { $0.title == "Learn Portuguese" })
        let old = next.actions[index]
        let renamed = rekey(old, to: NoteID(path: "Actions/Learn Spanish.md"), title: "Learn Spanish")
        next.actions[index] = renamed
        let move = VaultFileOp.move(from: old.id.path, to: renamed.id.path)

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [move])
        #expect(ops == [move], "the note itself did not change — only its name")
    }

    @Test func aRenameWithAnEditMovesFirstAndThenWritesTheNewPath() throws {
        var next = sample
        let index = try #require(next.actions.firstIndex { $0.title == "Learn Portuguese" })
        let old = next.actions[index]
        var renamed = rekey(old, to: NoteID(path: "Actions/Learn Spanish.md"), title: "Learn Spanish")
        renamed.status = .next
        next.actions[index] = renamed
        let move = VaultFileOp.move(from: old.id.path, to: renamed.id.path)

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [move])
        #expect(ops == [move, .put(path: renamed.id.path, text: NoteCodec.encode(renamed))])
    }

    // MARK: - Folder moves (R-5)

    /// A `.moveFolder` owns both ends of the tree it moves: the notes under the old path have not
    /// "left the snapshot" (no `.delete`), and the ones under the new path are the same notes
    /// (no `.put` for content that did not change).
    @Test func aFolderMoveOwnsEveryNoteThatTravelsWithIt() throws {
        var next = sample
        let index = try #require(next.actions.firstIndex { $0.title == "Learn Portuguese" })
        let old = next.actions[index]
        next.actions[index] = rekey(
            old, to: NoteID(path: "Lists/Reading/Learn Portuguese.md"), title: old.title)
        // Pretend the note lived in the folder that moved.
        var previous = sample
        previous.actions[index] = rekey(
            old, to: NoteID(path: "Lists/Read/Learn Portuguese.md"), title: old.title)
        let move = VaultFileOp.moveFolder(from: "Lists/Read", to: "Lists/Reading")

        let ops = try SnapshotDiff.ops(from: previous, to: next, extraOps: [move])
        #expect(ops == [move], "the folder move says it all — nothing is written or trashed")
    }

    @Test func aFolderMoveWithAnEditWritesTheNewPathAfterTheMove() throws {
        var next = sample
        let index = try #require(next.actions.firstIndex { $0.title == "Learn Portuguese" })
        let old = next.actions[index]
        var previous = sample
        previous.actions[index] = rekey(
            old, to: NoteID(path: "Lists/Read/Learn Portuguese.md"), title: old.title)
        var moved = rekey(
            old, to: NoteID(path: "Lists/Reading/Learn Portuguese.md"), title: old.title)
        moved.status = .next
        next.actions[index] = moved
        let move = VaultFileOp.moveFolder(from: "Lists/Read", to: "Lists/Reading")

        let ops = try SnapshotDiff.ops(from: previous, to: next, extraOps: [move])
        #expect(ops == [move, .put(path: moved.id.path, text: NoteCodec.encode(moved))])
    }

    // MARK: - The collections that are not `[Entity]`

    /// N3 — what the stale-write guard checks before a rename with an edit: the source path
    /// must still hold the old note, the destination must be absent, and the per-device routine
    /// log is never in the list.
    @Test func theGuardExpectsTheOldTextAtTheSourceAndNothingAtTheDestination() throws {
        let action = try #require(sample.actions.first { $0.title == "Fix the bike light" })
        let newPath = "Actions/Fix the bike light tonight.md"
        let ops: [VaultFileOp] = [
            .move(from: action.id.path, to: newPath),
            .put(path: newPath, text: "irrelevant"),
            .put(path: "GTD/RoutineLog/2026-09-19--fixtures.md", text: "irrelevant"),
            .moveFolder(from: "Lists/Read", to: "Lists/Reading"),
        ]

        let expected = SnapshotDiff.expectedContents(before: ops, in: sample)
        #expect(expected == [
            action.id.path: ContentHash.of(NoteCodec.encode(action)),
            newPath: ContentHash.absent,
        ])
    }

    @Test func onlyTheChangedDayAndDeviceOfTheRoutineLogIsRewritten() throws {
        var next = sample
        let entry = try #require(sample.routineLog.last)
        next.routineLog.append(RoutineLogEntry(
            day: Fixtures.today,
            routine: entry.routine,
            step: entry.step,
            result: .skipped,
            at: Fixtures.date(Fixtures.today, 7, 15),
            device: "iPad"))

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [])
        #expect(ops.count == 1)
        guard case let .put(path, _) = try #require(ops.first) else {
            Issue.record("expected a put")
            return
        }
        #expect(path == "GTD/RoutineLog/\(Fixtures.today.iso)--iPad.md")
    }

    @Test func theWeeklyReviewNoteIsWrittenFromTheChangedLastReview() throws {
        var next = sample
        let review = WeeklyReview(year: 2026, week: 38, achieved: "Quite a lot.")
        next.lastReview = review

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [])
        #expect(ops == [.put(
            path: "GTD/Reviews/2026/KW 38.md", text: NoteCodec.encode(review))])
    }

    @Test func theConfigIsWrittenOnlyWhenItChanged() throws {
        var next = sample
        next.config.nextCap = 12

        let ops = try SnapshotDiff.ops(from: sample, to: next, extraOps: [])
        #expect(ops == [.put(path: "GTD/Config.md", text: NoteCodec.encode(next.config))])
        #expect(try SnapshotDiff.ops(from: next, to: next, extraOps: []).isEmpty)
    }

    /// The diff never touches another device's log file, whatever the 14-day window drops.
    @Test func aLogFileThatLeftTheWindowIsNotDeleted() throws {
        var next = sample
        next.routineLog.removeAll { $0.day == sample.routineLog.first?.day }

        #expect(try SnapshotDiff.ops(from: sample, to: next, extraOps: []).isEmpty)
    }

    private func rekey(_ action: Action, to id: NoteID, title: String) -> Action {
        Action(
            id: id, title: title, status: action.status, contexts: action.contexts,
            timeEstimate: action.timeEstimate, project: action.project,
            deferDate: action.deferDate, due: action.due, waitingFor: action.waitingFor,
            followUpDate: action.followUpDate, created: action.created,
            completedDate: action.completedDate, reviewReason: action.reviewReason,
            modified: action.modified, why: action.why, what: action.what,
            passthrough: action.passthrough)
    }
}
