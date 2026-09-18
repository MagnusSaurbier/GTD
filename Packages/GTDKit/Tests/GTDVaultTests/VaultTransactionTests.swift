import Foundation
import GTDModel
import Testing
@testable import GTDVault

@Suite("Transactions: inverse ops, rollback, and never hard-deleting")
struct VaultTransactionTests {

    private func transaction(_ files: [String: String]) -> (VaultTransaction, InMemoryFileSystem) {
        let fs = InMemoryFileSystem(files: files)
        return (VaultTransaction(fileSystem: fs, layout: .default), fs)
    }

    // MARK: put

    @Test func putOverAnExistingFileInvertsToThePreviousContent() throws {
        let (tx, fs) = transaction(["Actions/A.md": "before"])
        let inverse = try tx.commit([.put(path: "Actions/A.md", text: "after")])
        #expect(try fs.readText("Actions/A.md") == "after")
        #expect(inverse == [.put(path: "Actions/A.md", text: "before")])

        _ = try tx.commit(inverse)
        #expect(try fs.readText("Actions/A.md") == "before")
    }

    @Test func putOfANewFileInvertsToADelete() throws {
        let (tx, fs) = transaction([:])
        let inverse = try tx.commit([.put(path: "Actions/New.md", text: "hello")])
        #expect(inverse == [.delete(path: "Actions/New.md")])

        _ = try tx.commit(inverse)
        #expect(fs.exists("Actions/New.md") == false)
        // Undoing a creation still does not destroy anything.
        #expect(try fs.readText("GTD/Trash/New.md") == "hello")
    }

    // MARK: move

    @Test func moveInvertsToTheReverseMove() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        let inverse = try tx.commit([.move(from: "Actions/A.md", to: "Archive/2026/09/A.md")])
        #expect(inverse == [.move(from: "Archive/2026/09/A.md", to: "Actions/A.md")])
        _ = try tx.commit(inverse)
        #expect(try fs.readText("Actions/A.md") == "x")
    }

    @Test func moveOntoAnExistingFileIsRefused() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x", "Actions/B.md": "y"])
        #expect(throws: VaultError.destinationExists(path: "Actions/B.md")) {
            try tx.commit([.move(from: "Actions/A.md", to: "Actions/B.md")])
        }
        #expect(try fs.readText("Actions/B.md") == "y")   // untouched
    }

    @Test func moveOfAMissingFileFails() throws {
        let (tx, _) = transaction([:])
        #expect(throws: VaultError.self) {
            try tx.commit([.move(from: "Actions/Gone.md", to: "Actions/Here.md")])
        }
    }

    @Test func aMoveOntoItselfIsANoOp() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        #expect(try tx.commit([.move(from: "Actions/A.md", to: "Actions/A.md")]).isEmpty)
        #expect(try fs.readText("Actions/A.md") == "x")
    }

    // MARK: delete → trash

    @Test func deleteMovesIntoTrashAndInvertsToAMoveBack() throws {
        let (tx, fs) = transaction(["Inbox/2026-09-19 081204.md": "capture"])
        let inverse = try tx.commit([.delete(path: "Inbox/2026-09-19 081204.md")])

        #expect(fs.exists("Inbox/2026-09-19 081204.md") == false)
        #expect(try fs.readText("GTD/Trash/2026-09-19 081204.md") == "capture")
        #expect(inverse == [.move(from: "GTD/Trash/2026-09-19 081204.md",
                                  to: "Inbox/2026-09-19 081204.md")])

        _ = try tx.commit(inverse)
        #expect(try fs.readText("Inbox/2026-09-19 081204.md") == "capture")
    }

    @Test func aSecondDeleteOfTheSameNameGetsAFreeTrashName() throws {
        let (tx, fs) = transaction([
            "Actions/A.md": "first",
            "GTD/Trash/A.md": "an older casualty",
        ])
        let inverse = try tx.commit([.delete(path: "Actions/A.md")])
        #expect(try fs.readText("GTD/Trash/A.md") == "an older casualty")   // not overwritten
        #expect(try fs.readText("GTD/Trash/A 2.md") == "first")
        #expect(inverse == [.move(from: "GTD/Trash/A 2.md", to: "Actions/A.md")])
    }

    @Test func deletingSomethingThatIsAlreadyGoneIsANoOp() throws {
        let (tx, _) = transaction([:])
        #expect(try tx.commit([.delete(path: "Actions/Gone.md")]).isEmpty)
    }

    // MARK: Ordering and rollback

    @Test func inverseOpsComeBackInUndoOrder() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        let inverse = try tx.commit([
            .put(path: "Actions/B.md", text: "new"),
            .move(from: "Actions/A.md", to: "Actions/C.md"),
        ])
        // Reverse order: undo the move first, then the creation.
        #expect(inverse == [
            .move(from: "Actions/C.md", to: "Actions/A.md"),
            .delete(path: "Actions/B.md"),
        ])
        _ = try tx.commit(inverse)
        #expect(try fs.readText("Actions/A.md") == "x")
        #expect(fs.exists("Actions/B.md") == false)
        #expect(fs.exists("Actions/C.md") == false)
    }

    @Test func aFailureInTheMiddleRollsBackEverythingBefore() throws {
        let (tx, fs) = transaction(["Actions/A.md": "original", "Actions/B.md": "keep"])
        fs.failWrites(matching: ["Actions/C.md"])

        #expect(throws: VaultError.self) {
            try tx.commit([
                .put(path: "Actions/A.md", text: "changed"),
                .move(from: "Actions/B.md", to: "Actions/B moved.md"),
                .put(path: "Actions/C.md", text: "never lands"),
            ])
        }

        #expect(try fs.readText("Actions/A.md") == "original")
        #expect(try fs.readText("Actions/B.md") == "keep")
        #expect(fs.exists("Actions/B moved.md") == false)
        #expect(fs.exists("Actions/C.md") == false)
    }

    @Test func rollbackOfACreationTrashesItRatherThanLosingIt() throws {
        let (tx, fs) = transaction([:])
        fs.failWrites(matching: ["Actions/Second.md"])
        #expect(throws: VaultError.self) {
            try tx.commit([
                .put(path: "Actions/First.md", text: "half-applied"),
                .put(path: "Actions/Second.md", text: "boom"),
            ])
        }
        #expect(fs.exists("Actions/First.md") == false)
        #expect(try fs.readText("GTD/Trash/First.md") == "half-applied")
    }

    @Test func aFailingRollbackIsReportedNotSwallowed() throws {
        let (tx, fs) = transaction(["Actions/A.md": "x"])
        // The move succeeds, the following put fails, and moving A back fails too.
        fs.failWrites(matching: ["Actions/C.md"])
        fs.failMoves(to: ["Actions/A.md"])

        var caught: VaultError?
        do {
            _ = try tx.commit([
                .move(from: "Actions/A.md", to: "Actions/B.md"),
                .put(path: "Actions/C.md", text: "boom"),
            ])
        } catch let error as VaultError {
            caught = error
        }
        guard case .rollbackFailed = caught else {
            Issue.record("expected rollbackFailed, got \(String(describing: caught))")
            return
        }
    }

    @Test func anEmptyCommitDoesNothing() throws {
        let (tx, _) = transaction([:])
        #expect(try tx.commit([]).isEmpty)
    }
}
